-- Payment and notification worker hardening.
-- Recover abandoned reservations/jobs after a worker or edge function crash.

CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
  p_provider text,
  p_order_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_invoice_requests%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_order_id IS NULL
     OR p_request_key IS NULL OR length(trim(p_request_key)) < 16
     OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid payment invoice request' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.payment_invoice_requests(provider, order_id, request_key)
  VALUES (lower(trim(p_provider)), p_order_id, trim(p_request_key))
  ON CONFLICT (provider, order_id) DO NOTHING
  RETURNING true INTO v_inserted;

  SELECT * INTO v_row
  FROM public.payment_invoice_requests
  WHERE provider = lower(trim(p_provider)) AND order_id = p_order_id
  FOR UPDATE;

  -- A crashed edge function must not permanently block payment retries.
  IF NOT COALESCE(v_inserted, false)
     AND v_row.status = 'processing'
     AND v_row.updated_at < now() - interval '10 minutes' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'failed', invoice_id = NULL, invoice_url = NULL,
        last_error = 'reservation:lease_expired', updated_at = now()
    WHERE id = v_row.id AND status = 'processing';
    v_row.status := 'failed';
    v_row.invoice_id := NULL;
    v_row.invoice_url := NULL;
  END IF;

  IF NOT COALESCE(v_inserted, false) AND v_row.status = 'failed' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'processing', request_key = trim(p_request_key),
        last_error = NULL, updated_at = now()
    WHERE id = v_row.id AND status = 'failed';
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
END;
$$;

ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_by text;

CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1,
      locked_at = now(), locked_by = COALESCE(current_setting('request.jwt.claim.sub', true), 'worker')
  WHERE id = p_job_id
    AND attempts < max_attempts
    AND next_attempt_at <= now()
    AND (
      status IN ('queued', 'failed')
      OR (status = 'processing' AND COALESCE(locked_at, 'epoch'::timestamptz) < now() - interval '10 minutes')
    )
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(
  p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs
  SET status = v_status,
      provider_message_id = COALESCE(p_provider_message_id, provider_message_id),
      last_error = NULLIF(trim(p_error), ''),
      next_attempt_at = COALESCE(v_next, next_attempt_at),
      sent_at = CASE WHEN p_success THEN now() ELSE sent_at END,
      dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END,
      locked_at = NULL, locked_by = NULL
  WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
