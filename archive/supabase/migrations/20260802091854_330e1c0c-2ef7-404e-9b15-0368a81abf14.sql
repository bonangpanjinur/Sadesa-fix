DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants$bootstrap_sql_7daed97e3978$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7daed97e3978$;

DO $bootstrap_do_dc524196b387$
BEGIN
  EXECUTE $bootstrap_sql_dc524196b387$DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses$bootstrap_sql_dc524196b387$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc524196b387$;

DO $bootstrap_do_36332517d7bf$
BEGIN
  EXECUTE $bootstrap_sql_36332517d7bf$
