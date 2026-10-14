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
  allowed_mime_types = EXCLUDED.allowed_mime_types$bootstrap_sql_83fa3e869a99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83fa3e869a99$;

DO $bootstrap_do_55e7e31f8901$
BEGIN
  EXECUTE $bootstrap_sql_55e7e31f8901$DROP POLICY IF EXISTS "Anyone can listen to notification sounds" ON storage.objects$bootstrap_sql_55e7e31f8901$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55e7e31f8901$;

DO $bootstrap_do_2a0c4527484e$
BEGIN
  EXECUTE $bootstrap_sql_2a0c4527484e$CREATE POLICY "Anyone can listen to notification sounds"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'notification-sounds')$bootstrap_sql_2a0c4527484e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a0c4527484e$;

DO $bootstrap_do_12540f3dc348$
BEGIN
  EXECUTE $bootstrap_sql_12540f3dc348$DROP POLICY IF EXISTS "Admins can upload notification sounds" ON storage.objects$bootstrap_sql_12540f3dc348$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12540f3dc348$;

DO $bootstrap_do_a84813d1f2da$
BEGIN
  EXECUTE $bootstrap_sql_a84813d1f2da$CREATE POLICY "Admins can upload notification sounds"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_a84813d1f2da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a84813d1f2da$;

DO $bootstrap_do_6e18c2a89b88$
BEGIN
  EXECUTE $bootstrap_sql_6e18c2a89b88$DROP POLICY IF EXISTS "Admins can update notification sounds" ON storage.objects$bootstrap_sql_6e18c2a89b88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e18c2a89b88$;

DO $bootstrap_do_b0217923a592$
BEGIN
  EXECUTE $bootstrap_sql_b0217923a592$CREATE POLICY "Admins can update notification sounds"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_b0217923a592$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0217923a592$;

DO $bootstrap_do_22b974783646$
BEGIN
  EXECUTE $bootstrap_sql_22b974783646$DROP POLICY IF EXISTS "Admins can delete notification sounds" ON storage.objects$bootstrap_sql_22b974783646$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22b974783646$;

DO $bootstrap_do_cc30a2c8cf57$
BEGIN
  EXECUTE $bootstrap_sql_cc30a2c8cf57$CREATE POLICY "Admins can delete notification sounds"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_cc30a2c8cf57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc30a2c8cf57$;

DO $bootstrap_do_12dbdc6181e6$
BEGIN
  EXECUTE $bootstrap_sql_12dbdc6181e6$INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'order_notification_sound_settings',
  '{"enabled":true,"merchant_enabled":true,"courier_enabled":true,"preset":"urgent","custom_audio_url":"","volume":1,"repeat_count":3,"repeat_gap_ms":700}'::jsonb,
  'notification',
  'Pengaturan suara alarm pesanan masuk untuk merchant dan kurir'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_12dbdc6181e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12dbdc6181e6$;

DO $bootstrap_do_20a9f65def78$
BEGIN
  EXECUTE $bootstrap_sql_20a9f65def78$
