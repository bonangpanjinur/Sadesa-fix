-- ===== BEGIN SOURCE: 20260922191500_auto_approve_merchants.sql =====
-- Merchant registration is automatically approved and active.
-- Admin can still deactivate a merchant later; no manual approval is required.

DO $bootstrap_do_auto_approve_merchant_function$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_merchant_function$CREATE OR REPLACE FUNCTION public.auto_approve_merchant_registration()
RETURNS TRIGGER AS $auto_approve_merchant$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.registration_status := 'APPROVED';
    NEW.status := 'ACTIVE';

    -- Every merchant is also a marketplace buyer. Keep both roles
    -- idempotent so retries and the dual-role trigger are harmless.
    IF NEW.user_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'buyer'::public.app_role)
      ON CONFLICT (user_id, role) DO NOTHING;

      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'merchant'::public.app_role)
      ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$auto_approve_merchant$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_auto_approve_merchant_function$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_merchant_function$;

DO $bootstrap_do_auto_approve_merchant_trigger$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_merchant_trigger$DROP TRIGGER IF EXISTS merchant_auto_approve_on_insert ON public.merchants$bootstrap_sql_auto_approve_merchant_trigger$;
  EXECUTE $bootstrap_sql_auto_approve_merchant_trigger$CREATE TRIGGER merchant_auto_approve_on_insert
    BEFORE INSERT ON public.merchants
    FOR EACH ROW EXECUTE FUNCTION public.auto_approve_merchant_registration()$bootstrap_sql_auto_approve_merchant_trigger$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_merchant_trigger$;

DO $bootstrap_do_auto_approve_merchant_backfill$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_merchant_backfill$UPDATE public.merchants
  SET registration_status = 'APPROVED',
      status = 'ACTIVE'
  WHERE registration_status = 'PENDING'
    AND COALESCE(status, '') <> 'REJECTED'$bootstrap_sql_auto_approve_merchant_backfill$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_merchant_backfill$;

DO $bootstrap_do_auto_approve_merchant_roles_backfill$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_merchant_roles_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT m.user_id, 'buyer'::public.app_role
  FROM public.merchants m
  WHERE m.user_id IS NOT NULL
    AND COALESCE(m.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_auto_approve_merchant_roles_backfill$;

  EXECUTE $bootstrap_sql_auto_approve_merchant_roles_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT m.user_id, 'merchant'::public.app_role
  FROM public.merchants m
  WHERE m.user_id IS NOT NULL
    AND COALESCE(m.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_auto_approve_merchant_roles_backfill$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_merchant_roles_backfill$;

DO $bootstrap_do_auto_approve_merchant_hardening$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_merchant_hardening$REVOKE ALL ON FUNCTION public.auto_approve_merchant_registration() FROM PUBLIC, anon, authenticated$bootstrap_sql_auto_approve_merchant_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_merchant_hardening$;


-- Keep the INSERT policy compatible with the auto-approval trigger. Public users
-- may only submit PENDING rows; admins may create merchants directly.
DO $bootstrap_do_auto_approve_insert_policy$
BEGIN
  EXECUTE $bootstrap_sql_auto_approve_insert_policy$DROP POLICY IF EXISTS "Anyone can register merchant" ON public.merchants$bootstrap_sql_auto_approve_insert_policy$;
  EXECUTE $bootstrap_sql_auto_approve_insert_policy$CREATE POLICY "Anyone can register merchant" ON public.merchants FOR INSERT TO authenticated WITH CHECK (registration_status = 'PENDING' OR public.is_admin())$bootstrap_sql_auto_approve_insert_policy$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_auto_approve_insert_policy$;

-- ===== END SOURCE: 20260922191500_auto_approve_merchants.sql =====
