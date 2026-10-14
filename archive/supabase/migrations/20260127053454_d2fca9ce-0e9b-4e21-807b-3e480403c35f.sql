-- Add new roles to app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'merchant'$bootstrap_sql_d27d1c590bcd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d27d1c590bcd$;

DO $bootstrap_do_b6c28d95910e$
BEGIN
  EXECUTE $bootstrap_sql_b6c28d95910e$ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'courier'$bootstrap_sql_b6c28d95910e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6c28d95910e$;

DO $bootstrap_do_b94403f62a08$
BEGIN
  EXECUTE $bootstrap_sql_b94403f62a08$ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'admin_desa'$bootstrap_sql_b94403f62a08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b94403f62a08$;

DO $bootstrap_do_68fbd3a38fac$
BEGIN
  EXECUTE $bootstrap_sql_68fbd3a38fac$
