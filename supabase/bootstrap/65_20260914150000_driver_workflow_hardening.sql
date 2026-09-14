-- Driver workflow hardening: explicit pickup/earning contract and safe release actions.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_earning_estimate integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_released_at timestamptz,
  ADD COLUMN IF NOT EXISTS courier_release_reason text;

UPDATE public.orders
SET courier_earning_estimate = shipping_cost,
    courier_platform_fee = 0
WHERE courier_earning_estimate = 0 AND shipping_cost > 0;

CREATE OR REPLACE FUNCTION public.courier_release_order(p_order_id uuid, p_reason text)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_from_status text;
  v_reason text := NULLIF(left(btrim(p_reason), 500), '');
BEGIN
  IF v_reason IS NULL THEN RAISE EXCEPTION 'Release reason is required' USING ERRCODE = '22023'; END IF;
  SELECT id INTO v_courier_id FROM public.couriers WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED' LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND courier_id = v_courier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501'; END IF;
  IF v_order.status NOT IN ('COURIER_ACCEPTED','PICKED_UP','SENT','DELIVERING') THEN
    RAISE EXCEPTION 'Order cannot be released from status %', v_order.status USING ERRCODE = '22023';
  END IF;
  v_from_status := v_order.status;
  UPDATE public.delivery_assignments SET status = 'CANCELED', responded_at = now(), rejection_reason = v_reason, updated_at = now()
    WHERE order_id = p_order_id AND courier_id = v_courier_id AND status = 'ACCEPTED';
  UPDATE public.orders SET courier_id = NULL, status = 'ASSIGNED', courier_released_at = now(), courier_release_reason = v_reason, status_updated_at = now(), updated_at = now()
    WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (p_order_id, v_from_status, 'ASSIGNED', auth.uid(), 'Kurir melepas tugas: ' || v_reason);
  IF v_order.buyer_id IS NOT NULL THEN
    PERFORM public.send_notification(v_order.buyer_id, 'Pesanan perlu kurir baru', 'Kurir melepas tugas: ' || v_reason, 'order', '/orders/' || p_order_id::text);
  END IF;
  IF v_order.merchant_id IS NOT NULL THEN
    PERFORM public.send_notification(m.user_id, 'Kurir melepas pesanan', 'Pesanan dikembalikan untuk penugasan ulang.', 'order', '/merchant/orders')
      FROM public.merchants m WHERE m.id = v_order.merchant_id AND m.user_id IS NOT NULL;
  END IF;
  RETURN v_order;
END; $$;

GRANT EXECUTE ON FUNCTION public.courier_release_order(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.driver_cancel_ride(p_ride_id uuid, p_reason text)
RETURNS public.ride_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
  v_reason text := NULLIF(left(btrim(p_reason), 500), '');
BEGIN
  IF v_reason IS NULL THEN RAISE EXCEPTION 'Cancellation reason is required' USING ERRCODE = '22023'; END IF;
  SELECT id INTO v_courier_id FROM public.couriers WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED' LIMIT 1;
  SELECT * INTO v_ride FROM public.ride_requests WHERE id = p_ride_id AND driver_id = v_courier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ride access denied' USING ERRCODE = '42501'; END IF;
  IF v_ride.status NOT IN ('ACCEPTED','PICKED_UP','IN_TRANSIT') THEN RAISE EXCEPTION 'Ride cannot be canceled from status %', v_ride.status USING ERRCODE = '22023'; END IF;
  UPDATE public.ride_requests SET status = 'CANCELED', cancelled_at = now(), cancellation_reason = v_reason, updated_at = now() WHERE id = p_ride_id RETURNING * INTO v_ride;
  IF v_ride.passenger_id IS NOT NULL THEN
    PERFORM public.send_notification(v_ride.passenger_id, 'Perjalanan dibatalkan driver', 'Driver membatalkan perjalanan: ' || v_reason, 'ride', '/ride/' || p_ride_id::text);
  END IF;
  RETURN v_ride;
END; $$;
GRANT EXECUTE ON FUNCTION public.driver_cancel_ride(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
