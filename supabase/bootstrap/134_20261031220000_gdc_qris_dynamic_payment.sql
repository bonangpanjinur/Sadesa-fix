-- GDC QRIS dynamic payment: merchant profiles, per-order attempts, idempotent provider processing.
-- Provider field mapping and signature format remain configurable in the GDC Edge Function.

CREATE TABLE IF NOT EXISTS public.gdc_payment_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'GDC' CHECK (provider = 'GDC'),
  status text NOT NULL DEFAULT 'PENDING_VALIDATION'
    CHECK (status IN ('PENDING_VALIDATION', 'ACTIVE', 'SUSPENDED')),
  provider_merchant_id text NOT NULL,
  provider_account_number text NOT NULL,
  nmid text,
  store_id text,
  terminal_id text,
  service_code text,
  verified_at timestamptz,
  verified_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, provider)
);

CREATE INDEX IF NOT EXISTS gdc_payment_profiles_status_idx
  ON public.gdc_payment_profiles(status, merchant_id);

CREATE TABLE IF NOT EXISTS public.gdc_payment_profile_activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES public.gdc_payment_profiles(id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  action text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gdc_payment_profile_activity_idx
  ON public.gdc_payment_profile_activity_logs(profile_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.gdc_qris_payment_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.gdc_payment_profiles(id),
  provider text NOT NULL DEFAULT 'GDC' CHECK (provider = 'GDC'),
  amount bigint NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (currency = 'IDR'),
  partner_reference_no text NOT NULL UNIQUE,
  provider_reference_no text,
  service_code text,
  status text NOT NULL DEFAULT 'CREATING'
    CHECK (status IN ('CREATING', 'PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'UNKNOWN')),
  qr_content text,
  qr_url text,
  qr_image text,
  expires_at timestamptz,
  provider_status text,
  provider_code text,
  provider_message text,
  last_error text,
  request_payload jsonb,
  response_payload jsonb,
  requested_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gdc_attempts_order_idx
  ON public.gdc_qris_payment_attempts(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS gdc_attempts_pending_idx
  ON public.gdc_qris_payment_attempts(status, updated_at)
  WHERE status IN ('CREATING', 'PENDING', 'UNKNOWN');
CREATE UNIQUE INDEX IF NOT EXISTS gdc_one_live_attempt_per_order_idx
  ON public.gdc_qris_payment_attempts(order_id)
  WHERE status IN ('CREATING', 'PENDING', 'UNKNOWN');

ALTER TABLE public.gdc_payment_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gdc_payment_profile_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gdc_qris_payment_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage GDC profiles" ON public.gdc_payment_profiles;
CREATE POLICY "Admins manage GDC profiles" ON public.gdc_payment_profiles
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Merchants read own GDC profile" ON public.gdc_payment_profiles;
CREATE POLICY "Merchants read own GDC profile" ON public.gdc_payment_profiles
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins read GDC profile logs" ON public.gdc_payment_profile_activity_logs;
CREATE POLICY "Admins read GDC profile logs" ON public.gdc_payment_profile_activity_logs
  FOR SELECT TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Admins write GDC profile logs" ON public.gdc_payment_profile_activity_logs;
CREATE POLICY "Admins write GDC profile logs" ON public.gdc_payment_profile_activity_logs
  FOR INSERT TO authenticated WITH CHECK (public.is_admin() AND actor_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers read own GDC attempts" ON public.gdc_qris_payment_attempts;
CREATE POLICY "Buyers read own GDC attempts" ON public.gdc_qris_payment_attempts
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Merchants read own GDC attempts" ON public.gdc_qris_payment_attempts;
CREATE POLICY "Merchants read own GDC attempts" ON public.gdc_qris_payment_attempts
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = merchant_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins read GDC attempts" ON public.gdc_qris_payment_attempts;
CREATE POLICY "Admins read GDC attempts" ON public.gdc_qris_payment_attempts
  FOR SELECT TO authenticated USING (public.is_admin());

REVOKE ALL ON public.gdc_payment_profiles FROM anon;
REVOKE ALL ON public.gdc_payment_profile_activity_logs FROM anon;
REVOKE ALL ON public.gdc_qris_payment_attempts FROM anon;
GRANT SELECT ON public.gdc_payment_profiles TO authenticated;
GRANT SELECT ON public.gdc_payment_profile_activity_logs TO authenticated;
GRANT SELECT ON public.gdc_qris_payment_attempts TO authenticated;
GRANT ALL ON public.gdc_payment_profiles, public.gdc_payment_profile_activity_logs, public.gdc_qris_payment_attempts TO service_role;

CREATE OR REPLACE FUNCTION public.touch_gdc_profile_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS gdc_profile_updated_at ON public.gdc_payment_profiles;
CREATE TRIGGER gdc_profile_updated_at BEFORE UPDATE ON public.gdc_payment_profiles
FOR EACH ROW EXECUTE FUNCTION public.touch_gdc_profile_updated_at();

CREATE OR REPLACE FUNCTION public.admin_upsert_gdc_payment_profile(
  p_merchant_id uuid,
  p_provider_merchant_id text,
  p_provider_account_number text,
  p_nmid text DEFAULT NULL,
  p_store_id text DEFAULT NULL,
  p_terminal_id text DEFAULT NULL,
  p_service_code text DEFAULT NULL,
  p_status text DEFAULT 'PENDING_VALIDATION'
)
RETURNS public.gdc_payment_profiles
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_profile public.gdc_payment_profiles;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501'; END IF;
  IF NULLIF(trim(p_provider_merchant_id), '') IS NULL OR NULLIF(trim(p_provider_account_number), '') IS NULL THEN
    RAISE EXCEPTION 'provider_merchant_id dan provider_account_number wajib diisi' USING ERRCODE = '22023';
  END IF;
  IF p_status NOT IN ('PENDING_VALIDATION', 'ACTIVE', 'SUSPENDED') THEN
    RAISE EXCEPTION 'Status profil GDC tidak valid' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.gdc_payment_profiles(
    merchant_id, provider_merchant_id, provider_account_number, nmid,
    store_id, terminal_id, service_code, status, verified_at, verified_by
  ) VALUES (
    p_merchant_id, trim(p_provider_merchant_id), trim(p_provider_account_number), NULLIF(trim(p_nmid), ''),
    NULLIF(trim(p_store_id), ''), NULLIF(trim(p_terminal_id), ''), NULLIF(trim(p_service_code), ''),
    p_status, CASE WHEN p_status = 'ACTIVE' THEN now() ELSE NULL END,
    CASE WHEN p_status = 'ACTIVE' THEN auth.uid() ELSE NULL END
  )
  ON CONFLICT (merchant_id, provider) DO UPDATE SET
    provider_merchant_id = EXCLUDED.provider_merchant_id,
    provider_account_number = EXCLUDED.provider_account_number,
    nmid = EXCLUDED.nmid,
    store_id = EXCLUDED.store_id,
    terminal_id = EXCLUDED.terminal_id,
    service_code = EXCLUDED.service_code,
    status = EXCLUDED.status,
    verified_at = EXCLUDED.verified_at,
    verified_by = EXCLUDED.verified_by,
    updated_at = now()
  RETURNING * INTO v_profile;

  INSERT INTO public.gdc_payment_profile_activity_logs(profile_id, actor_user_id, action, metadata)
  VALUES (v_profile.id, auth.uid(), 'PROFILE_UPSERTED', jsonb_build_object('status', v_profile.status));
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_upsert_gdc_payment_profile(uuid,text,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_gdc_payment_profile(uuid,text,text,text,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reserve_gdc_qris_attempt(p_order_id uuid, p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders;
  v_profile public.gdc_payment_profiles;
  v_attempt public.gdc_qris_payment_attempts;
  v_reference text;
BEGIN
  IF p_order_id IS NULL OR NULLIF(trim(p_request_key), '') IS NULL THEN
    RAISE EXCEPTION 'Order dan request key wajib diisi' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.payment_status IN ('PAID', 'REFUNDED') OR v_order.status IN ('CANCELED', 'CANCELLED', 'DONE', 'REFUNDED') THEN
    RAISE EXCEPTION 'Order tidak dapat dibayar' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_profile FROM public.gdc_payment_profiles
    WHERE merchant_id = v_order.merchant_id AND provider = 'GDC' AND status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'Profil GDC merchant belum aktif' USING ERRCODE = '55000'; END IF;

  SELECT * INTO v_attempt FROM public.gdc_qris_payment_attempts
    WHERE order_id = p_order_id AND status IN ('CREATING', 'PENDING', 'UNKNOWN')
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN RETURN jsonb_build_object('attempt_id', v_attempt.id, 'partner_reference_no', v_attempt.partner_reference_no, 'status', v_attempt.status, 'existing', true); END IF;

  v_reference := 'SADESA-' || upper(replace(p_order_id::text, '-', '')) || '-' || upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 12));
  INSERT INTO public.gdc_qris_payment_attempts(order_id, merchant_id, profile_id, amount, currency, partner_reference_no, service_code)
  VALUES (v_order.id, v_order.merchant_id, v_profile.id, v_order.total, 'IDR', v_reference, v_profile.service_code)
  RETURNING * INTO v_attempt;
  RETURN jsonb_build_object('attempt_id', v_attempt.id, 'partner_reference_no', v_attempt.partner_reference_no, 'status', v_attempt.status, 'existing', false);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_gdc_qris_attempt(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_gdc_qris_attempt(uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_gdc_qris_generate(
  p_attempt_id uuid, p_success boolean, p_provider_reference_no text DEFAULT NULL,
  p_qr_content text DEFAULT NULL, p_qr_url text DEFAULT NULL, p_qr_image text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL, p_provider_status text DEFAULT NULL,
  p_provider_code text DEFAULT NULL, p_provider_message text DEFAULT NULL,
  p_request_payload jsonb DEFAULT NULL, p_response_payload jsonb DEFAULT NULL,
  p_error text DEFAULT NULL
)
RETURNS public.gdc_qris_payment_attempts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_attempt public.gdc_qris_payment_attempts;
BEGIN
  SELECT * INTO STRICT v_attempt FROM public.gdc_qris_payment_attempts WHERE id = p_attempt_id FOR UPDATE;
  IF v_attempt.status IN ('SUCCEEDED', 'FAILED', 'EXPIRED') THEN RETURN v_attempt; END IF;
  UPDATE public.gdc_qris_payment_attempts SET
    status = CASE WHEN p_success THEN 'PENDING' ELSE 'UNKNOWN' END,
    provider_reference_no = COALESCE(NULLIF(trim(p_provider_reference_no), ''), provider_reference_no),
    qr_content = COALESCE(p_qr_content, qr_content), qr_url = COALESCE(p_qr_url, qr_url), qr_image = COALESCE(p_qr_image, qr_image),
    expires_at = COALESCE(p_expires_at, expires_at), provider_status = p_provider_status, provider_code = p_provider_code,
    provider_message = p_provider_message, request_payload = p_request_payload, response_payload = p_response_payload,
    last_error = p_error, responded_at = now(), updated_at = now()
  WHERE id = p_attempt_id RETURNING * INTO v_attempt;
  RETURN v_attempt;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_gdc_qris_generate(uuid,boolean,text,text,text,text,timestamptz,text,text,text,jsonb,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_gdc_qris_generate(uuid,boolean,text,text,text,text,timestamptz,text,text,text,jsonb,jsonb,text) TO service_role;

CREATE OR REPLACE FUNCTION public.process_gdc_qris_status(
  p_attempt_id uuid, p_status text, p_provider_reference_no text DEFAULT NULL,
  p_provider_status text DEFAULT NULL, p_provider_code text DEFAULT NULL,
  p_provider_message text DEFAULT NULL, p_paid_at timestamptz DEFAULT NULL,
  p_paid_amount bigint DEFAULT NULL, p_event_key text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_attempt public.gdc_qris_payment_attempts; v_order public.orders;
BEGIN
  SELECT * INTO STRICT v_attempt FROM public.gdc_qris_payment_attempts WHERE id = p_attempt_id FOR UPDATE;
  SELECT * INTO STRICT v_order FROM public.orders WHERE id = v_attempt.order_id FOR UPDATE;
  IF p_status NOT IN ('PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'UNKNOWN') THEN RAISE EXCEPTION 'Status GDC tidak valid' USING ERRCODE = '22023'; END IF;
  IF p_paid_amount IS NOT NULL AND p_paid_amount <> v_attempt.amount THEN RAISE EXCEPTION 'Payment amount mismatch' USING ERRCODE = '22003'; END IF;
  IF v_attempt.status = 'SUCCEEDED' AND p_status <> 'SUCCEEDED' THEN RETURN jsonb_build_object('duplicate', true, 'status', v_attempt.status); END IF;
  UPDATE public.gdc_qris_payment_attempts SET
    status = p_status, provider_reference_no = COALESCE(NULLIF(trim(p_provider_reference_no), ''), provider_reference_no),
    provider_status = p_provider_status, provider_code = p_provider_code, provider_message = p_provider_message,
    paid_at = CASE WHEN p_status = 'SUCCEEDED' THEN COALESCE(p_paid_at, paid_at, now()) ELSE paid_at END,
    updated_at = now()
  WHERE id = v_attempt.id;
  IF p_status = 'SUCCEEDED' AND v_order.payment_status IS DISTINCT FROM 'PAID' THEN
    UPDATE public.orders SET payment_status = 'PAID', payment_paid_at = COALESCE(p_paid_at, now()), updated_at = now()
    WHERE id = v_order.id AND payment_status IS DISTINCT FROM 'PAID';
  ELSIF p_status = 'EXPIRED' AND v_order.payment_status NOT IN ('PAID', 'REFUNDED') THEN
    UPDATE public.orders SET payment_status = 'EXPIRED', updated_at = now() WHERE id = v_order.id;
  ELSIF p_status = 'FAILED' AND v_order.payment_status NOT IN ('PAID', 'REFUNDED') THEN
    UPDATE public.orders SET payment_status = 'FAILED', updated_at = now() WHERE id = v_order.id;
  END IF;
  RETURN jsonb_build_object('processed', true, 'status', p_status, 'order_id', v_order.id);
END;
$$;
REVOKE ALL ON FUNCTION public.process_gdc_qris_status(uuid,text,text,text,text,text,timestamptz,bigint,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_gdc_qris_status(uuid,text,text,text,text,text,timestamptz,bigint,text) TO service_role;
