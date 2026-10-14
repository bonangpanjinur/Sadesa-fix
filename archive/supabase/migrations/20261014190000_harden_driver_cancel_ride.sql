-- Driver cancellation hardening.
-- Cancellation is only allowed before pickup. Once the passenger is picked up,
-- the driver must use the support/incident flow instead of abandoning the ride.
CREATE OR REPLACE FUNCTION public.driver_cancel_ride(p_ride_id uuid, p_reason text)
RETURNS public.ride_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
  v_reason text := NULLIF(left(btrim(COALESCE(p_reason, '')), 500), '');
BEGIN
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Cancellation reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid()
    AND status = 'ACTIVE'
    AND registration_status = 'APPROVED'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Courier is not active or approved' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id
    AND driver_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ride access denied' USING ERRCODE = '42501';
  END IF;

  -- A driver may cancel only before the passenger is picked up. After pickup,
  -- rejecting the request would strand a passenger without an operational
  -- incident/reassignment decision.
  IF v_ride.status <> 'ACCEPTED' THEN
    RAISE EXCEPTION 'Driver cancellation is only allowed before pickup; contact support for an in-flight incident'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.ride_requests
  SET status = 'CANCELED',
      cancelled_at = now(),
      cancellation_reason = v_reason,
      updated_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  PERFORM public.send_notification(
    v_ride.passenger_id,
    'Perjalanan dibatalkan driver',
    'Driver membatalkan perjalanan sebelum penjemputan: ' || v_reason,
    'ride',
    '/ride/' || p_ride_id::text
  );

  RETURN v_ride;
END;
$$;

REVOKE ALL ON FUNCTION public.driver_cancel_ride(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_cancel_ride(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
