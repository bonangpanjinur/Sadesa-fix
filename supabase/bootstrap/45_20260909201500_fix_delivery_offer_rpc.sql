-- Fix Kurir Desa offer RPC compatibility after workflow hardening.
-- The merchant UI can offer a courier directly from PROCESSED; the courier must
-- then accept or reject before the order becomes COURIER_ACCEPTED.

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED') OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;
  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.id = p_courier_id
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
      AND c.is_available = true
  ) THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id)
  VALUES (p_order_id, p_courier_id)
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED', courier_id = p_courier_id, assigned_at = now(), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, 'ASSIGNED', auth.uid(), 'Tawaran dikirim ke kurir desa');
  RETURN v_assignment;
END; $$;

CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_assignment public.delivery_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid();
  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.id = p_assignment_id AND da.courier_id = v_courier_id
  FOR UPDATE;
  IF NOT FOUND OR v_assignment.status <> 'OFFERED' OR v_assignment.expires_at < now() THEN
    RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_assignment.order_id FOR UPDATE;
  IF p_accept THEN
    UPDATE public.delivery_assignments
    SET status = 'ACCEPTED', responded_at = now(), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;
    UPDATE public.orders
    SET courier_id = v_courier_id, status = 'COURIER_ACCEPTED', courier_accepted_at = now(), status_updated_at = now(), updated_at = now()
    WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'COURIER_ACCEPTED', auth.uid(), 'Kurir menerima pesanan');
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;
    UPDATE public.orders
    SET courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id), status = 'ASSIGNED', status_updated_at = now(), updated_at = now()
    WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'ASSIGNED', auth.uid(), COALESCE(p_reason, 'Kurir menolak pesanan'));
  END IF;
  RETURN v_assignment;
END; $$;

GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid, boolean, text) TO authenticated;
NOTIFY pgrst, 'reload schema';

-- Couriers must advance their assigned orders through a server-side transition.
CREATE OR REPLACE FUNCTION public.courier_transition_order(p_order_id uuid, p_to_status text)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_allowed boolean := false;
  v_from_status text;
BEGIN
  SELECT c.id INTO v_courier_id FROM public.couriers c WHERE c.user_id = auth.uid();
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.courier_id IS DISTINCT FROM v_courier_id THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  v_allowed := (v_order.status = 'COURIER_ACCEPTED' AND p_to_status = 'PICKED_UP')
    OR (v_order.status = 'PICKED_UP' AND p_to_status = 'SENT')
    OR (v_order.status IN ('SENT', 'DELIVERING') AND p_to_status = 'DELIVERED');
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid courier transition: % -> %', v_order.status, p_to_status USING ERRCODE = '22023';
  END IF;
  v_from_status := v_order.status;
  UPDATE public.orders SET
    status = p_to_status,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    status_updated_at = now(),
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from_status, p_to_status, auth.uid(), 'Pembaruan status oleh kurir');
  RETURN v_order;
END; $$;
GRANT EXECUTE ON FUNCTION public.courier_transition_order(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
