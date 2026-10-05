-- DesaMart canonical bootstrap bundle; generated from archive source migration.
-- Source range: 20261005123000_close_stale_transport_offers.sql .. 20261005123000_close_stale_transport_offers.sql

-- Close every competing transport offer when a ride/order is cancelled or accepted.
-- This keeps realtime clients and polling clients consistent: no stale offer can
-- reappear and restart the alarm after the transport decision is final.

CREATE OR REPLACE FUNCTION public.cancel_ride(p_ride_id uuid, p_reason text DEFAULT 'Dibatalkan oleh penumpang')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_driver_id uuid; v_updated integer;
BEGIN
  UPDATE public.ride_requests SET status = 'CANCELLED', cancelled_at = now(),
    cancellation_reason = left(NULLIF(btrim(COALESCE(p_reason, '')), ''), 500), updated_at = now()
  WHERE id = p_ride_id AND passenger_id = auth.uid() AND status IN ('SEARCHING', 'ACCEPTED')
  RETURNING driver_id INTO v_driver_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN RAISE EXCEPTION 'Ride is not available for cancellation' USING ERRCODE = '22023'; END IF;
  UPDATE public.ride_request_offers SET status = 'REJECTED', responded_at = COALESCE(responded_at, now())
  WHERE ride_id = p_ride_id AND status = 'PENDING';
  IF v_driver_id IS NOT NULL THEN
    PERFORM public.send_notification((SELECT user_id FROM public.couriers WHERE id = v_driver_id), 'Perjalanan Dibatalkan', 'Penumpang membatalkan perjalanan ojek', 'ride', '/courier/rides');
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_courier public.couriers%ROWTYPE; v_ride public.ride_requests%ROWTYPE; v_offer public.ride_request_offers%ROWTYPE; v_passenger_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(7210953184926001);
  SELECT * INTO v_courier FROM public.couriers WHERE id = p_courier_id AND user_id = auth.uid() FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Courier identity is invalid' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_ride FROM public.ride_requests WHERE id = p_ride_id AND status = 'SEARCHING' AND driver_id IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO v_offer FROM public.ride_request_offers WHERE ride_id = p_ride_id AND courier_id = p_courier_id AND status = 'PENDING' FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_offer.expires_at <= now() OR v_courier.registration_status <> 'APPROVED' OR v_courier.status <> 'ACTIVE' OR v_courier.is_available IS DISTINCT FROM true OR v_courier.last_location_update IS NULL OR v_courier.last_location_update < now() - interval '90 seconds' OR v_courier.current_lat IS NULL OR v_courier.current_lng IS NULL OR EXISTS (SELECT 1 FROM public.ride_requests active_ride WHERE active_ride.driver_id = p_courier_id AND active_ride.id <> p_ride_id AND active_ride.status IN ('ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')) THEN
    UPDATE public.ride_request_offers SET status = 'EXPIRED', responded_at = now() WHERE id = v_offer.id;
    PERFORM public.dispatch_next_ride_offer(p_ride_id); RETURN false;
  END IF;
  UPDATE public.ride_request_offers SET status = 'ACCEPTED', responded_at = now() WHERE id = v_offer.id;
  UPDATE public.ride_request_offers SET status = 'REJECTED', responded_at = COALESCE(responded_at, now()) WHERE ride_id = p_ride_id AND status = 'PENDING' AND id <> v_offer.id;
  UPDATE public.ride_requests SET driver_id = p_courier_id, status = 'ACCEPTED', accepted_at = now(), updated_at = now() WHERE id = p_ride_id AND status = 'SEARCHING' AND driver_id IS NULL RETURNING passenger_id INTO v_passenger_id;
  IF NOT FOUND THEN RETURN false; END IF;
  PERFORM public.send_notification(v_passenger_id, 'Driver Ditemukan!', 'Driver sedang menuju lokasi jemput Anda', 'ride', '/ride/' || p_ride_id::text);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_assignment public.delivery_assignments%ROWTYPE; v_order public.orders%ROWTYPE; v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id FROM public.couriers c WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not active' USING ERRCODE = '42501'; END IF;
  SELECT da.* INTO v_assignment FROM public.delivery_assignments da WHERE da.id = p_assignment_id AND da.courier_id = v_courier_id FOR UPDATE;
  IF NOT FOUND OR v_assignment.status <> 'OFFERED' OR v_assignment.expires_at < now() THEN RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_assignment.order_id FOR UPDATE;
  IF v_order.status IS DISTINCT FROM 'ASSIGNED' THEN RAISE EXCEPTION 'Order is no longer available' USING ERRCODE = '22023'; END IF;
  IF p_accept THEN
    UPDATE public.delivery_assignments SET status = 'ACCEPTED', responded_at = now(), updated_at = now() WHERE id = p_assignment_id RETURNING * INTO v_assignment;
    UPDATE public.delivery_assignments SET status = 'REJECTED', responded_at = COALESCE(responded_at, now()), updated_at = now(), rejection_reason = 'Pesanan sudah diambil kurir lain' WHERE order_id = v_order.id AND status = 'OFFERED' AND id <> p_assignment_id;
    UPDATE public.orders SET courier_id = v_courier_id, status = 'COURIER_ACCEPTED', assigned_at = COALESCE(assigned_at, now()), courier_accepted_at = now(), status_updated_at = now(), updated_at = now() WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason) VALUES (v_order.id, v_order.status, 'COURIER_ACCEPTED', auth.uid(), 'Kurir menerima pesanan');
  ELSE
    UPDATE public.delivery_assignments SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now() WHERE id = p_assignment_id RETURNING * INTO v_assignment;
    UPDATE public.orders SET courier_id = NULL, assigned_at = NULL, courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id), status = 'ASSIGNED', status_updated_at = now(), updated_at = now() WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason) VALUES (v_order.id, 'ASSIGNED', 'ASSIGNED', auth.uid(), COALESCE(p_reason, 'Kurir menolak pesanan'));
  END IF;
  RETURN v_assignment;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_ride(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid, boolean, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
