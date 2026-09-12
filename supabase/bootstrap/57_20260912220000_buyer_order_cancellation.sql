-- Authoritative buyer cancellation path.
-- Stock reservation release is handled by the existing order-status trigger.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS cancellation_type text;

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
  IF v_previous_status NOT IN ('NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION') THEN
    RAISE EXCEPTION 'Order cannot be canceled from status %', v_previous_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET status = 'CANCELED',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancellation_reason = v_reason,
      cancellation_type = 'BUYER',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_previous_status, 'CANCELED', auth.uid(), v_reason);

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'from_status', v_previous_status,
    'to_status', 'CANCELED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_cancel_order(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_cancel_order(uuid, text) TO authenticated;

-- Buyer mutations must go through scoped RPCs, never a broad row update.
DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;
REVOKE UPDATE ON public.orders FROM authenticated, anon;

NOTIFY pgrst, 'reload schema';
