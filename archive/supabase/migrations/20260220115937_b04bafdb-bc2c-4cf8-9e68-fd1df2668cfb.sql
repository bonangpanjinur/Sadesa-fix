-- Fix search_path on set_updated_at function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public$bootstrap_sql_2d57410cf5af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d57410cf5af$;

DO $bootstrap_do_ae9dd03e91e2$
BEGIN
  EXECUTE $bootstrap_sql_ae9dd03e91e2$
