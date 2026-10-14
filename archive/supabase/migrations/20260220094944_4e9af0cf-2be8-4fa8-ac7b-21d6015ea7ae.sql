-- Add is_self_delivery column to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS is_self_delivery boolean DEFAULT false$bootstrap_sql_db906ce76c17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db906ce76c17$;

DO $bootstrap_do_e263e68a4c54$
BEGIN
  EXECUTE $bootstrap_sql_e263e68a4c54$
