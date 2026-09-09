-- Remove the legacy 4-argument overload. PostgREST cannot reliably resolve
-- merchant_transition_order when both 3-arg and 4-arg (with defaults) exist.
DROP FUNCTION IF EXISTS public.merchant_transition_order(uuid, text, text, boolean);

CREATE OR REPLACE FUNCTION public.merchant_transition_order(p_order_id uuid, p_to_status text, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_allowed boolean := false;
  v_fee_percent numeric := 10;
  v_attempt integer;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_allowed := CASE
    WHEN p_to_status = 'PROCESSED' THEN v_order.status IN ('NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT') AND (v_order.payment_method = 'COD' OR v_order.payment_status = 'PAID')
    WHEN p_to_status = 'READY' THEN v_order.status = 'PROCESSED'
    WHEN p_to_status = 'ASSIGNED' THEN v_order.status IN ('PROCESSED', 'READY', 'ASSIGNED') AND NOT COALESCE(v_order.is_self_delivery, false)
    WHEN p_to_status = 'DELIVERING' THEN v_order.status IN ('READY', 'PROCESSED')
    WHEN p_to_status = 'DELIVERED' THEN v_order.status IN ('DELIVERING', 'PICKED_UP', 'SENT')
    WHEN p_to_status = 'DONE' THEN v_order.status = 'DELIVERED'
    WHEN p_to_status IN ('CANCELED', 'REJECTED') THEN v_order.status NOT IN ('DONE', 'DELIVERED', 'CANCELED', 'REFUNDED')
    ELSE false
  END;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid order transition from % to %', v_order.status, p_to_status USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'DELIVERING' THEN
    v_attempt := COALESCE(v_order.self_delivery_attempt, 0) + 1;
    UPDATE public.orders SET
      is_self_delivery = true,
      self_delivery_attempt = v_attempt,
      status = p_to_status,
      status_updated_at = now(),
      delivered_at = NULL,
      updated_at = now()
    WHERE id = p_order_id;
    IF v_attempt > 2 THEN
      SELECT COALESCE((value->>'percent')::numeric, 10) INTO v_fee_percent
      FROM public.app_settings WHERE key = 'self_delivery_fee';
      INSERT INTO public.merchant_delivery_fee_ledger(merchant_id, order_id, attempt_number, basis_amount, percent_snapshot, fee_amount, status)
      VALUES (v_order.merchant_id, p_order_id, v_attempt, COALESCE(v_order.shipping_cost, 0), v_fee_percent, ROUND(COALESCE(v_order.shipping_cost, 0) * v_fee_percent / 100, 0), 'DUE')
      ON CONFLICT (order_id) DO NOTHING;
      UPDATE public.orders SET self_delivery_fee_amount = ROUND(COALESCE(v_order.shipping_cost, 0) * v_fee_percent / 100, 0), self_delivery_fee_status = 'DUE' WHERE id = p_order_id;
    END IF;
  ELSE
    UPDATE public.orders SET
      status = p_to_status,
      status_updated_at = now(),
      confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
      delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
      updated_at = now()
    WHERE id = p_order_id;
  END IF;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, p_to_status, auth.uid(), NULLIF(trim(p_reason), ''));
  RETURN jsonb_build_object('order_id', p_order_id, 'from_status', v_order.status, 'to_status', p_to_status);
END; $$;

GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
