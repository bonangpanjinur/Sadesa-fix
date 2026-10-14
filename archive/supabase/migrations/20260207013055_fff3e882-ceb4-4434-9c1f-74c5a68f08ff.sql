-- Add cover_image_url column to merchants table
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS cover_image_url TEXT$bootstrap_sql_a58538a05662$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a58538a05662$;

DO $bootstrap_do_01c04dd192da$
BEGIN
  EXECUTE $bootstrap_sql_01c04dd192da$
