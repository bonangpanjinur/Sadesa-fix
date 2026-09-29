-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

-- Recovery controls for provider/worker crashes.
-- The migration is idempotent and safe to run after the canonical bootstrap bundles.
DO $bootstrap_do_recover_jobs$
BEGIN
  EXECUTE $bootstrap_sql_recover_job_columns$ALTER TABLE public.payment_invoice_requests
    ADD COLUMN IF NOT EXISTS processing_started_at timestamptz$bootstrap_sql_recover_job_columns$;
  EXECUTE $bootstrap_sql_recover_job_columns_2$ALTER TABLE public.notification_delivery_jobs
    ADD COLUMN IF NOT EXISTS processing_started_at timestamptz$bootstrap_sql_recover_job_columns_2$;
  EXECUTE $bootstrap_sql_recover_job_index$CREATE INDEX IF NOT EXISTS idx_payment_invoice_requests_processing
    ON public.payment_invoice_requests(status, processing_started_at)
    WHERE status = 'processing'$bootstrap_sql_recover_job_index$;
  EXECUTE $bootstrap_sql_recover_job_index_2$CREATE INDEX IF NOT EXISTS idx_notification_jobs_processing
    ON public.notification_delivery_jobs(status, processing_started_at)
    WHERE status = 'processing'$bootstrap_sql_recover_job_index_2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_jobs$;

DO $bootstrap_do_recover_invoice$
BEGIN
  EXECUTE $bootstrap_sql_recover_invoice$CREATE OR REPLACE FUNCTION public.recover_stuck_payment_invoice_requests(p_lease_seconds integer DEFAULT 900)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Payment recovery requires admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.payment_invoice_requests
  SET status = 'failed',
      last_error = COALESCE(last_error, 'Recovered after payment provider lease expired'),
      updated_at = now()
  WHERE status = 'processing'
    AND processing_started_at IS NOT NULL
    AND processing_started_at < now() - make_interval(secs => GREATEST(60, p_lease_seconds));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$ $bootstrap_sql_recover_invoice$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_invoice$;

DO $bootstrap_do_recover_notification$
BEGIN
  EXECUTE $bootstrap_sql_recover_notification$CREATE OR REPLACE FUNCTION public.recover_stuck_notification_delivery_jobs(p_lease_seconds integer DEFAULT 900)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification recovery requires admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = CASE WHEN attempts >= max_attempts THEN 'dead_letter' ELSE 'failed' END,
      last_error = COALESCE(last_error, 'Recovered after worker lease expired'),
      next_attempt_at = CASE WHEN attempts >= max_attempts THEN next_attempt_at ELSE now() END,
      dead_letter_at = CASE WHEN attempts >= max_attempts THEN COALESCE(dead_letter_at, now()) ELSE dead_letter_at END
  WHERE status = 'processing'
    AND processing_started_at IS NOT NULL
    AND processing_started_at < now() - make_interval(secs => GREATEST(60, p_lease_seconds));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$ $bootstrap_sql_recover_notification$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_notification$;

DO $bootstrap_do_recover_grants$
BEGIN
  EXECUTE $bootstrap_sql_recover_grants$GRANT EXECUTE ON FUNCTION public.recover_stuck_payment_invoice_requests(integer) TO service_role$bootstrap_sql_recover_grants$;
  EXECUTE $bootstrap_sql_recover_grants_2$GRANT EXECUTE ON FUNCTION public.recover_stuck_notification_delivery_jobs(integer) TO service_role$bootstrap_sql_recover_grants_2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_grants$;

-- Keep the original function contract, but stamp the lease start whenever a
-- new or retryable provider request is claimed.
DO $bootstrap_do_recover_reserve$
BEGIN
  EXECUTE $bootstrap_sql_recover_reserve$CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
  p_provider text,
  p_order_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.payment_invoice_requests%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_order_id IS NULL
     OR p_request_key IS NULL OR length(trim(p_request_key)) < 16
     OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid payment invoice request' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.payment_invoice_requests(provider, order_id, request_key, processing_started_at)
  VALUES (lower(trim(p_provider)), p_order_id, trim(p_request_key), now())
  ON CONFLICT (provider, order_id) DO NOTHING
  RETURNING true INTO v_inserted;
  SELECT * INTO v_row
  FROM public.payment_invoice_requests
  WHERE provider = lower(trim(p_provider)) AND order_id = p_order_id
  FOR UPDATE;
  IF NOT COALESCE(v_inserted, false)
     AND (v_row.status = 'failed' OR (v_row.status = 'processing' AND v_row.processing_started_at < now() - interval '15 minutes')) THEN
    UPDATE public.payment_invoice_requests
    SET status = 'processing', request_key = trim(p_request_key), last_error = NULL,
        processing_started_at = now(), updated_at = now()
    WHERE id = v_row.id AND (status = 'failed' OR (status = 'processing' AND processing_started_at < now() - interval '15 minutes'));
    v_inserted := true;
    SELECT * INTO v_row FROM public.payment_invoice_requests WHERE id = v_row.id;
  END IF;
  RETURN jsonb_build_object(
    'can_process', COALESCE(v_inserted, false),
    'status', v_row.status,
    'request_key', v_row.request_key,
    'invoice_id', v_row.invoice_id,
    'invoice_url', v_row.invoice_url,
    'last_error', v_row.last_error,
    'created_at', v_row.created_at
  );
END; $$ $bootstrap_sql_recover_reserve$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_reserve$;

DO $bootstrap_do_recover_claim$
BEGIN
  EXECUTE $bootstrap_sql_recover_claim$CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1, processing_started_at = now()
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$ $bootstrap_sql_recover_claim$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_claim$;

DO $bootstrap_do_recover_complete$
BEGIN
  EXECUTE $bootstrap_sql_recover_complete$CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs
  SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id),
      last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at),
      sent_at = CASE WHEN p_success THEN now() ELSE sent_at END,
      dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END,
      processing_started_at = NULL
  WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$ $bootstrap_sql_recover_complete$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_recover_complete$;
