CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
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
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_one_subscription_billing_event()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event public.subscription_billing_events%ROWTYPE; v_payload jsonb; v_status text; v_period_start timestamptz; v_period_end timestamptz; v_grace timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Subscription event processing requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_event FROM public.subscription_billing_events WHERE status IN ('received','failed') ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('processed', false, 'reason', 'empty'); END IF;
  v_payload := COALESCE(v_event.payload, '{}'::jsonb);
  v_period_start := NULLIF(COALESCE(v_payload->>'period_start', v_payload->>'current_period_start'), '')::timestamptz;
  v_period_end := NULLIF(COALESCE(v_payload->>'period_end', v_payload->>'current_period_end'), '')::timestamptz;
  v_grace := NULLIF(v_payload->>'grace_period_until', '')::timestamptz;
  IF v_event.event_type IN ('payment_succeeded','invoice_paid','subscription_renewed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'PAID', status = 'ACTIVE', paid_at = COALESCE(paid_at, now()), current_period_start = COALESCE(v_period_start, current_period_start), current_period_end = COALESCE(v_period_end, current_period_end), grace_period_until = NULL, updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('payment_failed','invoice_failed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'UNPAID', status = CASE WHEN v_grace IS NULL OR v_grace > now() THEN 'PAST_DUE' ELSE 'EXPIRED' END, grace_period_until = COALESCE(v_grace, now() + interval '7 days'), updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('subscription_cancelled','cancelled') THEN
    UPDATE public.merchant_subscriptions SET status = 'CANCELLED', updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSE
    v_status := 'ignored';
  END IF;
  UPDATE public.subscription_billing_events SET status = v_status, processed_at = now(), error_message = NULL WHERE id = v_event.id;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', v_status);
EXCEPTION WHEN OTHERS THEN
  IF v_event.id IS NOT NULL THEN UPDATE public.subscription_billing_events SET status = 'failed', error_message = SQLERRM WHERE id = v_event.id; END IF;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', 'failed', 'error', SQLERRM);
END; $$;
REVOKE ALL ON FUNCTION public.process_one_subscription_billing_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_one_subscription_billing_event() TO authenticated, service_role;
