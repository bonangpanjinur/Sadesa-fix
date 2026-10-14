-- Drop overloads that will cause ambiguity when policies call the no-arg form
DROP FUNCTION IF EXISTS public.get_user_courier_id(uuid)$bootstrap_sql_fa8ea2e2e17d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa8ea2e2e17d$;

DO $bootstrap_do_602e1baa98fd$
BEGIN
  EXECUTE $bootstrap_sql_602e1baa98fd$DROP FUNCTION IF EXISTS public.get_user_merchant_id(uuid)$bootstrap_sql_602e1baa98fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_602e1baa98fd$;

DO $bootstrap_do_86ace08d8b84$
BEGIN
  EXECUTE $bootstrap_sql_86ace08d8b84$-- Recreate with SINGLE signature (no default arg to avoid overload conflict)
CREATE OR REPLACE FUNCTION public.get_user_merchant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.merchants WHERE user_id = auth.uid() LIMIT 1
$$$bootstrap_sql_86ace08d8b84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86ace08d8b84$;

DO $bootstrap_do_24988603f9b2$
BEGIN
  EXECUTE $bootstrap_sql_24988603f9b2$CREATE OR REPLACE FUNCTION public.get_user_courier_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.couriers WHERE user_id = auth.uid() LIMIT 1
$$$bootstrap_sql_24988603f9b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_24988603f9b2$;

DO $bootstrap_do_63094f7fb85a$
BEGIN
  EXECUTE $bootstrap_sql_63094f7fb85a$
