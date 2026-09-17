-- Authoritative buyer confirmation for delivered orders.
-- Buyers may only close an order that has already been marked DELIVERED.
CREATE OR REPLACE FUNCTION public.buyer_confirm_delivery(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status <> 'DELIVERED' THEN
    RAISE EXCEPTION 'Order can only be confirmed after delivery' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET status = 'DONE',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, 'DONE', auth.uid(), 'Dikonfirmasi oleh penerima');

  RETURN jsonb_build_object('order_id', p_order_id, 'from_status', v_order.status, 'to_status', 'DONE');
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_confirm_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_confirm_delivery(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
