-- SaDesa canonical bootstrap bundle; source migration: archive/supabase/migrations/20261015020000_meal_recommendation_templates.sql.
-- SAFE TO RE-RUN: seeds defaults only when absent and replaces the existing idempotent scheduled enqueue function.
-- Admin-configurable meal-time recommendation copy; the existing public settings SELECT policy
-- lets the homepage read non-sensitive copy while writes remain admin-only.
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
  'meal_time_recommendations',
  '{
    "pagi": {"title": "Pengingat makan pagi", "body": "Mulai hari dengan bubur ayam, nasi uduk, atau jajanan lokal.", "suggestion": "Bubur ayam, nasi uduk, atau kopi dan jajanan lokal cocok untuk memulai hari.", "enabled": true},
    "siang": {"title": "Pengingat makan siang", "body": "Saatnya makan siang—coba menu rumahan dari warung sekitar.", "suggestion": "Saatnya makan siang—coba nasi dengan lauk rumahan atau menu favorit dari warung sekitar.", "enabled": true},
    "sore": {"title": "Pengingat camilan sore", "body": "Temani sore dengan gorengan, camilan tradisional, atau minuman segar.", "suggestion": "Temani waktu santai dengan gorengan, camilan tradisional, atau minuman segar.", "enabled": true},
    "malam": {"title": "Pengingat makan malam", "body": "Cari makan malam yang mengenyangkan dari merchant lokal.", "suggestion": "Cari makan malam yang mengenyangkan atau pesan minuman hangat dari merchant lokal.", "enabled": true}
  }'::jsonb,
  'Template pesan push dan saran makanan untuk tiap waktu makan',
  'notification'
)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.enqueue_meal_time_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_enqueued integer := 0;
  v_templates jsonb;
BEGIN
  SELECT value INTO v_templates
  FROM public.app_settings
  WHERE key = 'meal_time_recommendations';

  IF v_templates IS NULL OR jsonb_typeof(v_templates) <> 'object' THEN
    v_templates := '{
      "pagi": {"title": "Pengingat makan pagi", "body": "Mulai hari dengan bubur ayam, nasi uduk, atau jajanan lokal.", "enabled": true},
      "siang": {"title": "Pengingat makan siang", "body": "Saatnya makan siang—coba menu rumahan dari warung sekitar.", "enabled": true},
      "sore": {"title": "Pengingat camilan sore", "body": "Temani sore dengan gorengan, camilan tradisional, atau minuman segar.", "enabled": true},
      "malam": {"title": "Pengingat makan malam", "body": "Cari makan malam yang mengenyangkan dari merchant lokal.", "enabled": true}
    }'::jsonb;
  END IF;

  DELETE FROM public.meal_reminder_dispatches
  WHERE local_date < (now() AT TIME ZONE 'UTC')::date - 45;

  WITH localized_subscriptions AS (
    SELECT DISTINCT
      ps.user_id,
      COALESCE(NULLIF(btrim(ps.timezone), ''), 'Asia/Jakarta') AS timezone_name,
      now() AT TIME ZONE COALESCE(NULLIF(btrim(ps.timezone), ''), 'Asia/Jakarta') AS local_now
    FROM public.push_subscriptions AS ps
    WHERE ps.endpoint IS NOT NULL
      AND ps.p256dh IS NOT NULL
      AND ps.auth IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM pg_timezone_names AS tz
        WHERE tz.name = COALESCE(NULLIF(btrim(ps.timezone), ''), 'Asia/Jakarta')
      )
  ), due_subscriptions AS (
    SELECT
      user_id,
      timezone_name,
      local_now::date AS local_date,
      CASE extract(hour FROM local_now)::integer
        WHEN 7 THEN 'pagi'
        WHEN 12 THEN 'siang'
        WHEN 16 THEN 'sore'
        WHEN 19 THEN 'malam'
      END AS meal_period
    FROM localized_subscriptions
    WHERE extract(minute FROM local_now)::integer = 0
      AND extract(hour FROM local_now)::integer IN (7, 12, 16, 19)
  ), newly_marked AS (
    INSERT INTO public.meal_reminder_dispatches (user_id, local_date, meal_period, timezone)
    SELECT due.user_id, due.local_date, due.meal_period, due.timezone_name
    FROM due_subscriptions AS due
    WHERE due.meal_period IS NOT NULL
      AND COALESCE(v_templates -> due.meal_period -> 'enabled', 'true'::jsonb) <> 'false'::jsonb
    ON CONFLICT (user_id, local_date, meal_period) DO NOTHING
    RETURNING user_id, local_date, meal_period, timezone
  )
  INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
  SELECT
    marked.user_id,
    'push',
    'meal_time_reminder',
    jsonb_build_object(
      'title', COALESCE(NULLIF(v_templates -> marked.meal_period ->> 'title', ''), CASE marked.meal_period
        WHEN 'pagi' THEN 'Pengingat makan pagi'
        WHEN 'siang' THEN 'Pengingat makan siang'
        WHEN 'sore' THEN 'Pengingat camilan sore'
        ELSE 'Pengingat makan malam'
      END),
      'body', COALESCE(NULLIF(v_templates -> marked.meal_period ->> 'body', ''), CASE marked.meal_period
        WHEN 'pagi' THEN 'Mulai hari dengan bubur ayam, nasi uduk, atau jajanan lokal.'
        WHEN 'siang' THEN 'Saatnya makan siang—coba menu rumahan dari warung sekitar.'
        WHEN 'sore' THEN 'Temani sore dengan gorengan, camilan tradisional, atau minuman segar.'
        ELSE 'Cari makan malam yang mengenyangkan dari merchant lokal.'
      END),
      'url', '/products?type=makanan',
      'data', jsonb_build_object(
        'type', 'meal_reminder',
        'period', marked.meal_period,
        'local_date', marked.local_date,
        'timezone', marked.timezone
      )
    )
  FROM newly_marked AS marked;

  GET DIAGNOSTICS v_enqueued = ROW_COUNT;
  RETURN v_enqueued;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_meal_time_reminders() FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION public.enqueue_meal_time_reminders() IS
  'Queues one enabled admin-configured Web Push meal reminder per opted-in user, local date, meal period, and timezone; the existing worker handles delivery and retries.';

NOTIFY pgrst, 'reload schema';
