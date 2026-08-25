-- Payment reconciliation ledger. Provider imports/callback processors write here;
-- business users only read the resulting reconciliation state.
CREATE TABLE IF NOT EXISTS public.payment_reconciliation_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  provider_event_id text,
  invoice_id text NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL,
  expected_amount numeric(15,2) NOT NULL DEFAULT 0,
  provider_amount numeric(15,2),
  provider_fee numeric(15,2) NOT NULL DEFAULT 0,
  net_amount numeric(15,2),
  currency text NOT NULL DEFAULT 'IDR',
  provider_status text NOT NULL,
  reconciliation_status text NOT NULL DEFAULT 'unmatched'
    CHECK (reconciliation_status IN ('unmatched', 'matched', 'mismatch', 'refunded', 'settled')),
  settlement_reference text,
  settlement_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, invoice_id),
  UNIQUE(provider, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_order
  ON public.payment_reconciliation_records(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_status
  ON public.payment_reconciliation_records(reconciliation_status, created_at DESC);

ALTER TABLE public.payment_reconciliation_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_reconciliation_records FROM anon, authenticated;
GRANT SELECT ON public.payment_reconciliation_records TO authenticated;
GRANT ALL ON public.payment_reconciliation_records TO service_role;

DROP POLICY IF EXISTS "Admins can view payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Admins can view payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Merchants can view own payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Merchants can view own payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.record_payment_reconciliation(
  p_provider text,
  p_provider_event_id text,
  p_invoice_id text,
  p_order_id uuid,
  p_expected_amount numeric,
  p_provider_amount numeric,
  p_provider_fee numeric,
  p_provider_status text,
  p_settlement_reference text DEFAULT NULL,
  p_settlement_at timestamptz DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_status text;
  v_id uuid;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_expected_amount IS NULL OR p_expected_amount < 0
     OR p_provider_amount IS NOT NULL AND p_provider_amount < 0
     OR p_provider_fee IS NULL OR p_provider_fee < 0
     OR NULLIF(trim(p_provider_status), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid reconciliation record' USING ERRCODE = '22023';
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  v_status := CASE
    WHEN lower(p_provider_status) IN ('refunded', 'refund') THEN 'refunded'
    WHEN p_provider_amount IS NULL THEN 'unmatched'
    WHEN p_provider_amount <> p_expected_amount THEN 'mismatch'
    WHEN p_settlement_reference IS NOT NULL THEN 'settled'
    ELSE 'matched'
  END;

  INSERT INTO public.payment_reconciliation_records(
    provider, provider_event_id, invoice_id, order_id, merchant_id,
    expected_amount, provider_amount, provider_fee, net_amount, provider_status,
    reconciliation_status, settlement_reference, settlement_at, metadata, updated_at
  ) VALUES (
    lower(trim(p_provider)), NULLIF(trim(p_provider_event_id), ''), p_invoice_id,
    p_order_id, v_order.merchant_id, p_expected_amount, p_provider_amount,
    p_provider_fee, CASE WHEN p_provider_amount IS NULL THEN NULL ELSE p_provider_amount - p_provider_fee END,
    trim(p_provider_status), v_status, NULLIF(trim(p_settlement_reference), ''), p_settlement_at,
    COALESCE(p_metadata, '{}'::jsonb), now()
  )
  ON CONFLICT (provider, invoice_id) DO UPDATE SET
    provider_event_id = COALESCE(EXCLUDED.provider_event_id, payment_reconciliation_records.provider_event_id),
    provider_amount = EXCLUDED.provider_amount,
    provider_fee = EXCLUDED.provider_fee,
    net_amount = EXCLUDED.net_amount,
    provider_status = EXCLUDED.provider_status,
    reconciliation_status = EXCLUDED.reconciliation_status,
    settlement_reference = COALESCE(EXCLUDED.settlement_reference, payment_reconciliation_records.settlement_reference),
    settlement_at = COALESCE(EXCLUDED.settlement_at, payment_reconciliation_records.settlement_at),
    metadata = payment_reconciliation_records.metadata || EXCLUDED.metadata,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'status', v_status, 'provider', lower(trim(p_provider)), 'invoice_id', p_invoice_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  TO service_role;
