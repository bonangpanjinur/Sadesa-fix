-- Automatic commission-wallet top-ups through the application's existing Xendit integration.
-- Manual bank/QRIS proof review remains available as a fallback.

ALTER TABLE public.commission_wallet_topup_requests
  ALTER COLUMN proof_path DROP NOT NULL;
ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_requests_proof_path_check;
ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_proof_path_check;
ALTER TABLE public.commission_wallet_topup_requests
  ADD CONSTRAINT commission_wallet_topup_proof_path_check
  CHECK (proof_path IS NULL OR length(proof_path) BETWEEN 8 AND 1000);
ALTER TABLE public.commission_wallet_topup_requests
  ADD COLUMN IF NOT EXISTS payment_provider text NOT NULL DEFAULT 'MANUAL'
    CHECK (payment_provider IN ('MANUAL', 'XENDIT')),
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'REVIEW'
    CHECK (payment_status IN ('REVIEW', 'PENDING', 'PAID', 'EXPIRED', 'FAILED')),
  ADD COLUMN IF NOT EXISTS payment_invoice_id text,
  ADD COLUMN IF NOT EXISTS payment_invoice_url text,
  ADD COLUMN IF NOT EXISTS payment_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS payment_channel text;
CREATE UNIQUE INDEX IF NOT EXISTS commission_wallet_topup_invoice_id_uq
  ON public.commission_wallet_topup_requests(payment_invoice_id)
  WHERE payment_invoice_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.commission_wallet_topup_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (provider = 'XENDIT'),
  event_key text NOT NULL,
  request_id uuid NOT NULL REFERENCES public.commission_wallet_topup_requests(id) ON DELETE RESTRICT,
  invoice_id text NOT NULL,
  payment_status text NOT NULL CHECK (payment_status IN ('PENDING', 'PAID', 'EXPIRED')),
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, event_key)
);
ALTER TABLE public.commission_wallet_topup_webhook_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commission_wallet_topup_webhook_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.commission_wallet_topup_webhook_events TO service_role;

CREATE OR REPLACE FUNCTION public.create_commission_wallet_topup_invoice_request(
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
$$;
REVOKE ALL ON FUNCTION public.create_commission_wallet_topup_invoice_request(text, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_commission_wallet_topup_invoice_request(text, bigint, text) TO authenticated;

-- Called only by the authenticated Xendit webhook; validates invoice + exact amount,
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
$$;
REVOKE ALL ON FUNCTION public.process_commission_wallet_topup_payment(uuid, text, text, text, numeric, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup_payment(uuid, text, text, text, numeric, text, text) TO service_role;

-- The manual-review RPC must not let an administrator credit a gateway request
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
$$;
REVOKE ALL ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_commission_wallet_topup(uuid, boolean, text) TO authenticated;
NOTIFY pgrst, 'reload schema';


ALTER TABLE public.commission_wallet_topup_requests
  ADD COLUMN IF NOT EXISTS invoice_generation_status text NOT NULL DEFAULT 'READY'
    CHECK (invoice_generation_status IN ('READY', 'PROCESSING', 'COMPLETED', 'FAILED')),
  ADD COLUMN IF NOT EXISTS invoice_generation_started_at timestamptz;

CREATE OR REPLACE FUNCTION public.reserve_commission_wallet_topup_invoice(p_request_id uuid)
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
$$;

CREATE OR REPLACE FUNCTION public.complete_commission_wallet_topup_invoice(
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
$$;
REVOKE ALL ON FUNCTION public.reserve_commission_wallet_topup_invoice(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_commission_wallet_topup_invoice(uuid, boolean, text, text, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_commission_wallet_topup_invoice(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_commission_wallet_topup_invoice(uuid, boolean, text, text, timestamptz, text) TO service_role;


-- Online invoices do not have a user-uploaded transfer proof; manual requests must retain one.
ALTER TABLE public.commission_wallet_topup_requests ALTER COLUMN proof_path DROP NOT NULL;
ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_requests_proof_path_check;
ALTER TABLE public.commission_wallet_topup_requests
  DROP CONSTRAINT IF EXISTS commission_wallet_topup_proof_matches_provider_check;
ALTER TABLE public.commission_wallet_topup_requests
  ADD CONSTRAINT commission_wallet_topup_proof_matches_provider_check CHECK (
    (payment_provider = 'MANUAL' AND proof_path IS NOT NULL AND length(proof_path) BETWEEN 8 AND 1000)
    OR (payment_provider = 'XENDIT' AND proof_path IS NULL)
  );
