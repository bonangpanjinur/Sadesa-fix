-- Admin-assisted, idempotent bridge from the legacy GDC profile table to the
-- QRIS application workflow. It never marks an imported application ACTIVE.
CREATE OR REPLACE FUNCTION public.enforce_qris_application_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_admin_import boolean := current_setting('app.qris_admin_import', true) = 'true';
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT (v_admin_import AND v_is_admin)
       AND (NEW.status <> 'SUBMITTED' OR NEW.applicant_user_id <> v_actor) THEN
      RAISE EXCEPTION 'Pengajuan QRIS baru hanya dapat dikirim oleh merchant pemilik' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;
  IF NOT v_is_admin AND (NEW.merchant_id <> OLD.merchant_id OR NEW.applicant_user_id <> OLD.applicant_user_id OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key OR NEW.issued_by_admin_id IS DISTINCT FROM OLD.issued_by_admin_id OR NEW.activated_by_admin_id IS DISTINCT FROM OLD.activated_by_admin_id) THEN
    RAISE EXCEPTION 'Merchant tidak dapat mengubah data penetapan QRIS' USING ERRCODE = '42501';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT v_is_admin THEN
      IF NOT (OLD.status = 'NEEDS_CORRECTION' AND NEW.status = 'SUBMITTED' AND OLD.applicant_user_id = v_actor) THEN
        RAISE EXCEPTION 'Transisi status QRIS ini hanya dapat dilakukan oleh admin' USING ERRCODE = '42501';
      END IF;
    ELSIF NOT (
      (OLD.status IN ('SUBMITTED','IN_REVIEW') AND NEW.status IN ('IN_REVIEW','NEEDS_CORRECTION','REJECTED','APPROVED_PENDING_ISSUANCE')) OR
      (OLD.status = 'APPROVED_PENDING_ISSUANCE' AND NEW.status = 'ISSUED_PENDING_ACTIVATION') OR
      (OLD.status = 'ISSUED_PENDING_ACTIVATION' AND NEW.status = 'ACTIVE')
    ) THEN
      RAISE EXCEPTION 'Transisi status QRIS tidak valid: % -> %', OLD.status, NEW.status USING ERRCODE = '23514';
    END IF;
  ELSIF NOT v_is_admin THEN
    IF OLD.status <> 'NEEDS_CORRECTION' OR NEW.status <> 'NEEDS_CORRECTION' OR OLD.applicant_user_id <> v_actor THEN
      RAISE EXCEPTION 'Merchant hanya dapat memperbarui pengajuan saat diminta perbaikan' USING ERRCODE = '42501';
    END IF;
    IF NEW.merchant_id <> OLD.merchant_id OR NEW.applicant_user_id <> OLD.applicant_user_id OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key THEN
      RAISE EXCEPTION 'Merchant tidak dapat mengubah data penetapan QRIS' USING ERRCODE = '42501';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_import_legacy_qris_application(
  p_merchant_id uuid,
  p_gdc_merchant_id text DEFAULT NULL,
  p_gdc_account_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_profile public.gdc_payment_profiles%ROWTYPE;
  v_existing public.qris_applications%ROWTYPE;
  v_application public.qris_applications%ROWTYPE;
  v_gdc_merchant_id text;
  v_gdc_account_number text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO STRICT v_merchant
  FROM public.merchants
  WHERE id = p_merchant_id;

  SELECT * INTO v_profile
  FROM public.gdc_payment_profiles
  WHERE merchant_id = p_merchant_id
    AND provider = 'GDC'
  ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
  LIMIT 1;

  v_gdc_merchant_id := NULLIF(btrim(COALESCE(p_gdc_merchant_id, v_profile.provider_merchant_id)), '');
  v_gdc_account_number := NULLIF(btrim(COALESCE(p_gdc_account_number, v_profile.provider_account_number)), '');
  IF v_gdc_merchant_id IS NULL OR v_gdc_account_number IS NULL THEN
    RAISE EXCEPTION 'Legacy GDC profile tidak memiliki Merchant ID dan Account Number lengkap' USING ERRCODE = '22023';
  END IF;
  IF length(v_gdc_merchant_id) > 100 OR length(v_gdc_account_number) > 100 THEN
    RAISE EXCEPTION 'GDC identity terlalu panjang' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_existing
  FROM public.qris_applications
  WHERE merchant_id = p_merchant_id
  ORDER BY created_at DESC
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'created', false,
      'application_id', v_existing.id,
      'status', v_existing.status,
      'message', 'Merchant sudah memiliki pengajuan QRIS'
    );
  END IF;

  PERFORM set_config('app.qris_admin_import', 'true', true);
  INSERT INTO public.qris_applications (
    merchant_id,
    applicant_user_id,
    business_criteria_code,
    business_age_code,
    qris_merchant_name_short,
    qris_merchant_name,
    documents,
    status,
    revision_number,
    decision_note,
    gdc_merchant_id,
    gdc_account_number
  )
  VALUES (
    v_merchant.id,
    v_merchant.user_id,
    'UMI',
    'LEGACY_IMPORT_REQUIRES_REVIEW',
    left(coalesce(nullif(btrim(v_merchant.name), ''), 'Merchant'), 25),
    left(coalesce(nullif(btrim(v_merchant.name), ''), 'Merchant'), 50),
    '{}'::jsonb,
    'SUBMITTED',
    1,
    'Diimpor admin dari profil GDC legacy. Lengkapi dan verifikasi dokumen sebelum penerbitan QRIS.',
    v_gdc_merchant_id,
    v_gdc_account_number
  )
  RETURNING * INTO v_application;

  RETURN jsonb_build_object(
    'success', true,
    'created', true,
    'application_id', v_application.id,
    'status', v_application.status,
    'gdc_merchant_id', v_application.gdc_merchant_id,
    'gdc_account_number', v_application.gdc_account_number
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_import_legacy_qris_application(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_import_legacy_qris_application(uuid, text, text) TO authenticated;
