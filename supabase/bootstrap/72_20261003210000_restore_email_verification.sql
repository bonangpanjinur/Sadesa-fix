-- Restore real mailbox ownership verification for new signups.
-- Supabase sends the verification link/OTP; the account is not confirmed
-- until the user completes that flow.
DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm ON auth.users;

-- Keep the legacy helper inaccessible to client roles if it exists from an
-- earlier deployment. The absence of the trigger is the effective control.
DO $bootstrap_do_restore_email_verification$
BEGIN
  EXECUTE $bootstrap_sql_restore_email_verification$REVOKE ALL ON FUNCTION public.handle_auto_confirm_email() FROM PUBLIC, anon, authenticated$bootstrap_sql_restore_email_verification$;
EXCEPTION
  WHEN undefined_function THEN NULL;
END;
$bootstrap_do_restore_email_verification$;
