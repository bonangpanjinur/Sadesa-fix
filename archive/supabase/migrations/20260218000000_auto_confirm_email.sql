-- Trigger to automatically confirm email for new users
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_email()
RETURNS TRIGGER AS $$
BEGIN
  NEW.email_confirmed_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_d3a097d1da81$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3a097d1da81$;

DO $bootstrap_do_95f795491a33$
BEGIN
  EXECUTE $bootstrap_sql_95f795491a33$-- Drop if exists and create trigger
DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm ON auth.users$bootstrap_sql_95f795491a33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95f795491a33$;

DO $bootstrap_do_ed89d12b3f2b$
BEGIN
  EXECUTE $bootstrap_sql_ed89d12b3f2b$CREATE TRIGGER on_auth_user_created_auto_confirm
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auto_confirm_email()$bootstrap_sql_ed89d12b3f2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed89d12b3f2b$;

DO $bootstrap_do_0e21ca92bd84$
BEGIN
  EXECUTE $bootstrap_sql_0e21ca92bd84$
