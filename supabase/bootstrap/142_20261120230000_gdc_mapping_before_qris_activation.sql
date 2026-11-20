-- Let admins record the GDC identity while the issued static QRIS is still
-- pending activation. Dynamic MPM remains disabled until a separate explicit
-- admin action after the application becomes ACTIVE.
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
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_application_id IS NULL
     OR NULLIF(trim(p_gdc_merchant_id), '') IS NULL
     OR NULLIF(trim(p_gdc_account_number), '') IS NULL
     OR length(trim(p_gdc_merchant_id)) > 100
     OR length(trim(p_gdc_account_number)) > 100 THEN
    RAISE EXCEPTION 'Valid GDC merchant identity is required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_application FROM public.qris_applications
  WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND OR v_application.status NOT IN ('ACTIVE', 'ISSUED_PENDING_ACTIVATION') THEN
    RAISE EXCEPTION 'Only an issued QRIS application can be configured' USING ERRCODE = '22023';
  END IF;
  UPDATE public.qris_applications
  SET gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      gdc_mpm_enabled = false,
      updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'status', v_application.status,
    'gdc_mpm_enabled', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
