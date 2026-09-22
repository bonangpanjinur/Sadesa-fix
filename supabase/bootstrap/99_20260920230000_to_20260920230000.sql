-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260920230000_seed_free_tier_quota_setting.sql .. 20260920230000_seed_free_tier_quota_setting.sql

-- ===== BEGIN SOURCE: 20260920230000_seed_free_tier_quota_setting.sql =====
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

-- ===== END SOURCE: 20260920230000_seed_free_tier_quota_setting.sql =====
