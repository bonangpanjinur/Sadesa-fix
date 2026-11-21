-- Fail fast if the production scheduler prerequisites or Vault secrets are absent.
-- Create SUPABASE_URL and GDC_RECONCILE_CRON_SECRET in Vault before applying this bundle.
DO $$
DECLARE
  missing text[] := ARRAY[]::text[];
  secret_url text;
  secret_cron text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    RAISE EXCEPTION 'GDC reconciliation scheduler requires pg_cron';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'net') THEN
    RAISE EXCEPTION 'GDC reconciliation scheduler requires pg_net';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'vault') THEN
    RAISE EXCEPTION 'GDC reconciliation scheduler requires Supabase Vault';
  END IF;

  SELECT decrypted_secret INTO secret_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL';
  SELECT decrypted_secret INTO secret_cron FROM vault.decrypted_secrets WHERE name = 'GDC_RECONCILE_CRON_SECRET';
  IF COALESCE(trim(secret_url), '') = '' THEN missing := array_append(missing, 'SUPABASE_URL'); END IF;
  IF COALESCE(trim(secret_cron), '') = '' THEN missing := array_append(missing, 'GDC_RECONCILE_CRON_SECRET'); END IF;
  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'Missing required Vault secret(s): %', array_to_string(missing, ', ');
  END IF;

  PERFORM cron.unschedule(jobid) FROM cron.job
    WHERE jobname IN ('gdc-qris-mpm-reconcile-expired', 'gdc-qris-mpm-reconcile-worker');
  PERFORM cron.schedule(
    'gdc-qris-mpm-reconcile-worker',
    '*/5 * * * *',
    $job$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL') || '/functions/v1/gdc-qris-reconcile',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'GDC_RECONCILE_CRON_SECRET')
        ),
        body := '{}'::jsonb
      );
    $job$
  );
END;
$$;
