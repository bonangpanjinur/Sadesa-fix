-- P0 security hardening: the application uses Supabase Auth's native
-- resetPasswordForEmail flow. The legacy public token table must not be
-- accessible from browser clients.

REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated$bootstrap_sql_259000afe5fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_259000afe5fe$;

DO $bootstrap_do_cd9e20b0b277$
BEGIN
  EXECUTE $bootstrap_sql_cd9e20b0b277$DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens$bootstrap_sql_cd9e20b0b277$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd9e20b0b277$;

DO $bootstrap_do_2fb59c504851$
BEGIN
  EXECUTE $bootstrap_sql_2fb59c504851$DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens$bootstrap_sql_2fb59c504851$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2fb59c504851$;

DO $bootstrap_do_21349a4170ef$
BEGIN
  EXECUTE $bootstrap_sql_21349a4170ef$DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens$bootstrap_sql_21349a4170ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_21349a4170ef$;

DO $bootstrap_do_bb1a133f7d5f$
BEGIN
  EXECUTE $bootstrap_sql_bb1a133f7d5f$-- Keep the table available only to trusted server-side service_role jobs.
DROP POLICY IF EXISTS "Service role manages password reset tokens" ON public.password_reset_tokens$bootstrap_sql_bb1a133f7d5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb1a133f7d5f$;

DO $bootstrap_do_42ec1d78f332$
BEGIN
  EXECUTE $bootstrap_sql_42ec1d78f332$CREATE POLICY "Service role manages password reset tokens"
  ON public.password_reset_tokens
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true)$bootstrap_sql_42ec1d78f332$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42ec1d78f332$;

DO $bootstrap_do_91d5e2847004$
BEGIN
  EXECUTE $bootstrap_sql_91d5e2847004$COMMENT ON TABLE public.password_reset_tokens IS
  'Legacy table retained for migration compatibility; browser access is revoked. Use Supabase Auth native password recovery or a trusted server-side flow.'$bootstrap_sql_91d5e2847004$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_91d5e2847004$;

DO $bootstrap_do_cf3cc838e855$
BEGIN
  EXECUTE $bootstrap_sql_cf3cc838e855$-- Prevent accidental exposure if future migrations re-grant table privileges.
ALTER TABLE public.password_reset_tokens FORCE ROW LEVEL SECURITY$bootstrap_sql_cf3cc838e855$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf3cc838e855$;

DO $bootstrap_do_42c775b2bc77$
BEGIN
  EXECUTE $bootstrap_sql_42c775b2bc77$
