-- Step 1: Add 'verifikator' role to the enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'verifikator'$bootstrap_sql_cd8754722b11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd8754722b11$;

DO $bootstrap_do_bf048aeb1393$
BEGIN
  EXECUTE $bootstrap_sql_bf048aeb1393$
