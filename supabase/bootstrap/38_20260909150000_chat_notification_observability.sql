-- Fase 7: chat notification contract, idempotency, and safe operations metrics.
-- Backward-compatible: legacy notifications remain readable and send_notification is unchanged.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES public.chat_conversations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS message_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sender_display_name text,
  ADD COLUMN IF NOT EXISTS preview text,
  ADD COLUMN IF NOT EXISTS deep_link text,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_chat_idempotency_uidx
  ON public.notifications (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS notifications_chat_conversation_idx
  ON public.notifications (conversation_id, created_at DESC)
  WHERE conversation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.chat_observability_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_name text NOT NULL CHECK (metric_name IN (
    'event_delivery_latency_ms', 'channel_subscribed', 'channel_timeout',
    'channel_closed', 'channel_error', 'reconnect_success',
    'duplicate_retry_recovered', 'inbox_query_latency_ms',
    'history_query_latency_ms', 'unread_notification_delivery',
    'retention_cleanup_success', 'retention_cleanup_failure',
    'retention_cleanup_lag_seconds', 'active_conversations'
  )),
  metric_value numeric NOT NULL DEFAULT 1,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'worker', 'database')),
  CONSTRAINT chat_observability_context_object CHECK (jsonb_typeof(context) = 'object')
);
CREATE INDEX IF NOT EXISTS chat_observability_metric_time_idx
  ON public.chat_observability_events (metric_name, occurred_at DESC);
ALTER TABLE public.chat_observability_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_observability_events FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.chat_observability_events TO authenticated, service_role;
GRANT SELECT ON public.chat_observability_events TO service_role;

CREATE OR REPLACE FUNCTION public.record_chat_observability(
  p_metric_name text,
  p_metric_value numeric DEFAULT 1,
  p_context jsonb DEFAULT '{}'::jsonb,
  p_source text DEFAULT 'app'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  IF p_metric_name NOT IN (
    'event_delivery_latency_ms', 'channel_subscribed', 'channel_timeout',
    'channel_closed', 'channel_error', 'reconnect_success',
    'duplicate_retry_recovered', 'inbox_query_latency_ms',
    'history_query_latency_ms', 'unread_notification_delivery',
    'retention_cleanup_success', 'retention_cleanup_failure',
    'retention_cleanup_lag_seconds', 'active_conversations'
  ) THEN
    RAISE EXCEPTION 'Unsupported chat metric' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.chat_observability_events(metric_name, metric_value, context, source)
  VALUES (
    p_metric_name,
    greatest(least(coalesce(p_metric_value, 1), 2147483647), -2147483647),
    CASE WHEN jsonb_typeof(coalesce(p_context, '{}'::jsonb)) = 'object' THEN coalesce(p_context, '{}'::jsonb) ELSE '{}'::jsonb END,
    CASE WHEN p_source IN ('app', 'worker', 'database') THEN p_source ELSE 'app' END
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_chat_observability(text, numeric, jsonb, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(p_user_id uuid, p_conversation_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE COALESCE((SELECT role FROM public.chat_participants WHERE conversation_id = p_conversation_id AND user_id = p_user_id AND left_at IS NULL LIMIT 1), '')
    WHEN 'merchant' THEN '/merchant/chat?conversation=' || p_conversation_id::text
    WHEN 'courier' THEN '/courier/chat?conversation=' || p_conversation_id::text
    WHEN 'passenger' THEN '/ride/tracking?conversation=' || p_conversation_id::text
    ELSE '/buyer/chat?conversation=' || p_conversation_id::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.send_chat_notification(
  p_recipient_id uuid,
  p_conversation_id uuid,
  p_message_id uuid,
  p_sender_display_name text,
  p_preview text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_key text := 'chat:' || p_message_id::text || ':' || p_recipient_id::text;
BEGIN
  INSERT INTO public.notifications(
    user_id, title, message, type, link, conversation_id, message_id,
    sender_display_name, preview, deep_link, idempotency_key
  ) VALUES (
    p_recipient_id, left(coalesce(p_sender_display_name, 'Pesan baru'), 120),
    left(coalesce(p_preview, 'Pesan baru'), 120), 'chat',
    public.chat_notification_deep_link(p_recipient_id, p_conversation_id),
    p_conversation_id, p_message_id, left(coalesce(p_sender_display_name, 'Pengguna'), 120),
    left(coalesce(p_preview, ''), 120),
    public.chat_notification_deep_link(p_recipient_id, p_conversation_id), v_key
  )
  ON CONFLICT (user_id, idempotency_key) DO UPDATE SET
    conversation_id = EXCLUDED.conversation_id,
    message_id = EXCLUDED.message_id,
    deep_link = EXCLUDED.deep_link
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE recipient record; sender_name text; message_preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(m.name, '') FROM public.merchants m WHERE m.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = NEW.sender_id LIMIT 1), 'Pengguna')
  INTO sender_name;
  message_preview := left(regexp_replace(trim(coalesce(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'), 120);
  FOR recipient IN SELECT p.user_id FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    PERFORM public.send_chat_notification(recipient.user_id, NEW.conversation_id, NEW.id, sender_name, message_preview);
  END LOOP;
  RETURN NEW;
END;
$$;

COMMENT ON TABLE public.chat_observability_events IS 'Safe chat metrics only; never store message bodies, tokens, signed URLs, or location.';
