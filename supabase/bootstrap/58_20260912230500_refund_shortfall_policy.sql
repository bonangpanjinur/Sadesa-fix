-- Refund shortfall policy.
-- A successful buyer refund must never be hidden by clamping a merchant balance
-- to zero. The deducted amount and any unpaid remainder are recorded separately.

CREATE TABLE IF NOT EXISTS public.merchant_refund_shortfalls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id uuid NOT NULL UNIQUE REFERENCES public.refund_settlements(id) ON DELETE RESTRICT,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
  refund_request_id uuid NOT NULL UNIQUE REFERENCES public.refund_requests(id) ON DELETE RESTRICT,
  amount numeric NOT NULL CHECK (amount > 0),
  deducted_amount numeric NOT NULL DEFAULT 0 CHECK (deducted_amount >= 0),
  outstanding_amount numeric NOT NULL CHECK (outstanding_amount >= 0),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RECOVERED')),
  recovered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.merchant_refund_shortfalls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage refund shortfalls" ON public.merchant_refund_shortfalls;
CREATE POLICY "Admins manage refund shortfalls" ON public.merchant_refund_shortfalls
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.merchant_refund_shortfalls FROM anon, authenticated;
GRANT SELECT ON public.merchant_refund_shortfalls TO authenticated;

CREATE INDEX IF NOT EXISTS idx_refund_shortfalls_merchant_status
  ON public.merchant_refund_shortfalls(merchant_id, status);

CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_balance numeric := 0;
  v_deducted numeric := 0;
  v_shortfall numeric := 0;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Settlement worker access required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_settlement FROM public.refund_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Settlement not found' USING ERRCODE = 'P0002'; END IF;
  IF v_settlement.status = 'COMPLETED' THEN
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED', 'duplicate', true);
  END IF;
  IF NOT p_success THEN
    UPDATE public.refund_settlements
      SET status = 'FAILED', last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now()
      WHERE id = p_settlement_id;
    UPDATE public.refund_requests SET settlement_status = 'FAILED', updated_at = now()
      WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;

  SELECT COALESCE(m.available_balance, 0) INTO v_balance
    FROM public.merchants m WHERE m.id = v_settlement.merchant_id FOR UPDATE;
  v_deducted := LEAST(GREATEST(v_balance, 0), v_settlement.amount);
  v_shortfall := GREATEST(v_settlement.amount - v_deducted, 0);

  UPDATE public.refund_settlements
    SET status = 'COMPLETED', provider_reference = left(p_provider_reference, 200),
        updated_at = now(), completed_at = now()
    WHERE id = p_settlement_id;
  UPDATE public.refund_requests SET settlement_status = 'COMPLETED', updated_at = now()
    WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now()
    WHERE id = v_settlement.order_id;
  UPDATE public.merchants
    SET available_balance = COALESCE(available_balance, 0) - v_deducted, updated_at = now()
    WHERE id = v_settlement.merchant_id;

  IF v_shortfall > 0 THEN
    INSERT INTO public.merchant_refund_shortfalls(
      settlement_id, merchant_id, order_id, refund_request_id,
      amount, deducted_amount, outstanding_amount, status
    ) VALUES (
      v_settlement.id, v_settlement.merchant_id, v_settlement.order_id, v_settlement.refund_request_id,
      v_settlement.amount, v_deducted, v_shortfall, 'OPEN'
    ) ON CONFLICT (settlement_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'id', p_settlement_id,
    'status', 'COMPLETED',
    'deducted_amount', v_deducted,
    'shortfall_amount', v_shortfall,
    'shortfall_status', CASE WHEN v_shortfall > 0 THEN 'OPEN' ELSE 'NONE' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) TO service_role;
NOTIFY pgrst, 'reload schema';
