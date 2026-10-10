-- SaDesa courier background ride offers; source migration:
-- archive/supabase/migrations/20261010160000_courier_background_ride_offers.sql
DO $bootstrap_do_20261010160000_courier_background_ride_offers$
BEGIN
  EXECUTE $bootstrap_sql_dispatch$
    CREATE OR REPLACE FUNCTION public.dispatch_next_ride_offer(p_ride_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $dispatch_function$
    DECLARE
      v_ride public.ride_requests%ROWTYPE;
      v_current public.ride_request_offers%ROWTYPE;
      v_candidate record;
      v_offer_id uuid;
      v_title text := 'Permintaan ojek untuk Anda';
      v_message text;
    BEGIN
      PERFORM pg_advisory_xact_lock(7210953184926001);
      SELECT * INTO v_ride FROM public.ride_requests WHERE id = p_ride_id FOR UPDATE;
      IF NOT FOUND OR v_ride.status <> 'SEARCHING' OR v_ride.driver_id IS NOT NULL
         OR v_ride.pickup_lat IS NULL OR v_ride.pickup_lng IS NULL THEN
        RETURN NULL;
      END IF;

      SELECT * INTO v_current FROM public.ride_request_offers
      WHERE ride_id = p_ride_id AND status = 'PENDING'
      ORDER BY offered_at DESC LIMIT 1 FOR UPDATE;
      IF FOUND AND v_current.expires_at > now() THEN RETURN v_current.id; END IF;
      IF FOUND THEN
        UPDATE public.ride_request_offers
        SET status = 'EXPIRED', responded_at = COALESCE(responded_at, now())
        WHERE id = v_current.id;
      END IF;

      SELECT ranked.id, ranked.user_id, ranked.distance_km INTO v_candidate
      FROM (
        SELECT c.id, c.user_id,
          6371 * 2 * asin(sqrt(LEAST(1::double precision, GREATEST(0::double precision,
            power(sin(radians(c.current_lat::double precision - v_ride.pickup_lat::double precision) / 2), 2)
            + cos(radians(v_ride.pickup_lat::double precision)) * cos(radians(c.current_lat::double precision))
              * power(sin(radians(c.current_lng::double precision - v_ride.pickup_lng::double precision) / 2), 2)
          )))) AS distance_km
        FROM public.couriers c
        WHERE c.user_id IS NOT NULL AND c.registration_status = 'APPROVED'
          AND c.status = 'ACTIVE' AND c.is_available = true
          AND c.current_lat IS NOT NULL AND c.current_lng IS NOT NULL
          AND c.last_location_update >= now() - interval '5 minutes'
          AND NOT EXISTS (
            SELECT 1 FROM public.ride_requests active_ride
            WHERE active_ride.driver_id = c.id AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.ride_request_offers previous_offer
            WHERE previous_offer.ride_id = p_ride_id AND previous_offer.courier_id = c.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.ride_request_offers concurrent_offer
            WHERE concurrent_offer.courier_id = c.id AND concurrent_offer.ride_id <> p_ride_id
              AND concurrent_offer.status = 'PENDING' AND concurrent_offer.expires_at > now()
          )
      ) AS ranked
      ORDER BY ranked.distance_km ASC, ranked.id ASC LIMIT 1;

      IF NOT FOUND THEN
        UPDATE public.ride_requests SET updated_at = now() WHERE id = p_ride_id;
        RETURN NULL;
      END IF;

      INSERT INTO public.ride_request_offers (ride_id, courier_id, distance_km, status, offered_at, expires_at)
      VALUES (p_ride_id, v_candidate.id, v_candidate.distance_km, 'PENDING', now(), now() + interval '90 seconds')
      RETURNING id INTO v_offer_id;

      v_message := left(
        'Ada permintaan ojek baru untuk Anda. Jemput di: '
          || COALESCE(NULLIF(v_ride.pickup_address, ''), 'lokasi pembeli')
          || '. Terima atau tolak dalam 90 detik.',
        240
      );
      INSERT INTO public.notifications (user_id, title, message, type, link)
      VALUES (v_candidate.user_id, v_title, v_message, 'ride', '/courier/rides');
      INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
      VALUES (
        v_candidate.user_id, 'push', 'new_ride_request',
        jsonb_build_object(
          'title', v_title, 'body', v_message, 'url', '/courier/rides',
          'data', jsonb_build_object('type', 'new_ride_request', 'ride_id', p_ride_id::text, 'offer_id', v_offer_id::text)
        )
      );
      UPDATE public.ride_requests SET updated_at = now() WHERE id = p_ride_id;
      RETURN v_offer_id;
    END;
    $dispatch_function$
  $bootstrap_sql_dispatch$;

  REVOKE ALL ON FUNCTION public.dispatch_next_ride_offer(uuid) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.dispatch_next_ride_offer(uuid) TO service_role;
  COMMENT ON FUNCTION public.dispatch_next_ride_offer(uuid) IS
    'Offers each SEARCHING ride to the nearest eligible courier using last-known GPS up to five minutes old; accepting still requires fresh GPS.';

  EXECUTE $bootstrap_sql_courier_can_view_ride$
    CREATE OR REPLACE FUNCTION public.courier_can_view_ride(p_ride_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = pg_catalog, public
    SET row_security = off
    AS $courier_view_function$
      SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.ride_requests r
        WHERE r.id = p_ride_id AND (
          EXISTS (
            SELECT 1 FROM public.couriers assigned_courier
            WHERE assigned_courier.id = r.driver_id AND assigned_courier.user_id = auth.uid()
          )
          OR EXISTS (
            SELECT 1 FROM public.ride_request_offers offer
            JOIN public.couriers offered_courier ON offered_courier.id = offer.courier_id
            WHERE offer.ride_id = r.id AND offer.status = 'PENDING' AND offer.expires_at > now()
              AND offered_courier.user_id = auth.uid()
              AND offered_courier.registration_status = 'APPROVED'
              AND offered_courier.status = 'ACTIVE'
              AND offered_courier.is_available IS TRUE
              AND offered_courier.current_lat IS NOT NULL AND offered_courier.current_lng IS NOT NULL
              AND offered_courier.last_location_update >= now() - interval '5 minutes'
              AND r.status = 'SEARCHING' AND r.driver_id IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM public.ride_requests active_ride
                WHERE active_ride.driver_id = offered_courier.id
                  AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
              )
          )
        )
      );
    $courier_view_function$
  $bootstrap_sql_courier_can_view_ride$;

  REVOKE ALL ON FUNCTION public.courier_can_view_ride(uuid) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.courier_can_view_ride(uuid) TO authenticated;
  COMMENT ON FUNCTION public.courier_can_view_ride(uuid) IS
    'RLS-safe ride visibility: assigned history or an unexpired targeted offer; new offers may use last-known courier GPS up to five minutes old.';
  NOTIFY pgrst, 'reload schema';
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20261010160000_courier_background_ride_offers$;
