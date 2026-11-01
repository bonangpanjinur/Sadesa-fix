-- QRIS workflow hardening: canonical assignment, live uniqueness, document
-- validation, admin application editing, and active-only checkout snapshots.

CREATE UNIQUE INDEX IF NOT EXISTS qris_applications_one_live_application_per_merchant_idx
  ON public.qris_applications (merchant_id)
  WHERE status IN ('SUBMITTED','IN_REVIEW','NEEDS_CORRECTION','APPROVED_PENDING_ISSUANCE','ISSUED_PENDING_ACTIVATION','ACTIVE');

CREATE OR REPLACE FUNCTION public.protect_merchant_qris_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.qris_image_url IS DISTINCT FROM OLD.qris_image_url
     AND current_setting('app.qris_assignment', true) <> 'true' THEN
    RAISE EXCEPTION 'QRIS Sadesa hanya dapat ditetapkan melalui alur QRIS Merchant' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_merchant_qris_assignment_trigger ON public.merchants;
CREATE TRIGGER protect_merchant_qris_assignment_trigger BEFORE UPDATE OF qris_image_url ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.protect_merchant_qris_assignment();

CREATE OR REPLACE FUNCTION public.enforce_qris_application_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  v_admin_import boolean := current_setting('app.qris_admin_import', true) = 'true';
  v_code text;
  v_path text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT (v_admin_import AND v_is_admin) AND (NEW.status <> 'SUBMITTED' OR NEW.applicant_user_id <> v_actor) THEN
      RAISE EXCEPTION 'Pengajuan QRIS baru hanya dapat dikirim oleh merchant pemilik' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT v_is_admin AND (
    NEW.merchant_id <> OLD.merchant_id OR NEW.applicant_user_id <> OLD.applicant_user_id
    OR NEW.qris_reference IS DISTINCT FROM OLD.qris_reference OR NEW.qris_asset_key IS DISTINCT FROM OLD.qris_asset_key
    OR NEW.issued_by_admin_id IS DISTINCT FROM OLD.issued_by_admin_id OR NEW.activated_by_admin_id IS DISTINCT FROM OLD.activated_by_admin_id
    OR NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id OR NEW.gdc_account_number IS DISTINCT FROM OLD.gdc_account_number
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
        FOREACH v_code IN ARRAY ARRAY['OWNER_ID','OWNER_SELFIE','BUSINESS_LOCATION','PRODUCT'] LOOP
          v_path := NULLIF(btrim(NEW.documents ->> v_code), '');
          IF v_path IS NULL OR split_part(v_path, '/', 1) <> NEW.applicant_user_id::text
             OR split_part(v_path, '/', 2) <> NEW.id::text
             OR NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'qris-applications' AND o.name = v_path) THEN
            RAISE EXCEPTION 'Dokumen wajib tidak ditemukan atau tidak valid: %', v_code USING ERRCODE = '23514';
          END IF;
        END LOOP;
      END IF;
      IF NOT (
        (OLD.status IN ('SUBMITTED','IN_REVIEW') AND NEW.status IN ('IN_REVIEW','NEEDS_CORRECTION','REJECTED','APPROVED_PENDING_ISSUANCE'))
        OR (OLD.status = 'APPROVED_PENDING_ISSUANCE' AND NEW.status = 'ISSUED_PENDING_ACTIVATION')
        OR (OLD.status = 'ISSUED_PENDING_ACTIVATION' AND NEW.status = 'ACTIVE')
      ) THEN
        RAISE EXCEPTION 'Transisi status QRIS tidak valid: % -> %', OLD.status, NEW.status USING ERRCODE = '23514';
      END IF;
    END IF;
  ELSIF NOT v_is_admin AND (OLD.status <> 'NEEDS_CORRECTION' OR NEW.status <> 'NEEDS_CORRECTION' OR OLD.applicant_user_id <> v_actor) THEN
    RAISE EXCEPTION 'Merchant hanya dapat memperbarui pengajuan saat diminta perbaikan' USING ERRCODE = '42501';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_qris_application_transition_trigger ON public.qris_applications;
CREATE TRIGGER enforce_qris_application_transition_trigger BEFORE INSERT OR UPDATE ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.enforce_qris_application_transition();

CREATE OR REPLACE FUNCTION public.admin_update_qris_application_details(
  p_application_id uuid, p_business_criteria_code text, p_business_age_code text,
  p_qris_merchant_name_short text, p_qris_merchant_name text,
  p_default_bank_name text, p_default_account_number text, p_default_account_name text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_application public.qris_applications%ROWTYPE; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  IF p_application_id IS NULL OR p_business_criteria_code NOT IN ('UMI','UME','UBE')
     OR NULLIF(btrim(p_business_age_code), '') IS NULL OR NULLIF(btrim(p_qris_merchant_name_short), '') IS NULL
     OR length(btrim(p_qris_merchant_name_short)) > 25 OR NULLIF(btrim(p_qris_merchant_name), '') IS NULL
     OR length(btrim(p_qris_merchant_name)) > 50 THEN
    RAISE EXCEPTION 'Data pengajuan QRIS tidak valid' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_application FROM public.qris_applications WHERE id = p_application_id FOR UPDATE;
  IF v_application.status IN ('ACTIVE','ISSUED_PENDING_ACTIVATION') THEN
    RAISE EXCEPTION 'Data aplikasi tidak dapat diedit setelah QRIS diterbitkan' USING ERRCODE = '42501';
  END IF;
  UPDATE public.qris_applications SET business_criteria_code = p_business_criteria_code, business_age_code = btrim(p_business_age_code),
    qris_merchant_name_short = btrim(p_qris_merchant_name_short), qris_merchant_name = btrim(p_qris_merchant_name),
    default_bank_name = NULLIF(btrim(p_default_bank_name), ''), default_account_number = NULLIF(btrim(p_default_account_number), ''),
    default_account_name = NULLIF(btrim(p_default_account_name), ''), updated_at = now() WHERE id = p_application_id;
  INSERT INTO public.qris_application_activity_logs(application_id, actor_user_id, actor_role, action, from_status, to_status, reason, metadata)
    VALUES (p_application_id, auth.uid(), 'admin', 'ADMIN_APPLICATION_EDITED', v_application.status, v_application.status, v_reason,
      jsonb_build_object('fields', ARRAY['business_criteria_code','business_age_code','qris_merchant_name_short','qris_merchant_name','default_bank_name','default_account_number','default_account_name']));
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', v_application.status);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_qris_application_details(uuid,text,text,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_qris_application_details(uuid,text,text,text,text,text,text,text,text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_issue_qris(uuid,text,text) FROM authenticated;

CREATE OR REPLACE FUNCTION public.admin_issue_qris_mpm(
  p_application_id uuid, p_qris_reference text, p_qris_asset_key text,
  p_gdc_merchant_id text, p_gdc_account_number text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  IF p_application_id IS NULL OR NULLIF(trim(p_qris_reference), '') IS NULL OR NULLIF(trim(p_qris_asset_key), '') IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL OR NULLIF(trim(p_gdc_account_number), '') IS NULL THEN
    RAISE EXCEPTION 'QRIS reference, asset, and GDC merchant credentials are required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_application FROM public.qris_applications WHERE id = p_application_id FOR UPDATE;
  IF v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN RAISE EXCEPTION 'Application is not ready for QRIS issuance' USING ERRCODE = '22023'; END IF;
  PERFORM set_config('app.qris_assignment', 'true', true);
  UPDATE public.merchants SET qris_image_url = left(trim(p_qris_asset_key), 1000), updated_at = now() WHERE id = v_application.merchant_id;
  UPDATE public.qris_applications SET qris_reference = left(trim(p_qris_reference), 200), qris_asset_key = left(trim(p_qris_asset_key), 1000),
    gdc_merchant_id = left(trim(p_gdc_merchant_id), 100), gdc_account_number = left(trim(p_gdc_account_number), 100),
    status = 'ISSUED_PENDING_ACTIVATION', issued_by_admin_id = auth.uid(), issued_at = now(), updated_at = now() WHERE id = p_application_id;
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ISSUED_PENDING_ACTIVATION');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris_mpm(uuid,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris_mpm(uuid,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.snapshot_order_payment_and_delivery_contract()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_merchant public.merchants%ROWTYPE; v_admin jsonb; v_active_qris_url text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.courier_delivery_fee_snapshot := GREATEST(COALESCE(NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost, 0), 0);
    IF NEW.payment_method = 'TRANSFER' AND NEW.confirmation_deadline IS NULL THEN NEW.confirmation_deadline := now() + interval '30 minutes'; END IF;
    IF NEW.payment_method = 'TRANSFER' AND NEW.payment_destination_snapshot IS NULL THEN
      IF NEW.merchant_id IS NOT NULL THEN
        SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
        SELECT a.qris_asset_key INTO v_active_qris_url FROM public.qris_applications a
          WHERE a.merchant_id = NEW.merchant_id AND a.status = 'ACTIVE' AND NULLIF(btrim(a.qris_asset_key), '') IS NOT NULL
          ORDER BY a.activated_at DESC NULLS LAST, a.updated_at DESC LIMIT 1;
      END IF;
      IF NEW.payment_channel = 'QRIS_MPM_GDC' THEN
        IF NOT EXISTS (SELECT 1 FROM public.qris_applications a WHERE a.merchant_id = NEW.merchant_id AND a.status = 'ACTIVE'
          AND NULLIF(btrim(a.gdc_merchant_id), '') IS NOT NULL AND NULLIF(btrim(a.gdc_account_number), '') IS NOT NULL) THEN
          RAISE EXCEPTION 'QRIS MPM merchant belum aktif untuk checkout' USING ERRCODE = '22023';
        END IF;
        NEW.payment_destination_snapshot := jsonb_build_object('source','GDC_MPM','merchant_name',v_merchant.name,'payment_channel','QRIS_MPM_GDC','version',3);
      ELSIF (NULLIF(btrim(COALESCE(v_merchant.bank_name, '')), '') IS NOT NULL AND NULLIF(btrim(COALESCE(v_merchant.bank_account_number, '')), '') IS NOT NULL) OR v_active_qris_url IS NOT NULL THEN
        NEW.payment_destination_snapshot := jsonb_build_object('source','MERCHANT','merchant_name',v_merchant.name,'bank_name',v_merchant.bank_name,'bank_account_number',v_merchant.bank_account_number,'bank_account_name',v_merchant.bank_account_name,'qris_image_url',v_active_qris_url,'version',2);
      ELSE
        SELECT value INTO v_admin FROM public.app_settings WHERE key = 'admin_payment_info';
        IF (NULLIF(btrim(COALESCE(v_admin->>'bank_name', '')), '') IS NOT NULL AND NULLIF(btrim(COALESCE(v_admin->>'bank_account_number', '')), '') IS NOT NULL) OR NULLIF(btrim(COALESCE(v_admin->>'qris_image_url', '')), '') IS NOT NULL THEN
          NEW.payment_destination_snapshot := jsonb_build_object('source','ADMIN','merchant_name',v_merchant.name,'bank_name',v_admin->>'bank_name','bank_account_number',v_admin->>'bank_account_number','bank_account_name',v_admin->>'bank_account_name','qris_image_url',v_admin->>'qris_image_url','version',1);
        END IF;
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.shipping_cost IS DISTINCT FROM OLD.shipping_cost OR NEW.shipping_pricing_contract IS DISTINCT FROM OLD.shipping_pricing_contract OR NEW.payment_destination_snapshot IS DISTINCT FROM OLD.payment_destination_snapshot OR NEW.courier_delivery_fee_snapshot IS DISTINCT FROM OLD.courier_delivery_fee_snapshot THEN
    RAISE EXCEPTION 'Order pricing/payment destination snapshots are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
