-- Add merchant auto approve setting to app_settings
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
    'merchant_auto_approve',
    '{"enabled": false}',
    'Enable/disable automatic approval for new merchant registrations',
    'registration'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_0e21ca92bd84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e21ca92bd84$;

DO $bootstrap_do_006c2cc346ab$
BEGIN
  EXECUTE $bootstrap_sql_006c2cc346ab$
