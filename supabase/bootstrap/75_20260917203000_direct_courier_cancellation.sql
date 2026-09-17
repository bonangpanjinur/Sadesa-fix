-- Direct courier bookings have a different cancellation lifecycle from marketplace orders.
-- Buyer may cancel while dispatch is searching or before pickup; after pickup use support/refund flow.
CREATE OR REPLACE FUNCTION public.buyer_cancel_order(
  p_order_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
  v_previous_status text;
  v_is_direct_courier boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF length(COALESCE(v_reason, '')) < 3 OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'Cancellation reason is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_previous_status := v_order.status;
  v_is_direct_courier := v_order.service_type = 'COURIER_DELIVERY'
    OR (v_order.merchant_id IS NULL AND v_order.pickup_address IS NOT NULL);

  IF v_is_direct_courier THEN
    IF v_previous_status NOT IN ('ASSIGNED', 'COURIER_ACCEPTED') THEN
      RAISE EXCEPTION 'Direct courier booking cannot be canceled after pickup' USING ERRCODE = '22023';
    END IF;

    UPDATE public.delivery_assignments
    SET status = 'CANCELED', responded_at = now(), rejection_reason = v_reason, updated_at = now()
    WHERE order_id = p_order_id AND status IN ('OFFERED', 'ACCEPTED');
  ELSE
    IF v_previous_status NOT IN ('NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION') THEN
      RAISE EXCEPTION 'Order cannot be canceled from status %', v_previous_status USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.orders
  SET status = 'CANCELED',
      courier_id = CASE WHEN v_is_direct_courier THEN NULL ELSE courier_id END,
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancellation_reason = v_reason,
      cancellation_type = 'BUYER',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_previous_status, 'CANCELED', auth.uid(), v_reason);

  IF v_is_direct_courier THEN
    PERFORM public.send_notification(
      c.user_id,
      'Pengiriman dibatalkan pemesan',
      'Pesanan kurir langsung telah dibatalkan sebelum pickup.',
      'order',
      '/courier/delivery'
    )
    FROM public.couriers c
    WHERE c.id = v_order.courier_id AND c.user_id IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'from_status', v_previous_status,
    'to_status', 'CANCELED',
    'service_type', CASE WHEN v_is_direct_courier THEN 'COURIER_DELIVERY' ELSE 'MARKETPLACE' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_cancel_order(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_cancel_order(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
