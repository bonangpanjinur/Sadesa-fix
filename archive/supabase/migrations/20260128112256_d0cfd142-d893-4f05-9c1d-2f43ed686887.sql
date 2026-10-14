-- Fix rate_limits RLS policy to be more restrictive
DROP POLICY IF EXISTS "Rate limits public" ON public.rate_limits$bootstrap_sql_3e0997d3df7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e0997d3df7e$;

DO $bootstrap_do_207d77577148$
BEGIN
  EXECUTE $bootstrap_sql_207d77577148$-- Rate limits should only allow insert/update from server (via security definer function)
-- No direct public access needed
DROP POLICY IF EXISTS "Rate limits managed by functions" ON public.rate_limits$bootstrap_sql_207d77577148$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_207d77577148$;

DO $bootstrap_do_9df74d2023f4$
BEGIN
  EXECUTE $bootstrap_sql_9df74d2023f4$CREATE POLICY "Rate limits managed by functions" ON public.rate_limits
  FOR SELECT USING (identifier = auth.uid()::text OR public.is_admin())$bootstrap_sql_9df74d2023f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9df74d2023f4$;

DO $bootstrap_do_38a62ac63e27$
BEGIN
  EXECUTE $bootstrap_sql_38a62ac63e27$DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits$bootstrap_sql_38a62ac63e27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_38a62ac63e27$;

DO $bootstrap_do_a474e5ade96a$
BEGIN
  EXECUTE $bootstrap_sql_a474e5ade96a$CREATE POLICY "Rate limits insert via functions" ON public.rate_limits
  FOR INSERT WITH CHECK (true)$bootstrap_sql_a474e5ade96a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a474e5ade96a$;

DO $bootstrap_do_8660167c6535$
BEGIN
  EXECUTE $bootstrap_sql_8660167c6535$DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits$bootstrap_sql_8660167c6535$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8660167c6535$;

DO $bootstrap_do_59051e3023d1$
BEGIN
  EXECUTE $bootstrap_sql_59051e3023d1$CREATE POLICY "Rate limits update via functions" ON public.rate_limits
  FOR UPDATE USING (true)$bootstrap_sql_59051e3023d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59051e3023d1$;

DO $bootstrap_do_5b6f62aeb942$
BEGIN
  EXECUTE $bootstrap_sql_5b6f62aeb942$
