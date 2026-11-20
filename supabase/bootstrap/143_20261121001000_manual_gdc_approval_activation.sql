-- QRIS MPM is generated dynamically per order by the GDC Edge Function.
-- Admins register the merchant manually in GDC and enter the approved MID and
-- account number here; this flow does not require a static QR image or provider
-- API validation before activation.
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
DECLARE
  v_application public.qris_applications%ROWTYPE;
  v_next_status text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(p_gdc_account_number), '') IS NULL
     OR length(trim(p_gdc_merchant_id)) > 100
     OR length(trim(p_gdc_account_number)) > 100 THEN
    RAISE EXCEPTION 'GDC Merchant ID and Account Number are required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_application FROM public.qris_applications
  WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND OR v_application.status NOT IN ('APPROVED_PENDING_ISSUANCE', 'ISSUED_PENDING_ACTIVATION', 'ACTIVE') THEN
    RAISE EXCEPTION 'Application is not ready for GDC mapping' USING ERRCODE = '22023';
  END IF;
  v_next_status := CASE
    WHEN v_application.status = 'APPROVED_PENDING_ISSUANCE' THEN 'ISSUED_PENDING_ACTIVATION'
    ELSE v_application.status
  END;
  UPDATE public.qris_applications
  SET gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      status = v_next_status,
      gdc_mpm_enabled = false,
      updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'status', v_next_status,
    'gdc_mpm_enabled', false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) TO authenticated;

-- Admin activation turns on the MPM mapping used by qr-mpm-generate.
-- The database enforces admin authorization and complete identity, not a
-- provider API verification that is outside this manual registration process.
CREATE OR REPLACE FUNCTION public.admin_activate_qris(p_application_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'ISSUED_PENDING_ACTIVATION' THEN
    RAISE EXCEPTION 'Pengajuan belum menunggu aktivasi admin' USING ERRCODE = '23514';
  END IF;
  IF NULLIF(trim(v_application.gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(v_application.gdc_account_number), '') IS NULL THEN
    RAISE EXCEPTION 'Merchant ID dan Account Number GDC wajib diisi admin sebelum aktivasi' USING ERRCODE = '23514';
  END IF;
  UPDATE public.qris_applications
  SET status = 'ACTIVE',
      gdc_mpm_enabled = true,
      activated_by_admin_id = auth.uid(),
      activated_at = now(),
      updated_at = now()
  WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_activate_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_qris(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
