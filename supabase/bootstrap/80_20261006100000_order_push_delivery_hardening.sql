-- DesaMart canonical bootstrap bundle; generated from an ordered archive migration.
-- SAFE TO RE-RUN: functions and triggers are replaced idempotently.
DO $bootstrap_do_order_push_delivery_hardening$
BEGIN
  EXECUTE $bootstrap_sql_order_push_delivery_hardening$-- ===== BEGIN SOURCE: 20261006100000_order_push_delivery_hardening.sql =====
-- Queue buyer order-status pushes from the database so merchants do not need
-- permission to call the admin-only send-push-notification Edge Function.
-- Keep the notification queue's worker lease contract current on staging
-- projects where the earlier recovery bundle has not been applied yet.
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_notification_jobs_processing
  ON public.notification_delivery_jobs(status, processing_started_at)
  WHERE status = 'processing';

CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501';
  END IF;

  UPDATE public.notification_delivery_jobs
  SET status = 'processing',
      attempts = attempts + 1,
      processing_started_at = now()
  WHERE id = p_job_id
    AND status IN ('queued', 'failed')
    AND next_attempt_at <= now()
    AND attempts < max_attempts
  RETURNING * INTO v_job;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000';
  END IF;

  RETURN v_job;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(
  p_job_id uuid,
  p_success boolean,
  p_provider_message_id text DEFAULT NULL,
  p_error text DEFAULT NULL
)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.notification_delivery_jobs%ROWTYPE;
  v_status text;
  v_next timestamptz;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_job
  FROM public.notification_delivery_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND OR v_job.status <> 'processing' THEN
    RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000';
  END IF;

  IF p_success THEN
    v_status := 'sent';
  ELSE
    v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END;
  END IF;
  v_next := CASE
    WHEN v_status = 'failed'
      THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7))))
    ELSE NULL
  END;

  UPDATE public.notification_delivery_jobs
  SET status = v_status,
      provider_message_id = COALESCE(p_provider_message_id, provider_message_id),
      last_error = NULLIF(trim(p_error), ''),
      next_attempt_at = COALESCE(v_next, next_attempt_at),
      sent_at = CASE WHEN p_success THEN now() ELSE sent_at END,
      dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END,
      processing_started_at = NULL
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  RETURN v_job;
END;
$$;

CREATE OR REPLACE FUNCTION public.recover_stuck_notification_delivery_jobs(
  p_lease_seconds integer DEFAULT 900
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      dead_letter_at = CASE
        WHEN attempts >= max_attempts THEN COALESCE(dead_letter_at, now())
        ELSE dead_letter_at
      END,
      processing_started_at = NULL
  WHERE status = 'processing'
    AND (
      processing_started_at < now() - make_interval(secs => GREATEST(60, p_lease_seconds))
      OR (
        processing_started_at IS NULL
        AND created_at < now() - make_interval(secs => GREATEST(60, p_lease_seconds))
      )
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.recover_stuck_notification_delivery_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recover_stuck_notification_delivery_jobs(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_buyer_order_status_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status_label text;
BEGIN
  CASE NEW.status
    WHEN 'NEW' THEN v_status_label := 'Pesanan baru';
    WHEN 'PENDING_CONFIRMATION' THEN v_status_label := 'Menunggu konfirmasi';
    WHEN 'PENDING_PAYMENT' THEN v_status_label := 'Menunggu pembayaran';
    WHEN 'PROCESSED' THEN v_status_label := 'Sedang diproses';
    WHEN 'READY' THEN v_status_label := 'Siap diambil';
    WHEN 'ASSIGNED' THEN v_status_label := 'Kurir ditugaskan';
    WHEN 'PICKED_UP' THEN v_status_label := 'Pesanan sudah diambil kurir';
    WHEN 'SENT' THEN v_status_label := 'Sedang dikirim';
    WHEN 'DELIVERING' THEN v_status_label := 'Sedang dikirim';
    WHEN 'DELIVERED' THEN v_status_label := 'Pesanan sudah tiba';
    WHEN 'DONE' THEN v_status_label := 'Pesanan selesai';
    WHEN 'CANCELED' THEN v_status_label := 'Pesanan dibatalkan';
    WHEN 'REJECTED' THEN v_status_label := 'Pesanan ditolak';
    WHEN 'REJECTED_BY_BUYER' THEN v_status_label := 'Pesanan dibatalkan pembeli';
    WHEN 'REFUNDED' THEN v_status_label := 'Dana pesanan dikembalikan';
    ELSE v_status_label := NEW.status;
  END CASE;

  INSERT INTO public.notification_delivery_jobs (
    recipient_id,
    channel,
    template_key,
    payload
  ) VALUES (
    NEW.buyer_id,
    'push',
    'order_status_update',
    jsonb_build_object(
      'title', 'Status Pesanan Diperbarui',
      'body', 'Pesanan #' || LEFT(NEW.id::TEXT, 8) || ' sekarang: ' || v_status_label || '. Ketuk untuk melihat detail.',
      'url', '/orders/' || NEW.id::TEXT,
      'data', jsonb_build_object(
        'type', 'order_status_update',
        'order_id', NEW.id::TEXT
      )
    )
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_buyer_order_status_push() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS buyer_order_status_push_trigger ON public.orders;
CREATE TRIGGER buyer_order_status_push_trigger
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.buyer_id IS NOT NULL)
EXECUTE FUNCTION public.notify_buyer_order_status_push();

-- A 30-second ride offer cannot rely only on the one-minute cron poll. Kick
-- the existing durable worker when a targeted ride-push job is enqueued; the
-- cron remains the fallback for retries and periods when Vault is unavailable.
CREATE OR REPLACE FUNCTION public.dispatch_urgent_ride_push_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.dispatch_notification_delivery_jobs();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_urgent_ride_push_job() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS dispatch_urgent_ride_push_job_trigger ON public.notification_delivery_jobs;
CREATE TRIGGER dispatch_urgent_ride_push_job_trigger
AFTER INSERT ON public.notification_delivery_jobs
FOR EACH ROW
WHEN (NEW.channel = 'push' AND NEW.template_key = 'new_ride_request')
EXECUTE FUNCTION public.dispatch_urgent_ride_push_job();
-- ===== END SOURCE: 20261006100000_order_push_delivery_hardening.sql =====
$bootstrap_sql_order_push_delivery_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_order_push_delivery_hardening$;
