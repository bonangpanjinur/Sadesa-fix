-- Keep merchant business categories aligned with the admin-managed categories catalog.
ALTER TABLE public.merchants
  ALTER COLUMN business_category SET DEFAULT NULL$bootstrap_sql_f4f6480528db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4f6480528db$;

DO $bootstrap_do_cc8964d0c21a$
BEGIN
  EXECUTE $bootstrap_sql_cc8964d0c21a$CREATE OR REPLACE FUNCTION public.validate_active_merchant_business_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.business_category IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.categories
       WHERE slug = NEW.business_category
         AND is_active = true
     ) THEN
    RAISE EXCEPTION 'business_category must reference an active admin category: %', NEW.business_category
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_cc8964d0c21a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc8964d0c21a$;

DO $bootstrap_do_791dae8a8544$
BEGIN
  EXECUTE $bootstrap_sql_791dae8a8544$DROP TRIGGER IF EXISTS merchants_active_business_category ON public.merchants$bootstrap_sql_791dae8a8544$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_791dae8a8544$;

DO $bootstrap_do_a51e146807f8$
BEGIN
  EXECUTE $bootstrap_sql_a51e146807f8$CREATE TRIGGER merchants_active_business_category
  BEFORE INSERT OR UPDATE OF business_category ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_active_merchant_business_category()$bootstrap_sql_a51e146807f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a51e146807f8$;

DO $bootstrap_do_3b4b88abc0ab$
BEGIN
  EXECUTE $bootstrap_sql_3b4b88abc0ab$COMMENT ON FUNCTION public.validate_active_merchant_business_category() IS
  'Prevents merchant registrations and updates from using categories that are missing or inactive in the admin catalog.'$bootstrap_sql_3b4b88abc0ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b4b88abc0ab$;

DO $bootstrap_do_10e541a8cbed$
BEGIN
  EXECUTE $bootstrap_sql_10e541a8cbed$
