-- Legacy profiles can have NULL is_blocked because the column was added after
-- those rows were created. Treat NULL as not blocked so normal users can still
-- edit their own profile; blocked rows remain denied.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = user_id AND COALESCE(is_blocked, false) = false)
  WITH CHECK (auth.uid() = user_id AND COALESCE(is_blocked, false) = false);
