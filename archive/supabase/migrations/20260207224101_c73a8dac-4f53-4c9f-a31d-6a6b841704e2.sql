-- Add cancellation columns to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ$bootstrap_sql_4dbcf7061de0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dbcf7061de0$;

DO $bootstrap_do_9487dd02c82e$
BEGIN
  EXECUTE $bootstrap_sql_9487dd02c82e$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_by UUID$bootstrap_sql_9487dd02c82e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9487dd02c82e$;

DO $bootstrap_do_6f0f6a48c7ad$
BEGIN
  EXECUTE $bootstrap_sql_6f0f6a48c7ad$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT$bootstrap_sql_6f0f6a48c7ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f0f6a48c7ad$;

DO $bootstrap_do_d627fd12e52d$
BEGIN
  EXECUTE $bootstrap_sql_d627fd12e52d$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_type TEXT$bootstrap_sql_d627fd12e52d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d627fd12e52d$;

DO $bootstrap_do_f765a337ffb6$
BEGIN
  EXECUTE $bootstrap_sql_f765a337ffb6$
