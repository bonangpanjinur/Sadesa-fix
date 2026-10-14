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
)$bootstrap_sql_5ff4303b46bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ff4303b46bf$;

DO $bootstrap_do_f550da216e98$
BEGIN
  EXECUTE $bootstrap_sql_f550da216e98$CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_order
  ON public.payment_reconciliation_records(order_id, created_at DESC)$bootstrap_sql_f550da216e98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f550da216e98$;

DO $bootstrap_do_83aae09a7cfa$
BEGIN
  EXECUTE $bootstrap_sql_83aae09a7cfa$CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_status
  ON public.payment_reconciliation_records(reconciliation_status, created_at DESC)$bootstrap_sql_83aae09a7cfa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83aae09a7cfa$;

DO $bootstrap_do_89becf1e53a1$
BEGIN
  EXECUTE $bootstrap_sql_89becf1e53a1$ALTER TABLE public.payment_reconciliation_records ENABLE ROW LEVEL SECURITY$bootstrap_sql_89becf1e53a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89becf1e53a1$;

DO $bootstrap_do_a1ad4bb37b32$
BEGIN
  EXECUTE $bootstrap_sql_a1ad4bb37b32$REVOKE ALL ON public.payment_reconciliation_records FROM anon, authenticated$bootstrap_sql_a1ad4bb37b32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1ad4bb37b32$;

DO $bootstrap_do_19dacb551236$
BEGIN
  EXECUTE $bootstrap_sql_19dacb551236$GRANT SELECT ON public.payment_reconciliation_records TO authenticated$bootstrap_sql_19dacb551236$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19dacb551236$;

DO $bootstrap_do_c2d35bc430e9$
BEGIN
  EXECUTE $bootstrap_sql_c2d35bc430e9$GRANT ALL ON public.payment_reconciliation_records TO service_role$bootstrap_sql_c2d35bc430e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2d35bc430e9$;

DO $bootstrap_do_103bbc265d25$
BEGIN
  EXECUTE $bootstrap_sql_103bbc265d25$DROP POLICY IF EXISTS "Admins can view payment reconciliation" ON public.payment_reconciliation_records$bootstrap_sql_103bbc265d25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_103bbc265d25$;

DO $bootstrap_do_c2badd97612e$
BEGIN
  EXECUTE $bootstrap_sql_c2badd97612e$CREATE POLICY "Admins can view payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (public.is_admin())$bootstrap_sql_c2badd97612e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2badd97612e$;

DO $bootstrap_do_619cc2ca0f3d$
BEGIN
  EXECUTE $bootstrap_sql_619cc2ca0f3d$DROP POLICY IF EXISTS "Merchants can view own payment reconciliation" ON public.payment_reconciliation_records$bootstrap_sql_619cc2ca0f3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_619cc2ca0f3d$;

DO $bootstrap_do_a0e10ecd3b00$
BEGIN
  EXECUTE $bootstrap_sql_a0e10ecd3b00$CREATE POLICY "Merchants can view own payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_a0e10ecd3b00$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0e10ecd3b00$;

DO $bootstrap_do_f18770afd845$
BEGIN
  EXECUTE $bootstrap_sql_f18770afd845$CREATE OR REPLACE FUNCTION public.record_payment_reconciliation(
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
$$$bootstrap_sql_f18770afd845$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f18770afd845$;

DO $bootstrap_do_667c8cd8da2e$
BEGIN
  EXECUTE $bootstrap_sql_667c8cd8da2e$REVOKE ALL ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  FROM PUBLIC, anon, authenticated$bootstrap_sql_667c8cd8da2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_667c8cd8da2e$;

DO $bootstrap_do_844288f26ec7$
BEGIN
  EXECUTE $bootstrap_sql_844288f26ec7$GRANT EXECUTE ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  TO service_role$bootstrap_sql_844288f26ec7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_844288f26ec7$;

DO $bootstrap_do_cd0ea4f8c191$
BEGIN
  EXECUTE $bootstrap_sql_cd0ea4f8c191$
