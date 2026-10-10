-- Stop provisioning the retired merchant free trial during registration.
-- The commission wallet is provisioned independently by the current wallet trigger.
DO $bootstrap_do_retire_merchant_free_trial_trigger$
BEGIN
  EXECUTE $bootstrap_sql_retire_merchant_free_trial_trigger$
    DROP TRIGGER IF EXISTS grant_new_merchant_free_trial_trigger ON public.merchants
  $bootstrap_sql_retire_merchant_free_trial_trigger$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema
    OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_retire_merchant_free_trial_trigger$;
