-- Separate dynamic GDC availability from the static QRIS application lifecycle.
-- This also repairs migration 140's INSERT guard: merchant applications with no
-- GDC assignment must remain insertable by their owners.
ALTER TABLE public.qris_applications
  ADD COLUMN IF NOT EXISTS gdc_mpm_enabled boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.guard_qris_gdc_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Ordinary merchant applications contain no GDC mapping. Only reject an
    -- insert that tries to set GDC identity or turn on dynamic payments.
    IF (NULLIF(trim(NEW.gdc_merchant_id), '') IS NOT NULL
        OR NULLIF(trim(NEW.gdc_account_number), '') IS NOT NULL
        OR NEW.gdc_mpm_enabled IS TRUE)
       AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'Identitas GDC QRIS hanya dapat dikelola admin' USING ERRCODE = '42501';
    END IF;
  ELSIF (NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id
      OR NEW.gdc_account_number IS DISTINCT FROM OLD.gdc_account_number
      OR NEW.gdc_mpm_enabled IS DISTINCT FROM OLD.gdc_mpm_enabled)
      AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Identitas GDC QRIS hanya dapat dikelola admin' USING ERRCODE = '42501';
  END IF;

  IF NEW.gdc_mpm_enabled IS TRUE
     AND (NEW.status <> 'ACTIVE'
       OR NULLIF(trim(NEW.gdc_merchant_id), '') IS NULL
       OR NULLIF(trim(NEW.gdc_account_number), '') IS NULL) THEN
    RAISE EXCEPTION 'QRIS MPM hanya dapat diaktifkan pada mapping lengkap dan aplikasi aktif' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_qris_gdc_assignment() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS qris_applications_guard_gdc_assignment ON public.qris_applications;
CREATE TRIGGER qris_applications_guard_gdc_assignment
BEFORE INSERT OR UPDATE OF gdc_merchant_id, gdc_account_number, gdc_mpm_enabled, status
ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.guard_qris_gdc_assignment();

-- Audit mapping changes and enable/disable actions without storing the actual
-- merchant identifiers or account number in the log metadata.
CREATE OR REPLACE FUNCTION public.log_qris_gdc_mapping_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND (NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id
       OR NEW.gdc_account_number IS DISTINCT FROM OLD.gdc_account_number
       OR NEW.gdc_mpm_enabled IS DISTINCT FROM OLD.gdc_mpm_enabled) THEN
    INSERT INTO public.qris_application_activity_logs(
      application_id, actor_user_id, actor_role, action, from_status, to_status, metadata
    ) VALUES (
      NEW.id,
      auth.uid(),
      'admin',
      'GDC_MPM_MAPPING_CHANGED',
      CASE WHEN OLD.gdc_mpm_enabled THEN 'ENABLED' ELSE 'DISABLED' END,
      CASE WHEN NEW.gdc_mpm_enabled THEN 'ENABLED' ELSE 'DISABLED' END,
      jsonb_build_object(
        'merchant_id_changed', NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id,
        'account_number_changed', NEW.gdc_account_number IS DISTINCT FROM OLD.gdc_account_number,
        'enabled_changed', NEW.gdc_mpm_enabled IS DISTINCT FROM OLD.gdc_mpm_enabled
      )
    );
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.log_qris_gdc_mapping_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS qris_applications_log_gdc_mapping_change ON public.qris_applications;
CREATE TRIGGER qris_applications_log_gdc_mapping_change
AFTER UPDATE OF gdc_merchant_id, gdc_account_number, gdc_mpm_enabled
ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.log_qris_gdc_mapping_change();

CREATE OR REPLACE FUNCTION public.merchant_has_active_gdc_qris(p_merchant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.qris_applications
    WHERE merchant_id = p_merchant_id
      AND status = 'ACTIVE'
      AND gdc_mpm_enabled IS TRUE
      AND NULLIF(trim(gdc_merchant_id), '') IS NOT NULL
      AND NULLIF(trim(gdc_account_number), '') IS NOT NULL
  );
$$;
REVOKE ALL ON FUNCTION public.merchant_has_active_gdc_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_has_active_gdc_qris(uuid) TO authenticated;

-- Updating an active identity first disables dynamic payment atomically; the
-- administrator must explicitly re-enable it after checking the new pairing.
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
  IF NOT FOUND OR v_application.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Only an active QRIS application can be configured' USING ERRCODE = '22023';
  END IF;
  UPDATE public.qris_applications
  SET gdc_merchant_id = trim(p_gdc_merchant_id),
      gdc_account_number = trim(p_gdc_account_number),
      gdc_mpm_enabled = false,
      updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'status', 'ACTIVE', 'gdc_mpm_enabled', false);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_configure_qris_mpm(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_qris_mpm_enabled(
  p_application_id uuid,
  p_enabled boolean
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
  IF p_application_id IS NULL OR p_enabled IS NULL THEN
    RAISE EXCEPTION 'Application and enable state are required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_application FROM public.qris_applications
  WHERE id = p_application_id FOR UPDATE;
  IF NOT FOUND OR v_application.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'GDC MPM can only be changed for an active QRIS application' USING ERRCODE = '22023';
  END IF;
  IF p_enabled AND (
    NULLIF(trim(v_application.gdc_merchant_id), '') IS NULL
    OR NULLIF(trim(v_application.gdc_account_number), '') IS NULL
  ) THEN
    RAISE EXCEPTION 'Configure and verify the GDC merchant mapping before enabling' USING ERRCODE = '22023';
  END IF;
  UPDATE public.qris_applications
  SET gdc_mpm_enabled = p_enabled, updated_at = now()
  WHERE id = p_application_id;
  RETURN jsonb_build_object('success', true, 'application_id', p_application_id, 'gdc_mpm_enabled', p_enabled);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_qris_mpm_enabled(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_qris_mpm_enabled(uuid, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
