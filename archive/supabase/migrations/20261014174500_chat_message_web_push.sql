DO $bootstrap_do_f3ea1fa8afcd$
BEGIN
  EXECUTE $bootstrap_sql_f3ea1fa8afcd$-- Deliver chat alerts through Web Push when the recipient has an active
-- browser subscription. Keep the in-app notification path unchanged.
-- The push preview intentionally avoids exposing message text on lock screens.
CREATE UNIQUE INDEX IF NOT EXISTS notification_jobs_chat_push_dedupe_uidx
  ON public.notification_delivery_jobs (dedupe_key)
  WHERE dedupe_key IS NOT NULL AND dedupe_key LIKE 'chat:%'$bootstrap_sql_f3ea1fa8afcd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3ea1fa8afcd$;

DO $bootstrap_do_fdfb45bf1e44$
BEGIN
  EXECUTE $bootstrap_sql_fdfb45bf1e44$CREATE OR REPLACE FUNCTION public.send_chat_notification(
  p_recipient_id uuid,
  p_conversation_id uuid,
  p_message_id uuid,
  p_sender_display_name text,
  p_preview text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_key text := 'chat:' || p_message_id::text || ':' || p_recipient_id::text;
  v_link text := public.chat_notification_deep_link(p_recipient_id, p_conversation_id);
  v_sender text := left(coalesce(nullif(trim(p_sender_display_name), ''), 'Pengguna'), 120);
BEGIN
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    link,
    conversation_id,
    message_id,
    sender_display_name,
    preview,
    deep_link,
    idempotency_key
  )
  VALUES (
    p_recipient_id,
    left(coalesce(nullif(trim(p_sender_display_name), ''), 'Pesan baru'), 120),
    left(coalesce(nullif(trim(p_preview), ''), 'Pesan baru'), 120),
    'chat',
    v_link,
    p_conversation_id,
    p_message_id,
    v_sender,
    left(coalesce(p_preview, ''), 120),
    v_link,
    v_key
  )
  ON CONFLICT (user_id, idempotency_key) DO UPDATE SET
    conversation_id = EXCLUDED.conversation_id,
    message_id = EXCLUDED.message_id,
    link = EXCLUDED.link,
    deep_link = EXCLUDED.deep_link
  RETURNING id INTO v_id;

  IF EXISTS (
    SELECT 1
    FROM public.push_subscriptions
    WHERE user_id = p_recipient_id
  ) THEN
    INSERT INTO public.notification_delivery_jobs (
      recipient_id,
      channel,
      template_key,
      payload,
      dedupe_key
    )
    VALUES (
      p_recipient_id,
      'push',
      'new_chat_message',
      jsonb_build_object(
        'title', 'Pesan baru dari ' || v_sender,
        'body', 'Anda menerima pesan baru. Buka SaDesa untuk membalas.',
        'url', v_link,
        'data', jsonb_build_object(
          'type', 'chat',
          'conversation_id', p_conversation_id::text,
          'message_id', p_message_id::text
        )
      ),
      v_key
    )
    ON CONFLICT (dedupe_key)
      WHERE dedupe_key IS NOT NULL AND dedupe_key LIKE 'chat:%'
    DO NOTHING;
  END IF;

  RETURN v_id;
END;
$$$bootstrap_sql_fdfb45bf1e44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fdfb45bf1e44$;

DO $bootstrap_do_f436b64befbb$
BEGIN
  EXECUTE $bootstrap_sql_f436b64befbb$REVOKE ALL ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text)
  FROM PUBLIC, anon, authenticated$bootstrap_sql_f436b64befbb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f436b64befbb$;

DO $bootstrap_do_f94f99ac3354$
BEGIN
  EXECUTE $bootstrap_sql_f94f99ac3354$GRANT EXECUTE ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text)
  TO service_role$bootstrap_sql_f94f99ac3354$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f94f99ac3354$;

DO $bootstrap_do_14f8f64f8680$
BEGIN
  EXECUTE $bootstrap_sql_14f8f64f8680$-- Wake the existing durable worker immediately for new chat alerts; the
-- scheduled queue worker remains the retry/fallback path.
CREATE OR REPLACE FUNCTION public.dispatch_urgent_chat_push_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.dispatch_notification_delivery_jobs();
  RETURN NEW;
END;
$$$bootstrap_sql_14f8f64f8680$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14f8f64f8680$;

DO $bootstrap_do_5007be4c6eea$
BEGIN
  EXECUTE $bootstrap_sql_5007be4c6eea$REVOKE ALL ON FUNCTION public.dispatch_urgent_chat_push_job() FROM PUBLIC, anon, authenticated$bootstrap_sql_5007be4c6eea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5007be4c6eea$;

DO $bootstrap_do_c36db4863875$
BEGIN
  EXECUTE $bootstrap_sql_c36db4863875$DROP TRIGGER IF EXISTS dispatch_urgent_chat_push_job_trigger ON public.notification_delivery_jobs$bootstrap_sql_c36db4863875$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c36db4863875$;

DO $bootstrap_do_73f2a6fe92be$
BEGIN
  EXECUTE $bootstrap_sql_73f2a6fe92be$CREATE TRIGGER dispatch_urgent_chat_push_job_trigger
AFTER INSERT ON public.notification_delivery_jobs
FOR EACH ROW
WHEN (NEW.channel = 'push' AND NEW.template_key = 'new_chat_message')
EXECUTE FUNCTION public.dispatch_urgent_chat_push_job()$bootstrap_sql_73f2a6fe92be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_73f2a6fe92be$;
