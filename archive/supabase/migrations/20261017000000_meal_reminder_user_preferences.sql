-- Persist per-user meal reminder schedules and snooze state for authenticated users.
CREATE TABLE IF NOT EXISTS public.meal_reminder_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pagi_time time NOT NULL DEFAULT '07:00',
  siang_time time NOT NULL DEFAULT '12:00',
  sore_time time NOT NULL DEFAULT '16:00',
  malam_time time NOT NULL DEFAULT '19:00',
  snoozed_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meal_reminder_preferences_times_valid CHECK (
    pagi_time >= '00:00' AND pagi_time < '24:00'
    AND siang_time >= '00:00' AND siang_time < '24:00'
    AND sore_time >= '00:00' AND sore_time < '24:00'
    AND malam_time >= '00:00' AND malam_time < '24:00'
  )
);

ALTER TABLE public.meal_reminder_preferences ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.meal_reminder_preferences TO authenticated;

DROP POLICY IF EXISTS "Users can view their meal reminder preferences" ON public.meal_reminder_preferences;
CREATE POLICY "Users can view their meal reminder preferences"
  ON public.meal_reminder_preferences FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create their meal reminder preferences" ON public.meal_reminder_preferences;
CREATE POLICY "Users can create their meal reminder preferences"
  ON public.meal_reminder_preferences FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their meal reminder preferences" ON public.meal_reminder_preferences;
CREATE POLICY "Users can update their meal reminder preferences"
  ON public.meal_reminder_preferences FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their meal reminder preferences" ON public.meal_reminder_preferences;
CREATE POLICY "Users can delete their meal reminder preferences"
  ON public.meal_reminder_preferences FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.enqueue_meal_time_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_enqueued integer := 0;
BEGIN
  DELETE FROM public.meal_reminder_dispatches
  WHERE local_date < (now() AT TIME ZONE 'UTC')::date - 45;

  WITH localized_subscriptions AS (
    SELECT DISTINCT
      ps.user_id,
      COALESCE(NULLIF(btrim(ps.timezone), ''), 'Asia/Jakarta') AS timezone_name,
      now() AT TIME ZONE COALESCE(NULLIF(btrim(ps.timezone), ''), 'Asia/Jakarta') AS local_now,
      COALESCE(mrp.pagi_time, '07:00'::time) AS pagi_time,
      COALESCE(mrp.siang_time, '12:00'::time) AS siang_time,
      COALESCE(mrp.sore_time, '16:00'::time) AS sore_time,
      COALESCE(mrp.malam_time, '19:00'::time) AS malam_time,
      mrp.snoozed_until
    FROM public.push_subscriptions AS ps
    LEFT JOIN public.meal_reminder_preferences AS mrp ON mrp.user_id = ps.user_id
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
      CASE
        WHEN to_char(local_now, 'HH24:MI') = to_char(pagi_time, 'HH24:MI') THEN 'pagi'
        WHEN to_char(local_now, 'HH24:MI') = to_char(siang_time, 'HH24:MI') THEN 'siang'
        WHEN to_char(local_now, 'HH24:MI') = to_char(sore_time, 'HH24:MI') THEN 'sore'
        WHEN to_char(local_now, 'HH24:MI') = to_char(malam_time, 'HH24:MI') THEN 'malam'
      END AS meal_period
    FROM localized_subscriptions
    WHERE (snoozed_until IS NULL OR now() >= snoozed_until)
      AND extract(second FROM local_now)::integer < 60
      AND (
        to_char(local_now, 'HH24:MI') IN (
          to_char(pagi_time, 'HH24:MI'),
          to_char(siang_time, 'HH24:MI'),
          to_char(sore_time, 'HH24:MI'),
          to_char(malam_time, 'HH24:MI')
        )
      )
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
COMMENT ON TABLE public.meal_reminder_preferences IS 'Per-user meal reminder schedule and snooze preferences used by the Web Push cron dispatcher.';
COMMENT ON FUNCTION public.enqueue_meal_time_reminders() IS 'Queues one daily Web Push meal reminder using each user schedule, subscription timezone, and snooze state.';

NOTIFY pgrst, 'reload schema';
