-- Make the admin-selected order alarm system-wide. Keep legacy role keys
-- enabled for older clients, while the frontend now uses only `enabled`.
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'order_notification_sound_settings',
  '{"enabled":true,"merchant_enabled":true,"courier_enabled":true,"preset":"urgent","custom_audio_url":"","volume":1,"repeat_count":3,"repeat_gap_ms":700}'::jsonb,
  'notification',
  'Nada sistem global untuk semua order masuk termasuk ojek dan kurir'
)
ON CONFLICT (key) DO UPDATE
SET value = public.app_settings.value || '{"merchant_enabled":true,"courier_enabled":true}'::jsonb,
    category = 'notification',
    description = 'Nada sistem global untuk semua order masuk termasuk ojek dan kurir';
