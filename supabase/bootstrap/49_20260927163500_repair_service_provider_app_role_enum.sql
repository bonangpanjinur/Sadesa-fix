-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

-- Repair schema drift in deployments where the exclusive-business-role
-- function was installed before app_role gained service_provider.
-- Keep enum extension isolated from any use of the new label in this file.
DO $bootstrap_do_49_role_enum$
BEGIN
  EXECUTE $bootstrap_sql_49_role_enum$ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'service_provider'$bootstrap_sql_49_role_enum$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49_role_enum$;
