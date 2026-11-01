-- Prevent QRIS approval when any required merchant document is missing.
-- This is intentionally enforced in the trigger so direct API/database updates
-- cannot bypass the admin UI guard.
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
  v_required_document text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT (v_admin_import AND v_is_admin)
       AND (NEW.status <> 'SUBMITTED' OR NEW.applicant_user_id <> v_actor) THEN
      RAISE EXCEPTION 'Pengajuan QRIS baru hanya dapat dikirim oleh merchant pemilik' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT v_is_admin AND (
    NEW.merchant_id <> OLD.merchant_id
    OR NEW.applicant_user_id <> OLD.applicant_user_id
    OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference
    OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key
    OR NEW.issued_by_admin_id IS DISTINCT FROM OLD.issued_by_admin_id
    OR NEW.activated_by_admin_id IS DISTINCT FROM OLD.activated_by_admin_id
  ) THEN
    RAISE EXCEPTION 'Merchant tidak dapat mengubah data penetapan QRIS' USING ERRCODE = '42501';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT v_is_admin THEN
      IF NOT (OLD.status = 'NEEDS_CORRECTION' AND NEW.status = 'SUBMITTED' AND OLD.applicant_user_id = v_actor) THEN
        RAISE EXCEPTION 'Transisi status QRIS ini hanya dapat dilakukan oleh admin' USING ERRCODE = '42501';
      END IF;
    ELSE
      IF NEW.status = 'APPROVED_PENDING_ISSUANCE' THEN
        FOREACH v_required_document IN ARRAY ARRAY['OWNER_ID', 'OWNER_SELFIE', 'BUSINESS_LOCATION', 'PRODUCT'] LOOP
          IF COALESCE(NULLIF(btrim(NEW.documents ->> v_required_document), ''), '') = '' THEN
            RAISE EXCEPTION 'Dokumen wajib belum lengkap: %', v_required_document USING ERRCODE = '23514';
          END IF;
        END LOOP;
      END IF;

      IF NOT (
        (OLD.status IN ('SUBMITTED','IN_REVIEW') AND NEW.status IN ('IN_REVIEW','NEEDS_CORRECTION','REJECTED','APPROVED_PENDING_ISSUANCE')) OR
        (OLD.status = 'APPROVED_PENDING_ISSUANCE' AND NEW.status = 'ISSUED_PENDING_ACTIVATION') OR
        (OLD.status = 'ISSUED_PENDING_ACTIVATION' AND NEW.status = 'ACTIVE')
      ) THEN
        RAISE EXCEPTION 'Transisi status QRIS tidak valid: % -> %', OLD.status, NEW.status USING ERRCODE = '23514';
      END IF;
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
