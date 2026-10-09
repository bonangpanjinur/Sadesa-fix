-- Operational hardening for commission wallets: receivables, courier delivery,
-- dynamic policies, and legacy quota retirement without deleting historical rows.

ALTER TABLE public.commission_wallets
  ADD COLUMN IF NOT EXISTS debt_rupiah bigint NOT NULL DEFAULT 0 CHECK (debt_rupiah >= 0);

ALTER TABLE public.commission_wallet_ledger
  ADD COLUMN IF NOT EXISTS debt_delta_rupiah bigint NOT NULL DEFAULT 0;

ALTER TABLE public.commission_wallet_ledger
  DROP CONSTRAINT IF EXISTS commission_ledger_type_sign;
ALTER TABLE public.commission_wallet_ledger
  DROP CONSTRAINT IF EXISTS commission_wallet_ledger_source_type_check;
ALTER TABLE public.commission_wallet_ledger
  ADD CONSTRAINT commission_wallet_ledger_source_type_check
    CHECK (source_type IN ('ORDER', 'RIDE', 'COURIER_DELIVERY', 'PAYMENT', 'ADMIN'));
ALTER TABLE public.commission_wallet_ledger
  ADD CONSTRAINT commission_ledger_type_sign CHECK (
    (entry_type = 'TOPUP' AND amount_delta_rupiah >= 0 AND debt_delta_rupiah <= 0
      AND amount_delta_rupiah - debt_delta_rupiah > 0)
    OR (entry_type = 'COMMISSION' AND amount_delta_rupiah <= 0 AND debt_delta_rupiah >= 0
      AND -amount_delta_rupiah + debt_delta_rupiah > 0)
    OR (entry_type = 'REFUND' AND amount_delta_rupiah >= 0 AND debt_delta_rupiah <= 0
      AND amount_delta_rupiah - debt_delta_rupiah > 0)
    OR (entry_type = 'ADJUSTMENT' AND (amount_delta_rupiah <> 0 OR debt_delta_rupiah <> 0))
  );

-- The courier rate can cover passenger rides and, when enabled, courier delivery
-- earnings. The rate remains shared, while the activity scope is explicit.
ALTER TABLE public.commission_fee_settings
  ADD COLUMN IF NOT EXISTS charge_courier_delivery boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.commission_wallet_policy_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id = true),
  refund_window_days integer NOT NULL DEFAULT 7 CHECK (refund_window_days BETWEEN 1 AND 365),
  low_balance_threshold_rupiah bigint NOT NULL DEFAULT 10000 CHECK (low_balance_threshold_rupiah >= 0),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.commission_wallet_policy_settings (id, refund_window_days, low_balance_threshold_rupiah)
VALUES (true, 7, 10000)
ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.commission_wallet_policy_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commission_wallet_policy_read_authenticated ON public.commission_wallet_policy_settings;
CREATE POLICY commission_wallet_policy_read_authenticated
  ON public.commission_wallet_policy_settings FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS commission_wallet_policy_admin_write ON public.commission_wallet_policy_settings;
CREATE POLICY commission_wallet_policy_admin_write
  ON public.commission_wallet_policy_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE ON public.commission_wallet_policy_settings TO authenticated;
GRANT ALL ON public.commission_wallet_policy_settings TO service_role;

-- A funded top-up first pays any commission receivable, then credits usable wallet funds.
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
$$;

-- Applies the charge as an available-balance debit plus a receivable shortfall.
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
$$;

-- Keep the existing two-argument trusted backend contract for compatibility.
CREATE OR REPLACE FUNCTION public.apply_transaction_commission(p_owner_type text, p_source_id uuid)
RETURNS TABLE(success boolean, already_applied boolean, fee_rupiah bigint, balance_after_rupiah bigint, message text)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT * FROM public.apply_transaction_commission(
    p_owner_type, p_source_id,
    CASE WHEN upper(trim(p_owner_type)) = 'MERCHANT' THEN 'ORDER' ELSE 'RIDE' END
  );
$$;

CREATE OR REPLACE FUNCTION public.charge_commission_on_completion()
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
$$;

DROP TRIGGER IF EXISTS orders_charge_commission_after_completion ON public.orders;
CREATE TRIGGER orders_charge_commission_after_completion
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion();
DROP TRIGGER IF EXISTS rides_charge_commission_after_completion ON public.ride_requests;
CREATE TRIGGER rides_charge_commission_after_completion
AFTER UPDATE OF status ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.charge_commission_on_completion();

-- With courier fees active, an online/assigned courier must have a funded wallet and no debt.
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
$$;
DROP TRIGGER IF EXISTS courier_wallet_debt_availability_guard ON public.couriers;
CREATE TRIGGER courier_wallet_debt_availability_guard
BEFORE INSERT OR UPDATE OF is_available ON public.couriers
FOR EACH ROW EXECUTE FUNCTION public.guard_courier_wallet_debt_availability();

-- Public listing reveals eligibility only, not a wallet balance or debt amount.
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
$$;
REVOKE ALL ON FUNCTION public.get_merchant_wallet_gate(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_merchant_wallet_gate(uuid[]) TO anon, authenticated;

-- Retire legacy tiers at migration time. Rows and ledgers remain available for audit.
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
$$;
UPDATE public.transaction_packages SET is_active = false, updated_at = now() WHERE is_active IS DISTINCT FROM false;
UPDATE public.quota_tiers SET is_active = false WHERE is_active IS DISTINCT FROM false;
UPDATE public.merchant_subscriptions
SET status = 'EXPIRED', expired_at = LEAST(expired_at, now()), updated_at = now()
WHERE upper(status) = 'ACTIVE';
UPDATE public.merchants m SET current_subscription_id = NULL
WHERE current_subscription_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.merchant_subscriptions s
    WHERE s.id = m.current_subscription_id AND upper(s.status) = 'ACTIVE' AND s.expired_at > now()
  );

-- Preserve subscriptions as history, but block new legacy sales/activation at the database boundary.
DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can create subscriptions"
  ON public.merchant_subscriptions FOR INSERT TO authenticated WITH CHECK (false);
CREATE OR REPLACE FUNCTION public.prevent_legacy_subscription_activation()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' OR (upper(NEW.status) = 'ACTIVE' AND upper(OLD.status) IS DISTINCT FROM 'ACTIVE') THEN
    RAISE EXCEPTION 'paket kuota legacy sudah dihentikan; gunakan wallet komisi' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS legacy_subscription_retirement_guard ON public.merchant_subscriptions;
CREATE TRIGGER legacy_subscription_retirement_guard
BEFORE INSERT OR UPDATE OF status ON public.merchant_subscriptions
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_subscription_activation();

REVOKE ALL ON FUNCTION public.credit_commission_wallet(uuid, bigint, text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_transaction_commission(text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_transaction_commission(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_transaction_commission(text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_transaction_commission(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.charge_commission_on_completion() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_courier_wallet_debt_availability() FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commission_wallet_policy_settings TO authenticated;
NOTIFY pgrst, 'reload schema';


-- Existing manual top-up approvals now repay debt before adding spendable balance.
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
$$;

CREATE OR REPLACE FUNCTION public.admin_credit_commission_wallet(
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
$$;

-- Admin cannot accidentally reactivate or recreate retired legacy packages.
CREATE OR REPLACE FUNCTION public.prevent_legacy_package_activation()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.is_active IS TRUE THEN
    RAISE EXCEPTION 'paket kuota legacy sudah dihentikan; gunakan wallet komisi' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS transaction_package_retirement_guard ON public.transaction_packages;
CREATE TRIGGER transaction_package_retirement_guard
BEFORE INSERT OR UPDATE OF is_active ON public.transaction_packages
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_package_activation();
DROP TRIGGER IF EXISTS quota_tier_retirement_guard ON public.quota_tiers;
CREATE TRIGGER quota_tier_retirement_guard
BEFORE INSERT OR UPDATE OF is_active ON public.quota_tiers
FOR EACH ROW EXECUTE FUNCTION public.prevent_legacy_package_activation();
REVOKE ALL ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_credit_commission_wallet(text, uuid, bigint, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.prevent_legacy_subscription_activation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_legacy_package_activation() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.guard_new_work_for_courier_with_wallet_debt()
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
$$;
DROP TRIGGER IF EXISTS ride_wallet_debt_assignment_guard ON public.ride_requests;
CREATE TRIGGER ride_wallet_debt_assignment_guard
BEFORE UPDATE OF status ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_new_work_for_courier_with_wallet_debt();
DROP TRIGGER IF EXISTS delivery_wallet_debt_assignment_guard ON public.orders;
CREATE TRIGGER delivery_wallet_debt_assignment_guard
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_new_work_for_courier_with_wallet_debt();
REVOKE ALL ON FUNCTION public.guard_new_work_for_courier_with_wallet_debt() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.guard_new_order_for_merchant_wallet_debt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.merchant_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'MERCHANT' AND s.is_enabled)
     AND EXISTS (SELECT 1 FROM public.commission_wallets w WHERE w.owner_type = 'MERCHANT' AND w.merchant_id = NEW.merchant_id AND w.debt_rupiah > 0) THEN
    RAISE EXCEPTION 'pedagang memiliki tagihan komisi; lunasi sebelum menerima pesanan baru' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS merchant_wallet_debt_new_order_guard ON public.orders;
CREATE TRIGGER merchant_wallet_debt_new_order_guard
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_new_order_for_merchant_wallet_debt();
REVOKE ALL ON FUNCTION public.guard_new_order_for_merchant_wallet_debt() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.sync_courier_availability_to_commission_wallet()
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
$$;
DROP TRIGGER IF EXISTS commission_fee_sync_courier_availability ON public.commission_fee_settings;
CREATE TRIGGER commission_fee_sync_courier_availability
AFTER INSERT OR UPDATE OF is_enabled ON public.commission_fee_settings
FOR EACH ROW EXECUTE FUNCTION public.sync_courier_availability_to_commission_wallet();
REVOKE ALL ON FUNCTION public.sync_courier_availability_to_commission_wallet() FROM PUBLIC, anon, authenticated;
UPDATE public.couriers c SET is_available = false
WHERE c.is_available IS TRUE
  AND EXISTS (SELECT 1 FROM public.commission_fee_settings s WHERE s.owner_type = 'COURIER' AND s.is_enabled)
  AND NOT EXISTS (
    SELECT 1 FROM public.commission_wallets w
    WHERE w.owner_type = 'COURIER' AND w.courier_id = c.id
      AND w.is_active AND w.balance_rupiah > 0 AND w.debt_rupiah = 0
  );
