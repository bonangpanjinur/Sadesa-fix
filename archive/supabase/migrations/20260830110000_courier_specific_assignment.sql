-- OJK-13: atomically assign a specific courier from an authorized merchant/admin.
CREATE OR REPLACE FUNCTION public.assign_specific_courier(
  p_order_id uuid,
  p_courier_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_active_orders integer;
  v_courier_user_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR p_courier_id IS NULL THEN
    RAISE EXCEPTION 'Order and courier are required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = v_order.merchant_id AND m.user_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'Not allowed to assign this order' USING ERRCODE = '42501';
  END IF;

  IF v_order.courier_id IS NOT NULL THEN
    RAISE EXCEPTION 'Order already has courier assigned' USING ERRCODE = '23505';
  END IF;
  IF v_order.status NOT IN ('PROCESSING', 'PROCESSED', 'READY') THEN
    RAISE EXCEPTION 'Order status cannot be assigned to a courier' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
  FOR UPDATE;
  IF NOT FOUND OR v_courier.status <> 'ACTIVE'
     OR v_courier.registration_status <> 'APPROVED'
     OR v_courier.is_available IS NOT TRUE
     OR v_courier.last_location_update IS NULL
     OR v_courier.last_location_update < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_active_orders
  FROM public.orders
  WHERE courier_id = p_courier_id
    AND status IN ('ASSIGNED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING');
  IF v_active_orders >= 3 THEN
    RAISE EXCEPTION 'Courier capacity is full' USING ERRCODE = '55000';
  END IF;

  UPDATE public.orders
  SET courier_id = p_courier_id,
      status = 'ASSIGNED',
      assigned_at = now(),
      updated_at = now()
  WHERE id = p_order_id AND courier_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order was assigned by another request' USING ERRCODE = '40001';
  END IF;

  v_courier_user_id := v_courier.user_id;
  IF v_courier_user_id IS NOT NULL THEN
    INSERT INTO public.notifications(user_id, title, message, type, link)
    VALUES (
      v_courier_user_id,
      'Pesanan Baru Ditugaskan',
      'Anda mendapat pesanan baru #' || upper(left(p_order_id::text, 8)) || '. Segera ambil pesanan.',
      'order',
      '/courier'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'courier_id', p_courier_id,
    'status', 'ASSIGNED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.assign_specific_courier(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_specific_courier(uuid, uuid) TO authenticated;
