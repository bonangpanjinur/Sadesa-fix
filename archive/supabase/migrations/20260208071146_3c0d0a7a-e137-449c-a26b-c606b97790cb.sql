-- Add notification sound setting to merchants
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS notification_sound_enabled BOOLEAN DEFAULT true$bootstrap_sql_03a8d66459c8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03a8d66459c8$;

DO $bootstrap_do_6aebc3672a53$
BEGIN
  EXECUTE $bootstrap_sql_6aebc3672a53$
