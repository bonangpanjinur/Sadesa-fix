-- DesaMart canonical bootstrap bundle; generated from archive source migration.
-- DO NOT apply to an existing project with migration history.
-- Source: 20260929011000_nearest_courier_sequential_ride_dispatch.sql

DO $bootstrap_do_647d5fad940b$
BEGIN
  EXECUTE $bootstrap_sql_647d5fad940b$-- Offer each new ride to one eligible courier at a time, nearest first.
-- A pending offer expires after 30 seconds; a decline or expiry advances to
-- the next eligible courier. Courier clients run the expiry processor while
-- online, so this remains active without a dedicated server worker.

CREATE TABLE IF NOT EXISTS public.ride_request_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  distance_km numeric(9, 3) NOT NULL CHECK (distance_km >= 0),
  status text NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED')),
  offered_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  responded_at timestamptz,
  CONSTRAINT ride_request_offers_expiry_after_offer
    CHECK (expires_at > offered_at),
  CONSTRAINT ride_request_offers_one_attempt_per_courier
    UNIQUE (ride_id, courier_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ride_request_offers_one_pending_per_ride
  ON public.ride_request_offers (ride_id)
  WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_ride_request_offers_courier_queue
  ON public.ride_request_offers (courier_id, status, expires_at);

ALTER TABLE public.ride_request_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ride_request_offers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ride_request_offers TO authenticated;
DROP POLICY IF EXISTS "Couriers can view own ride offers" ON public.ride_request_offers;
CREATE POLICY "Couriers can view own ride offers"
  ON public.ride_request_offers
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.id = ride_request_offers.courier_id
      AND c.user_id = auth.uid()
  ));

CREATE OR REPLACE FUNCTION public.dispatch_next_ride_offer(p_ride_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_current public.ride_request_offers%ROWTYPE;
  v_candidate record;
  v_offer_id uuid;
  v_title text := 'Permintaan ojek untuk Anda';
  v_message text;
BEGIN
  -- Serialize candidate selection so concurrent new rides do not offer to
  -- the same courier before the first offer becomes visible.
  PERFORM pg_advisory_xact_lock(7210953184926001);

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_ride.status <> 'SEARCHING'
     OR v_ride.driver_id IS NOT NULL
     OR v_ride.pickup_lat IS NULL
     OR v_ride.pickup_lng IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_current
  FROM public.ride_request_offers
  WHERE ride_id = p_ride_id AND status = 'PENDING'
  ORDER BY offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND AND v_current.expires_at > now() THEN
    RETURN v_current.id;
  END IF;

  IF FOUND THEN
    UPDATE public.ride_request_offers
    SET status = 'EXPIRED', responded_at = COALESCE(responded_at, now())
    WHERE id = v_current.id;
  END IF;

  SELECT ranked.id, ranked.user_id, ranked.distance_km
  INTO v_candidate
  FROM (
    SELECT
      c.id,
      c.user_id,
      6371 * 2 * asin(sqrt(LEAST(1::double precision, GREATEST(0::double precision,
        power(sin(radians(c.current_lat::double precision - v_ride.pickup_lat::double precision) / 2), 2)
        + cos(radians(v_ride.pickup_lat::double precision))
          * cos(radians(c.current_lat::double precision))
          * power(sin(radians(c.current_lng::double precision - v_ride.pickup_lng::double precision) / 2), 2)
      )))) AS distance_km
    FROM public.couriers c
    WHERE c.user_id IS NOT NULL
      AND c.registration_status = 'APPROVED'
      AND c.status = 'ACTIVE'
      AND c.is_available = true
      AND c.current_lat IS NOT NULL
      AND c.current_lng IS NOT NULL
      AND c.last_location_update >= now() - interval '90 seconds'
      AND NOT EXISTS (
        SELECT 1
        FROM public.ride_requests active_ride
        WHERE active_ride.driver_id = c.id
          AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.ride_request_offers previous_offer
        WHERE previous_offer.ride_id = p_ride_id
          AND previous_offer.courier_id = c.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.ride_request_offers concurrent_offer
        WHERE concurrent_offer.courier_id = c.id
          AND concurrent_offer.ride_id <> p_ride_id
          AND concurrent_offer.status = 'PENDING'
          AND concurrent_offer.expires_at > now()
      )
  ) AS ranked
  ORDER BY ranked.distance_km ASC, ranked.id ASC
  LIMIT 1;

  IF NOT FOUND THEN
    -- Publish the expiry to realtime subscribers even when no next courier is
    -- currently eligible. An online courier can retry the queue later.
    UPDATE public.ride_requests SET updated_at = now() WHERE id = p_ride_id;
    RETURN NULL;
  END IF;

  INSERT INTO public.ride_request_offers (
    ride_id, courier_id, distance_km, status, offered_at, expires_at
  ) VALUES (
    p_ride_id, v_candidate.id, v_candidate.distance_km, 'PENDING', now(), now() + interval '30 seconds'
  )
  RETURNING id INTO v_offer_id;

  v_message := left(
    'Ada permintaan ojek baru untuk Anda. Jemput di: '
      || COALESCE(NULLIF(v_ride.pickup_address, ''), 'lokasi pembeli')
      || '. Terima atau tolak dalam 30 detik.',
    240
  );

  INSERT INTO public.notifications (user_id, title, message, type, link)
  VALUES (v_candidate.user_id, v_title, v_message, 'ride', '/courier/rides');

  INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
  VALUES (
    v_candidate.user_id,
    'push',
    'new_ride_request',
    jsonb_build_object(
      'title', v_title,
      'body', v_message,
      'url', '/courier/rides',
      'data', jsonb_build_object(
        'type', 'new_ride_request',
        'ride_id', p_ride_id::text,
        'offer_id', v_offer_id::text
      )
    )
  );

  -- Realtime subscribers refresh the courier feed after the offer is recorded.
  UPDATE public.ride_requests SET updated_at = now() WHERE id = p_ride_id;
  RETURN v_offer_id;
END;
$$;
REVOKE ALL ON FUNCTION public.dispatch_next_ride_offer(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_next_ride_offer(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_couriers_new_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.dispatch_next_ride_offer(NEW.id);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_couriers_new_ride() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_couriers_new_ride() TO service_role;
COMMENT ON FUNCTION public.notify_couriers_new_ride() IS
  'Starts a nearest-first, single-courier offer for each newly created SEARCHING ride.';

CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_ride public.ride_requests%ROWTYPE;
  v_offer public.ride_request_offers%ROWTYPE;
  v_passenger_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(7210953184926001);

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id AND user_id = auth.uid()
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier identity is invalid' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id AND status = 'SEARCHING' AND driver_id IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT * INTO v_offer
  FROM public.ride_request_offers
  WHERE ride_id = p_ride_id
    AND courier_id = p_courier_id
    AND status = 'PENDING'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_offer.expires_at <= now()
     OR v_courier.registration_status <> 'APPROVED'
     OR v_courier.status <> 'ACTIVE'
     OR v_courier.is_available IS DISTINCT FROM true
     OR v_courier.last_location_update IS NULL
     OR v_courier.last_location_update < now() - interval '90 seconds'
     OR v_courier.current_lat IS NULL
     OR v_courier.current_lng IS NULL
     OR EXISTS (
       SELECT 1
       FROM public.ride_requests active_ride
       WHERE active_ride.driver_id = p_courier_id
         AND active_ride.id <> p_ride_id
         AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
     ) THEN
    UPDATE public.ride_request_offers
    SET status = 'EXPIRED', responded_at = now()
    WHERE id = v_offer.id;
    PERFORM public.dispatch_next_ride_offer(p_ride_id);
    RETURN false;
  END IF;

  UPDATE public.ride_request_offers
  SET status = 'ACCEPTED', responded_at = now()
  WHERE id = v_offer.id;

  UPDATE public.ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_ride_id AND status = 'SEARCHING' AND driver_id IS NULL
  RETURNING passenger_id INTO v_passenger_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  PERFORM public.send_notification(
    v_passenger_id,
    'Driver Ditemukan!',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  );
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.accept_ride(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.decline_ride_request(p_ride_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
  v_ride public.ride_requests%ROWTYPE;
  v_offer_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(7210953184926001);

  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid()
  LIMIT 1;
  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Courier identity is invalid' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id AND status = 'SEARCHING' AND driver_id IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  UPDATE public.ride_request_offers
  SET status = 'REJECTED', responded_at = now()
  WHERE ride_id = p_ride_id
    AND courier_id = v_courier_id
    AND status = 'PENDING'
    AND expires_at > now()
  RETURNING id INTO v_offer_id;

  IF v_offer_id IS NULL THEN
    -- A decline arriving just after the deadline also releases the next offer.
    UPDATE public.ride_request_offers
    SET status = 'EXPIRED', responded_at = COALESCE(responded_at, now())
    WHERE ride_id = p_ride_id
      AND courier_id = v_courier_id
      AND status = 'PENDING';
    PERFORM public.dispatch_next_ride_offer(p_ride_id);
    RETURN false;
  END IF;

  PERFORM public.dispatch_next_ride_offer(p_ride_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.decline_ride_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decline_ride_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.process_expired_ride_offers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride_id uuid;
  v_offer_id uuid;
  v_processed integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
      AND c.registration_status = 'APPROVED'
      AND c.status = 'ACTIVE'
      AND c.is_available = true
      AND c.last_location_update >= now() - interval '90 seconds'
  ) THEN
    RAISE EXCEPTION 'Only an active, available courier can process ride dispatch' USING ERRCODE = '42501';
  END IF;

  -- All live courier sessions may call this heartbeat; one transaction does
  -- the small queue scan at a time.
  IF NOT pg_try_advisory_xact_lock(7210953184926001) THEN
    RETURN 0;
  END IF;

  FOR v_ride_id IN
    SELECT r.id
    FROM public.ride_requests r
    WHERE r.status = 'SEARCHING'
      AND r.driver_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.ride_request_offers pending_offer
        WHERE pending_offer.ride_id = r.id
          AND pending_offer.status = 'PENDING'
          AND pending_offer.expires_at > now()
      )
    ORDER BY r.created_at ASC
    LIMIT 50
  LOOP
    v_offer_id := public.dispatch_next_ride_offer(v_ride_id);
    IF v_offer_id IS NOT NULL THEN
      v_processed := v_processed + 1;
    END IF;
  END LOOP;

  RETURN v_processed;
END;
$$;
REVOKE ALL ON FUNCTION public.process_expired_ride_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_expired_ride_offers() TO authenticated;

DROP POLICY IF EXISTS "Couriers can view searching rides" ON public.ride_requests;
CREATE POLICY "Couriers can view searching rides"
  ON public.ride_requests
  FOR SELECT TO authenticated
  USING (
    status = 'SEARCHING'
    AND driver_id IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.ride_request_offers offer
      JOIN public.couriers c ON c.id = offer.courier_id
      WHERE offer.ride_id = ride_requests.id
        AND offer.status = 'PENDING'
        AND offer.expires_at > now()
        AND c.user_id = auth.uid()
        AND c.registration_status = 'APPROVED'
        AND c.status = 'ACTIVE'
        AND c.is_available = true
        AND c.last_location_update >= now() - interval '90 seconds'
        AND NOT EXISTS (
          SELECT 1
          FROM public.ride_requests active_ride
          WHERE active_ride.driver_id = c.id
            AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
        )
    )
  );

COMMENT ON TABLE public.ride_request_offers IS
  'Private sequential offers for passenger rides; only the targeted courier can read their offer.';
COMMENT ON FUNCTION public.process_expired_ride_offers() IS
  'Advances unaccepted SEARCHING rides to the next eligible nearest courier; called by active courier clients while online.';
$bootstrap_sql_647d5fad940b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_647d5fad940b$;

-- ===== BEGIN SOURCE: 20260929123000_pos_trial_activation_hardening.sql =====
-- POS trial activation hardening.
DO $$
BEGIN
  EXECUTE $sql$
    CREATE OR REPLACE FUNCTION public.activate_pos_trial()
    RETURNS public.pos_subscriptions
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
    AS $fn$
    DECLARE
      v_merchant_id uuid;
      v_config jsonb;
      v_trial_days integer;
      v_subscription public.pos_subscriptions%ROWTYPE;
    BEGIN
      IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Autentikasi diperlukan' USING ERRCODE = '42501'; END IF;
      SELECT id INTO v_merchant_id FROM public.merchants WHERE user_id = auth.uid() FOR UPDATE;
      IF v_merchant_id IS NULL THEN RAISE EXCEPTION 'Merchant tidak ditemukan' USING ERRCODE = '42501'; END IF;
      IF EXISTS (SELECT 1 FROM public.pos_subscriptions WHERE merchant_id = v_merchant_id AND is_trial = true) THEN RAISE EXCEPTION 'Trial POS sudah pernah digunakan' USING ERRCODE = '23505'; END IF;
      IF EXISTS (SELECT 1 FROM public.pos_subscriptions WHERE merchant_id = v_merchant_id AND status IN ('PENDING', 'ACTIVE')) THEN RAISE EXCEPTION 'Sudah ada subscription POS yang sedang berjalan' USING ERRCODE = '23505'; END IF;
      SELECT value INTO v_config FROM public.app_settings WHERE key = 'pos_config' FOR SHARE;
      v_trial_days := LEAST(GREATEST(COALESCE((v_config ->> 'trial_days')::integer, 30), 1), 90);
      INSERT INTO public.pos_subscriptions (merchant_id, package_id, status, is_trial, payment_amount, payment_status, started_at, expired_at)
      VALUES (v_merchant_id, NULL, 'ACTIVE', true, 0, 'FREE', now(), now() + make_interval(days => v_trial_days))
      RETURNING * INTO v_subscription;
      RETURN v_subscription;
    END;
    $fn$
  $sql$;
  EXECUTE 'REVOKE ALL ON FUNCTION public.activate_pos_trial() FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.activate_pos_trial() TO authenticated';
END
$$;
-- ===== END SOURCE: 20260929123000_pos_trial_activation_hardening.sql =====

-- ===== BEGIN SOURCE: 20260929130000_pos_canonical_catalog_integration.sql =====
-- POS canonical catalog integration for merchants that have an active POS tenant.
-- POS owns operational product fields and outlet stock; marketplace products remain
-- the public projection consumed by the buyer experience.

CREATE OR REPLACE FUNCTION public.sync_pos_product_to_merchant_catalog(p_pos_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pos public.pos_products%ROWTYPE;
BEGIN
  SELECT * INTO v_pos FROM public.pos_products WHERE id = p_pos_product_id;
  IF NOT FOUND OR v_pos.merchant_product_id IS NULL THEN RETURN; END IF;

  PERFORM set_config('app.pos_catalog_projection', 'on', true);
  UPDATE public.products
  SET name = v_pos.name,
      price = GREATEST(0, ROUND(v_pos.price))::integer,
      image_url = v_pos.image_url,
      description = v_pos.description,
      is_active = v_pos.is_active,
      updated_at = now()
  WHERE id = v_pos.merchant_product_id
    AND EXISTS (
      SELECT 1
      FROM public.pos_tenants pt
      WHERE pt.id = v_pos.tenant_id
        AND pt.merchant_id = products.merchant_id
        AND pt.is_active = true
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_product_to_merchant_catalog_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(current_setting('app.merchant_catalog_projection', true), '') <> 'on' THEN
    PERFORM public.sync_pos_product_to_merchant_catalog(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_product_to_merchant_catalog ON public.pos_products;
CREATE TRIGGER trg_sync_pos_product_to_merchant_catalog
AFTER UPDATE OF name, price, image_url, description, is_active, merchant_product_id, tenant_id
ON public.pos_products
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_product_to_merchant_catalog_trigger();

-- Restore the stock projection trigger in the current canonical bootstrap. This
-- keeps products.stock and variant stock equal to available POS outlet stock.
DROP TRIGGER IF EXISTS trg_sync_pos_stock_to_marketplace ON public.pos_stock;
CREATE TRIGGER trg_sync_pos_stock_to_marketplace
AFTER INSERT OR UPDATE OF quantity, reserved_quantity, product_id, tenant_id, outlet_id OR DELETE
ON public.pos_stock
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_stock_to_marketplace_after_change();

-- Any direct marketplace stock edit for an active POS-linked product is invalid.
CREATE OR REPLACE FUNCTION public.prevent_manual_stock_edit_for_pos_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.stock IS DISTINCT FROM OLD.stock
     AND COALESCE(current_setting('app.pos_stock_projection', true), '') <> 'on'
     AND EXISTS (
       SELECT 1
       FROM public.pos_products pp
       JOIN public.pos_tenants pt ON pt.id = pp.tenant_id
       WHERE pp.merchant_product_id = NEW.id
         AND pt.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Stock produk tertaut POS hanya dapat diubah dari stok outlet POS'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_stock_edit_for_pos_product ON public.products;
CREATE TRIGGER trg_prevent_manual_stock_edit_for_pos_product
BEFORE UPDATE OF stock ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.prevent_manual_stock_edit_for_pos_product();

-- POS is the operational source for core catalog fields once linked.
CREATE OR REPLACE FUNCTION public.prevent_manual_core_edit_for_pos_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(current_setting('app.pos_catalog_projection', true), '') <> 'on'
     AND (NEW.name IS DISTINCT FROM OLD.name
       OR NEW.price IS DISTINCT FROM OLD.price
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.image_url IS DISTINCT FROM OLD.image_url
       OR NEW.is_active IS DISTINCT FROM OLD.is_active)
     AND EXISTS (
       SELECT 1 FROM public.pos_products pp
       JOIN public.pos_tenants pt ON pt.id = pp.tenant_id
       WHERE pp.merchant_product_id = NEW.id AND pt.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Produk tertaut POS hanya dapat mengubah nama, harga, deskripsi, gambar, dan status dari POS'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_core_edit_for_pos_product ON public.products;
CREATE TRIGGER trg_prevent_manual_core_edit_for_pos_product
BEFORE UPDATE OF name, price, description, image_url, is_active ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.prevent_manual_core_edit_for_pos_product();

REVOKE ALL ON FUNCTION public.sync_pos_product_to_merchant_catalog(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_product_to_merchant_catalog_trigger() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_manual_stock_edit_for_pos_product() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_manual_core_edit_for_pos_product() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_tenant record;
BEGIN
  FOR v_tenant IN SELECT id FROM public.pos_tenants WHERE is_active = true AND merchant_id IS NOT NULL LOOP
    PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant.id);
  END LOOP;
END $$;

-- ===== END SOURCE: 20260929130000_pos_canonical_catalog_integration.sql =====
