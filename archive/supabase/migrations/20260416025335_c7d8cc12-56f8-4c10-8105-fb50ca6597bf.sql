-- Fix 3 functions missing search_path

ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public$bootstrap_sql_797473a876b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_797473a876b9$;

DO $bootstrap_do_994d6a406730$
BEGIN
  EXECUTE $bootstrap_sql_994d6a406730$ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public$bootstrap_sql_994d6a406730$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_994d6a406730$;

DO $bootstrap_do_2871c9813033$
BEGIN
  EXECUTE $bootstrap_sql_2871c9813033$ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public$bootstrap_sql_2871c9813033$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2871c9813033$;

DO $bootstrap_do_1844b93fd4d6$
BEGIN
  EXECUTE $bootstrap_sql_1844b93fd4d6$-- Fix overly permissive RLS policy on rate_limits (WITH CHECK (true))
DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits$bootstrap_sql_1844b93fd4d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1844b93fd4d6$;

DO $bootstrap_do_0bb01840dd43$
BEGIN
  EXECUTE $bootstrap_sql_0bb01840dd43$CREATE POLICY "Rate limits insert via functions" ON public.rate_limits
  FOR INSERT TO authenticated
  WITH CHECK (identifier = auth.uid()::text OR public.is_admin())$bootstrap_sql_0bb01840dd43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0bb01840dd43$;

DO $bootstrap_do_a46635dbf2b0$
BEGIN
  EXECUTE $bootstrap_sql_a46635dbf2b0$DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits$bootstrap_sql_a46635dbf2b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a46635dbf2b0$;

DO $bootstrap_do_a5cdb09be029$
BEGIN
  EXECUTE $bootstrap_sql_a5cdb09be029$CREATE POLICY "Rate limits update via functions" ON public.rate_limits
  FOR UPDATE TO authenticated
  USING (identifier = auth.uid()::text OR public.is_admin())
  WITH CHECK (identifier = auth.uid()::text OR public.is_admin())$bootstrap_sql_a5cdb09be029$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5cdb09be029$;

DO $bootstrap_do_262de7982c03$
BEGIN
  EXECUTE $bootstrap_sql_262de7982c03$
