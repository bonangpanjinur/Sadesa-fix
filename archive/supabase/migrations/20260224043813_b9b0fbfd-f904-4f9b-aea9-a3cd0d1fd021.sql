-- Add sold_count column to products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sold_count integer NOT NULL DEFAULT 0$bootstrap_sql_f7593c801f67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7593c801f67$;

DO $bootstrap_do_61e764d74670$
BEGIN
  EXECUTE $bootstrap_sql_61e764d74670$-- Create index for sorting by sold_count
CREATE INDEX IF NOT EXISTS idx_products_sold_count ON public.products(sold_count DESC)$bootstrap_sql_61e764d74670$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_61e764d74670$;

DO $bootstrap_do_a3b89606a87e$
BEGIN
  EXECUTE $bootstrap_sql_a3b89606a87e$
