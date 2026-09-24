-- The profile editor sends ktp_number for merchant onboarding.
-- Keep this migration idempotent so it is safe on partially migrated projects.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS ktp_number TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_ktp_number_unique_idx
  ON public.profiles (ktp_number)
  WHERE ktp_number IS NOT NULL AND btrim(ktp_number) <> '';

-- Legacy profiles can have NULL is_blocked because the column was added after
-- those rows were created. Treat NULL as not blocked so normal users can still
-- edit their own profile; blocked rows remain denied.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = user_id AND COALESCE(is_blocked, false) = false)
  WITH CHECK (auth.uid() = user_id AND COALESCE(is_blocked, false) = false);
