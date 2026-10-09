-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_1d691cd74d85$
BEGIN
  EXECUTE $bootstrap_sql_1d691cd74d85$-- Automatic commission-wallet top-ups through the application's existing Xendit integration.
-- Manual bank/QRIS proof review remains available as a fallback.

ALTER TABLE public.commission_wallet_topup_requests
  ALTER COLUMN proof_path DROP NOT NULL$bootstrap_sql_1d691cd74d85$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d691cd74d85$;

DO $bootstrap_do_fce008c261d8$
BEGIN
  EXECUTE $bootstrap_sql_fce008c261d8$ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_requests_proof_path_check$bootstrap_sql_fce008c261d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fce008c261d8$;

DO $bootstrap_do_d2fe934b24e3$
BEGIN
  EXECUTE $bootstrap_sql_d2fe934b24e3$ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_proof_path_check$bootstrap_sql_d2fe934b24e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2fe934b24e3$;

DO $bootstrap_do_40d4b6b4e455$
BEGIN
  EXECUTE $bootstrap_sql_40d4b6b4e455$ALTER TABLE public.commission_wallet_topup_requests
  ADD CONSTRAINT commission_wallet_topup_proof_path_check
  CHECK (proof_path IS NULL OR length(proof_path) BETWEEN 8 AND 1000)$bootstrap_sql_40d4b6b4e455$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40d4b6b4e455$;

DO $bootstrap_do_102b36802592$
BEGIN
  EXECUTE $bootstrap_sql_102b36802592$ALTER TABLE public.commission_wallet_topup_requests
  ADD COLUMN IF NOT EXISTS payment_provider text NOT NULL DEFAULT 'MANUAL'
    CHECK (payment_provider IN ('MANUAL', 'XENDIT')),
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'REVIEW'
    CHECK (payment_status IN ('REVIEW', 'PENDING', 'PAID', 'EXPIRED', 'FAILED')),
  ADD COLUMN IF NOT EXISTS payment_invoice_id text,
  ADD COLUMN IF NOT EXISTS payment_invoice_url text,
  ADD COLUMN IF NOT EXISTS payment_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS payment_channel text$bootstrap_sql_102b36802592$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_102b36802592$;

DO $bootstrap_do_e8b2f65aab72$
BEGIN
  EXECUTE $bootstrap_sql_e8b2f65aab72$CREATE UNIQUE INDEX IF NOT EXISTS commission_wallet_topup_invoice_id_uq
  ON public.commission_wallet_topup_requests(payment_invoice_id)
  WHERE payment_invoice_id IS NOT NULL$bootstrap_sql_e8b2f65aab72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8b2f65aab72$;

DO $bootstrap_do_eab368078e5a$
BEGIN
  EXECUTE $bootstrap_sql_eab368078e5a$CREATE TABLE IF NOT EXISTS public.commission_wallet_topup_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (provider = 'XENDIT'),
  event_key text NOT NULL,
  request_id uuid NOT NULL REFERENCES public.commission_wallet_topup_requests(id) ON DELETE RESTRICT,
  invoice_id text NOT NULL,
  payment_status text NOT NULL CHECK (payment_status IN ('PENDING', 'PAID', 'EXPIRED')),
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, event_key)
)$bootstrap_sql_eab368078e5a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eab368078e5a$;

DO $bootstrap_do_777d5eb512e3$
BEGIN
  EXECUTE $bootstrap_sql_777d5eb512e3$ALTER TABLE public.commission_wallet_topup_webhook_events ENABLE ROW LEVEL SECURITY$bootstrap_sql_777d5eb512e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_777d5eb512e3$;

DO $bootstrap_do_ae775ecad755$
BEGIN
  EXECUTE $bootstrap_sql_ae775ecad755$REVOKE ALL ON public.commission_wallet_topup_webhook_events FROM PUBLIC, anon, authenticated$bootstrap_sql_ae775ecad755$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae775ecad755$;

DO $bootstrap_do_e861034d5cbb$
BEGIN
  EXECUTE $bootstrap_sql_e861034d5cbb$GRANT ALL ON public.commission_wallet_topup_webhook_events TO service_role$bootstrap_sql_e861034d5cbb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e861034d5cbb$;

DO $bootstrap_do_d6ba2a6ee2ce$
BEGIN
  EXECUTE $bootstrap_sql_d6ba2a6ee2ce$CREATE OR REPLACE FUNCTION public.create_commission_wallet_topup_invoice_request(
  p_owner_type text,
  p_amount_rupiah bigint,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_owner_type text := upper(trim(p_owner_type));
  v_owner_id uuid;
  v_request_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'login required' USING ERRCODE = '42501'; END IF;
  IF v_owner_type NOT IN ('MERCHANT', 'COURIER') OR p_amount_rupiah NOT BETWEEN 10000 AND 1000000000
     OR length(COALESCE(p_note, '')) > 500 THEN
    RAISE EXCEPTION 'permintaan invoice top-up tidak valid' USING ERRCODE = '22023';
  END IF;
  IF v_owner_type = 'MERCHANT' THEN
    SELECT m.id INTO v_owner_id FROM public.merchants m
    WHERE m.user_id = auth.uid() AND m.status = 'ACTIVE' AND m.registration_status = 'APPROVED' FOR SHARE;
  ELSE
    SELECT c.id INTO v_owner_id FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED' FOR SHARE;
  END IF;
  IF v_owner_id IS NULL THEN RAISE EXCEPTION 'akun aktif tidak ditemukan' USING ERRCODE = '42501'; END IF;

  INSERT INTO public.commission_wallet_topup_requests (
    owner_type, merchant_id, courier_id, amount_rupiah, proof_path, note,
    payment_provider, payment_status
  ) VALUES (
    v_owner_type,
    CASE WHEN v_owner_type = 'MERCHANT' THEN v_owner_id END,
    CASE WHEN v_owner_type = 'COURIER' THEN v_owner_id END,
    p_amount_rupiah, NULL, NULLIF(trim(p_note), ''), 'XENDIT', 'PENDING'
  ) RETURNING id INTO v_request_id;
  RETURN v_request_id;
END;
$$$bootstrap_sql_d6ba2a6ee2ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6ba2a6ee2ce$;

DO $bootstrap_do_71272bb5aefc$
BEGIN
  EXECUTE $bootstrap_sql_71272bb5aefc$REVOKE ALL ON FUNCTION public.create_commission_wallet_topup_invoice_request(text, bigint, text) FROM PUBLIC, anon$bootstrap_sql_71272bb5aefc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71272bb5aefc$;

DO $bootstrap_do_b25f676717ab$
BEGIN
  EXECUTE $bootstrap_sql_b25f676717ab$GRANT EXECUTE ON FUNCTION public.create_commission_wallet_topup_invoice_request(text, bigint, text) TO authenticated$bootstrap_sql_b25f676717ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b25f676717ab$;

DO $bootstrap_do_e4ffffa91160$
BEGIN
  EXECUTE $bootstrap_sql_e4ffffa91160$-- Called only by the authenticated Xendit webhook; validates invoice + exact amount,
-- deduplicates provider events, and credits balance/debt in the same transaction.
CREATE OR REPLACE FUNCTION public.process_commission_wallet_topup_payment(
  p_request_id uuid,
  p_event_key text,
  p_invoice_id text,
  p_status text,
  p_paid_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
  v_wallet_id uuid;
  v_balance bigint;
  v_inserted boolean := false;
  v_late_paid boolean := false;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Xendit webhook service access required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL OR length(trim(COALESCE(p_event_key, ''))) NOT BETWEEN 8 AND 250
     OR length(trim(COALESCE(p_invoice_id, ''))) NOT BETWEEN 1 AND 200
     OR p_status IS NULL OR p_status NOT IN ('PENDING', 'PAID', 'EXPIRED') THEN
    RAISE EXCEPTION 'invalid top-up payment event' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request FROM public.commission_wallet_topup_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'top-up request not found' USING ERRCODE = 'P0002'; END IF;
  IF v_request.payment_provider <> 'XENDIT'
     OR v_request.payment_invoice_id IS NULL OR v_request.payment_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'top-up invoice mismatch' USING ERRCODE = '23P01';
  END IF;
  IF p_status = 'PAID' AND (p_paid_amount IS NULL OR p_paid_amount <> v_request.amount_rupiah) THEN
    RAISE EXCEPTION 'top-up payment amount mismatch' USING ERRCODE = '22003';
  END IF;

  INSERT INTO public.commission_wallet_topup_webhook_events(provider, event_key, request_id, invoice_id, payment_status)
  VALUES ('XENDIT', trim(p_event_key), v_request.id, p_invoice_id, p_status)
  ON CONFLICT (provider, event_key) DO NOTHING RETURNING true INTO v_inserted;
  IF NOT COALESCE(v_inserted, false) THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', v_request.payment_status);
  END IF;

  IF v_request.payment_status = 'PAID' OR v_request.status = 'APPROVED' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'PAID');
  END IF;
  v_late_paid := v_request.status = 'REJECTED' AND v_request.payment_status = 'EXPIRED' AND p_status = 'PAID';
  IF v_request.status <> 'PENDING' AND NOT v_late_paid THEN
    RETURN jsonb_build_object('success', true, 'ignored', true, 'status', v_request.status);
  END IF;

  IF p_status = 'PENDING' THEN
    UPDATE public.commission_wallet_topup_requests
    SET payment_status = 'PENDING', payment_method = NULLIF(left(trim(COALESCE(p_payment_method, '')), 100), ''),
        payment_channel = NULLIF(left(trim(COALESCE(p_payment_channel, '')), 100), '')
    WHERE id = v_request.id;
    RETURN jsonb_build_object('success', true, 'processed', true, 'status', 'PENDING');
  ELSIF p_status = 'EXPIRED' THEN
    UPDATE public.commission_wallet_topup_requests
    SET status = 'REJECTED', payment_status = 'EXPIRED',
        admin_notes = COALESCE(admin_notes, 'Invoice kedaluwarsa; silakan ajukan top-up baru.'), reviewed_at = now()
    WHERE id = v_request.id;
    RETURN jsonb_build_object('success', true, 'processed', true, 'status', 'EXPIRED');
  END IF;

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
    'Top-up otomatis Xendit ' || v_request.id::text, NULL
  );
  UPDATE public.commission_wallet_topup_requests
  SET status = 'APPROVED', payment_status = 'PAID',
      payment_method = NULLIF(left(trim(COALESCE(p_payment_method, '')), 100), ''),
      payment_channel = NULLIF(left(trim(COALESCE(p_payment_channel, '')), 100), ''),
      reviewed_at = now(),
      admin_notes = CASE WHEN v_late_paid THEN 'Pembayaran diterima setelah callback kedaluwarsa; top-up dikreditkan otomatis.' ELSE admin_notes END
  WHERE id = v_request.id;
  RETURN jsonb_build_object('success', true, 'processed', true, 'status', 'PAID', 'balance_rupiah', v_balance);
END;
$$$bootstrap_sql_e4ffffa91160$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4ffffa91160$;

DO $bootstrap_do_0d8b6cdb5683$
BEGIN
  EXECUTE $bootstrap_sql_0d8b6cdb5683$REVOKE ALL ON FUNCTION public.process_commission_wallet_topup_payment(uuid, text, text, text, numeric, text, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_0d8b6cdb5683$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d8b6cdb5683$;

DO $bootstrap_do_63d1d67a6659$
BEGIN
  EXECUTE $bootstrap_sql_63d1d67a6659$GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup_payment(uuid, text, text, text, numeric, text, text) TO service_role$bootstrap_sql_63d1d67a6659$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63d1d67a6659$;

DO $bootstrap_do_8dc91bd0d4fa$
BEGIN
  EXECUTE $bootstrap_sql_8dc91bd0d4fa$-- The manual-review RPC must not let an administrator credit a gateway request
-- while its provider invoice can still settle asynchronously.
CREATE OR REPLACE FUNCTION public.process_commission_wallet_topup(
  p_request_id uuid, p_approve boolean, p_admin_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
  v_wallet_id uuid;
  v_balance bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501'; END IF;
  IF p_request_id IS NULL OR length(COALESCE(p_admin_notes, '')) > 500 THEN RAISE EXCEPTION 'request/catatan tidak valid'; END IF;
  SELECT * INTO v_request FROM public.commission_wallet_topup_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'permintaan top-up tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF v_request.payment_provider <> 'MANUAL' OR v_request.proof_path IS NULL THEN
    RAISE EXCEPTION 'permintaan ini bukan top-up manual yang dapat ditinjau' USING ERRCODE = '55000';
  END IF;
  IF v_request.status <> 'PENDING' THEN
    SELECT w.balance_rupiah INTO v_balance FROM public.commission_wallets w
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
    v_balance := public.credit_commission_wallet(v_wallet_id, v_request.amount_rupiah, 'PAYMENT', v_request.id,
      'topup-request:' || v_request.id::text, 'Top-up manual ' || v_request.id::text, auth.uid());
  END IF;
  UPDATE public.commission_wallet_topup_requests
  SET status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
      payment_status = CASE WHEN p_approve THEN 'PAID' ELSE 'FAILED' END,
      admin_notes = NULLIF(trim(p_admin_notes), ''), reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = p_request_id;
  RETURN jsonb_build_object('status', CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
    'balance_rupiah', v_balance, 'already_processed', false);
END;
$$$bootstrap_sql_8dc91bd0d4fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8dc91bd0d4fa$;

DO $bootstrap_do_42624d64107d$
BEGIN
  EXECUTE $bootstrap_sql_42624d64107d$REVOKE ALL ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_42624d64107d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42624d64107d$;

DO $bootstrap_do_8ce6eb42bc5c$
BEGIN
  EXECUTE $bootstrap_sql_8ce6eb42bc5c$GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) TO authenticated$bootstrap_sql_8ce6eb42bc5c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ce6eb42bc5c$;

DO $bootstrap_do_686331d26cf3$
BEGIN
  EXECUTE $bootstrap_sql_686331d26cf3$NOTIFY pgrst, 'reload schema'$bootstrap_sql_686331d26cf3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_686331d26cf3$;

DO $bootstrap_do_df04e21b4b00$
BEGIN
  EXECUTE $bootstrap_sql_df04e21b4b00$ALTER TABLE public.commission_wallet_topup_requests
  ADD COLUMN IF NOT EXISTS invoice_generation_status text NOT NULL DEFAULT 'READY'
    CHECK (invoice_generation_status IN ('READY', 'PROCESSING', 'COMPLETED', 'FAILED')),
  ADD COLUMN IF NOT EXISTS invoice_generation_started_at timestamptz$bootstrap_sql_df04e21b4b00$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df04e21b4b00$;

DO $bootstrap_do_2ad03abd67bf$
BEGIN
  EXECUTE $bootstrap_sql_2ad03abd67bf$CREATE OR REPLACE FUNCTION public.reserve_commission_wallet_topup_invoice(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'payment service access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.commission_wallet_topup_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'top-up request not found' USING ERRCODE = 'P0002'; END IF;
  IF v_request.status <> 'PENDING' OR v_request.payment_provider <> 'XENDIT' THEN
    RAISE EXCEPTION 'top-up request cannot be invoiced' USING ERRCODE = '55000';
  END IF;
  IF v_request.payment_invoice_id IS NOT NULL AND v_request.payment_invoice_url IS NOT NULL THEN
    RETURN jsonb_build_object('can_process', false, 'invoice_id', v_request.payment_invoice_id, 'invoice_url', v_request.payment_invoice_url);
  END IF;
  IF v_request.invoice_generation_status = 'PROCESSING'
     AND v_request.invoice_generation_started_at > now() - interval '5 minutes' THEN
    RETURN jsonb_build_object('can_process', false, 'processing', true);
  END IF;
  UPDATE public.commission_wallet_topup_requests
  SET invoice_generation_status = 'PROCESSING', invoice_generation_started_at = now()
  WHERE id = p_request_id;
  RETURN jsonb_build_object('can_process', true, 'request_key', 'sadesa-wallet-topup-' || p_request_id::text);
END;
$$$bootstrap_sql_2ad03abd67bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ad03abd67bf$;

DO $bootstrap_do_a131d9009f28$
BEGIN
  EXECUTE $bootstrap_sql_a131d9009f28$CREATE OR REPLACE FUNCTION public.complete_commission_wallet_topup_invoice(
  p_request_id uuid,
  p_success boolean,
  p_invoice_id text DEFAULT NULL,
  p_invoice_url text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL,
  p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.commission_wallet_topup_requests%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'payment service access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.commission_wallet_topup_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'top-up request not found' USING ERRCODE = 'P0002'; END IF;
  IF v_request.status <> 'PENDING' OR v_request.payment_provider <> 'XENDIT' THEN
    RAISE EXCEPTION 'top-up request cannot be updated' USING ERRCODE = '55000';
  END IF;
  IF p_success THEN
    IF length(trim(COALESCE(p_invoice_id, ''))) NOT BETWEEN 1 AND 200
       OR length(trim(COALESCE(p_invoice_url, ''))) NOT BETWEEN 1 AND 2000 THEN
      RAISE EXCEPTION 'provider invoice data is invalid' USING ERRCODE = '22023';
    END IF;
    UPDATE public.commission_wallet_topup_requests
    SET payment_invoice_id = p_invoice_id, payment_invoice_url = p_invoice_url,
        payment_expires_at = p_expires_at, payment_status = 'PENDING',
        invoice_generation_status = 'COMPLETED', admin_notes = NULL
    WHERE id = p_request_id;
  ELSE
    UPDATE public.commission_wallet_topup_requests
    SET invoice_generation_status = 'FAILED',
        admin_notes = left(COALESCE(p_error, 'Xendit invoice creation failed'), 500)
    WHERE id = p_request_id;
  END IF;
  RETURN jsonb_build_object('success', p_success, 'request_id', p_request_id);
END;
$$$bootstrap_sql_a131d9009f28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a131d9009f28$;

DO $bootstrap_do_e943de70a5c1$
BEGIN
  EXECUTE $bootstrap_sql_e943de70a5c1$REVOKE ALL ON FUNCTION public.reserve_commission_wallet_topup_invoice(uuid) FROM PUBLIC, anon, authenticated$bootstrap_sql_e943de70a5c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e943de70a5c1$;

DO $bootstrap_do_2495dab52e32$
BEGIN
  EXECUTE $bootstrap_sql_2495dab52e32$REVOKE ALL ON FUNCTION public.complete_commission_wallet_topup_invoice(uuid, boolean, text, text, timestamptz, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_2495dab52e32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2495dab52e32$;

DO $bootstrap_do_0601139cbd03$
BEGIN
  EXECUTE $bootstrap_sql_0601139cbd03$GRANT EXECUTE ON FUNCTION public.reserve_commission_wallet_topup_invoice(uuid) TO service_role$bootstrap_sql_0601139cbd03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0601139cbd03$;

DO $bootstrap_do_c5192afd4d3f$
BEGIN
  EXECUTE $bootstrap_sql_c5192afd4d3f$GRANT EXECUTE ON FUNCTION public.complete_commission_wallet_topup_invoice(uuid, boolean, text, text, timestamptz, text) TO service_role$bootstrap_sql_c5192afd4d3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5192afd4d3f$;

DO $bootstrap_do_140b7891e7be$
BEGIN
  EXECUTE $bootstrap_sql_140b7891e7be$-- Online invoices do not have a user-uploaded transfer proof; manual requests must retain one.
ALTER TABLE public.commission_wallet_topup_requests ALTER COLUMN proof_path DROP NOT NULL$bootstrap_sql_140b7891e7be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_140b7891e7be$;

DO $bootstrap_do_a0f27de6df63$
BEGIN
  EXECUTE $bootstrap_sql_a0f27de6df63$ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_requests_proof_path_check$bootstrap_sql_a0f27de6df63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0f27de6df63$;

DO $bootstrap_do_9c57f85cfa43$
BEGIN
  EXECUTE $bootstrap_sql_9c57f85cfa43$ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_proof_matches_provider_check$bootstrap_sql_9c57f85cfa43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c57f85cfa43$;

DO $bootstrap_do_6df8241d89a4$
BEGIN
  EXECUTE $bootstrap_sql_6df8241d89a4$ALTER TABLE public.commission_wallet_topup_requests
  ADD CONSTRAINT commission_wallet_topup_proof_matches_provider_check CHECK (
    (payment_provider = 'MANUAL' AND proof_path IS NOT NULL AND length(proof_path) BETWEEN 8 AND 1000)
    OR (payment_provider = 'XENDIT' AND proof_path IS NULL)
  )$bootstrap_sql_6df8241d89a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6df8241d89a4$;
