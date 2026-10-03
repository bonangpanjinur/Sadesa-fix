-- Auto-confirm ordinary account signups so registration does not block on OTP.
-- Business applications remain subject to their existing merchant/courier/village
-- review workflows and are not auto-approved by this migration.
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.email_confirmed_at = COALESCE(NEW.email_confirmed_at, NOW());
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_auto_confirm_email() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm ON auth.users;
CREATE TRIGGER on_auth_user_created_auto_confirm
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auto_confirm_email();
