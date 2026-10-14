CREATE TABLE IF NOT EXISTS public.notification_delivery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('whatsapp','push','email','in_app')),
  template_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','sent','failed','dead_letter','cancelled','opted_out')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  dead_letter_at timestamptz
)$bootstrap_sql_cfbf52bdbea3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cfbf52bdbea3$;

DO $bootstrap_do_6af80420ae0d$
BEGIN
  EXECUTE $bootstrap_sql_6af80420ae0d$CREATE INDEX IF NOT EXISTS idx_notification_jobs_due ON public.notification_delivery_jobs(status, next_attempt_at) WHERE status IN ('queued','failed')$bootstrap_sql_6af80420ae0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6af80420ae0d$;

DO $bootstrap_do_b3c85b5b70cb$
BEGIN
  EXECUTE $bootstrap_sql_b3c85b5b70cb$CREATE INDEX IF NOT EXISTS idx_notification_jobs_recipient ON public.notification_delivery_jobs(recipient_id, created_at DESC)$bootstrap_sql_b3c85b5b70cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3c85b5b70cb$;

DO $bootstrap_do_e290e92673ea$
BEGIN
  EXECUTE $bootstrap_sql_e290e92673ea$ALTER TABLE public.notification_delivery_jobs ENABLE ROW LEVEL SECURITY$bootstrap_sql_e290e92673ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e290e92673ea$;

DO $bootstrap_do_fd1e8bae0f57$
BEGIN
  EXECUTE $bootstrap_sql_fd1e8bae0f57$DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs$bootstrap_sql_fd1e8bae0f57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd1e8bae0f57$;

DO $bootstrap_do_e102373cf940$
BEGIN
  EXECUTE $bootstrap_sql_e102373cf940$CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated USING (recipient_id = auth.uid() OR public.is_admin())$bootstrap_sql_e102373cf940$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e102373cf940$;

DO $bootstrap_do_c6abee062338$
BEGIN
  EXECUTE $bootstrap_sql_c6abee062338$DROP POLICY IF EXISTS "Admins manage notification jobs" ON public.notification_delivery_jobs$bootstrap_sql_c6abee062338$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6abee062338$;

DO $bootstrap_do_f94d5b27190d$
BEGIN
  EXECUTE $bootstrap_sql_f94d5b27190d$CREATE POLICY "Admins manage notification jobs" ON public.notification_delivery_jobs FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_f94d5b27190d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f94d5b27190d$;

DO $bootstrap_do_aa076ec89bea$
BEGIN
  EXECUTE $bootstrap_sql_aa076ec89bea$CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$$bootstrap_sql_aa076ec89bea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa076ec89bea$;

DO $bootstrap_do_afcf6eb205f9$
BEGIN
  EXECUTE $bootstrap_sql_afcf6eb205f9$CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$$bootstrap_sql_afcf6eb205f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_afcf6eb205f9$;

DO $bootstrap_do_6ab28a8649f7$
BEGIN
  EXECUTE $bootstrap_sql_6ab28a8649f7$REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon$bootstrap_sql_6ab28a8649f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ab28a8649f7$;

DO $bootstrap_do_06735710dd7a$
BEGIN
  EXECUTE $bootstrap_sql_06735710dd7a$REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon$bootstrap_sql_06735710dd7a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06735710dd7a$;

DO $bootstrap_do_fb9060ad8ca0$
BEGIN
  EXECUTE $bootstrap_sql_fb9060ad8ca0$GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated$bootstrap_sql_fb9060ad8ca0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb9060ad8ca0$;

DO $bootstrap_do_c753ff3f5aaf$
BEGIN
  EXECUTE $bootstrap_sql_c753ff3f5aaf$GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated$bootstrap_sql_c753ff3f5aaf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c753ff3f5aaf$;

DO $bootstrap_do_dd9742a378da$
BEGIN
  EXECUTE $bootstrap_sql_dd9742a378da$
