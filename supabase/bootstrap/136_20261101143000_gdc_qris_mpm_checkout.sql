-- GDC/Neo QRIS MPM checkout. Credentials remain in Supabase Edge Function secrets.
ALTER TABLE public.qris_applications
  ADD COLUMN IF NOT EXISTS gdc_merchant_id text,
  ADD COLUMN IF NOT EXISTS gdc_account_number text;

CREATE OR REPLACE FUNCTION public.guard_qris_gdc_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id
      OR NEW.gdc_account_number IS DISTINCT FROM OLD.gdc_account_number)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Identitas GDC QRIS hanya dapat dikelola admin' USING ERRCODE = '42501';
  END IF;
  IF NEW.status = 'ACTIVE'
     AND (NULLIF(trim(NEW.gdc_merchant_id), '') IS NULL
       OR NULLIF(trim(NEW.gdc_account_number), '') IS NULL) THEN
    RAISE EXCEPTION 'QRIS MPM memerlukan Merchant ID dan Account Number GDC' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_qris_gdc_assignment() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS qris_applications_guard_gdc_assignment ON public.qris_applications;
CREATE TRIGGER qris_applications_guard_gdc_assignment
BEFORE UPDATE OF gdc_merchant_id, gdc_account_number, status ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.guard_qris_gdc_assignment();

CREATE OR REPLACE FUNCTION public.admin_issue_qris_mpm(
  p_application_id uuid,
  p_qris_reference text,
  p_qris_asset_key text,
  p_gdc_merchant_id text,
  p_gdc_account_number text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(trim(p_qris_reference), '') IS NULL
     OR NULLIF(trim(p_qris_asset_key), '') IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(p_gdc_account_number), '') IS NULL
     OR length(trim(p_gdc_merchant_id)) > 100
     OR length(trim(p_gdc_account_number)) > 100 THEN
    RAISE EXCEPTION 'QRIS reference, asset, and GDC merchant credentials are required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_application FROM public.qris_applications
  WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND OR v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN
    RAISE EXCEPTION 'Application is not ready for QRIS issuance' USING ERRCODE = '22023';
  END IF;
  UPDATE public.merchants SET qris_image_url = trim(p_qris_asset_key), updated_at = now()
  WHERE id = v_application.merchant_id;
  UPDATE public.qris_applications
  SET qris_reference = left(trim(p_qris_reference), 200),
      qris_asset_key = left(trim(p_qris_asset_key), 1000),
      gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      status = 'ISSUED_PENDING_ACTIVATION',
      issued_by_admin_id = auth.uid(),
      issued_at = now(),
      updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ISSUED_PENDING_ACTIVATION');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris_mpm(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris_mpm(uuid, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_configure_qris_mpm(
  p_application_id uuid,
  p_gdc_merchant_id text,
  p_gdc_account_number text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  IF p_application_id IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(p_gdc_account_number), '') IS NULL
     OR length(trim(p_gdc_merchant_id)) > 100
     OR length(trim(p_gdc_account_number)) > 100 THEN
    RAISE EXCEPTION 'Valid GDC merchant identity is required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_application FROM public.qris_applications
  WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND OR v_application.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Only an active QRIS application can be configured' USING ERRCODE = '22023';
  END IF;
  UPDATE public.qris_applications
  SET gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ACTIVE');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) TO authenticated;

CREATE TABLE IF NOT EXISTS public.gdc_qris_mpm_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id),
  partner_reference_no uuid NOT NULL UNIQUE,
  external_id uuid NOT NULL UNIQUE,
  reference_no text,
  amount numeric(14,2) NOT NULL CHECK (amount > 0 AND amount = trunc(amount, 2)),
  currency text NOT NULL DEFAULT 'IDR' CHECK (currency = 'IDR'),
  qr_content text,
  status text NOT NULL DEFAULT 'CREATING' CHECK (status IN ('CREATING','PENDING','PAID','FAILED')),
  provider_response_code text,
  error_code text,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'PENDING' OR (reference_no IS NOT NULL AND qr_content IS NOT NULL)),
  CHECK (status <> 'PAID' OR paid_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS gdc_qris_mpm_payments_merchant_created_idx
  ON public.gdc_qris_mpm_payments(merchant_id, created_at DESC);
ALTER TABLE public.gdc_qris_mpm_payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.gdc_qris_mpm_payments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.gdc_qris_mpm_payments TO service_role;

CREATE OR REPLACE FUNCTION public.settle_gdc_qris_mpm_payment(
  p_order_id uuid,
  p_partner_reference_no uuid,
  p_reference_no text,
  p_paid_amount numeric,
  p_paid_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC payment settlement requires service role' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR p_partner_reference_no IS NULL
     OR NULLIF(trim(p_reference_no), '') IS NULL OR p_paid_amount IS NULL THEN
    RAISE EXCEPTION 'Invalid GDC payment settlement request' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments
  WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no <> p_partner_reference_no
     OR v_payment.reference_no <> p_reference_no THEN
    RAISE EXCEPTION 'GDC payment reference mismatch' USING ERRCODE = '23P01';
  END IF;
  IF v_payment.amount <> p_paid_amount THEN
    RAISE EXCEPTION 'GDC payment amount mismatch' USING ERRCODE = '22003';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002'; END IF;
  IF v_order.total IS NULL OR v_order.total <> p_paid_amount THEN
    RAISE EXCEPTION 'Order amount mismatch' USING ERRCODE = '22003';
  END IF;
  IF v_payment.status = 'PAID' OR v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'PAID');
  END IF;
  IF v_order.payment_method <> 'TRANSFER'
     OR v_order.payment_status IN ('REFUNDED','EXPIRED')
     OR v_order.status IN ('CANCELLED','CANCELED','REJECTED','REFUNDED') THEN
    RAISE EXCEPTION 'Order is not eligible for GDC payment settlement' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders
  SET payment_status = 'PAID', payment_paid_at = COALESCE(p_paid_at, now()),
      payment_method = 'TRANSFER', payment_channel = 'QRIS_MPM_GDC', status = 'CONFIRMED', updated_at = now()
  WHERE id = p_order_id;
  UPDATE public.gdc_qris_mpm_payments
  SET status = 'PAID', paid_at = COALESCE(p_paid_at, now()),
      provider_response_code = '00', updated_at = now()
  WHERE order_id = p_order_id;
  RETURN jsonb_build_object('success', true, 'status', 'PAID', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid, uuid, text, numeric, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid, uuid, text, numeric, timestamptz) TO service_role;


-- Repair the deployed schema drift reported by the checkout/admin console.
-- Function 111 exists in the canonical history, but production PostgREST did
-- not expose touch_admin_login_activity(p_device_id) at the time of the report.
CREATE TABLE IF NOT EXISTS public.admin_login_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT 'Browser',
  device_type text NOT NULL DEFAULT 'browser' CHECK (device_type IN ('browser', 'pwa')),
  platform text,
  user_agent text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  login_count integer NOT NULL DEFAULT 1 CHECK (login_count > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_admin_login_activity_last_seen ON public.admin_login_activity(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_login_activity_user ON public.admin_login_activity(user_id, last_seen_at DESC);
ALTER TABLE public.admin_login_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins view login activity" ON public.admin_login_activity;
CREATE POLICY "Admins view login activity" ON public.admin_login_activity
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.record_admin_login_activity(
  p_device_id text,
  p_device_name text DEFAULT 'Browser',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL
)
RETURNS public.admin_login_activity
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_activity public.admin_login_activity%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RETURN NULL; END IF;
  IF NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser', 'pwa') THEN
    RAISE EXCEPTION 'Invalid admin login activity payload' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.admin_login_activity(user_id, device_id, device_name, device_type, platform, user_agent)
  VALUES (auth.uid(), trim(p_device_id), COALESCE(NULLIF(left(trim(p_device_name), 120), ''), 'Browser'),
          p_device_type, NULLIF(left(trim(p_platform), 120), ''), NULLIF(left(p_user_agent, 500), ''))
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type,
    platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent,
    last_seen_at = now(), login_count = public.admin_login_activity.login_count + 1, updated_at = now()
  RETURNING * INTO v_activity;
  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_admin_login_activity(p_device_id text)
RETURNS public.admin_login_activity
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_activity public.admin_login_activity%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RETURN NULL; END IF;
  IF NULLIF(trim(p_device_id), '') IS NULL THEN RAISE EXCEPTION 'Invalid device id' USING ERRCODE = '22023'; END IF;
  UPDATE public.admin_login_activity SET last_seen_at = now(), updated_at = now()
  WHERE user_id = auth.uid() AND device_id = trim(p_device_id)
  RETURNING * INTO v_activity;
  RETURN v_activity;
END;
$$;
REVOKE ALL ON FUNCTION public.record_admin_login_activity(text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.touch_admin_login_activity(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_admin_login_activity(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_admin_login_activity(text) TO authenticated;
NOTIFY pgrst, 'reload schema';
