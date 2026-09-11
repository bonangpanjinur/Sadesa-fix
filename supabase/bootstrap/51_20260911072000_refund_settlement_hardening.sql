-- Refund settlement hardening.
-- Approval creates a durable settlement intent; money and balances change only
-- after a trusted provider completion callback.

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS settlement_status text NOT NULL DEFAULT 'NOT_REQUIRED',
  ADD COLUMN IF NOT EXISTS settlement_id uuid;
REVOKE INSERT ON public.refund_requests FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.refund_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_request_id uuid NOT NULL UNIQUE REFERENCES public.refund_requests(id) ON DELETE RESTRICT,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE RESTRICT,
  amount integer NOT NULL CHECK (amount > 0),
  provider text NOT NULL DEFAULT 'xendit',
  idempotency_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')),
  provider_reference text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
ALTER TABLE public.refund_settlements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyers can view own refund settlements" ON public.refund_settlements;
CREATE POLICY "Buyers can view own refund settlements" ON public.refund_settlements
  FOR SELECT USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Admins can manage refund settlements" ON public.refund_settlements;
CREATE POLICY "Admins can manage refund settlements" ON public.refund_settlements
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.refund_settlements FROM anon, authenticated;
GRANT SELECT ON public.refund_settlements TO authenticated;

CREATE OR REPLACE FUNCTION public.process_refund_decision(p_refund_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_settlement_id uuid;
  v_new_status text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_refund FROM public.refund_requests WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND OR v_refund.status <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund is no longer pending' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_refund.order_id FOR UPDATE;
  IF NOT FOUND OR v_refund.amount <= 0 OR v_refund.amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is invalid' USING ERRCODE = '22023';
  END IF;
  v_new_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  IF p_approve THEN
    INSERT INTO public.refund_settlements(refund_request_id, order_id, buyer_id, merchant_id, amount, idempotency_key)
    VALUES (v_refund.id, v_refund.order_id, v_refund.buyer_id, v_refund.merchant_id, v_refund.amount, 'refund:' || v_refund.id::text)
    ON CONFLICT (refund_request_id) DO UPDATE SET updated_at = now()
    RETURNING id INTO v_settlement_id;
    UPDATE public.refund_requests
    SET status = 'APPROVED', settlement_status = 'PENDING', settlement_id = v_settlement_id,
        admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(),
        processed_at = now(), updated_at = now(), dispute_status = 'RESOLVED_REFUND'
    WHERE id = p_refund_id;
  ELSE
    UPDATE public.refund_requests
    SET status = 'REJECTED', settlement_status = 'NOT_REQUIRED',
        admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(),
        processed_at = now(), updated_at = now(), dispute_status = 'RESOLVED_REJECTED'
    WHERE id = p_refund_id;
  END IF;
  RETURN jsonb_build_object('id', p_refund_id, 'status', v_new_status,
    'settlement_status', CASE WHEN p_approve THEN 'PENDING' ELSE 'NOT_REQUIRED' END,
    'settlement_id', v_settlement_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
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
    UPDATE public.refund_settlements SET status = 'FAILED', last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now() WHERE id = p_settlement_id;
    UPDATE public.refund_requests SET settlement_status = 'FAILED', updated_at = now() WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;
  UPDATE public.refund_settlements SET status = 'COMPLETED', provider_reference = left(p_provider_reference, 200), updated_at = now(), completed_at = now() WHERE id = p_settlement_id;
  UPDATE public.refund_requests SET settlement_status = 'COMPLETED', updated_at = now() WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now() WHERE id = v_settlement.order_id;
  UPDATE public.merchants SET available_balance = GREATEST(0, COALESCE(available_balance, 0) - v_settlement.amount), updated_at = now() WHERE id = v_settlement.merchant_id;
  RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED');
END;
$$;

-- PAID is terminal except for the trusted, completed refund transition.
CREATE OR REPLACE FUNCTION public.prevent_paid_payment_downgrade()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.payment_status = 'PAID' AND NEW.payment_status IS DISTINCT FROM 'PAID'
     AND NEW.payment_status IS DISTINCT FROM 'REFUNDED' THEN
    RAISE EXCEPTION 'Paid order payment status is terminal' USING ERRCODE = '27000';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.process_refund_decision(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_refund_decision(uuid, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) TO service_role;
