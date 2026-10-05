-- Run the durable Web Push queue independently of merchant browser sessions.
-- The worker secret and project credentials live in Supabase Vault, not SQL source.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

CREATE OR REPLACE FUNCTION public.dispatch_notification_delivery_jobs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_project_url text;
  v_publishable_key text;
  v_worker_secret text;
BEGIN
  SELECT
    max(decrypted_secret) FILTER (WHERE name = 'sadesa_project_url'),
    max(decrypted_secret) FILTER (WHERE name = 'sadesa_publishable_key'),
    max(decrypted_secret) FILTER (WHERE name = 'sadesa_notification_worker_secret')
  INTO v_project_url, v_publishable_key, v_worker_secret
  FROM vault.decrypted_secrets
  WHERE name IN (
    'sadesa_project_url',
    'sadesa_publishable_key',
    'sadesa_notification_worker_secret'
  );

  IF nullif(trim(v_project_url), '') IS NULL
    OR nullif(trim(v_publishable_key), '') IS NULL
    OR nullif(trim(v_worker_secret), '') IS NULL THEN
    RAISE WARNING 'Notification queue dispatch skipped: required Supabase Vault secrets are missing';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/process-notification-queue',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_publishable_key,
      'x-worker-secret', v_worker_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_notification_delivery_jobs() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.dispatch_notification_delivery_jobs() IS
  'Invokes the authenticated notification queue Edge Function using credentials stored in Supabase Vault.';

DO $$
DECLARE
  existing_job record;
BEGIN
  FOR existing_job IN
    SELECT jobid FROM cron.job WHERE jobname = 'sadesa-notification-delivery'
  LOOP
    PERFORM cron.unschedule(existing_job.jobid);
  END LOOP;
END
$$;

SELECT cron.schedule(
  'sadesa-notification-delivery',
  '* * * * *',
  $$SELECT public.dispatch_notification_delivery_jobs()$$
);
