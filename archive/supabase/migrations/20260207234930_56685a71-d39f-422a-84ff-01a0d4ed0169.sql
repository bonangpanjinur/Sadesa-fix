-- Fix the permissive INSERT policy - restrict to authenticated users whose merchant matches
DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs$bootstrap_sql_feb66cbc3b00$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_feb66cbc3b00$;

DO $bootstrap_do_09c505a21fcd$
BEGIN
  EXECUTE $bootstrap_sql_09c505a21fcd$DROP POLICY IF EXISTS "Authenticated users can insert quota logs" ON public.quota_usage_logs$bootstrap_sql_09c505a21fcd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09c505a21fcd$;

DO $bootstrap_do_46ecd45f5c46$
BEGIN
  EXECUTE $bootstrap_sql_46ecd45f5c46$CREATE POLICY "Authenticated users can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin')
  )$bootstrap_sql_46ecd45f5c46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46ecd45f5c46$;

DO $bootstrap_do_98ef524da12c$
BEGIN
  EXECUTE $bootstrap_sql_98ef524da12c$
