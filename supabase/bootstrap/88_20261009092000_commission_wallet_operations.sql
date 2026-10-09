-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_c1813b748dcc$
BEGIN
  EXECUTE $bootstrap_sql_c1813b748dcc$-- Operational hardening for commission wallets: receivables, courier delivery,
-- dynamic policies, and legacy quota retirement without deleting historical rows.

ALTER TABLE public.commission_wallets
  ADD COLUMN IF NOT EXISTS debt_rupiah bigint NOT NULL DEFAULT 0 CHECK (debt_rupiah >= 0)$bootstrap_sql_c1813b748dcc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1813b748dcc$;

DO $bootstrap_do_7d1911e8fb25$
BEGIN
  EXECUTE $bootstrap_sql_7d1911e8fb25$ALTER TABLE public.commission_wallet_ledger
  ADD COLUMN IF NOT EXISTS debt_delta_rupiah bigint NOT NULL DEFAULT 0$bootstrap_sql_7d1911e8fb25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d1911e8fb25$;

DO $bootstrap_do_acf6e8a0204e$
BEGIN
  EXECUTE $bootstrap_sql_acf6e8a0204e$ALTER TABLE public.commission_wallet_ledger
  DROP CONSTRAINT IF EXISTS commission_ledger_type_sign$bootstrap_sql_acf6e8a0204e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_acf6e8a0204e$;

DO $bootstrap_do_aa068c0121f0$
BEGIN
  EXECUTE $bootstrap_sql_aa068c0121f0$ALTER TABLE public.commission_wallet_ledger
  DROP CONSTRAINT IF EXISTS commission_wallet_ledger_source_type_check$bootstrap_sql_aa068c0121f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa068c0121f0$;

DO $bootstrap_do_569162635fab$
BEGIN
  EXECUTE $bootstrap_sql_569162635fab$ALTER TABLE public.commission_wallet_ledger
  ADD CONSTRAINT commission_wallet_ledger_source_type_check
    CHECK (source_type IN ('ORDER', 'RIDE', 'COURIER_DELIVERY', 'PAYMENT', 'ADMIN'))$bootstrap_sql_569162635fab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_569162635fab$;

DO $bootstrap_do_42a4aba00fe1$
BEGIN
  EXECUTE $bootstrap_sql_42a4aba00fe1$ALTER TABLE public.commission_wallet_ledger
  ADD CONSTRAINT commission_ledger_type_sign CHECK (
    (entry_type = 'TOPUP' AND amount_delta_rupiah >= 0 AND debt_delta_rupiah <= 0
      AND amount_delta_rupiah - debt_delta_rupiah > 0)
    OR (entry_type = 'COMMISSION' AND amount_delta_rupiah <= 0 AND debt_delta_rupiah >= 0
      AND -amount_delta_rupiah + debt_delta_rupiah > 0)
    OR (entry_type = 'REFUND' AND amount_delta_rupiah >= 0 AND debt_delta_rupiah <= 0
      AND amount_delta_rupiah - debt_delta_rupiah > 0)
    OR (entry_type = 'ADJUSTMENT' AND (amount_delta_rupiah <> 0 OR debt_delta_rupiah <> 0))
  )$bootstrap_sql_42a4aba00fe1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42a4aba00fe1$;

DO $bootstrap_do_966b7a253d0f$
BEGIN
  EXECUTE $bootstrap_sql_966b7a253d0f$-- The courier rate can cover passenger rides and, when enabled, courier delivery
-- earnings. The rate remains shared, while the activity scope is explicit.
ALTER TABLE public.commission_fee_settings
  ADD COLUMN IF NOT EXISTS charge_courier_delivery boolean NOT NULL DEFAULT true$bootstrap_sql_966b7a253d0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_966b7a253d0f$;

DO $bootstrap_do_7ec007734c76$
BEGIN
  EXECUTE $bootstrap_sql_7ec007734c76$CREATE TABLE IF NOT EXISTS public.commission_wallet_policy_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id = true),
  refund_window_days integer NOT NULL DEFAULT 7 CHECK (refund_window_days BETWEEN 1 AND 365),
  low_balance_threshold_rupiah bigint NOT NULL DEFAULT 10000 CHECK (low_balance_threshold_rupiah >= 0),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_7ec007734c76$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ec007734c76$;

DO $bootstrap_do_c6118627830e$
BEGIN
  EXECUTE $bootstrap_sql_c6118627830e$INSERT INTO public.commission_wallet_policy_settings (id, refund_window_days, low_balance_threshold_rupiah)
VALUES (true, 7, 10000)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_c6118627830e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6118627830e$;

DO $bootstrap_do_b3111e833b4b$
BEGIN
  EXECUTE $bootstrap_sql_b3111e833b4b$ALTER TABLE public.commission_wallet_policy_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_b3111e833b4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3111e833b4b$;

DO $bootstrap_do_8f824f09edee$
BEGIN
  EXECUTE $bootstrap_sql_8f824f09edee$DROP POLICY IF EXISTS commission_wallet_policy_read_authenticated ON public.commission_wallet_policy_settings$bootstrap_sql_8f824f09edee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8f824f09edee$;

DO $bootstrap_do_15ccd07734d8$
BEGIN
  EXECUTE $bootstrap_sql_15ccd07734d8$CREATE POLICY commission_wallet_policy_read_authenticated
  ON public.commission_wallet_policy_settings FOR SELECT TO authenticated USING (true)$bootstrap_sql_15ccd07734d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15ccd07734d8$;

DO $bootstrap_do_1cf8f2d74d88$
BEGIN
  EXECUTE $bootstrap_sql_1cf8f2d74d88$DROP POLICY IF EXISTS commission_wallet_policy_admin_write ON public.commission_wallet_policy_settings$bootstrap_sql_1cf8f2d74d88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1cf8f2d74d88$;

DO $bootstrap_do_3cb0b6d6505f$
BEGIN
  EXECUTE $bootstrap_sql_3cb0b6d6505f$CREATE POLICY commission_wallet_policy_admin_write
  ON public.commission_wallet_policy_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_3cb0b6d6505f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3cb0b6d6505f$;

DO $bootstrap_do_bed6c705cd24$
BEGIN
  EXECUTE $bootstrap_sql_bed6c705cd24$GRANT SELECT, INSERT, UPDATE ON public.commission_wallet_policy_settings TO authenticated$bootstrap_sql_bed6c705cd24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bed6c705cd24$;

DO $bootstrap_do_bca12dd8557e$
BEGIN
  EXECUTE $bootstrap_sql_bca12dd8557e$GRANT ALL ON public.commission_wallet_policy_settings TO service_role$bootstrap_sql_bca12dd8557e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bca12dd8557e$;

DO $bootstrap_do_4a1259562a5d$
BEGIN
  EXECUTE $bootstrap_sql_4a1259562a5d$-- A funded top-up first pays any commission receivable, then credits usable wallet funds.
CREATE OR REPLACE FUNCTION public.credit_commission_wallet(
  p_wallet_id uuid,
  p_amount_rupiah bigint,
  p_source_type text,
  p_source_id uuid,
  p_idempotency_key text,
  p_note text,
  p_created_by uuid DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wallet public.commission_wallets%ROWTYPE;
  v_existing public.commission_wallet_ledger%ROWTYPE;
  v_debt_paid bigint;
  v_wallet_credit bigint;
BEGIN
  IF p_wallet_id IS NULL OR p_amount_rupiah <= 0
     OR p_source_type NOT IN ('PAYMENT', 'ADMIN')
     OR length(trim(COALESCE(p_idempotency_key, ''))) < 8 THEN
    RAISE EXCEPTION 'data kredit wallet tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_wallet FROM public.commission_wallets WHERE id = p_wallet_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet tidak ditemukan' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO v_existing FROM public.commission_wallet_ledger
  WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_existing.wallet_id <> p_wallet_id OR v_existing.entry_type <> 'TOPUP'
       OR v_existing.source_type <> p_source_type
       OR v_existing.amount_delta_rupiah - v_existing.debt_delta_rupiah <> p_amount_rupiah THEN
      RAISE EXCEPTION 'idempotency key sudah digunakan untuk mutasi lain' USING ERRCODE = '23505';
    END IF;
    RETURN v_wallet.balance_rupiah;
  END IF;

  v_debt_paid := LEAST(v_wallet.debt_rupiah, p_amount_rupiah);
  v_wallet_credit := p_amount_rupiah - v_debt_paid;
  UPDATE public.commission_wallets
  SET balance_rupiah = balance_rupiah + v_wallet_credit,
      debt_rupiah = debt_rupiah - v_debt_paid,
      updated_at = now()
  WHERE id = p_wallet_id
  RETURNING * INTO v_wallet;

  INSERT INTO public.commission_wallet_ledger (
    wallet_id, entry_type, source_type, source_id, idempotency_key,
    amount_delta_rupiah, debt_delta_rupiah, note, created_by
  ) VALUES (
    p_wallet_id, 'TOPUP', p_source_type, p_source_id, p_idempotency_key,
    v_wallet_credit, -v_debt_paid,
    COALESCE(NULLIF(trim(p_note), ''), 'Top-up wallet')
      || CASE WHEN v_debt_paid > 0 THEN ' (pelunasan komisi tertunggak ' || v_debt_paid::text || ')' ELSE '' END,
    p_created_by
  );
  RETURN v_wallet.balance_rupiah;
END;
$$$bootstrap_sql_4a1259562a5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a1259562a5d$;

DO $bootstrap_do_80d72f388803$
BEGIN
  EXECUTE $bootstrap_sql_80d72f388803$-- Applies the charge as an available-balance debit plus a receivable shortfall.
-- Completion never rolls back a physically finished order/ride; new work is gated until debt is paid.
CREATE OR REPLACE FUNCTION public.apply_transaction_commission(
  p_owner_type text,
  p_source_id uuid,
  p_source_type text
)
RETURNS TABLE (
  success boolean,
  already_applied boolean,
  fee_rupiah bigint,
  balance_after_rupiah bigint,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_source text := upper(trim(p_source_type));
  v_owner_id uuid;
  v_base_amount bigint;
  v_status text;
  v_rate numeric(7,4);
  v_enabled boolean := false;
  v_delivery_enabled boolean := true;
  v_fee bigint;
  v_wallet_id uuid;
  v_balance bigint;
  v_debt bigint;
  v_available_debit bigint;
  v_debt_added bigint;
  v_existing public.commission_wallet_ledger%ROWTYPE;
BEGIN
  IF p_source_id IS NULL OR v_owner_type NOT IN ('MERCHANT', 'COURIER') THEN
    RAISE EXCEPTION 'owner type atau source id tidak valid' USING ERRCODE = '22023';
  END IF;

  IF v_owner_type = 'MERCHANT' AND v_source = 'ORDER' THEN
    SELECT o.merchant_id, o.subtotal::bigint, o.status
      INTO v_owner_id, v_base_amount, v_status
    FROM public.orders o WHERE o.id = p_source_id FOR UPDATE;
    IF NOT FOUND OR v_owner_id IS NULL THEN RAISE EXCEPTION 'order merchant tidak ditemukan'; END IF;
    IF upper(v_status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
      RAISE EXCEPTION 'komisi pedagang hanya dapat diterapkan pada order selesai';
    END IF;
  ELSIF v_owner_type = 'COURIER' AND v_source = 'RIDE' THEN
    SELECT r.driver_id, r.final_fare::bigint, r.status
      INTO v_owner_id, v_base_amount, v_status
    FROM public.ride_requests r WHERE r.id = p_source_id FOR UPDATE;
    IF NOT FOUND OR v_owner_id IS NULL THEN RAISE EXCEPTION 'ride courier tidak ditemukan'; END IF;
    IF upper(v_status) <> 'COMPLETED' THEN RAISE EXCEPTION 'fee ojek hanya dapat diterapkan pada perjalanan selesai'; END IF;
  ELSIF v_owner_type = 'COURIER' AND v_source = 'COURIER_DELIVERY' THEN
    SELECT o.courier_id,
           COALESCE(o.courier_earning_estimate, o.shipping_cost, 0)::bigint,
           o.status
      INTO v_owner_id, v_base_amount, v_status
    FROM public.orders o
    WHERE o.id = p_source_id AND o.courier_id IS NOT NULL
    FOR UPDATE;
    IF NOT FOUND OR v_owner_id IS NULL THEN RAISE EXCEPTION 'order courier tidak ditemukan'; END IF;
    IF upper(v_status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
      RAISE EXCEPTION 'fee kurir barang hanya dapat diterapkan pada pengiriman selesai';
    END IF;
  ELSE
    RAISE EXCEPTION 'kombinasi owner dan sumber transaksi tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT s.fee_percent, s.is_enabled, COALESCE(s.charge_courier_delivery, true)
    INTO v_rate, v_enabled, v_delivery_enabled
  FROM public.commission_fee_settings s WHERE s.owner_type = v_owner_type;
  IF NOT FOUND OR NOT v_enabled OR (v_source = 'COURIER_DELIVERY' AND NOT v_delivery_enabled) THEN
    RETURN QUERY SELECT true, false, 0::bigint, NULL::bigint, 'Komisi tidak aktif untuk sumber ini';
    RETURN;
  END IF;

  v_fee := round(GREATEST(COALESCE(v_base_amount, 0), 0)::numeric * v_rate / 100)::bigint;
  IF v_fee = 0 THEN
    RETURN QUERY SELECT true, false, 0::bigint, NULL::bigint, 'Komisi transaksi adalah Rp0';
    RETURN;
  END IF;

  IF v_owner_type = 'MERCHANT' THEN
    SELECT w.id, w.balance_rupiah, w.debt_rupiah
      INTO v_wallet_id, v_balance, v_debt
    FROM public.commission_wallets w
    WHERE w.owner_type = 'MERCHANT' AND w.merchant_id = v_owner_id
    FOR UPDATE;
  ELSE
    SELECT w.id, w.balance_rupiah, w.debt_rupiah
      INTO v_wallet_id, v_balance, v_debt
    FROM public.commission_wallets w
    WHERE w.owner_type = 'COURIER' AND w.courier_id = v_owner_id
    FOR UPDATE;
  END IF;
  IF v_wallet_id IS NULL THEN RAISE EXCEPTION 'wallet komisi tidak ditemukan'; END IF;

  SELECT * INTO v_existing FROM public.commission_wallet_ledger l
  WHERE l.source_type = v_source AND l.source_id = p_source_id AND l.entry_type = 'COMMISSION';
  IF FOUND THEN
    RETURN QUERY SELECT true, true,
      COALESCE(-v_existing.amount_delta_rupiah + v_existing.debt_delta_rupiah,
        round(COALESCE(v_existing.base_amount_rupiah, 0)::numeric * COALESCE(v_existing.fee_percent, 0) / 100)::bigint),
      v_balance, 'Komisi sudah pernah diterapkan';
    RETURN;
  END IF;

  v_available_debit := LEAST(v_balance, v_fee);
  v_debt_added := v_fee - v_available_debit;
  UPDATE public.commission_wallets w
  SET balance_rupiah = w.balance_rupiah - v_available_debit,
      debt_rupiah = w.debt_rupiah + v_debt_added,
      updated_at = now()
  WHERE w.id = v_wallet_id
  RETURNING w.balance_rupiah, w.debt_rupiah INTO v_balance, v_debt;

  INSERT INTO public.commission_wallet_ledger (
    wallet_id, entry_type, source_type, source_id, idempotency_key,
    amount_delta_rupiah, debt_delta_rupiah, base_amount_rupiah, fee_percent, note, created_by
  ) VALUES (
    v_wallet_id, 'COMMISSION', v_source, p_source_id,
    'commission:' || v_source || ':' || p_source_id::text,
    -v_available_debit, v_debt_added, GREATEST(COALESCE(v_base_amount, 0), 0), v_rate,
    'Komisi ' || v_owner_type || ' atas ' || v_source || ' ' || p_source_id::text,
    auth.uid()
  );

  IF v_owner_type = 'COURIER' AND v_debt > 0 THEN
    UPDATE public.couriers SET is_available = false WHERE id = v_owner_id;
  END IF;

  RETURN QUERY SELECT true, false, v_fee, v_balance,
    CASE WHEN v_debt_added > 0
      THEN 'Transaksi selesai; kekurangan komisi dicatat sebagai tagihan dan mengunci transaksi baru'
      ELSE 'Komisi berhasil dipotong' END;
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO v_existing FROM public.commission_wallet_ledger l
    WHERE l.source_type = v_source AND l.source_id = p_source_id AND l.entry_type = 'COMMISSION';
    IF NOT FOUND THEN RAISE; END IF;
    SELECT w.balance_rupiah INTO v_balance FROM public.commission_wallets w
    WHERE w.id = v_wallet_id;
    RETURN QUERY SELECT true, true,
      -v_existing.amount_delta_rupiah + v_existing.debt_delta_rupiah,
      v_balance, 'Komisi sudah pernah diterapkan';
END;
$$$bootstrap_sql_80d72f388803$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_80d72f388803$;

DO $bootstrap_do_d104fb0b86df$
BEGIN
  EXECUTE $bootstrap_sql_d104fb0b86df$-- Keep the existing two-argument trusted backend contract for compatibility.
CREATE OR REPLACE FUNCTION public.apply_transaction_commission(p_owner_type text, p_source_id uuid)
RETURNS TABLE(success boolean, already_applied boolean, fee_rupiah bigint, balance_after_rupiah bigint, message text)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT * FROM public.apply_transaction_commission(
    p_owner_type, p_source_id,
    CASE WHEN upper(trim(p_owner_type)) = 'MERCHANT' THEN 'ORDER' ELSE 'RIDE' END
  );
$$$bootstrap_sql_d104fb0b86df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d104fb0b86df$;

DO $bootstrap_do_bce160845d2c$
BEGIN
  EXECUTE $bootstrap_sql_bce160845d2c$CREATE OR REPLACE FUNCTION public.charge_commission_on_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result record;
BEGIN
  IF TG_TABLE_NAME = 'orders'
     AND upper(NEW.status) IN ('DONE', 'DELIVERED', 'COMPLETED')
     AND upper(OLD.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    IF NEW.merchant_id IS NOT NULL THEN
      SELECT * INTO v_result FROM public.apply_transaction_commission('MERCHANT', NEW.id, 'ORDER');
    END IF;
    IF NEW.courier_id IS NOT NULL THEN
      SELECT * INTO v_result FROM public.apply_transaction_commission('COURIER', NEW.id, 'COURIER_DELIVERY');
    END IF;
  ELSIF TG_TABLE_NAME = 'ride_requests'
     AND upper(NEW.status) = 'COMPLETED' AND upper(OLD.status) <> 'COMPLETED' THEN
    SELECT * INTO v_result FROM public.apply_transaction_commission('COURIER', NEW.id, 'RIDE');
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_bce160845d2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bce160845d2c$;

DO $bootstrap_do_2ce1299b6cfb$
BEGIN
  EXECUTE $bootstrap_sql_2ce1299b6cfb$DROP TRIGGER IF EXISTS orders_charge_commission_after_completion ON public.orders$bootstrap_sql_2ce1299b6cfb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ce1299b6cfb$;

DO $bootstrap_do_64d4ffda8628$
BEGIN
  EXECUTE $bootstrap_sql_64d4ffda8628$CREATE TRIGGER orders_charge_commission_after_completion
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion()$bootstrap_sql_64d4ffda8628$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64d4ffda8628$;

DO $bootstrap_do_8640199ff6a6$
BEGIN
  EXECUTE $bootstrap_sql_8640199ff6a6$DROP TRIGGER IF EXISTS rides_charge_commission_after_completion ON public.ride_requests$bootstrap_sql_8640199ff6a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8640199ff6a6$;

DO $bootstrap_do_89fbd007bf82$
BEGIN
  EXECUTE $bootstrap_sql_89fbd007bf82$CREATE TRIGGER rides_charge_commission_after_completion
AFTER UPDATE OF status ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion()$bootstrap_sql_89fbd007bf82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89fbd007bf82$;

DO $bootstrap_do_434fa141f10d$
BEGIN
  EXECUTE $bootstrap_sql_434fa141f10d$-- With courier fees active, an online/assigned courier must have a funded wallet and no debt.
CREATE OR REPLACE FUNCTION public.guard_courier_wallet_debt_availability()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.is_available IS TRUE
     AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'COURIER' AND s.is_enabled)
     AND NOT EXISTS (
       SELECT 1 FROM public.commission_wallets w
       WHERE w.owner_type = 'COURIER' AND w.courier_id = NEW.id
         AND w.is_active AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
     ) THEN
    RAISE EXCEPTION 'isi saldo wallet dan lunasi tagihan komisi sebelum online' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_434fa141f10d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_434fa141f10d$;

DO $bootstrap_do_155f984d76f0$
BEGIN
  EXECUTE $bootstrap_sql_155f984d76f0$DROP TRIGGER IF EXISTS courier_wallet_debt_availability_guard ON public.couriers$bootstrap_sql_155f984d76f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_155f984d76f0$;

DO $bootstrap_do_fcb39549ff59$
BEGIN
  EXECUTE $bootstrap_sql_fcb39549ff59$CREATE TRIGGER courier_wallet_debt_availability_guard
BEFORE INSERT OR UPDATE OF is_available ON public.couriers
FOR EACH ROW EXECUTE FUNCTION public.guard_courier_wallet_debt_availability()$bootstrap_sql_fcb39549ff59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fcb39549ff59$;

DO $bootstrap_do_410d397dd4d4$
BEGIN
  EXECUTE $bootstrap_sql_410d397dd4d4$-- Public listing reveals eligibility only, not a wallet balance or debt amount.
CREATE OR REPLACE FUNCTION public.get_merchant_wallet_gate(p_merchant_ids uuid[])
RETURNS TABLE(is_enabled boolean, merchant_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH mode AS (
    SELECT COALESCE((SELECT s.is_enabled FROM public.commission_fee_settings s WHERE s.owner_type = 'MERCHANT'), false) AS is_enabled
  )
  SELECT mode.is_enabled, eligible.merchant_id
  FROM mode
  LEFT JOIN LATERAL (
    SELECT w.merchant_id
    FROM public.commission_wallets w
    JOIN public.merchants m ON m.id = w.merchant_id
    WHERE mode.is_enabled
      AND w.owner_type = 'MERCHANT'
      AND w.merchant_id = ANY(COALESCE(p_merchant_ids, '{}'::uuid[]))
      AND w.is_active = true AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
      AND m.status = 'ACTIVE' AND m.registration_status = 'APPROVED'
  ) eligible ON true;
$$$bootstrap_sql_410d397dd4d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_410d397dd4d4$;

DO $bootstrap_do_25583cb0db32$
BEGIN
  EXECUTE $bootstrap_sql_25583cb0db32$REVOKE ALL ON FUNCTION public.get_merchant_wallet_gate(uuid[]) FROM PUBLIC$bootstrap_sql_25583cb0db32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_25583cb0db32$;

DO $bootstrap_do_16dec8ba6373$
BEGIN
  EXECUTE $bootstrap_sql_16dec8ba6373$GRANT EXECUTE ON FUNCTION public.get_merchant_wallet_gate(uuid[]) TO anon, authenticated$bootstrap_sql_16dec8ba6373$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16dec8ba6373$;

DO $bootstrap_do_dc93169f262c$
BEGIN
  EXECUTE $bootstrap_sql_dc93169f262c$-- Retire legacy tiers at migration time. Rows and ledgers remain available for audit.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.merchant_subscriptions s
    WHERE upper(COALESCE(s.status, '')) IN ('PENDING', 'PENDING_PAYMENT', 'PENDING_APPROVAL', 'AWAITING_PAYMENT')
       OR upper(COALESCE(s.payment_status, '')) IN ('PENDING', 'PENDING_APPROVAL', 'PENDING_TRANSFER')
  ) THEN
    RAISE EXCEPTION 'Resolve all pending legacy quota purchases/payments before applying the wallet cutover migration';
  END IF;
END;
$$$bootstrap_sql_dc93169f262c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc93169f262c$;

DO $bootstrap_do_55632ab68eca$
BEGIN
  EXECUTE $bootstrap_sql_55632ab68eca$UPDATE public.transaction_packages SET is_active = false, updated_at = now() WHERE is_active IS DISTINCT FROM false$bootstrap_sql_55632ab68eca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55632ab68eca$;

DO $bootstrap_do_c1b18c19f29a$
BEGIN
  EXECUTE $bootstrap_sql_c1b18c19f29a$UPDATE public.quota_tiers SET is_active = false WHERE is_active IS DISTINCT FROM false$bootstrap_sql_c1b18c19f29a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1b18c19f29a$;

DO $bootstrap_do_6c1720ac07b8$
BEGIN
  EXECUTE $bootstrap_sql_6c1720ac07b8$UPDATE public.merchant_subscriptions
SET status = 'EXPIRED', expired_at = LEAST(expired_at, now()), updated_at = now()
WHERE upper(status) = 'ACTIVE'$bootstrap_sql_6c1720ac07b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c1720ac07b8$;

DO $bootstrap_do_3e4fc62a04b1$
BEGIN
  EXECUTE $bootstrap_sql_3e4fc62a04b1$UPDATE public.merchants m SET current_subscription_id = NULL
WHERE current_subscription_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.merchant_subscriptions s
    WHERE s.id = m.current_subscription_id AND upper(s.status) = 'ACTIVE' AND s.expired_at > now()
  )$bootstrap_sql_3e4fc62a04b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e4fc62a04b1$;

DO $bootstrap_do_e0eb7f285e8e$
BEGIN
  EXECUTE $bootstrap_sql_e0eb7f285e8e$-- Preserve subscriptions as history, but block new legacy sales/activation at the database boundary.
DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions$bootstrap_sql_e0eb7f285e8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e0eb7f285e8e$;

DO $bootstrap_do_0b34ad20a7a4$
BEGIN
  EXECUTE $bootstrap_sql_0b34ad20a7a4$CREATE POLICY "Merchants can create subscriptions"
  ON public.merchant_subscriptions FOR INSERT TO authenticated WITH CHECK (false)$bootstrap_sql_0b34ad20a7a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b34ad20a7a4$;

DO $bootstrap_do_b2be58b64a6b$
BEGIN
  EXECUTE $bootstrap_sql_b2be58b64a6b$CREATE OR REPLACE FUNCTION public.prevent_legacy_subscription_activation()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' OR (upper(NEW.status) = 'ACTIVE' AND upper(OLD.status) IS DISTINCT FROM 'ACTIVE') THEN
    RAISE EXCEPTION 'paket kuota legacy sudah dihentikan; gunakan wallet komisi' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_b2be58b64a6b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2be58b64a6b$;

DO $bootstrap_do_c7190ab3b70e$
BEGIN
  EXECUTE $bootstrap_sql_c7190ab3b70e$DROP TRIGGER IF EXISTS legacy_subscription_retirement_guard ON public.merchant_subscriptions$bootstrap_sql_c7190ab3b70e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7190ab3b70e$;

DO $bootstrap_do_4adee9132a1f$
BEGIN
  EXECUTE $bootstrap_sql_4adee9132a1f$CREATE TRIGGER legacy_subscription_retirement_guard
BEFORE INSERT OR UPDATE OF status ON public.merchant_subscriptions
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_subscription_activation()$bootstrap_sql_4adee9132a1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4adee9132a1f$;

DO $bootstrap_do_ab43c4747230$
BEGIN
  EXECUTE $bootstrap_sql_ab43c4747230$REVOKE ALL ON FUNCTION public.credit_commission_wallet(uuid, bigint, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated$bootstrap_sql_ab43c4747230$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab43c4747230$;

DO $bootstrap_do_b9bb5864460e$
BEGIN
  EXECUTE $bootstrap_sql_b9bb5864460e$REVOKE ALL ON FUNCTION public.apply_transaction_commission(text, uuid, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_b9bb5864460e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9bb5864460e$;

DO $bootstrap_do_78b6b1607e99$
BEGIN
  EXECUTE $bootstrap_sql_78b6b1607e99$REVOKE ALL ON FUNCTION public.apply_transaction_commission(text, uuid) FROM PUBLIC, anon, authenticated$bootstrap_sql_78b6b1607e99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78b6b1607e99$;

DO $bootstrap_do_530320dc824b$
BEGIN
  EXECUTE $bootstrap_sql_530320dc824b$GRANT EXECUTE ON FUNCTION public.apply_transaction_commission(text, uuid, text) TO service_role$bootstrap_sql_530320dc824b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_530320dc824b$;

DO $bootstrap_do_74eb18f32400$
BEGIN
  EXECUTE $bootstrap_sql_74eb18f32400$GRANT EXECUTE ON FUNCTION public.apply_transaction_commission(text, uuid) TO service_role$bootstrap_sql_74eb18f32400$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_74eb18f32400$;

DO $bootstrap_do_9b77c18a9a3c$
BEGIN
  EXECUTE $bootstrap_sql_9b77c18a9a3c$REVOKE ALL ON FUNCTION public.charge_commission_on_completion() FROM PUBLIC, anon, authenticated$bootstrap_sql_9b77c18a9a3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b77c18a9a3c$;

DO $bootstrap_do_ea8984dc6a09$
BEGIN
  EXECUTE $bootstrap_sql_ea8984dc6a09$REVOKE ALL ON FUNCTION public.guard_courier_wallet_debt_availability() FROM PUBLIC, anon, authenticated$bootstrap_sql_ea8984dc6a09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea8984dc6a09$;

DO $bootstrap_do_9dc3179d2c97$
BEGIN
  EXECUTE $bootstrap_sql_9dc3179d2c97$GRANT SELECT ON public.commission_wallet_policy_settings TO authenticated$bootstrap_sql_9dc3179d2c97$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dc3179d2c97$;

DO $bootstrap_do_444f673fd16b$
BEGIN
  EXECUTE $bootstrap_sql_444f673fd16b$NOTIFY pgrst, 'reload schema'$bootstrap_sql_444f673fd16b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_444f673fd16b$;

DO $bootstrap_do_9cac6d7d665f$
BEGIN
  EXECUTE $bootstrap_sql_9cac6d7d665f$-- Existing manual top-up approvals now repay debt before adding spendable balance.
CREATE OR REPLACE FUNCTION public.process_commission_wallet_topup(
  p_request_id uuid,
  p_approve boolean,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
  v_wallet_id uuid;
  v_balance bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501'; END IF;
  IF p_request_id IS NULL OR length(COALESCE(p_admin_notes, '')) > 500 THEN
    RAISE EXCEPTION 'id permintaan atau catatan tidak valid' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_request FROM public.commission_wallet_topup_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'permintaan top-up tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF v_request.status <> 'PENDING' THEN
    SELECT w.id, w.balance_rupiah INTO v_wallet_id, v_balance
    FROM public.commission_wallets w
    WHERE (v_request.owner_type = 'MERCHANT' AND w.merchant_id = v_request.merchant_id)
       OR (v_request.owner_type = 'COURIER' AND w.courier_id = v_request.courier_id);
    RETURN jsonb_build_object('status', v_request.status, 'balance_rupiah', v_balance, 'already_processed', true);
  END IF;

  IF p_approve THEN
    IF v_request.owner_type = 'MERCHANT' THEN
      INSERT INTO public.commission_wallets(owner_type, merchant_id) VALUES ('MERCHANT', v_request.merchant_id) ON CONFLICT DO NOTHING;
      SELECT id INTO v_wallet_id FROM public.commission_wallets WHERE owner_type = 'MERCHANT' AND merchant_id = v_request.merchant_id FOR UPDATE;
    ELSE
      INSERT INTO public.commission_wallets(owner_type, courier_id) VALUES ('COURIER', v_request.courier_id) ON CONFLICT DO NOTHING;
      SELECT id INTO v_wallet_id FROM public.commission_wallets WHERE owner_type = 'COURIER' AND courier_id = v_request.courier_id FOR UPDATE;
    END IF;
    IF v_wallet_id IS NULL THEN RAISE EXCEPTION 'wallet penerima tidak ditemukan'; END IF;
    v_balance := public.credit_commission_wallet(
      v_wallet_id, v_request.amount_rupiah, 'PAYMENT', v_request.id,
      'topup-request:' || v_request.id::text,
      'Top-up request ' || v_request.id::text, auth.uid()
    );
  END IF;

  UPDATE public.commission_wallet_topup_requests
  SET status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
      admin_notes = NULLIF(trim(p_admin_notes), ''), reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = p_request_id;
  RETURN jsonb_build_object(
    'status', CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
    'balance_rupiah', v_balance, 'already_processed', false
  );
END;
$$$bootstrap_sql_9cac6d7d665f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cac6d7d665f$;

DO $bootstrap_do_293291cd22e1$
BEGIN
  EXECUTE $bootstrap_sql_293291cd22e1$CREATE OR REPLACE FUNCTION public.admin_credit_commission_wallet(
  p_owner_type text, p_owner_id uuid, p_amount_rupiah bigint,
  p_idempotency_key text, p_note text
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_wallet_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501'; END IF;
  IF v_owner_type NOT IN ('MERCHANT', 'COURIER') OR p_owner_id IS NULL OR p_amount_rupiah <= 0
     OR length(trim(COALESCE(p_idempotency_key, ''))) < 8 OR length(COALESCE(p_note, '')) > 500 THEN
    RAISE EXCEPTION 'data top-up tidak valid' USING ERRCODE = '22023';
  END IF;
  IF v_owner_type = 'MERCHANT' THEN
    INSERT INTO public.commission_wallets(owner_type, merchant_id) VALUES ('MERCHANT', p_owner_id) ON CONFLICT DO NOTHING;
    SELECT id INTO v_wallet_id FROM public.commission_wallets WHERE owner_type = 'MERCHANT' AND merchant_id = p_owner_id FOR UPDATE;
  ELSE
    INSERT INTO public.commission_wallets(owner_type, courier_id) VALUES ('COURIER', p_owner_id) ON CONFLICT DO NOTHING;
    SELECT id INTO v_wallet_id FROM public.commission_wallets WHERE owner_type = 'COURIER' AND courier_id = p_owner_id FOR UPDATE;
  END IF;
  IF v_wallet_id IS NULL THEN RAISE EXCEPTION 'pemilik wallet tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  RETURN public.credit_commission_wallet(v_wallet_id, p_amount_rupiah, 'ADMIN', NULL,
    p_idempotency_key, p_note, auth.uid());
END;
$$$bootstrap_sql_293291cd22e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_293291cd22e1$;

DO $bootstrap_do_6b260c80b99c$
BEGIN
  EXECUTE $bootstrap_sql_6b260c80b99c$-- Admin cannot accidentally reactivate or recreate retired legacy packages.
CREATE OR REPLACE FUNCTION public.prevent_legacy_package_activation()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.is_active IS TRUE THEN
    RAISE EXCEPTION 'paket kuota legacy sudah dihentikan; gunakan wallet komisi' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_6b260c80b99c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b260c80b99c$;

DO $bootstrap_do_ddcd6037d86c$
BEGIN
  EXECUTE $bootstrap_sql_ddcd6037d86c$DROP TRIGGER IF EXISTS transaction_package_retirement_guard ON public.transaction_packages$bootstrap_sql_ddcd6037d86c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddcd6037d86c$;

DO $bootstrap_do_e8b2c06cc085$
BEGIN
  EXECUTE $bootstrap_sql_e8b2c06cc085$CREATE TRIGGER transaction_package_retirement_guard
BEFORE INSERT OR UPDATE OF is_active ON public.transaction_packages
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_package_activation()$bootstrap_sql_e8b2c06cc085$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8b2c06cc085$;

DO $bootstrap_do_893e988c9e94$
BEGIN
  EXECUTE $bootstrap_sql_893e988c9e94$DROP TRIGGER IF EXISTS quota_tier_retirement_guard ON public.quota_tiers$bootstrap_sql_893e988c9e94$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_893e988c9e94$;

DO $bootstrap_do_c0a301650c2f$
BEGIN
  EXECUTE $bootstrap_sql_c0a301650c2f$CREATE TRIGGER quota_tier_retirement_guard
BEFORE INSERT OR UPDATE OF is_active ON public.quota_tiers
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_package_activation()$bootstrap_sql_c0a301650c2f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0a301650c2f$;

DO $bootstrap_do_3dadd1272f73$
BEGIN
  EXECUTE $bootstrap_sql_3dadd1272f73$REVOKE ALL ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_3dadd1272f73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3dadd1272f73$;

DO $bootstrap_do_d7e0a2c7414a$
BEGIN
  EXECUTE $bootstrap_sql_d7e0a2c7414a$GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) TO authenticated$bootstrap_sql_d7e0a2c7414a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7e0a2c7414a$;

DO $bootstrap_do_e00b1bbfa278$
BEGIN
  EXECUTE $bootstrap_sql_e00b1bbfa278$REVOKE ALL ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) FROM PUBLIC, anon$bootstrap_sql_e00b1bbfa278$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e00b1bbfa278$;

DO $bootstrap_do_5b1def2f91fe$
BEGIN
  EXECUTE $bootstrap_sql_5b1def2f91fe$GRANT EXECUTE ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) TO authenticated, service_role$bootstrap_sql_5b1def2f91fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b1def2f91fe$;

DO $bootstrap_do_f9f897a2ebd1$
BEGIN
  EXECUTE $bootstrap_sql_f9f897a2ebd1$REVOKE ALL ON FUNCTION public.prevent_legacy_subscription_activation() FROM PUBLIC, anon, authenticated$bootstrap_sql_f9f897a2ebd1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f9f897a2ebd1$;

DO $bootstrap_do_9c8ae14725f0$
BEGIN
  EXECUTE $bootstrap_sql_9c8ae14725f0$REVOKE ALL ON FUNCTION public.prevent_legacy_package_activation() FROM PUBLIC, anon, authenticated$bootstrap_sql_9c8ae14725f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c8ae14725f0$;

DO $bootstrap_do_a0c7a65f2d9c$
BEGIN
  EXECUTE $bootstrap_sql_a0c7a65f2d9c$CREATE OR REPLACE FUNCTION public.guard_new_work_for_courier_with_wallet_debt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_courier_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'ride_requests'
     AND upper(NEW.status) = 'ACCEPTED' AND upper(OLD.status) IS DISTINCT FROM 'ACCEPTED' THEN
    v_courier_id := NEW.driver_id;
  ELSIF TG_TABLE_NAME = 'orders'
     AND upper(NEW.status) = 'COURIER_ACCEPTED' AND upper(OLD.status) IS DISTINCT FROM 'COURIER_ACCEPTED' THEN
    v_courier_id := NEW.courier_id;
  ELSE
    RETURN NEW;
  END IF;
  IF v_courier_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'COURIER' AND s.is_enabled)
     AND NOT EXISTS (
       SELECT 1 FROM public.commission_wallets w
       WHERE w.owner_type = 'COURIER' AND w.courier_id = v_courier_id
         AND w.is_active AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
     ) THEN
    RAISE EXCEPTION 'courier harus memiliki saldo wallet positif dan tanpa tagihan sebelum menerima pekerjaan baru' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_a0c7a65f2d9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0c7a65f2d9c$;

DO $bootstrap_do_49867335e891$
BEGIN
  EXECUTE $bootstrap_sql_49867335e891$DROP TRIGGER IF EXISTS ride_wallet_debt_assignment_guard ON public.ride_requests$bootstrap_sql_49867335e891$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49867335e891$;

DO $bootstrap_do_7d9810a7a14c$
BEGIN
  EXECUTE $bootstrap_sql_7d9810a7a14c$CREATE TRIGGER ride_wallet_debt_assignment_guard
BEFORE UPDATE OF status ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_new_work_for_courier_with_wallet_debt()$bootstrap_sql_7d9810a7a14c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d9810a7a14c$;

DO $bootstrap_do_e660ffa0d716$
BEGIN
  EXECUTE $bootstrap_sql_e660ffa0d716$DROP TRIGGER IF EXISTS delivery_wallet_debt_assignment_guard ON public.orders$bootstrap_sql_e660ffa0d716$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e660ffa0d716$;

DO $bootstrap_do_f11dbe365ecd$
BEGIN
  EXECUTE $bootstrap_sql_f11dbe365ecd$CREATE TRIGGER delivery_wallet_debt_assignment_guard
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_new_work_for_courier_with_wallet_debt()$bootstrap_sql_f11dbe365ecd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f11dbe365ecd$;

DO $bootstrap_do_f87ec797a58f$
BEGIN
  EXECUTE $bootstrap_sql_f87ec797a58f$REVOKE ALL ON FUNCTION public.guard_new_work_for_courier_with_wallet_debt() FROM PUBLIC, anon, authenticated$bootstrap_sql_f87ec797a58f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f87ec797a58f$;

DO $bootstrap_do_9f9e030d4ebc$
BEGIN
  EXECUTE $bootstrap_sql_9f9e030d4ebc$CREATE OR REPLACE FUNCTION public.guard_new_order_for_merchant_wallet_debt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.merchant_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'MERCHANT' AND s.is_enabled)
     AND EXISTS (SELECT 1 FROM public.commission_wallets w WHERE w.owner_type = 'MERCHANT' AND w.merchant_id = NEW.merchant_id AND w.debt_rupiah > 0) THEN
    RAISE EXCEPTION 'pedagang memiliki tagihan komisi; lunasi sebelum menerima pesanan baru' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_9f9e030d4ebc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f9e030d4ebc$;

DO $bootstrap_do_7831386d452c$
BEGIN
  EXECUTE $bootstrap_sql_7831386d452c$DROP TRIGGER IF EXISTS merchant_wallet_debt_new_order_guard ON public.orders$bootstrap_sql_7831386d452c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7831386d452c$;

DO $bootstrap_do_de1b428b8808$
BEGIN
  EXECUTE $bootstrap_sql_de1b428b8808$CREATE TRIGGER merchant_wallet_debt_new_order_guard
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_new_order_for_merchant_wallet_debt()$bootstrap_sql_de1b428b8808$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de1b428b8808$;

DO $bootstrap_do_42a294769216$
BEGIN
  EXECUTE $bootstrap_sql_42a294769216$REVOKE ALL ON FUNCTION public.guard_new_order_for_merchant_wallet_debt() FROM PUBLIC, anon, authenticated$bootstrap_sql_42a294769216$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42a294769216$;

DO $bootstrap_do_77fe406ec130$
BEGIN
  EXECUTE $bootstrap_sql_77fe406ec130$CREATE OR REPLACE FUNCTION public.sync_courier_availability_to_commission_wallet()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.owner_type = 'COURIER' AND NEW.is_enabled THEN
    UPDATE public.couriers c SET is_available = false
    WHERE c.is_available IS TRUE
      AND NOT EXISTS (
        SELECT 1 FROM public.commission_wallets w
        WHERE w.owner_type = 'COURIER' AND w.courier_id = c.id
          AND w.is_active AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
      );
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_77fe406ec130$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77fe406ec130$;

DO $bootstrap_do_f37b9a711a55$
BEGIN
  EXECUTE $bootstrap_sql_f37b9a711a55$DROP TRIGGER IF EXISTS commission_fee_sync_courier_availability ON public.commission_fee_settings$bootstrap_sql_f37b9a711a55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f37b9a711a55$;

DO $bootstrap_do_651e5ad2b6a5$
BEGIN
  EXECUTE $bootstrap_sql_651e5ad2b6a5$CREATE TRIGGER commission_fee_sync_courier_availability
AFTER INSERT OR UPDATE OF is_enabled ON public.commission_fee_settings
FOR EACH ROW EXECUTE FUNCTION public.sync_courier_availability_to_commission_wallet()$bootstrap_sql_651e5ad2b6a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_651e5ad2b6a5$;

DO $bootstrap_do_60a65f309579$
BEGIN
  EXECUTE $bootstrap_sql_60a65f309579$REVOKE ALL ON FUNCTION public.sync_courier_availability_to_commission_wallet() FROM PUBLIC, anon, authenticated$bootstrap_sql_60a65f309579$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60a65f309579$;

DO $bootstrap_do_1451935adbf1$
BEGIN
  EXECUTE $bootstrap_sql_1451935adbf1$UPDATE public.couriers c SET is_available = false
WHERE c.is_available IS TRUE
  AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'COURIER' AND s.is_enabled)
  AND NOT EXISTS (
    SELECT 1 FROM public.commission_wallets w
    WHERE w.owner_type = 'COURIER' AND w.courier_id = c.id
      AND w.is_active AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
  )$bootstrap_sql_1451935adbf1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1451935adbf1$;
