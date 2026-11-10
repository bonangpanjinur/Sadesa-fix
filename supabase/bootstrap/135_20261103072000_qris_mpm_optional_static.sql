-- QRIS MPM-only merchants do not need an uploaded static QR image.
-- Keep the existing RPC signatures so current admin clients remain compatible.
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
  v_qris_asset_key text := NULLIF(trim(COALESCE(p_qris_asset_key, '')), '');
  v_qris_reference text := NULLIF(left(trim(COALESCE(p_qris_reference, '')), 200), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(p_gdc_account_number), '') IS NULL
     OR length(trim(p_gdc_merchant_id)) > 100
     OR length(trim(p_gdc_account_number)) > 100
     OR (v_qris_asset_key IS NOT NULL AND length(v_qris_asset_key) > 1000) THEN
    RAISE EXCEPTION 'Valid GDC merchant identity is required; static QR image is optional' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF NOT FOUND OR v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN
    RAISE EXCEPTION 'Application is not ready for QRIS MPM issuance' USING ERRCODE = '22023';
  END IF;

  -- Only update the merchant static QR field when an optional asset was supplied.
  IF v_qris_asset_key IS NOT NULL THEN
    UPDATE public.merchants
    SET qris_image_url = v_qris_asset_key, updated_at = now()
    WHERE id = v_application.merchant_id;
  END IF;

  UPDATE public.qris_applications
  SET qris_reference = v_qris_reference,
      qris_asset_key = v_qris_asset_key,
      gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      status = 'ISSUED_PENDING_ACTIVATION',
      issued_by_admin_id = auth.uid(),
      issued_at = now(),
      updated_at = now()
  WHERE id = p_application_id;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'status', 'ISSUED_PENDING_ACTIVATION',
    'qris_mpm_enabled', true,
    'static_qr_uploaded', v_qris_asset_key IS NOT NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris_mpm(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris_mpm(uuid, text, text, text, text) TO authenticated;

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
    RAISE EXCEPTION 'Pengajuan belum siap diaktifkan' USING ERRCODE = '23514';
  END IF;
  IF NULLIF(trim(v_application.gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(v_application.gdc_account_number), '') IS NULL THEN
    RAISE EXCEPTION 'NMID/Merchant ID dan Account Number GDC wajib sebelum QR MPM diaktifkan' USING ERRCODE = '23514';
  END IF;

  -- If an optional static QR was uploaded, retain the old ownership/attachment check.
  IF NULLIF(trim(v_application.qris_asset_key), '') IS NOT NULL THEN
    IF NULLIF(trim(v_application.qris_reference), '') IS NULL THEN
      RAISE EXCEPTION 'Referensi penerbitan wajib untuk QRIS statis' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = v_application.merchant_id
        AND m.qris_image_url = v_application.qris_asset_key
    ) THEN
      RAISE EXCEPTION 'QRIS tidak terpasang pada merchant yang diajukan' USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE public.qris_applications
  SET status = 'ACTIVE',
      activated_by_admin_id = auth.uid(),
      activated_at = now(),
      updated_at = now()
  WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_activate_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_qris(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
