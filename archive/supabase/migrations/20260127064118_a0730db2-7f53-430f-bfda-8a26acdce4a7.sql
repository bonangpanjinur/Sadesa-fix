-- Add COD settings to app_settings
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
  'cod_settings',
  '{"enabled": true, "max_amount": 75000, "max_distance_km": 3, "service_fee": 0, "min_trust_score": 50, "confirmation_timeout_minutes": 15, "penalty_points": 50, "success_bonus_points": 1}',
  'Pengaturan fitur COD (Cash on Delivery)',
  'payment'
) ON CONFLICT (key) DO NOTHING$bootstrap_sql_d3b318bbd1e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3b318bbd1e3$;

DO $bootstrap_do_1ce0873361b5$
BEGIN
  EXECUTE $bootstrap_sql_1ce0873361b5$
