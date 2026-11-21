-- Schedule the real GDC reconciliation worker. The worker queries GDC first;
-- this SQL function only expires items after the provider-query grace period.
CREATE OR REPLACE FUNCTION public.reconcile_gdc_qris_mpm_payments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC reconciliation requires service role' USING ERRCODE = '42501';
  END IF;

  WITH expired AS (
    UPDATE public.gdc_qris_mpm_payments p
    SET status = 'EXPIRED', error_code = 'PAYMENT_DEADLINE_EXPIRED', updated_at = now()
    FROM public.orders o
    WHERE p.order_id = o.id
      AND p.status IN ('CREATING', 'PENDING')
      AND o.payment_status NOT IN ('PAID', 'REFUNDED', 'EXPIRED')
      AND o.confirmation_deadline IS NOT NULL
      AND o.confirmation_deadline + interval '15 minutes' <= now()
    RETURNING p.id
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_gdc_qris_mpm_payments() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_gdc_qris_mpm_payments() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron')
     AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'net')
     AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'vault') THEN
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
  ELSE
    RAISE NOTICE 'pg_cron/pg_net/vault unavailable; configure the GDC reconciliation worker schedule manually';
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function OR insufficient_privilege THEN
  RAISE NOTICE 'Could not install GDC reconciliation worker schedule; configure it manually';
END;
$$;

NOTIFY pgrst, 'reload schema';
