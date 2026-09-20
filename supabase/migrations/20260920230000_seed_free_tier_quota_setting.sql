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
ON CONFLICT (key) DO NOTHING;
