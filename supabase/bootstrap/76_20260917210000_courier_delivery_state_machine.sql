-- Direct courier state machine: all courier mutations are authorized, locked, and audited.
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
     OR v_order.status NOT IN ('PICKED_UP', 'SENT', 'DELIVERING') THEN
    RAISE EXCEPTION 'Order is not ready to complete' USING ERRCODE = '22023';
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
