-- Fase 1: Pasang trigger handle_new_user yang hilang
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users$bootstrap_sql_8d2489d7defd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d2489d7defd$;

DO $bootstrap_do_a02243218035$
BEGIN
  EXECUTE $bootstrap_sql_a02243218035$CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user()$bootstrap_sql_a02243218035$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a02243218035$;

DO $bootstrap_do_0fd3bc9ad2fd$
BEGIN
  EXECUTE $bootstrap_sql_0fd3bc9ad2fd$
