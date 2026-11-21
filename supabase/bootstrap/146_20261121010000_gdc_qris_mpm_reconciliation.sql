-- GDC QRIS MPM expiry/reconciliation guardrails.
-- Provider settlement remains canonical through settle_gdc_qris_mpm_payment.
ALTER TABLE public.gdc_qris_mpm_payments
  DROP CONSTRAINT IF EXISTS gdc_qris_mpm_payments_status_check;
ALTER TABLE public.gdc_qris_mpm_payments
  ADD CONSTRAINT gdc_qris_mpm_payments_status_check
  CHECK (status IN ('CREATING','PENDING','PAID','FAILED','EXPIRED'));

CREATE INDEX IF NOT EXISTS gdc_qris_mpm_payments_pending_idx
  ON public.gdc_qris_mpm_payments(status, updated_at)
  WHERE status IN ('CREATING', 'PENDING');

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
      AND o.confirmation_deadline <= now()
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
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'gdc-qris-mpm-reconcile-expired';
    PERFORM cron.schedule(
      'gdc-qris-mpm-reconcile-expired',
      '*/5 * * * *',
      $job$SELECT public.reconcile_gdc_qris_mpm_payments();$job$
    );
  END IF;
EXCEPTION WHEN undefined_function OR insufficient_privilege THEN
  RAISE NOTICE 'pg_cron is unavailable; run gdc-qris-reconcile as a service-role Edge Function';
END;
$$;

NOTIFY pgrst, 'reload schema';
