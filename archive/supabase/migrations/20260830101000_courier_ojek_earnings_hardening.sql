-- OJK-02/OJK-04: server-authoritative ride state transitions and earnings.
CREATE OR REPLACE FUNCTION public.transition_ride_status(
  p_ride_id uuid,
  p_to_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_fare integer;
  v_earning_id uuid;
  v_created_earning boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ride not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = v_ride.driver_id
    AND user_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ride transition denied' USING ERRCODE = '42501';
  END IF;

  IF p_to_status NOT IN ('PICKED_UP', 'IN_TRANSIT', 'COMPLETED') THEN
    RAISE EXCEPTION 'Invalid ride status' USING ERRCODE = '22023';
  END IF;
  IF NOT (
    (v_ride.status = 'ACCEPTED' AND p_to_status = 'PICKED_UP') OR
    (v_ride.status = 'PICKED_UP' AND p_to_status = 'IN_TRANSIT') OR
    (v_ride.status = 'IN_TRANSIT' AND p_to_status = 'COMPLETED')
  ) THEN
    RAISE EXCEPTION 'Ride transition from % to % is not allowed', v_ride.status, p_to_status USING ERRCODE = '55000';
  END IF;

  IF p_to_status = 'PICKED_UP' THEN
    UPDATE public.ride_requests
    SET status = p_to_status, picked_up_at = now()
    WHERE id = p_ride_id;
  ELSIF p_to_status = 'COMPLETED' THEN
    v_fare := COALESCE(v_ride.final_fare, v_ride.estimated_fare);
    IF v_fare IS NULL OR v_fare <= 0 THEN
      RAISE EXCEPTION 'Ride fare is invalid' USING ERRCODE = '22023';
    END IF;
    UPDATE public.ride_requests
    SET status = p_to_status, final_fare = v_fare, completed_at = now()
    WHERE id = p_ride_id;

    SELECT id INTO v_earning_id
    FROM public.courier_earnings
    WHERE courier_id = v_courier.id
      AND type = 'RIDE'
      AND order_id = p_ride_id
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.courier_earnings(courier_id, order_id, amount, type, status)
      VALUES (v_courier.id, p_ride_id, v_fare, 'RIDE', 'PENDING')
      RETURNING id INTO v_earning_id;
      v_created_earning := true;
      UPDATE public.couriers
      SET pending_balance = COALESCE(pending_balance, 0) + v_fare,
          updated_at = now()
      WHERE id = v_courier.id;
    END IF;
  ELSE
    UPDATE public.ride_requests
    SET status = p_to_status
    WHERE id = p_ride_id;
  END IF;

  PERFORM public.send_notification(
    v_ride.passenger_id,
    CASE p_to_status
      WHEN 'PICKED_UP' THEN 'Driver sudah menjemput'
      WHEN 'IN_TRANSIT' THEN 'Perjalanan dimulai'
      ELSE 'Perjalanan selesai'
    END,
    CASE p_to_status
      WHEN 'PICKED_UP' THEN 'Driver sudah tiba dan menjemput Anda.'
      WHEN 'IN_TRANSIT' THEN 'Anda sedang dalam perjalanan ke tujuan.'
      ELSE 'Perjalanan Anda telah selesai.'
    END,
    'ride',
    '/ride/' || p_ride_id::text
  );

  RETURN jsonb_build_object(
    'ride_id', p_ride_id,
    'status', p_to_status,
    'fare', CASE WHEN p_to_status = 'COMPLETED' THEN v_fare ELSE NULL END,
    'earning_id', v_earning_id,
    'earning_created', v_created_earning
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;
