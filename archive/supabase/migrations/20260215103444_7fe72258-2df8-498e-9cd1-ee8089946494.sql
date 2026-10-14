-- Fix search_path on generate_merchant_slug
ALTER FUNCTION public.generate_merchant_slug(text) SET search_path = public$bootstrap_sql_4df7a459726a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4df7a459726a$;

DO $bootstrap_do_0d39acfddd5c$
BEGIN
  EXECUTE $bootstrap_sql_0d39acfddd5c$
