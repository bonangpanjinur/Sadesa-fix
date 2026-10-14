-- Keep the legacy monthly free-tier fallback configured for merchants that do
-- not have an active subscription. The onboarding package remains authoritative
-- for new merchants.
INSERT INTO public.app_settings (key, category, value, description)
VALUES (
  'free_tier_quota',
  'quota',
  '{"limit": 100}'::jsonb,
  'Batas transaksi gratis fallback per bulan untuk merchant tanpa subscription aktif'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_401bf2f34956$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_401bf2f34956$;

DO $bootstrap_do_19d39a7cec60$
BEGIN
  EXECUTE $bootstrap_sql_19d39a7cec60$
