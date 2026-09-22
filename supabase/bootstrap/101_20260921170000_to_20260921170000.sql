-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260921170000_order_notification_sounds.sql .. 20260921170000_order_notification_sounds.sql

-- ===== BEGIN SOURCE: 20260921170000_order_notification_sounds.sql =====
-- Admin-managed audio assets for order notification alarms.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'notification-sounds',
  'notification-sounds',
  true,
  5242880,
  ARRAY['audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp4']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Anyone can listen to notification sounds" ON storage.objects;
CREATE POLICY "Anyone can listen to notification sounds"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'notification-sounds');

DROP POLICY IF EXISTS "Admins can upload notification sounds" ON storage.objects;
CREATE POLICY "Admins can upload notification sounds"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can update notification sounds" ON storage.objects;
CREATE POLICY "Admins can update notification sounds"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete notification sounds" ON storage.objects;
CREATE POLICY "Admins can delete notification sounds"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin());

INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'order_notification_sound_settings',
  '{"enabled":true,"merchant_enabled":true,"courier_enabled":true,"preset":"urgent","custom_audio_url":"","volume":1,"repeat_count":3,"repeat_gap_ms":700}'::jsonb,
  'notification',
  'Pengaturan suara alarm pesanan masuk untuk merchant dan kurir'
)
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260921170000_order_notification_sounds.sql =====
