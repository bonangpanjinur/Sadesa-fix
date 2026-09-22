-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 66_20260914153000_ride_driver_verification.sql .. 77_20260918170000_pod_delivery_proof_policy.sql

-- ===== BEGIN BUNDLE: 66_20260914153000_ride_driver_verification.sql =====
-- Ride driver verification: require a short confirmation note and persist audit metadata.
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS pickup_verification_method text,
  ADD COLUMN IF NOT EXISTS pickup_verification_note text,
  ADD COLUMN IF NOT EXISTS pickup_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS completion_verification_method text,
  ADD COLUMN IF NOT EXISTS completion_verification_note text,
  ADD COLUMN IF NOT EXISTS completion_verified_at timestamptz;

DROP FUNCTION IF EXISTS public.transition_ride_status(uuid, text);

CREATE OR REPLACE FUNCTION public.transition_ride_status(
  p_ride_id uuid,
  p_to_status text,
  p_verification_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
  v_final_fare integer;
  v_note text := NULLIF(left(btrim(COALESCE(p_verification_note, '')), 500), '');
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid()
    AND registration_status = 'APPROVED'
    AND status = 'ACTIVE'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Kurir tidak aktif atau belum disetujui';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id AND driver_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perjalanan tidak ditemukan atau bukan milik kurir ini';
  END IF;

  IF (v_ride.status, p_to_status) NOT IN (
    ('ACCEPTED', 'PICKED_UP'),
    ('PICKED_UP', 'IN_TRANSIT'),
    ('IN_TRANSIT', 'COMPLETED')
  ) THEN
    RAISE EXCEPTION 'Perubahan status perjalanan tidak valid';
  END IF;

  IF p_to_status IN ('PICKED_UP', 'COMPLETED') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Confirmation note is required for pickup and completion' USING ERRCODE = '22023';
  END IF;

  v_final_fare := COALESCE(v_ride.final_fare, v_ride.estimated_fare);

  UPDATE public.ride_requests
  SET status = p_to_status,
      final_fare = CASE WHEN p_to_status = 'COMPLETED' THEN v_final_fare ELSE final_fare END,
      picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
      completed_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completed_at END,
      pickup_verification_method = CASE WHEN p_to_status = 'PICKED_UP' THEN 'DRIVER_CONFIRMATION' ELSE pickup_verification_method END,
      pickup_verification_note = CASE WHEN p_to_status = 'PICKED_UP' THEN v_note ELSE pickup_verification_note END,
      pickup_verified_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE pickup_verified_at END,
      completion_verification_method = CASE WHEN p_to_status = 'COMPLETED' THEN 'DRIVER_CONFIRMATION' ELSE completion_verification_method END,
      completion_verification_note = CASE WHEN p_to_status = 'COMPLETED' THEN v_note ELSE completion_verification_note END,
      completion_verified_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completion_verified_at END,
      updated_at = now()
  WHERE id = p_ride_id;

  IF p_to_status = 'COMPLETED' THEN
    INSERT INTO public.courier_earnings (
      courier_id, ride_request_id, amount, type, status, distance_km, base_amount, created_at
    )
    SELECT v_courier_id, p_ride_id, v_final_fare, 'RIDE', 'PENDING', v_ride.distance_km, v_final_fare, now()
    WHERE NOT EXISTS (
      SELECT 1 FROM public.courier_earnings
      WHERE ride_request_id = p_ride_id AND type = 'RIDE'
    );
  END IF;

  RETURN p_to_status;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 66_20260914153000_ride_driver_verification.sql =====

-- ===== BEGIN BUNDLE: 67_20260915160000_unify_courier_and_ride_ratings.sql =====
-- Keep courier rating statistics consistent across marketplace deliveries and Ojek Desa rides.
-- Both flows represent feedback for the same courier profile, but historically maintained
-- separate storage paths.

CREATE OR REPLACE FUNCTION public.refresh_courier_rating(p_courier_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg numeric;
  v_count integer;
BEGIN
  SELECT
    COALESCE(round(avg(r.rating)::numeric, 2), 0),
    count(*)::integer
  INTO v_avg, v_count
  FROM (
    SELECT rating
    FROM public.courier_ratings
    WHERE courier_id = p_courier_id
    UNION ALL
    SELECT rating
    FROM public.ride_requests
    WHERE driver_id = p_courier_id
      AND status = 'COMPLETED'
      AND rating IS NOT NULL
  ) AS r;

  UPDATE public.couriers
  SET rating_avg = v_avg,
      rating_count = v_count,
      updated_at = now()
  WHERE id = p_courier_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_courier_rating_from_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.driver_id IS NOT NULL THEN
      PERFORM public.refresh_courier_rating(OLD.driver_id);
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.driver_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.rating IS DISTINCT FROM OLD.rating OR NEW.driver_id IS DISTINCT FROM OLD.driver_id) THEN
    PERFORM public.refresh_courier_rating(NEW.driver_id);
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.driver_id IS NOT NULL
     AND OLD.driver_id IS DISTINCT FROM NEW.driver_id THEN
    PERFORM public.refresh_courier_rating(OLD.driver_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_courier_rating_from_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_courier_rating(OLD.courier_id);
    RETURN OLD;
  END IF;

  PERFORM public.refresh_courier_rating(NEW.courier_id);
  IF TG_OP = 'UPDATE' AND OLD.courier_id IS DISTINCT FROM NEW.courier_id THEN
    PERFORM public.refresh_courier_rating(OLD.courier_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_courier_rating_after_ride ON public.ride_requests;
CREATE TRIGGER sync_courier_rating_after_ride
AFTER INSERT OR UPDATE OF driver_id, rating OR DELETE ON public.ride_requests
FOR EACH ROW
EXECUTE FUNCTION public.sync_courier_rating_from_ride();

DROP TRIGGER IF EXISTS sync_courier_rating_after_delivery ON public.courier_ratings;
CREATE TRIGGER sync_courier_rating_after_delivery
AFTER INSERT OR UPDATE OF courier_id, rating OR DELETE ON public.courier_ratings
FOR EACH ROW
EXECUTE FUNCTION public.sync_courier_rating_from_delivery();

-- Backfill profiles created before the unified aggregation existed.
UPDATE public.couriers AS c
SET rating_avg = stats.rating_avg,
    rating_count = stats.rating_count,
    updated_at = now()
FROM (
  SELECT
    c2.id,
    COALESCE(round(avg(r.rating)::numeric, 2), 0) AS rating_avg,
    count(r.rating)::integer AS rating_count
  FROM public.couriers AS c2
  LEFT JOIN (
    SELECT courier_id, rating
    FROM public.courier_ratings
    UNION ALL
    SELECT driver_id AS courier_id, rating
    FROM public.ride_requests
    WHERE status = 'COMPLETED' AND rating IS NOT NULL
  ) AS r ON r.courier_id = c2.id
  GROUP BY c2.id
) AS stats
WHERE c.id = stats.id;

REVOKE ALL ON FUNCTION public.refresh_courier_rating(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_courier_rating_from_ride() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_courier_rating_from_delivery() FROM PUBLIC, anon, authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 67_20260915160000_unify_courier_and_ride_ratings.sql =====

-- ===== BEGIN BUNDLE: 68_20260917100000_delivery_assignments_created_by_compatibility.sql =====
-- Compatibility fix for existing Supabase projects.
-- The delivery_assignments table may have been created before the
-- create_courier_order RPC started writing created_by.

ALTER TABLE public.delivery_assignments
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_delivery_assignments_created_by
  ON public.delivery_assignments(created_by);

NOTIFY pgrst, 'reload schema';

-- Existing assignments remain unchanged; created_by is NULL for old rows.
-- New courier bookings will store auth.uid() in this column.
-- ===== END BUNDLE: 68_20260917100000_delivery_assignments_created_by_compatibility.sql =====

-- ===== BEGIN BUNDLE: 69_20260917110000_notify_courier_delivery_offer.sql =====
-- Notify the assigned courier when a merchant creates a delivery offer.
-- The offer is already visible in delivery_assignments, but without this
-- notification the courier has no reliable in-app signal to open the offer.

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED')
     OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;

  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.id = p_courier_id
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id
    AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = p_courier_id,
      assigned_at = now(),
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir desa'
  );

  -- Keep notification creation inside the same transaction as the offer so
  -- the courier never receives a stale notification for a failed assignment.
  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada tawaran pengiriman baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier?orderId=' || p_order_id::text
  );

  RETURN v_assignment;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 69_20260917110000_notify_courier_delivery_offer.sql =====

-- ===== BEGIN BUNDLE: 69_20260917180000_order_service_type.sql =====
-- Make buyer transaction classification explicit while preserving legacy orders.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS service_type text NOT NULL DEFAULT 'MARKETPLACE';

UPDATE public.orders
SET service_type = 'COURIER_DELIVERY'
WHERE service_type = 'MARKETPLACE'
  AND merchant_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.order_items oi WHERE oi.order_id = orders.id
  )
  AND pickup_address IS NOT NULL
  AND package_type IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'orders_service_type_check'
      AND conrelid = 'public.orders'::regclass
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_service_type_check
      CHECK (service_type IN ('MARKETPLACE', 'COURIER_DELIVERY'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_buyer_service_type_created
  ON public.orders (buyer_id, service_type, created_at DESC);

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 69_20260917180000_order_service_type.sql =====

-- ===== BEGIN BUNDLE: 70_20260917152000_offer_status_integrity.sql =====
-- Keep assignment and acceptance separate.
-- ASSIGNED means an offer was sent to a courier; COURIER_ACCEPTED means
-- the courier explicitly accepted it.

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED')
     OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;

  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.id = p_courier_id
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  -- Do not put the courier on the order yet. The courier_id and assigned_at
  -- fields become authoritative only after respond_delivery_offer(true).
  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = NULL,
      assigned_at = NULL,
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir; menunggu keputusan kurir',
    jsonb_build_object('courier_id', p_courier_id, 'assignment_id', v_assignment.id)
  );

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada tawaran pengiriman baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/rides?orderId=' || p_order_id::text
  );

  RETURN v_assignment;
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_offer_order_to_courier(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.create_delivery_offer(p_order_id, p_courier_id);
END;
$$;

-- Acceptance is the only operation that makes the courier authoritative.
CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assignment public.delivery_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.id = p_assignment_id AND da.courier_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND OR v_assignment.status <> 'OFFERED' OR v_assignment.expires_at < now() THEN
    RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = v_assignment.order_id FOR UPDATE;

  IF p_accept THEN
    UPDATE public.delivery_assignments
    SET status = 'ACCEPTED', responded_at = now(), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;

    UPDATE public.orders
    SET courier_id = v_courier_id,
        status = 'COURIER_ACCEPTED',
        assigned_at = COALESCE(assigned_at, now()),
        courier_accepted_at = now(),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'COURIER_ACCEPTED', auth.uid(), 'Kurir menerima pesanan');
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;

    UPDATE public.orders
    SET courier_id = NULL,
        assigned_at = NULL,
        courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id),
        status = 'ASSIGNED',
        status_updated_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, 'ASSIGNED', 'ASSIGNED', auth.uid(), COALESCE(p_reason, 'Kurir menolak pesanan'));
  END IF;

  RETURN v_assignment;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid, boolean, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 70_20260917152000_offer_status_integrity.sql =====

-- ===== BEGIN BUNDLE: 70_20260917190000_renew_courier_offer.sql =====
-- Keep a still-pending courier offer visible when a courier dashboard was offline.
-- The courier may renew only their own offer and only while the order is ASSIGNED.
CREATE OR REPLACE FUNCTION public.renew_delivery_offer(p_assignment_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assignment public.delivery_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.registration_status = 'APPROVED';

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.id = p_assignment_id
    AND da.courier_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND OR v_assignment.status <> 'OFFERED' THEN
    RAISE EXCEPTION 'Offer is no longer available' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = v_assignment.order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.status <> 'ASSIGNED' THEN
    RAISE EXCEPTION 'Order is no longer waiting for a courier' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET expires_at = GREATEST(expires_at, now()) + interval '5 minutes'
  WHERE id = p_assignment_id
  RETURNING * INTO v_assignment;

  RETURN v_assignment;
END;
$$;

REVOKE ALL ON FUNCTION public.renew_delivery_offer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_delivery_offer(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 70_20260917190000_renew_courier_offer.sql =====

-- ===== BEGIN BUNDLE: 71_20260917193000_retry_courier_dispatch.sql =====
-- Retry courier dispatch for bookings that remain ASSIGNED without a visible offer.
-- This is idempotent: an active offer is reused; expired offers are reopened.
CREATE OR REPLACE FUNCTION public.dispatch_courier_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (buyer_id = auth.uid() OR public.is_admin())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'ASSIGNED' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    UPDATE public.orders
    SET courier_id = v_assignment.courier_id,
        assigned_at = COALESCE(assigned_at, now()),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'dispatch_status', 'OFFERED');
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')))
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_order.pickup_lat) / 2), 2)
      + cos(radians(v_order.pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_order.pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id AND da.courier_id = v_courier.id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, offered_at, expires_at)
    VALUES (p_order_id, v_courier.id, now(), now() + interval '5 minutes')
    RETURNING * INTO v_assignment;
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'OFFERED', offered_at = now(), expires_at = now() + interval '5 minutes', responded_at = NULL, rejection_reason = NULL
    WHERE id = v_assignment.id
    RETURNING * INTO v_assignment;
  END IF;

  -- The courier must be associated with the order before acceptance so the
  -- courier-side orders RLS policy can expose the nested order payload.
  UPDATE public.orders
  SET courier_id = v_courier.id,
      assigned_at = COALESCE(assigned_at, now()),
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.send_notification(
    v_courier.user_id,
    'Pesanan Kurir Baru',
    'Ada pesanan kurir baru di sekitar lokasi Anda',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'courier_id', v_courier.id, 'dispatch_status', 'OFFERED');
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_courier_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 71_20260917193000_retry_courier_dispatch.sql =====

-- ===== BEGIN BUNDLE: 72_20260917195000_courier_offer_feed.sql =====
-- Courier offer feed: avoids nested orders RLS hiding an OFFERED assignment
-- before orders.courier_id is populated by acceptance.
CREATE OR REPLACE FUNCTION public.get_courier_delivery_offers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
  v_offers jsonb;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', da.id,
    'order_id', da.order_id,
    'expires_at', da.expires_at,
    'orders', jsonb_build_object(
      'total', o.total,
      'shipping_cost', o.shipping_cost,
      'courier_earning_estimate', o.courier_earning_estimate,
      'courier_platform_fee', o.courier_platform_fee,
      'pickup_address', o.pickup_address,
      'pickup_lat', o.pickup_lat,
      'pickup_lng', o.pickup_lng,
      'delivery_name', o.delivery_name,
      'delivery_address', o.delivery_address,
      'delivery_lat', o.delivery_lat,
      'delivery_lng', o.delivery_lng,
      'notes', o.notes,
      'merchants', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('name', m.name, 'address', m.address) END
    )
  ) ORDER BY da.offered_at DESC), '[]'::jsonb)
  INTO v_offers
  FROM public.delivery_assignments da
  JOIN public.orders o ON o.id = da.order_id
  LEFT JOIN public.merchants m ON m.id = o.merchant_id
  WHERE da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now();

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 72_20260917195000_courier_offer_feed.sql =====

-- ===== BEGIN BUNDLE: 73_20260917200000_courier_offer_authority_repair.sql =====
-- Courier delivery flow repair:
-- ASSIGNED means an offer is waiting for a courier decision.
-- courier_id/assigned_at become authoritative only after acceptance.

-- Repair rows created by the older booking/dispatch functions.
UPDATE public.orders o
SET courier_id = NULL,
    assigned_at = NULL,
    updated_at = now()
WHERE o.status = 'ASSIGNED'
  AND EXISTS (
    SELECT 1
    FROM public.delivery_assignments da
    WHERE da.order_id = o.id
      AND da.status = 'OFFERED'
  );

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED')
     OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;

  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.id = p_courier_id
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = NULL,
      assigned_at = NULL,
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir; menunggu keputusan kurir',
    jsonb_build_object('courier_id', p_courier_id, 'assignment_id', v_assignment.id)
  );

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada tawaran pengiriman baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/deliveries'
  );

  RETURN v_assignment;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_courier_order(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_pickup_lat numeric := (p_request->>'pickup_lat')::numeric;
  v_pickup_lng numeric := (p_request->>'pickup_lng')::numeric;
  v_destination_lat numeric := (p_request->>'destination_lat')::numeric;
  v_destination_lng numeric := (p_request->>'destination_lng')::numeric;
  v_distance numeric;
  v_weight numeric := COALESCE((p_request->>'weight_kg')::numeric, 1);
  v_base integer;
  -- COD is intentionally free for every courier transaction.
  v_cod_fee integer := 0;
  v_shipping integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  IF v_pickup_lat NOT BETWEEN -90 AND 90 OR v_destination_lat NOT BETWEEN -90 AND 90
     OR v_pickup_lng NOT BETWEEN -180 AND 180 OR v_destination_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid courier coordinates' USING ERRCODE = '22023';
  END IF;
  IF v_weight <= 0 OR v_weight > 50 THEN
    RAISE EXCEPTION 'Package weight must be between 0 and 50 kg' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(p_request->>'pickup_address'), '') IS NULL
     OR NULLIF(btrim(p_request->>'destination_address'), '') IS NULL
     OR NULLIF(btrim(p_request->>'recipient_name'), '') IS NULL
     OR NULLIF(btrim(p_request->>'recipient_phone'), '') IS NULL
     OR NULLIF(btrim(p_request->>'package_type'), '') IS NULL THEN
    RAISE EXCEPTION 'Courier address, recipient, and package details are required' USING ERRCODE = '22023';
  END IF;

  v_distance := 6371 * 2 * asin(sqrt(
    power(sin(radians(v_destination_lat - v_pickup_lat) / 2), 2)
    + cos(radians(v_pickup_lat)) * cos(radians(v_destination_lat))
    * power(sin(radians(v_destination_lng - v_pickup_lng) / 2), 2)
  ));
  IF v_distance IS NULL OR v_distance <= 0 OR v_distance > 10 THEN
    RAISE EXCEPTION 'Internal courier service supports distances up to 10 km' USING ERRCODE = '22023';
  END IF;

  v_base := CASE WHEN v_distance <= 3 THEN 8000 WHEN v_distance <= 7 THEN 12000 ELSE 18000 END;
  v_shipping := v_base + (GREATEST(0, v_weight - 2) * 2500)::integer;

  INSERT INTO public.orders (
    buyer_id, merchant_id, service_type, status, handled_by, delivery_type,
    delivery_address, delivery_phone, delivery_name, delivery_lat, delivery_lng,
    shipping_cost, subtotal, total, notes, payment_method, payment_status,
    buyer_distance_km, is_self_delivery, pickup_address, pickup_lat, pickup_lng,
    package_type, package_weight_kg, courier_notes, scheduled_pickup, cod_service_fee
  ) VALUES (
    auth.uid(), NULL, 'COURIER_DELIVERY', 'ASSIGNED', 'ADMIN', 'INTERNAL',
    left(btrim(p_request->>'destination_address'), 500),
    left(btrim(p_request->>'recipient_phone'), 40),
    left(btrim(p_request->>'recipient_name'), 160), v_destination_lat, v_destination_lng,
    v_shipping, 0, v_shipping + v_cod_fee, NULLIF(left(btrim(p_request->>'notes'), 1000), ''),
    'COD', 'COD', round(v_distance, 2), false,
    left(btrim(p_request->>'pickup_address'), 500), v_pickup_lat, v_pickup_lng,
    left(btrim(p_request->>'package_type'), 160), v_weight,
    NULLIF(left(btrim(p_request->>'notes'), 1000), ''),
    COALESCE((p_request->>'scheduled')::boolean, false), v_cod_fee
  ) RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (v_order.id, NULL, 'ASSIGNED', auth.uid(), 'Courier booking dibuat oleh buyer');

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_pickup_lat) / 2), 2)
      + cos(radians(v_pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NOT NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
    VALUES (v_order.id, v_courier.id, auth.uid())
    RETURNING * INTO v_assignment;

    PERFORM public.send_notification(
      v_courier.user_id,
      'Pesanan Kurir Baru',
      'Ada pesanan kurir baru di sekitar lokasi Anda',
      'order',
      '/courier/deliveries'
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'assignment_id', v_assignment.id,
    'status', v_order.status,
    'distance_km', round(v_distance, 2),
    'shipping_cost', v_shipping,
    'cod_fee', v_cod_fee,
    'dispatch_status', CASE WHEN v_assignment.id IS NULL THEN 'WAITING_FOR_COURIER' ELSE 'OFFERED' END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.dispatch_courier_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (buyer_id = auth.uid() OR public.is_admin())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.status <> 'ASSIGNED' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;
  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    UPDATE public.orders
    SET courier_id = NULL, assigned_at = NULL, status_updated_at = now(), updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'dispatch_status', 'OFFERED');
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')))
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_order.pickup_lat) / 2), 2)
      + cos(radians(v_order.pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_order.pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    UPDATE public.orders
    SET courier_id = NULL, assigned_at = NULL, updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id AND da.courier_id = v_courier.id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, offered_at, expires_at)
    VALUES (p_order_id, v_courier.id, now(), now() + interval '5 minutes')
    RETURNING * INTO v_assignment;
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'OFFERED',
        offered_at = now(),
        expires_at = now() + interval '5 minutes',
        responded_at = NULL,
        rejection_reason = NULL
    WHERE id = v_assignment.id
    RETURNING * INTO v_assignment;
  END IF;

  UPDATE public.orders
  SET courier_id = NULL, assigned_at = NULL, status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.send_notification(
    v_courier.user_id,
    'Pesanan Kurir Baru',
    'Ada pesanan kurir baru di sekitar lokasi Anda',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'courier_id', v_courier.id, 'dispatch_status', 'OFFERED');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_courier_delivery_offers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
  v_offers jsonb;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  UPDATE public.delivery_assignments da
  SET expires_at = now() + interval '5 minutes'
  FROM public.orders o
  WHERE da.order_id = o.id
    AND da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at <= now()
    AND o.status = 'ASSIGNED';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', da.id,
    'order_id', da.order_id,
    'expires_at', da.expires_at,
    'orders', jsonb_build_object(
      'total', o.total,
      'shipping_cost', o.shipping_cost,
      'courier_earning_estimate', o.courier_earning_estimate,
      'courier_platform_fee', o.courier_platform_fee,
      'pickup_address', o.pickup_address,
      'pickup_lat', o.pickup_lat,
      'pickup_lng', o.pickup_lng,
      'delivery_name', o.delivery_name,
      'delivery_address', o.delivery_address,
      'delivery_lat', o.delivery_lat,
      'delivery_lng', o.delivery_lng,
      'notes', o.notes,
      'merchants', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('name', m.name, 'address', m.address) END
    )
  ) ORDER BY da.offered_at DESC), '[]'::jsonb)
  INTO v_offers
  FROM public.delivery_assignments da
  JOIN public.orders o ON o.id = da.order_id
  LEFT JOIN public.merchants m ON m.id = o.merchant_id
  WHERE da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
    AND o.status = 'ASSIGNED';

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.create_courier_order(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dispatch_courier_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_courier_order(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 73_20260917200000_courier_offer_authority_repair.sql =====

-- ===== BEGIN BUNDLE: 74_20260917201000_buyer_delivery_confirmation.sql =====
-- Authoritative buyer confirmation for delivered orders.
-- Buyers may only close an order that has already been marked DELIVERED.
CREATE OR REPLACE FUNCTION public.buyer_confirm_delivery(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'DELIVERED' THEN
    RAISE EXCEPTION 'Order can only be confirmed after delivery' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET status = 'DONE',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, 'DONE', auth.uid(), 'Dikonfirmasi oleh penerima');

  RETURN jsonb_build_object('order_id', p_order_id, 'from_status', v_order.status, 'to_status', 'DONE');
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_confirm_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_confirm_delivery(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 74_20260917201000_buyer_delivery_confirmation.sql =====

-- ===== BEGIN BUNDLE: 75_20260917203000_direct_courier_cancellation.sql =====
-- Direct courier bookings have a different cancellation lifecycle from marketplace orders.
-- Buyer may cancel while dispatch is searching or before pickup; after pickup use support/refund flow.
CREATE OR REPLACE FUNCTION public.buyer_cancel_order(
  p_order_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
  v_previous_status text;
  v_is_direct_courier boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF length(COALESCE(v_reason, '')) < 3 OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'Cancellation reason is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_previous_status := v_order.status;
  v_is_direct_courier := v_order.service_type = 'COURIER_DELIVERY'
    OR (v_order.merchant_id IS NULL AND v_order.pickup_address IS NOT NULL);

  IF v_is_direct_courier THEN
    IF v_previous_status NOT IN ('ASSIGNED', 'COURIER_ACCEPTED') THEN
      RAISE EXCEPTION 'Direct courier booking cannot be canceled after pickup' USING ERRCODE = '22023';
    END IF;

    UPDATE public.delivery_assignments
    SET status = 'CANCELED', responded_at = now(), rejection_reason = v_reason, updated_at = now()
    WHERE order_id = p_order_id AND status IN ('OFFERED', 'ACCEPTED');
  ELSE
    IF v_previous_status NOT IN ('NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION') THEN
      RAISE EXCEPTION 'Order cannot be canceled from status %', v_previous_status USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.orders
  SET status = 'CANCELED',
      courier_id = CASE WHEN v_is_direct_courier THEN NULL ELSE courier_id END,
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancellation_reason = v_reason,
      cancellation_type = 'BUYER',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_previous_status, 'CANCELED', auth.uid(), v_reason);

  IF v_is_direct_courier THEN
    PERFORM public.send_notification(
      c.user_id,
      'Pengiriman dibatalkan pemesan',
      'Pesanan kurir langsung telah dibatalkan sebelum pickup.',
      'order',
      '/courier/delivery'
    )
    FROM public.couriers c
    WHERE c.id = v_order.courier_id AND c.user_id IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'from_status', v_previous_status,
    'to_status', 'CANCELED',
    'service_type', CASE WHEN v_is_direct_courier THEN 'COURIER_DELIVERY' ELSE 'MARKETPLACE' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_cancel_order(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_cancel_order(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 75_20260917203000_direct_courier_cancellation.sql =====

-- ===== BEGIN BUNDLE: 76_20260917210000_courier_delivery_state_machine.sql =====
-- Direct courier state machine: all courier mutations are authorized, locked, and audited.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_proof_url text,
  ADD COLUMN IF NOT EXISTS delivery_notes text;

ALTER TABLE public.order_status_history
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('pod-images', 'pod-images', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Couriers upload delivery proof images" ON storage.objects;
CREATE POLICY "Couriers upload delivery proof images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED'
  )
);

DROP POLICY IF EXISTS "Couriers delete own delivery proof images" ON storage.objects;
CREATE POLICY "Couriers delete own delivery proof images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED'
  )
);

CREATE OR REPLACE FUNCTION public.courier_pickup_order(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status <> 'COURIER_ACCEPTED' THEN
    RAISE EXCEPTION 'Order is not ready for pickup' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders SET status = 'PICKED_UP', picked_up_at = now(), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, 'COURIER_ACCEPTED', 'PICKED_UP', auth.uid(), 'Kurir mengambil barang');
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_start_delivery(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT') THEN
    RAISE EXCEPTION 'Order is not ready for delivery' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders SET status = 'DELIVERING', status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, 'PICKED_UP', 'DELIVERING', auth.uid(), 'Kurir memulai pengantaran');
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_complete_delivery(p_order_id uuid, p_proof_path text, p_notes text DEFAULT NULL)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid; v_from_status text;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  IF NULLIF(trim(p_proof_path), '') IS NULL THEN RAISE EXCEPTION 'Proof of delivery is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED') THEN
    RAISE EXCEPTION 'Order is not ready to complete' USING ERRCODE = '22023';
  END IF;
  -- A lost network response may cause the courier to retry after the first
  -- request already committed. Return the completed order instead of failing.
  IF v_order.status = 'DELIVERED' THEN
    IF v_order.delivery_proof_url IS NULL THEN
      UPDATE public.orders SET delivery_proof_url = p_proof_path,
        delivery_notes = COALESCE(NULLIF(trim(p_notes), ''), delivery_notes),
        updated_at = now()
      WHERE id = p_order_id RETURNING * INTO v_order;
    END IF;
    RETURN v_order;
  END IF;
  v_from_status := v_order.status;
  UPDATE public.orders SET status = 'DELIVERED', delivered_at = now(), delivery_proof_url = p_proof_path,
    delivery_notes = NULLIF(trim(p_notes), ''), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (p_order_id, v_from_status, 'DELIVERED', auth.uid(), 'Kurir menyelesaikan pengiriman', jsonb_build_object('proof_path', p_proof_path));
  RETURN v_order;
END; $$;

REVOKE ALL ON FUNCTION public.courier_pickup_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_start_delivery(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_complete_delivery(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.courier_pickup_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_start_delivery(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_complete_delivery(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 76_20260917210000_courier_delivery_state_machine.sql =====

-- ===== BEGIN BUNDLE: 77_20260917213000_courier_offer_feed_runtime_repair.sql =====
-- Runtime repair for the courier offer feed used by /courier/deliveries.
-- The courier must be able to read an offer assigned to their account before acceptance.
CREATE OR REPLACE FUNCTION public.get_courier_delivery_offers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
  v_offers jsonb;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', da.id,
    'order_id', da.order_id,
    'expires_at', da.expires_at,
    'orders', jsonb_build_object(
      'total', o.total,
      'shipping_cost', o.shipping_cost,
      'courier_earning_estimate', o.courier_earning_estimate,
      'courier_platform_fee', o.courier_platform_fee,
      'pickup_address', o.pickup_address,
      'pickup_lat', o.pickup_lat,
      'pickup_lng', o.pickup_lng,
      'delivery_name', o.delivery_name,
      'delivery_address', o.delivery_address,
      'delivery_lat', o.delivery_lat,
      'delivery_lng', o.delivery_lng,
      'notes', o.notes,
      'merchants', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('name', m.name, 'address', m.address) END
    )
  ) ORDER BY da.offered_at DESC), '[]'::jsonb)
  INTO v_offers
  FROM public.delivery_assignments da
  JOIN public.orders o ON o.id = da.order_id
  LEFT JOIN public.merchants m ON m.id = o.merchant_id
  WHERE da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
    AND o.status = 'ASSIGNED';

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;

-- Keep the active delivery feed authoritative and independent from client-side
-- orders RLS joins. Acceptance still sets orders.courier_id; this function makes
-- the resulting active rows readable through one audited path.
CREATE OR REPLACE FUNCTION public.get_courier_active_deliveries()
RETURNS SETOF public.orders
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT o.*
  FROM public.orders o
  WHERE o.courier_id = v_courier_id
    AND o.service_type = 'COURIER_DELIVERY'
    AND o.status IN ('COURIER_ACCEPTED', 'PICKED_UP', 'DELIVERING')
  ORDER BY o.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_deliveries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_deliveries() TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 77_20260917213000_courier_offer_feed_runtime_repair.sql =====

-- ===== BEGIN BUNDLE: 77_20260918170000_pod_delivery_proof_policy.sql =====
-- Align POD storage access with the current orders.delivery_proof_url column.
-- The bucket configuration is intentionally not updated here: migration 76
-- already creates/configures pod-images, and avoiding a second relation lock
-- prevents a deadlock with concurrent storage metadata access. The bucket
-- remains private; clients must use createSignedUrl().

DROP POLICY IF EXISTS "POD images: read by order parties" ON storage.objects;
DROP POLICY IF EXISTS "POD images: read by delivery parties" ON storage.objects;
CREATE POLICY "POD images: read by delivery parties"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      LEFT JOIN public.couriers c ON c.id = o.courier_id
      WHERE o.delivery_proof_url IS NOT NULL
        AND (
          o.delivery_proof_url = storage.objects.name
          OR o.delivery_proof_url LIKE '%/' || storage.objects.name
          OR o.delivery_proof_url LIKE '%/pod-images/' || storage.objects.name
        )
        AND (
          o.buyer_id = auth.uid()
          OR m.user_id = auth.uid()
          OR c.user_id = auth.uid()
        )
    )
  )
);

DROP POLICY IF EXISTS "POD images: upload by courier or merchant" ON storage.objects;
DROP POLICY IF EXISTS "Couriers upload delivery proof images" ON storage.objects;
CREATE POLICY "Couriers upload delivery proof images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
  )
);

DROP POLICY IF EXISTS "Couriers delete own delivery proof images" ON storage.objects;
CREATE POLICY "Couriers delete own delivery proof images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
  )
);

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 77_20260918170000_pod_delivery_proof_policy.sql =====

