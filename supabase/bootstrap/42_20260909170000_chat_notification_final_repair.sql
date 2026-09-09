-- Final chat notification repair.
-- This migration is self-contained so deploying only the latest chat patch still
-- creates an in-app notification for every incoming chat message.

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

CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(
  p_user_id uuid,
  p_conversation_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE COALESCE((
    SELECT role
    FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
    LIMIT 1
  ), '')
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN '/courier/chat?conversationId=' || p_conversation_id::text
    WHEN 'passenger' THEN '/ride/tracking?conversationId=' || p_conversation_id::text
    WHEN 'admin_desa' THEN '/desa/chat?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.send_chat_notification(
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
    left(coalesce(p_sender_display_name, 'Pengguna'), 120),
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

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recipient record;
  sender_name text;
  message_preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(m.name, '') FROM public.merchants m WHERE m.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = NEW.sender_id LIMIT 1),
    'Pengguna'
  ) INTO sender_name;

  message_preview := left(
    regexp_replace(trim(coalesce(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
    120
  );

  FOR recipient IN
    SELECT p.user_id
    FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id
      AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL
      AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    BEGIN
      PERFORM public.send_chat_notification(
        recipient.user_id,
        NEW.conversation_id,
        NEW.id,
        sender_name,
        message_preview
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'chat notification failed for message %: % (%)', NEW.id, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_notify_recipient ON public.chat_messages;
CREATE TRIGGER chat_messages_notify_recipient
AFTER INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.notify_chat_message();

COMMENT ON FUNCTION public.notify_chat_message() IS
  'Creates one idempotent in-app notification per active chat recipient without rolling back the message.';
