-- Phase 1: make passenger ride mutations server-authoritative.
-- Safe to replay after the existing ride schema and transition RPC migrations.

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
SET search_path = public
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

-- Preserve the existing signature for older clients, but bind the courier to auth.uid().
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_passenger_id uuid;
  v_updated integer;
BEGIN
  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
    AND user_id = auth.uid()
    AND registration_status = 'APPROVED'
    AND status = 'ACTIVE'
    AND is_available = true
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier identity is invalid or unavailable' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL
  RETURNING passenger_id INTO v_passenger_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
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

CREATE OR REPLACE FUNCTION public.cancel_ride(p_ride_id uuid, p_reason text DEFAULT 'Dibatalkan oleh penumpang')
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id uuid;
  v_updated integer;
BEGIN
  UPDATE public.ride_requests
  SET status = 'CANCELLED',
      cancelled_at = now(),
      cancellation_reason = left(NULLIF(btrim(COALESCE(p_reason, '')), ''), 500),
      updated_at = now()
  WHERE id = p_ride_id
    AND passenger_id = auth.uid()
    AND status IN ('SEARCHING', 'ACCEPTED')
  RETURNING driver_id INTO v_driver_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Ride is not available for cancellation' USING ERRCODE = '22023';
  END IF;

  IF v_driver_id IS NOT NULL THEN
    PERFORM public.send_notification(
      (SELECT user_id FROM public.couriers WHERE id = v_driver_id),
      'Perjalanan Dibatalkan',
      'Penumpang membatalkan perjalanan ojek',
      'ride',
      '/courier/rides'
    );
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_ride_rating(
  p_ride_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '22023';
  END IF;

  UPDATE public.ride_requests
  SET rating = p_rating,
      rating_comment = NULLIF(left(btrim(COALESCE(p_comment, '')), 500), ''),
      updated_at = now()
  WHERE id = p_ride_id
    AND passenger_id = auth.uid()
    AND status = 'COMPLETED'
    AND rating IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Ride is not eligible for rating or has already been rated' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object('ride_id', p_ride_id, 'rating', p_rating);
END;
$$;

-- All sensitive ride mutations now go through the RPCs above.
REVOKE INSERT, UPDATE ON public.ride_requests FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_ride_request(numeric, numeric, text, numeric, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_ride(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_ride_rating(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
