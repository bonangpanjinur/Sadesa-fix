-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_6c47b38ab74c$
BEGIN
  EXECUTE $bootstrap_sql_6c47b38ab74c$-- The profile editor sends ktp_number for merchant onboarding.
-- Keep this migration idempotent so it is safe on partially migrated projects.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS ktp_number TEXT$bootstrap_sql_6c47b38ab74c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c47b38ab74c$;

DO $bootstrap_do_034a23942350$
BEGIN
  EXECUTE $bootstrap_sql_034a23942350$CREATE UNIQUE INDEX IF NOT EXISTS profiles_ktp_number_unique_idx
  ON public.profiles (ktp_number)
  WHERE ktp_number IS NOT NULL AND btrim(ktp_number) <> ''$bootstrap_sql_034a23942350$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_034a23942350$;

DO $bootstrap_do_fa64f4b9a6f4$
BEGIN
  EXECUTE $bootstrap_sql_fa64f4b9a6f4$-- Legacy profiles can have NULL is_blocked because the column was added after
-- those rows were created. Treat NULL as not blocked so normal users can still
-- edit their own profile; blocked rows remain denied.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles$bootstrap_sql_fa64f4b9a6f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa64f4b9a6f4$;

DO $bootstrap_do_6a51a2b20ed8$
BEGIN
  EXECUTE $bootstrap_sql_6a51a2b20ed8$CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = user_id AND COALESCE(is_blocked, false) = false)
  WITH CHECK (auth.uid() = user_id AND COALESCE(is_blocked, false) = false)$bootstrap_sql_6a51a2b20ed8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a51a2b20ed8$;
