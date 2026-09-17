-- Retry courier dispatch for bookings that remain ASSIGNED without a visible offer.
-- This is idempotent: an active offer is reused; expired offers are reopened.
CREATE OR REPLACE FUNCTION public.dispatch_courier_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (buyer_id = auth.uid() OR public.is_admin())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'ASSIGNED' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
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
    UPDATE public.orders
    SET courier_id = v_assignment.courier_id,
        assigned_at = COALESCE(assigned_at, now()),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'dispatch_status', 'OFFERED');
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

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id AND da.courier_id = v_courier.id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, offered_at, expires_at)
    VALUES (p_order_id, v_courier.id, now(), now() + interval '5 minutes')
    RETURNING * INTO v_assignment;
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'OFFERED', offered_at = now(), expires_at = now() + interval '5 minutes', responded_at = NULL, rejection_reason = NULL
    WHERE id = v_assignment.id
    RETURNING * INTO v_assignment;
  END IF;

  -- The courier must be associated with the order before acceptance so the
  -- courier-side orders RLS policy can expose the nested order payload.
  UPDATE public.orders
  SET courier_id = v_courier.id,
      assigned_at = COALESCE(assigned_at, now()),
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.send_notification(
    v_courier.user_id,
    'Pesanan Kurir Baru',
    'Ada pesanan kurir baru di sekitar lokasi Anda',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'courier_id', v_courier.id, 'dispatch_status', 'OFFERED');
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_courier_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
