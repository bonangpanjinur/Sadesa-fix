-- P0 security hardening: the application uses Supabase Auth's native
-- resetPasswordForEmail flow. The legacy public token table must not be
-- accessible from browser clients.

REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated;

DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens;

-- Keep the table available only to trusted server-side service_role jobs.
DROP POLICY IF EXISTS "Service role manages password reset tokens" ON public.password_reset_tokens;
CREATE POLICY "Service role manages password reset tokens"
  ON public.password_reset_tokens
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.password_reset_tokens IS
  'Legacy table retained for migration compatibility; browser access is revoked. Use Supabase Auth native password recovery or a trusted server-side flow.';

-- Prevent accidental exposure if future migrations re-grant table privileges.
ALTER TABLE public.password_reset_tokens FORCE ROW LEVEL SECURITY;
