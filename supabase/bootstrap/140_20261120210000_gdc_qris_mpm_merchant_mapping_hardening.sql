-- QRIS MPM merchant mapping hardening.
-- One Sadesa merchant must resolve to one unambiguous active GDC identity.

CREATE UNIQUE INDEX IF NOT EXISTS qris_applications_one_active_per_merchant_idx
  ON public.qris_applications (merchant_id)
  WHERE status = 'ACTIVE';

CREATE OR REPLACE FUNCTION public.guard_qris_gdc_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'Identitas GDC QRIS hanya dapat dikelola admin' USING ERRCODE = '42501';
    END IF;
  ELSIF (NEW.gdc_merchant_id IS DISTINCT FROM OLD.gdc_merchant_id
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
BEFORE INSERT OR UPDATE OF gdc_merchant_id, gdc_account_number, status ON public.qris_applications
FOR EACH ROW EXECUTE FUNCTION public.guard_qris_gdc_assignment();

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
      AND NULLIF(trim(gdc_merchant_id), '') IS NOT NULL
      AND NULLIF(trim(gdc_account_number), '') IS NOT NULL
  );
$$;
REVOKE ALL ON FUNCTION public.merchant_has_active_gdc_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_has_active_gdc_qris(uuid) TO authenticated;

-- Keep browser access limited to the application workflow; payment transactions
-- remain service-role-only and can only be written by the Edge Function.
ALTER TABLE public.gdc_qris_mpm_payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.gdc_qris_mpm_payments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.gdc_qris_mpm_payments TO service_role;
