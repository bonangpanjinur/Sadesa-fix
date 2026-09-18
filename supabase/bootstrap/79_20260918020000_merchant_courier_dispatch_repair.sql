-- Repair merchant-originated courier dispatch. The previous frontend called
-- /api/assign-courier, but no such API exists in this application.
CREATE OR REPLACE FUNCTION public.dispatch_merchant_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_merchant_id uuid;
BEGIN
  SELECT m.id INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = auth.uid()
  LIMIT 1;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (public.is_admin() OR merchant_id = v_merchant_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.delivery_type <> 'INTERNAL' OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not an internal courier order' USING ERRCODE = '22023';
  END IF;
  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED') THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;
  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RAISE EXCEPTION 'Merchant pickup location is required' USING ERRCODE = '22023';
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'order_id', p_order_id,
      'assignment_id', v_assignment.id,
      'courier_id', v_assignment.courier_id,
      'dispatch_status', 'OFFERED'
    );
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')))
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_order.pickup_lat) / 2), 2)
      + cos(radians(v_order.pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_order.pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by, offered_at, expires_at)
  VALUES (p_order_id, v_courier.id, auth.uid(), now(), now() + interval '5 minutes')
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED', courier_id = NULL, assigned_at = NULL,
      status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (p_order_id, v_order.status, 'ASSIGNED', auth.uid(),
    'Tawaran courier dibuat dari order toko',
    jsonb_build_object('courier_id', v_courier.id, 'assignment_id', v_assignment.id));

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada pesanan toko baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'assignment_id', v_assignment.id,
    'courier_id', v_courier.id,
    'dispatch_status', 'OFFERED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_merchant_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_merchant_order(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
