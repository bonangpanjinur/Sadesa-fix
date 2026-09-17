-- Keep assignment and acceptance separate.
-- ASSIGNED means an offer was sent to a courier; COURIER_ACCEPTED means
-- the courier explicitly accepted it.

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED')
     OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;

  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.id = p_courier_id
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  -- Do not put the courier on the order yet. The courier_id and assigned_at
  -- fields become authoritative only after respond_delivery_offer(true).
  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = NULL,
      assigned_at = NULL,
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir; menunggu keputusan kurir',
    jsonb_build_object('courier_id', p_courier_id, 'assignment_id', v_assignment.id)
  );

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada tawaran pengiriman baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/rides?orderId=' || p_order_id::text
  );

  RETURN v_assignment;
END;
$$;

CREATE OR REPLACE FUNCTION public.merchant_offer_order_to_courier(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.create_delivery_offer(p_order_id, p_courier_id);
END;
$$;

-- Acceptance is the only operation that makes the courier authoritative.
CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assignment public.delivery_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

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
    SET courier_id = v_courier_id,
        status = 'COURIER_ACCEPTED',
        assigned_at = COALESCE(assigned_at, now()),
        courier_accepted_at = now(),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'COURIER_ACCEPTED', auth.uid(), 'Kurir menerima pesanan');
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;

    UPDATE public.orders
    SET courier_id = NULL,
        assigned_at = NULL,
        courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id),
        status = 'ASSIGNED',
        status_updated_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, 'ASSIGNED', 'ASSIGNED', auth.uid(), COALESCE(p_reason, 'Kurir menolak pesanan'));
  END IF;

  RETURN v_assignment;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid, boolean, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
