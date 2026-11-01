-- Extend QRIS admin editing to include the merchant profile name and the
-- default account identifier captured with the application.
CREATE OR REPLACE FUNCTION public.admin_update_qris_application_details(
  p_application_id uuid,
  p_merchant_name text,
  p_default_account_id uuid,
  p_business_criteria_code text,
  p_business_age_code text,
  p_qris_merchant_name_short text,
  p_qris_merchant_name text,
  p_default_bank_name text,
  p_default_account_number text,
  p_default_account_name text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
  v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(btrim(p_merchant_name), '') IS NULL
     OR length(btrim(p_merchant_name)) > 150
     OR p_business_criteria_code NOT IN ('UMI','UME','UBE')
     OR NULLIF(btrim(p_business_age_code), '') IS NULL
     OR NULLIF(btrim(p_qris_merchant_name_short), '') IS NULL
     OR length(btrim(p_qris_merchant_name_short)) > 25
     OR NULLIF(btrim(p_qris_merchant_name), '') IS NULL
     OR length(btrim(p_qris_merchant_name)) > 50 THEN
    RAISE EXCEPTION 'Data pengajuan QRIS tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;

  IF v_application.status IN ('ACTIVE','ISSUED_PENDING_ACTIVATION') THEN
    RAISE EXCEPTION 'Data aplikasi tidak dapat diedit setelah QRIS diterbitkan' USING ERRCODE = '42501';
  END IF;

  UPDATE public.merchants
  SET name = btrim(p_merchant_name), updated_at = now()
  WHERE id = v_application.merchant_id;

  UPDATE public.qris_applications
  SET default_account_id = p_default_account_id,
      business_criteria_code = p_business_criteria_code,
      business_age_code = btrim(p_business_age_code),
      qris_merchant_name_short = btrim(p_qris_merchant_name_short),
      qris_merchant_name = btrim(p_qris_merchant_name),
      default_bank_name = NULLIF(btrim(p_default_bank_name), ''),
      default_account_number = NULLIF(btrim(p_default_account_number), ''),
      default_account_name = NULLIF(btrim(p_default_account_name), ''),
      updated_at = now()
  WHERE id = p_application_id;

  INSERT INTO public.qris_application_activity_logs(
    application_id, actor_user_id, actor_role, action, from_status, to_status, reason, metadata
  ) VALUES (
    p_application_id, auth.uid(), 'admin', 'ADMIN_APPLICATION_EDITED',
    v_application.status, v_application.status, v_reason,
    jsonb_build_object('fields', ARRAY[
      'merchant_name','default_account_id','business_criteria_code','business_age_code',
      'qris_merchant_name_short','qris_merchant_name','default_bank_name',
      'default_account_number','default_account_name'
    ])
  );

  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', v_application.status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_qris_application_details(uuid,text,text,text,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_update_qris_application_details(uuid,text,uuid,text,text,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_qris_application_details(uuid,text,uuid,text,text,text,text,text,text,text,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
