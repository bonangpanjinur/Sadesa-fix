-- OJK-01: bind ride acceptance to the authenticated courier.
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_updated integer;
  v_active_rides integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
    AND user_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND
     OR v_courier.registration_status <> 'APPROVED'
     OR v_courier.status <> 'ACTIVE'
     OR v_courier.is_available IS NOT TRUE THEN
    RAISE EXCEPTION 'Courier is not eligible to accept rides' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_active_rides
  FROM public.ride_requests
  WHERE driver_id = v_courier.id
    AND status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT');

  IF v_active_rides >= 1 THEN
    RAISE EXCEPTION 'Courier already has an active ride' USING ERRCODE = '55000';
  END IF;

  UPDATE public.ride_requests
  SET driver_id = v_courier.id,
      status = 'ACCEPTED',
      accepted_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN false;
  END IF;

  PERFORM public.send_notification(
    passenger_id,
    'Driver Ditemukan!',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  )
  FROM public.ride_requests
  WHERE id = p_ride_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_ride(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;
