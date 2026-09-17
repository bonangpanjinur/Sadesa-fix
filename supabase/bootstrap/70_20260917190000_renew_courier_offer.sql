-- Keep a still-pending courier offer visible when a courier dashboard was offline.
-- The courier may renew only their own offer and only while the order is ASSIGNED.
CREATE OR REPLACE FUNCTION public.renew_delivery_offer(p_assignment_id uuid)
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
    AND c.registration_status = 'APPROVED';

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.id = p_assignment_id
    AND da.courier_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND OR v_assignment.status <> 'OFFERED' THEN
    RAISE EXCEPTION 'Offer is no longer available' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = v_assignment.order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.status <> 'ASSIGNED' THEN
    RAISE EXCEPTION 'Order is no longer waiting for a courier' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET expires_at = GREATEST(expires_at, now()) + interval '5 minutes'
  WHERE id = p_assignment_id
  RETURNING * INTO v_assignment;

  RETURN v_assignment;
END;
$$;

REVOKE ALL ON FUNCTION public.renew_delivery_offer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.renew_delivery_offer(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
