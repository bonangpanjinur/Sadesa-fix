-- ===== BEGIN SOURCE: 20260922170000_dual_buyer_roles.sql =====
-- Every merchant and courier is also a marketplace buyer.
-- Keep role assignment server-side and repair legacy profiles missing role rows.

DO $bootstrap_do_dual_merchant_role$
BEGIN
  EXECUTE $bootstrap_sql_dual_merchant_role$CREATE OR REPLACE FUNCTION public.handle_merchant_approval_role()
RETURNS TRIGGER AS $dual_merchant_role$
BEGIN
  IF NEW.user_id IS NOT NULL AND COALESCE(NEW.registration_status, '') <> 'REJECTED' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'buyer')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'merchant')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$dual_merchant_role$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_dual_merchant_role$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dual_merchant_role$;

DO $bootstrap_do_dual_courier_role$
BEGIN
  EXECUTE $bootstrap_sql_dual_courier_role$CREATE OR REPLACE FUNCTION public.handle_courier_registration_role()
RETURNS TRIGGER AS $dual_courier_role$
BEGIN
  IF NEW.user_id IS NOT NULL AND COALESCE(NEW.registration_status, '') <> 'REJECTED' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'buyer')
    ON CONFLICT (user_id, role) DO NOTHING;

    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'courier')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$dual_courier_role$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_dual_courier_role$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dual_courier_role$;

DO $bootstrap_do_dual_role_triggers$
BEGIN
  EXECUTE $bootstrap_sql_dual_role_triggers$DROP TRIGGER IF EXISTS on_merchant_dual_role_insert ON public.merchants$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$CREATE TRIGGER on_merchant_dual_role_insert
    AFTER INSERT ON public.merchants
    FOR EACH ROW EXECUTE FUNCTION public.handle_merchant_approval_role()$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$DROP TRIGGER IF EXISTS on_merchant_dual_role_update ON public.merchants$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$CREATE TRIGGER on_merchant_dual_role_update
    AFTER UPDATE OF user_id, registration_status ON public.merchants
    FOR EACH ROW EXECUTE FUNCTION public.handle_merchant_approval_role()$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$DROP TRIGGER IF EXISTS on_courier_dual_role_insert ON public.couriers$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$CREATE TRIGGER on_courier_dual_role_insert
    AFTER INSERT ON public.couriers
    FOR EACH ROW EXECUTE FUNCTION public.handle_courier_registration_role()$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$DROP TRIGGER IF EXISTS on_courier_dual_role_update ON public.couriers$bootstrap_sql_dual_role_triggers$;
  EXECUTE $bootstrap_sql_dual_role_triggers$CREATE TRIGGER on_courier_dual_role_update
    AFTER UPDATE OF user_id, registration_status ON public.couriers
    FOR EACH ROW EXECUTE FUNCTION public.handle_courier_registration_role()$bootstrap_sql_dual_role_triggers$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dual_role_triggers$;

DO $bootstrap_do_dual_role_backfill$
BEGIN
  EXECUTE $bootstrap_sql_dual_role_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT m.user_id, 'buyer'::public.app_role
  FROM public.merchants m
  WHERE m.user_id IS NOT NULL AND COALESCE(m.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_dual_role_backfill$;
  EXECUTE $bootstrap_sql_dual_role_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT m.user_id, 'merchant'::public.app_role
  FROM public.merchants m
  WHERE m.user_id IS NOT NULL AND COALESCE(m.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_dual_role_backfill$;
  EXECUTE $bootstrap_sql_dual_role_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT c.user_id, 'buyer'::public.app_role
  FROM public.couriers c
  WHERE c.user_id IS NOT NULL AND COALESCE(c.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_dual_role_backfill$;
  EXECUTE $bootstrap_sql_dual_role_backfill$INSERT INTO public.user_roles (user_id, role)
  SELECT DISTINCT c.user_id, 'courier'::public.app_role
  FROM public.couriers c
  WHERE c.user_id IS NOT NULL AND COALESCE(c.registration_status, '') <> 'REJECTED'
  ON CONFLICT (user_id, role) DO NOTHING$bootstrap_sql_dual_role_backfill$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dual_role_backfill$;

DO $bootstrap_do_dual_role_hardening$
BEGIN
  EXECUTE $bootstrap_sql_dual_role_hardening$ALTER FUNCTION public.handle_merchant_approval_role() SET search_path = public$bootstrap_sql_dual_role_hardening$;
  EXECUTE $bootstrap_sql_dual_role_hardening$ALTER FUNCTION public.handle_courier_registration_role() SET search_path = public$bootstrap_sql_dual_role_hardening$;
  EXECUTE $bootstrap_sql_dual_role_hardening$REVOKE ALL ON FUNCTION public.handle_merchant_approval_role() FROM PUBLIC, anon, authenticated$bootstrap_sql_dual_role_hardening$;
  EXECUTE $bootstrap_sql_dual_role_hardening$REVOKE ALL ON FUNCTION public.handle_courier_registration_role() FROM PUBLIC, anon, authenticated$bootstrap_sql_dual_role_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dual_role_hardening$;

-- ===== END SOURCE: 20260922170000_dual_buyer_roles.sql =====
