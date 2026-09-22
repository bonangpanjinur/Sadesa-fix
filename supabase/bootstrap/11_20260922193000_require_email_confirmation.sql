-- ===== BEGIN SOURCE: 20260922193000_require_email_confirmation.sql =====
-- New accounts must confirm ownership of the mailbox before they can sign in.
-- Do not alter already-confirmed users; this changes signup behavior going forward.

DO $bootstrap_do_require_email_confirmation$
BEGIN
  EXECUTE $bootstrap_sql_require_email_confirmation$DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm ON auth.users$bootstrap_sql_require_email_confirmation$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_require_email_confirmation$;

-- Keep the legacy function harmless if an older deployment references it, but
-- prevent public roles from invoking it directly.
DO $bootstrap_do_require_email_confirmation_hardening$
BEGIN
  EXECUTE $bootstrap_sql_require_email_confirmation_hardening$REVOKE ALL ON FUNCTION public.handle_auto_confirm_email() FROM PUBLIC, anon, authenticated$bootstrap_sql_require_email_confirmation_hardening$;
EXCEPTION
  WHEN undefined_function OR duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_require_email_confirmation_hardening$;

-- ===== END SOURCE: 20260922193000_require_email_confirmation.sql =====
