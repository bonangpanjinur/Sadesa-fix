-- DesaMart canonical bootstrap bundle; generated from archive source migration.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260929160000_ride_requests_rls_recursion_fix.sql .. 20260929160000_ride_requests_rls_recursion_fix.sql

-- ===== BEGIN SOURCE: 20260929160000_ride_requests_rls_recursion_fix.sql =====
-- Repair ride request visibility without self-referencing RLS policies.
-- Older courier policies remain permissive OR branches unless explicitly removed.

-- Preserve the established RPC signature and fare calculation, while making
-- the one-active-ride-per-passenger rule atomic across tabs/devices.
CREATE OR REPLACE FUNCTION public.create_ride_request(
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_pickup_address text,
  p_destination_lat numeric,
  p_destination_lng numeric,
  p_destination_address text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_distance numeric;
  v_settings jsonb;
  v_base numeric;
  v_per_km numeric;
  v_min numeric;
  v_max numeric;
  v_fare numeric;
  v_ride_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF p_pickup_lat NOT BETWEEN -90 AND 90 OR p_destination_lat NOT BETWEEN -90 AND 90
     OR p_pickup_lng NOT BETWEEN -180 AND 180 OR p_destination_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid ride coordinates' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_pickup_address, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_destination_address, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Pickup and destination addresses are required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('ride_create_request:' || auth.uid()::text, 0)
  );
  IF EXISTS (
    SELECT 1
    FROM public.ride_requests active_ride
    WHERE active_ride.passenger_id = auth.uid()
      AND active_ride.status IN ('SEARCHING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
  ) THEN
    RAISE EXCEPTION 'Passenger already has an active ride' USING ERRCODE = '23505';
  END IF;

  v_distance := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2)
    + cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat))
    * power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2)
  ));
  IF v_distance IS NULL OR v_distance <= 0 OR v_distance > 10 THEN
    RAISE EXCEPTION 'Ride distance must be greater than 0 and no more than 10 km' USING ERRCODE = '22023';
  END IF;

  SELECT value INTO v_settings
  FROM public.app_settings
  WHERE key = 'ride_fare_settings';
  v_base := COALESCE((v_settings->>'base_fare')::numeric, 5000);
  v_per_km := COALESCE((v_settings->>'per_km_fare')::numeric, 3000);
  v_min := COALESCE((v_settings->>'min_fare')::numeric, 5000);
  v_max := COALESCE((v_settings->>'max_fare')::numeric, 100000);
  v_fare := LEAST(v_max, GREATEST(v_min, round(v_base + v_distance * v_per_km)));

  INSERT INTO public.ride_requests (
    passenger_id, pickup_lat, pickup_lng, pickup_address,
    destination_lat, destination_lng, destination_address,
    distance_km, estimated_fare, status
  ) VALUES (
    auth.uid(), p_pickup_lat, p_pickup_lng, left(btrim(p_pickup_address), 500),
    p_destination_lat, p_destination_lng, left(btrim(p_destination_address), 500),
    round(v_distance, 2), v_fare, 'SEARCHING'
  )
  RETURNING id INTO v_ride_id;
  RETURN v_ride_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_ride_request(numeric, numeric, text, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ride_request(numeric, numeric, text, numeric, numeric, text) TO authenticated;
COMMENT ON FUNCTION public.create_ride_request(numeric, numeric, text, numeric, numeric, text) IS
  'Creates a ride with the canonical fare rules and serializes per-passenger active-ride checks.';

CREATE OR REPLACE FUNCTION public.courier_can_view_ride(p_ride_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
SET row_security = off
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.ride_requests r
    WHERE r.id = p_ride_id
      AND (
        -- Couriers retain access to their own assigned ride history.
        EXISTS (
          SELECT 1
          FROM public.couriers assigned_courier
          WHERE assigned_courier.id = r.driver_id
            AND assigned_courier.user_id = auth.uid()
        )
        OR
        -- A courier may read a SEARCHING ride only while holding its live offer.
        EXISTS (
          SELECT 1
          FROM public.ride_request_offers offer
          JOIN public.couriers offered_courier
            ON offered_courier.id = offer.courier_id
          WHERE offer.ride_id = r.id
            AND offer.status = 'PENDING'
            AND offer.expires_at > now()
            AND offered_courier.user_id = auth.uid()
            AND offered_courier.registration_status = 'APPROVED'
            AND offered_courier.status = 'ACTIVE'
            AND offered_courier.is_available IS TRUE
            AND offered_courier.current_lat IS NOT NULL
            AND offered_courier.current_lng IS NOT NULL
            AND offered_courier.last_location_update >= now() - interval '90 seconds'
            AND r.status = 'SEARCHING'
            AND r.driver_id IS NULL
            AND NOT EXISTS (
              SELECT 1
              FROM public.ride_requests active_ride
              WHERE active_ride.driver_id = offered_courier.id
                AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
            )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.courier_can_view_ride(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.courier_can_view_ride(uuid) TO authenticated;
COMMENT ON FUNCTION public.courier_can_view_ride(uuid) IS
  'RLS-safe ride visibility: assigned history or a live targeted offer; runs as definer to avoid recursive ride_requests policies.';

-- Remove all historical courier SELECT policy names. PostgreSQL combines
-- permissive policies with OR, so leaving an older SEARCHING policy would
-- bypass the targeted-offer contract even after adding the new policy.
DROP POLICY IF EXISTS "Drivers can view searching rides" ON public.ride_requests;
DROP POLICY IF EXISTS "Couriers can view searching rides" ON public.ride_requests;
DROP POLICY IF EXISTS "Drivers can view assigned rides" ON public.ride_requests;
DROP POLICY IF EXISTS "Drivers can view their assigned rides" ON public.ride_requests;
DROP POLICY IF EXISTS "Couriers can view assigned rides" ON public.ride_requests;
DROP POLICY IF EXISTS "Couriers can view assigned or targeted rides" ON public.ride_requests;

CREATE POLICY "Couriers can view assigned or targeted rides"
  ON public.ride_requests
  FOR SELECT TO authenticated
  USING (public.courier_can_view_ride(id));

NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260929160000_ride_requests_rls_recursion_fix.sql =====

DO $bootstrap_do_ride_requests_rls_recursion_fix$
BEGIN
  NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE;
END;
$bootstrap_do_ride_requests_rls_recursion_fix$;
