-- Self-delivery lifecycle hardening: make retries idempotent and keep the fee
-- ledger aligned when an in-flight delivery is canceled or refunded.

CREATE OR REPLACE FUNCTION public.sync_self_delivery_fee_ledger_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IN ('CANCELED', 'REFUNDED')
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.merchant_delivery_fee_ledger
    SET status = 'WAIVED'
    WHERE order_id = NEW.id
      AND status = 'DUE';

    UPDATE public.orders
    SET self_delivery_fee_status = 'WAIVED',
        updated_at = now()
    WHERE id = NEW.id
      AND self_delivery_fee_status = 'DUE';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_self_delivery_fee_ledger_lifecycle ON public.orders;
CREATE TRIGGER sync_self_delivery_fee_ledger_lifecycle
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_self_delivery_fee_ledger_lifecycle();

CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_from text;
  v_allowed boolean := false;
  v_fee_percent numeric := 0;
  v_fee_enabled boolean := false;
  v_fee_amount numeric := 0;
  v_fee_status text := 'WAIVED';
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = auth.uid()
  LIMIT 1;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_from := v_order.status;

  -- A client retry after the first transaction committed must be harmless.
  -- Do not add another history row or increment the attempt counter.
  IF p_to_status = 'DELIVERING'
     AND v_from = 'DELIVERING'
     AND COALESCE(v_order.is_self_delivery, false) THEN
    RETURN v_order;
  END IF;

  v_allowed := CASE
    WHEN v_from IN ('NEW', 'PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED', 'CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PENDING_PAYMENT' AND p_to_status IN ('CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status IN ('READY', 'DELIVERING', 'ASSIGNED', 'CANCELED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION' THEN true
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'READY' AND p_to_status = 'DONE' AND v_order.delivery_type = 'PICKUP' THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from = 'DELIVERING' AND COALESCE(v_order.is_self_delivery, false) AND p_to_status = 'CANCELED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000';
  END IF;

  IF p_to_status = 'DELIVERING' THEN
    IF v_order.delivery_type <> 'INTERNAL' OR COALESCE(v_order.is_self_delivery, false) THEN
      RAISE EXCEPTION 'Order is not eligible for self delivery' USING ERRCODE = '22023';
    END IF;

    SELECT
      GREATEST(0, LEAST(100, COALESCE((value->>'percent')::numeric, 0))),
      COALESCE((value->>'enabled')::boolean, false)
    INTO v_fee_percent, v_fee_enabled
    FROM public.app_settings
    WHERE key = 'self_delivery_fee';

    v_fee_amount := ROUND(COALESCE(v_order.shipping_cost, 0) * v_fee_percent / 100, 0);
    v_fee_status := CASE WHEN v_fee_enabled AND v_fee_amount > 0 THEN 'DUE' ELSE 'WAIVED' END;

    UPDATE public.orders
    SET is_self_delivery = true,
        self_delivery_attempt = COALESCE(self_delivery_attempt, 0) + 1,
        self_delivery_fee_amount = v_fee_amount,
        self_delivery_fee_status = v_fee_status,
        status = p_to_status,
        status_updated_at = now(),
        delivered_at = NULL,
        updated_at = now()
    WHERE id = p_order_id
    RETURNING * INTO v_order;

    INSERT INTO public.merchant_delivery_fee_ledger (
      merchant_id, order_id, attempt_number, basis_amount,
      percent_snapshot, fee_amount, status
    )
    SELECT
      v_order.merchant_id, p_order_id, v_order.self_delivery_attempt,
      COALESCE(v_order.shipping_cost, 0), v_fee_percent, v_fee_amount, v_fee_status
    WHERE NOT EXISTS (
      SELECT 1 FROM public.merchant_delivery_fee_ledger l WHERE l.order_id = p_order_id
    );
  ELSE
    UPDATE public.orders
    SET status = p_to_status,
        status_updated_at = now(),
        confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
        delivered_at = CASE WHEN p_to_status IN ('DELIVERED', 'DONE') THEN COALESCE(delivered_at, now()) ELSE delivered_at END,
        self_delivery_fee_status = CASE
          WHEN p_to_status = 'CANCELED'
            AND COALESCE(is_self_delivery, false)
            AND self_delivery_fee_status = 'DUE' THEN 'WAIVED'
          ELSE self_delivery_fee_status
        END,
        updated_at = now()
    WHERE id = p_order_id
    RETURNING * INTO v_order;
  END IF;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from, p_to_status, auth.uid(), NULLIF(trim(p_reason), ''));

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_self_delivery_fee_ledger_lifecycle() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.merchant_transition_order(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
