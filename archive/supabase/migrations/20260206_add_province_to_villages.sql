-- Add province column to villages table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'villages' AND column_name = 'province') THEN
        ALTER TABLE public.villages ADD COLUMN province text;
    END IF;
END $$$bootstrap_sql_073d857ab53c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_073d857ab53c$;

DO $bootstrap_do_fff48422902c$
BEGIN
  EXECUTE $bootstrap_sql_fff48422902c$-- Update existing villages with a default province if needed
-- UPDATE public.villages SET province = 'Jawa Tengah' WHERE province IS NULL;
