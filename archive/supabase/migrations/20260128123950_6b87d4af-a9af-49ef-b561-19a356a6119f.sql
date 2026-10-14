-- Fix overly permissive RLS policies

-- 1. Fix notifications table: "System can insert notifications" with WITH CHECK (true)
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications$bootstrap_sql_5d20ad708383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d20ad708383$;

DO $bootstrap_do_afcc7e961882$
BEGIN
  EXECUTE $bootstrap_sql_afcc7e961882$DROP POLICY IF EXISTS "System can insert notifications for authenticated users" ON public.notifications$bootstrap_sql_afcc7e961882$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_afcc7e961882$;

DO $bootstrap_do_df4f0f1f5ac3$
BEGIN
  EXECUTE $bootstrap_sql_df4f0f1f5ac3$CREATE POLICY "System can insert notifications for authenticated users"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (true)$bootstrap_sql_df4f0f1f5ac3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df4f0f1f5ac3$;

DO $bootstrap_do_ffba3a8d3afb$
BEGIN
  EXECUTE $bootstrap_sql_ffba3a8d3afb$-- 2. Fix rate_limits table
DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits$bootstrap_sql_ffba3a8d3afb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ffba3a8d3afb$;

DO $bootstrap_do_b1558ca834c0$
BEGIN
  EXECUTE $bootstrap_sql_b1558ca834c0$DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits$bootstrap_sql_b1558ca834c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1558ca834c0$;

DO $bootstrap_do_2c544fe9380b$
BEGIN
  EXECUTE $bootstrap_sql_2c544fe9380b$DROP POLICY IF EXISTS "Users can insert own rate limits" ON public.rate_limits$bootstrap_sql_2c544fe9380b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c544fe9380b$;

DO $bootstrap_do_fc2600d03410$
BEGIN
  EXECUTE $bootstrap_sql_fc2600d03410$CREATE POLICY "Users can insert own rate limits"
ON public.rate_limits
FOR INSERT
TO authenticated
WITH CHECK (identifier = (auth.uid())::text)$bootstrap_sql_fc2600d03410$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc2600d03410$;

DO $bootstrap_do_2b4203bb789e$
BEGIN
  EXECUTE $bootstrap_sql_2b4203bb789e$DROP POLICY IF EXISTS "Users can update own rate limits" ON public.rate_limits$bootstrap_sql_2b4203bb789e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b4203bb789e$;

DO $bootstrap_do_768823bf6e47$
BEGIN
  EXECUTE $bootstrap_sql_768823bf6e47$CREATE POLICY "Users can update own rate limits"
ON public.rate_limits
FOR UPDATE
TO authenticated
USING (identifier = (auth.uid())::text)$bootstrap_sql_768823bf6e47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_768823bf6e47$;

DO $bootstrap_do_08e698479fdd$
BEGIN
  EXECUTE $bootstrap_sql_08e698479fdd$-- 3. Fix password_reset_tokens table - add policies
DROP POLICY IF EXISTS "Anyone can request password reset" ON public.password_reset_tokens$bootstrap_sql_08e698479fdd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08e698479fdd$;

DO $bootstrap_do_c09e46615036$
BEGIN
  EXECUTE $bootstrap_sql_c09e46615036$CREATE POLICY "Anyone can request password reset"
ON public.password_reset_tokens
FOR INSERT
TO anon, authenticated
WITH CHECK (true)$bootstrap_sql_c09e46615036$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c09e46615036$;

DO $bootstrap_do_a48fa57589f3$
BEGIN
  EXECUTE $bootstrap_sql_a48fa57589f3$DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens$bootstrap_sql_a48fa57589f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a48fa57589f3$;

DO $bootstrap_do_02de447e9792$
BEGIN
  EXECUTE $bootstrap_sql_02de447e9792$CREATE POLICY "Users can verify their tokens"
ON public.password_reset_tokens
FOR SELECT
TO anon, authenticated
USING (true)$bootstrap_sql_02de447e9792$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_02de447e9792$;

DO $bootstrap_do_ca72c5c4625b$
BEGIN
  EXECUTE $bootstrap_sql_ca72c5c4625b$DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens$bootstrap_sql_ca72c5c4625b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca72c5c4625b$;

DO $bootstrap_do_257db9e258fc$
BEGIN
  EXECUTE $bootstrap_sql_257db9e258fc$CREATE POLICY "Tokens can be marked as used"
ON public.password_reset_tokens
FOR UPDATE
TO anon, authenticated
USING (used_at IS NULL AND expires_at > now())$bootstrap_sql_257db9e258fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_257db9e258fc$;

DO $bootstrap_do_4d4b4d8457cb$
BEGIN
  EXECUTE $bootstrap_sql_4d4b4d8457cb$
