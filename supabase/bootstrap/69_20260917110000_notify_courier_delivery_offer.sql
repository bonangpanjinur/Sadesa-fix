-- Notify the assigned courier when a merchant creates a delivery offer.
-- The offer is already visible in delivery_assignments, but without this
-- notification the courier has no reliable in-app signal to open the offer.

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
  WHERE order_id = p_order_id
    AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = p_courier_id,
      assigned_at = now(),
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir desa'
  );

  -- Keep notification creation inside the same transaction as the offer so
  -- the courier never receives a stale notification for a failed assignment.
  PERFORM public.send_notification(
    v_courier.user_id,
    'Pesanan Kurir Baru',
    'Ada tugas pengiriman baru. Buka notifikasi untuk melihat detail dan menerima pesanan.',
    'order',
    '/courier?orderId=' || p_order_id::text
  );

  RETURN v_assignment;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
