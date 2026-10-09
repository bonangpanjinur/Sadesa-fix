-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_f9c5ecbcee55$
BEGIN
  EXECUTE $bootstrap_sql_f9c5ecbcee55$-- Configurable refund request window and commission reversal after actual settlement.
-- Partial refunds reverse commission proportionally to refund_amount / order.total.

CREATE OR REPLACE FUNCTION public.create_refund_request(
  p_order_id uuid, p_amount integer, p_reason text, p_evidence_urls text[] DEFAULT '{}',
  p_title text DEFAULT 'Komplain Pesanan', p_category text DEFAULT 'Lainnya'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_id uuid;
  v_evidence text[] := COALESCE(p_evidence_urls, '{}');
  v_window_days integer;
  v_completed_at timestamptz;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Order is not eligible for refund' USING ERRCODE = '42501';
  END IF;
  IF upper(COALESCE(v_order.payment_status, '')) IN ('UNPAID', 'PENDING_TRANSFER', 'FAILED', 'EXPIRED') THEN
    RAISE EXCEPTION 'Unpaid orders cannot be refunded' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is outside the eligible range' USING ERRCODE = '22023';
  END IF;
  IF length(trim(COALESCE(p_reason, ''))) < 10 OR length(p_reason) > 4000 THEN
    RAISE EXCEPTION 'Refund reason is invalid' USING ERRCODE = '22023';
  END IF;
  IF cardinality(v_evidence) > 5 OR EXISTS (
    SELECT 1 FROM unnest(v_evidence) url WHERE length(url) > 1000 OR url ~* '^(javascript|data):'
  ) THEN RAISE EXCEPTION 'Refund evidence is invalid' USING ERRCODE = '22023'; END IF;
  IF EXISTS (SELECT 1 FROM public.refund_requests WHERE order_id = p_order_id AND status IN ('PENDING', 'APPROVED')) THEN
    RAISE EXCEPTION 'An active refund request already exists' USING ERRCODE = '23505';
  END IF;

  SELECT COALESCE(refund_window_days, 7) INTO v_window_days
  FROM public.commission_wallet_policy_settings WHERE id = true;
  v_window_days := COALESCE(v_window_days, 7);
  SELECT max(h.created_at) INTO v_completed_at
  FROM public.order_status_history h
  WHERE h.order_id = p_order_id AND upper(h.to_status) IN ('DONE', 'DELIVERED', 'COMPLETED');
  v_completed_at := COALESCE(v_completed_at, v_order.updated_at, v_order.created_at);
  IF now() > v_completed_at + make_interval(days => v_window_days) THEN
    RAISE EXCEPTION 'Refund request window expired (% days)', v_window_days USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.refund_requests(
    order_id, buyer_id, merchant_id, amount, reason, status, evidence_urls, refund_type, title, category, dispute_status
  ) VALUES (
    p_order_id, auth.uid(), v_order.merchant_id, p_amount, trim(p_reason), 'PENDING', v_evidence,
    CASE WHEN p_amount = v_order.total THEN 'FULL' ELSE 'PARTIAL' END,
    left(COALESCE(NULLIF(trim(p_title), ''), 'Komplain Pesanan'), 200),
    left(COALESCE(NULLIF(trim(p_category), ''), 'Lainnya'), 80), 'OPEN'
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'order_id', p_order_id, 'amount', p_amount, 'refund_window_days', v_window_days);
END;
$$$bootstrap_sql_f9c5ecbcee55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f9c5ecbcee55$;

DO $bootstrap_do_1a8d87ba2995$
BEGIN
  EXECUTE $bootstrap_sql_1a8d87ba2995$REVOKE ALL ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) FROM PUBLIC, anon$bootstrap_sql_1a8d87ba2995$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1a8d87ba2995$;

DO $bootstrap_do_a1a549aa1166$
BEGIN
  EXECUTE $bootstrap_sql_a1a549aa1166$GRANT EXECUTE ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) TO authenticated$bootstrap_sql_a1a549aa1166$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1a549aa1166$;

DO $bootstrap_do_8b8dc12c3e2f$
BEGIN
  EXECUTE $bootstrap_sql_8b8dc12c3e2f$CREATE OR REPLACE FUNCTION public.reverse_commission_for_refund(
  p_refund_request_id uuid,
  p_order_id uuid,
  p_refund_amount numeric
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.refund_requests%ROWTYPE;
  v_order_total numeric;
  v_window_days integer;
  v_completed_at timestamptz;
  v_commission record;
  v_gross_fee bigint;
  v_refund_fee bigint;
  v_debt_paid bigint;
  v_balance_credit bigint;
  v_reversed bigint := 0;
  v_idempotency_key text;
BEGIN
  SELECT * INTO v_request FROM public.refund_requests WHERE id = p_refund_request_id;
  IF NOT FOUND OR v_request.order_id <> p_order_id THEN RAISE EXCEPTION 'refund request/order mismatch'; END IF;
  SELECT o.total INTO v_order_total FROM public.orders o WHERE o.id = p_order_id;
  IF v_order_total IS NULL OR v_order_total <= 0 OR p_refund_amount <= 0 THEN RETURN 0; END IF;
  SELECT COALESCE(refund_window_days, 7) INTO v_window_days FROM public.commission_wallet_policy_settings WHERE id = true;
  v_window_days := COALESCE(v_window_days, 7);
  SELECT max(h.created_at) INTO v_completed_at
  FROM public.order_status_history h
  WHERE h.order_id = p_order_id AND upper(h.to_status) IN ('DONE', 'DELIVERED', 'COMPLETED');
  IF v_request.created_at > COALESCE(v_completed_at, now()) + make_interval(days => v_window_days) THEN RETURN 0; END IF;

  FOR v_commission IN
    SELECT l.id, l.wallet_id, l.source_type, l.amount_delta_rupiah, l.debt_delta_rupiah,
           w.debt_rupiah
    FROM public.commission_wallet_ledger l
    JOIN public.commission_wallets w ON w.id = l.wallet_id
    WHERE l.entry_type = 'COMMISSION'
      AND l.source_id = p_order_id
      AND l.source_type IN ('ORDER', 'COURIER_DELIVERY')
    ORDER BY l.source_type
    FOR UPDATE OF l, w
  LOOP
    v_idempotency_key := 'commission-refund:' || p_refund_request_id::text || ':' || v_commission.source_type;
    IF EXISTS (SELECT 1 FROM public.commission_wallet_ledger WHERE idempotency_key = v_idempotency_key) THEN
      CONTINUE;
    END IF;
    v_gross_fee := GREATEST(-v_commission.amount_delta_rupiah + v_commission.debt_delta_rupiah, 0);
    v_refund_fee := LEAST(v_gross_fee, round(v_gross_fee::numeric * LEAST(p_refund_amount / v_order_total, 1))::bigint);
    IF v_refund_fee <= 0 THEN CONTINUE; END IF;
    v_debt_paid := LEAST(v_commission.debt_rupiah, v_refund_fee);
    v_balance_credit := v_refund_fee - v_debt_paid;
    UPDATE public.commission_wallets
    SET debt_rupiah = debt_rupiah - v_debt_paid,
        balance_rupiah = balance_rupiah + v_balance_credit,
        updated_at = now()
    WHERE id = v_commission.wallet_id;
    INSERT INTO public.commission_wallet_ledger(
      wallet_id, entry_type, source_type, source_id, idempotency_key,
      amount_delta_rupiah, debt_delta_rupiah, note, created_by
    ) VALUES (
      v_commission.wallet_id, 'REFUND', v_commission.source_type, p_order_id,
      v_idempotency_key, v_balance_credit, -v_debt_paid,
      'Pembalikan komisi proporsional atas refund ' || p_refund_request_id::text,
      NULL
    );
    v_reversed := v_reversed + v_refund_fee;
  END LOOP;
  RETURN v_reversed;
END;
$$$bootstrap_sql_8b8dc12c3e2f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b8dc12c3e2f$;

DO $bootstrap_do_e07a99e98b5b$
BEGIN
  EXECUTE $bootstrap_sql_e07a99e98b5b$REVOKE ALL ON FUNCTION public.reverse_commission_for_refund(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated$bootstrap_sql_e07a99e98b5b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e07a99e98b5b$;

DO $bootstrap_do_db6f1e68340c$
BEGIN
  EXECUTE $bootstrap_sql_db6f1e68340c$-- Financial reversal happens only when the refund provider settlement is completed.
CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_balance numeric := 0;
  v_deducted numeric := 0;
  v_shortfall numeric := 0;
  v_commission_reversed bigint := 0;
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
    SET status = 'COMPLETED', provider_reference = left(p_provider_reference, 200), updated_at = now(), completed_at = now()
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
      settlement_id, merchant_id, order_id, refund_request_id, amount, deducted_amount, outstanding_amount, status
    ) VALUES (
      v_settlement.id, v_settlement.merchant_id, v_settlement.order_id, v_settlement.refund_request_id,
      v_settlement.amount, v_deducted, v_shortfall, 'OPEN'
    ) ON CONFLICT (settlement_id) DO NOTHING;
  END IF;

  v_commission_reversed := public.reverse_commission_for_refund(
    v_settlement.refund_request_id, v_settlement.order_id, v_settlement.amount
  );
  RETURN jsonb_build_object(
    'id', p_settlement_id, 'status', 'COMPLETED', 'deducted_amount', v_deducted,
    'shortfall_amount', v_shortfall,
    'shortfall_status', CASE WHEN v_shortfall > 0 THEN 'OPEN' ELSE 'NONE' END,
    'commission_reversed_rupiah', v_commission_reversed
  );
END;
$$$bootstrap_sql_db6f1e68340c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db6f1e68340c$;

DO $bootstrap_do_bb11527cfd7b$
BEGIN
  EXECUTE $bootstrap_sql_bb11527cfd7b$REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_bb11527cfd7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb11527cfd7b$;

DO $bootstrap_do_1c07bc470712$
BEGIN
  EXECUTE $bootstrap_sql_1c07bc470712$GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) TO service_role$bootstrap_sql_1c07bc470712$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c07bc470712$;

DO $bootstrap_do_b26de9dcd39d$
BEGIN
  EXECUTE $bootstrap_sql_b26de9dcd39d$NOTIFY pgrst, 'reload schema'$bootstrap_sql_b26de9dcd39d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b26de9dcd39d$;
