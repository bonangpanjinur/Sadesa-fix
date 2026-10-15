-- Schedule four opt-in meal reminder pushes using each subscription's local timezone.
-- Jobs flow through notification_delivery_jobs so the existing worker retains retries and delivery logs.
ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Asia/Jakarta';

CREATE TABLE IF NOT EXISTS public.meal_reminder_dispatches (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date date NOT NULL,
  meal_period text NOT NULL CHECK (meal_period IN ('pagi', 'siang', 'sore', 'malam')),
  timezone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, local_date, meal_period)
);

ALTER TABLE public.meal_reminder_dispatches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.meal_reminder_dispatches FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enqueue_meal_time_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_enqueued integer := 0;
BEGIN
  -- Keep this idempotency ledger bounded while preserving recent retry history.
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
    SELECT user_id, local_date, meal_period, timezone_name
    FROM due_subscriptions
    WHERE meal_period IS NOT NULL
    ON CONFLICT (user_id, local_date, meal_period) DO NOTHING
    RETURNING user_id, local_date, meal_period, timezone
  )
  INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
  SELECT
    marked.user_id,
    'push',
    'meal_time_reminder',
    jsonb_build_object(
      'title', CASE marked.meal_period
        WHEN 'pagi' THEN 'Pengingat makan pagi'
        WHEN 'siang' THEN 'Pengingat makan siang'
        WHEN 'sore' THEN 'Pengingat camilan sore'
        ELSE 'Pengingat makan malam'
      END,
      'body', CASE marked.meal_period
        WHEN 'pagi' THEN 'Mulai hari dengan bubur ayam, nasi uduk, atau jajanan lokal.'
        WHEN 'siang' THEN 'Saatnya makan siang—coba menu rumahan dari warung sekitar.'
        WHEN 'sore' THEN 'Temani sore dengan gorengan, camilan tradisional, atau minuman segar.'
        ELSE 'Cari makan malam yang mengenyangkan dari merchant lokal.'
      END,
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
  'Queues one daily Web Push meal reminder per opted-in user, local date, meal period, and subscription timezone; the existing notification worker handles delivery and retries.';

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $schedule_meal_time_push_reminders$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job WHERE jobname = 'sadesa-meal-time-push-reminders'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'sadesa-meal-time-push-reminders',
    '* * * * *',
    'SELECT public.enqueue_meal_time_reminders();'
  );
END
$schedule_meal_time_push_reminders$;

NOTIFY pgrst, 'reload schema';
