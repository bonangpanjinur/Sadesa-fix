-- Guest checkout rollout control.
-- Default is disabled so deployment can validate staging and pilot traffic first.
DO $bootstrap_do_guest_checkout_rollout_flag$
BEGIN
  EXECUTE $bootstrap_sql_guest_checkout_rollout_flag$
    INSERT INTO public.app_settings (key, value)
    VALUES ('guest_checkout_enabled', '{"enabled": false, "rollout_percent": 0, "pilot_user_ids": []}'::jsonb)
    ON CONFLICT (key) DO NOTHING;
  $bootstrap_sql_guest_checkout_rollout_flag$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_guest_checkout_rollout_flag$;
