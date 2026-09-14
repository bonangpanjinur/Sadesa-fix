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
