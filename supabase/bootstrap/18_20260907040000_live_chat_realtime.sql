-- Live chat realtime foundation.
-- This is intentionally additive: legacy chat_messages columns and policies
-- remain available while clients are migrated to conversations.

CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  context_type text NOT NULL CHECK (context_type IN ('order', 'ride')),
  order_id uuid NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  ride_request_id uuid NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  conversation_type text NOT NULL CHECK (conversation_type IN (
    'buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier'
  )),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed', 'archived')),
  last_message_id uuid NULL,
  last_message_at timestamptz NULL,
  closed_at timestamptz NULL,
  retention_until timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_order_type_uidx
  ON public.chat_conversations(order_id, conversation_type)
  WHERE order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_ride_type_uidx
  ON public.chat_conversations(ride_request_id, conversation_type)
  WHERE ride_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS chat_conversations_last_message_idx
  ON public.chat_conversations(last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS public.chat_participants (
  conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('buyer', 'merchant', 'courier', 'passenger')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  last_read_at timestamptz NULL,
  last_read_message_id uuid NULL,
  muted_until timestamptz NULL,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_participants_user_idx
  ON public.chat_participants(user_id, left_at);

ALTER TABLE public.chat_messages
  ALTER COLUMN order_id DROP NOT NULL;
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS conversation_id uuid NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS body text NULL,
  ADD COLUMN IF NOT EXISTS attachment_path text NULL,
  ADD COLUMN IF NOT EXISTS client_message_id uuid NULL,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;

UPDATE public.chat_messages
SET body = message
WHERE body IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_body_length_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_body_length_check
      CHECK (length(trim(COALESCE(body, message))) BETWEEN 1 AND 4000);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_message_type_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_message_type_check
      CHECK (message_type IN ('text'));
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS chat_messages_sender_client_uidx
  ON public.chat_messages(sender_id, client_message_id)
  WHERE client_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS chat_messages_conversation_cursor_idx
  ON public.chat_messages(conversation_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS chat_messages_sender_created_idx
  ON public.chat_messages(sender_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_message_reads (
  message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_message_reads_user_idx
  ON public.chat_message_reads(user_id, read_at DESC);

CREATE OR REPLACE FUNCTION public.chat_is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id
      AND role IN ('admin', 'admin_desa')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_chat_conversation_participant(
  p_conversation_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_domain_participants(
  p_context_type text,
  p_order_id uuid,
  p_ride_request_id uuid,
  p_conversation_type text
)
RETURNS TABLE(user_id uuid, role text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_context_type = 'order' THEN
    RETURN QUERY
    SELECT o.buyer_id, 'buyer'::text
    FROM public.orders o
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_merchant'
    UNION ALL
    SELECT m.user_id, 'merchant'::text
    FROM public.orders o
    JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_merchant'
    UNION ALL
    SELECT o.buyer_id, 'buyer'::text
    FROM public.orders o
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_courier'
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.orders o
    JOIN public.couriers c ON c.id = o.courier_id
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_courier'
    UNION ALL
    SELECT m.user_id, 'merchant'::text
    FROM public.orders o
    JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND p_conversation_type = 'merchant_courier'
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.orders o
    JOIN public.couriers c ON c.id = o.courier_id
    WHERE o.id = p_order_id AND p_conversation_type = 'merchant_courier';
  ELSIF p_context_type = 'ride' AND p_conversation_type = 'passenger_courier' THEN
    RETURN QUERY
    SELECT r.passenger_id, 'passenger'::text
    FROM public.ride_requests r
    WHERE r.id = p_ride_request_id
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.ride_requests r
    JOIN public.couriers c ON c.id = r.driver_id
    WHERE r.id = p_ride_request_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_or_create_chat_conversation(
  p_context_type text,
  p_order_id uuid DEFAULT NULL,
  p_ride_request_id uuid DEFAULT NULL,
  p_conversation_type text DEFAULT 'buyer_merchant'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_participant_count integer;
  v_caller_is_participant boolean;
BEGIN
  IF p_context_type NOT IN ('order', 'ride')
     OR (p_context_type = 'order' AND p_order_id IS NULL)
     OR (p_context_type = 'ride' AND p_ride_request_id IS NULL)
     OR (p_context_type = 'order' AND p_ride_request_id IS NOT NULL)
     OR (p_context_type = 'ride' AND p_order_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'invalid chat context' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chat_domain_participants(
      p_context_type, p_order_id, p_ride_request_id, p_conversation_type
    )
  ) THEN
    RAISE EXCEPTION 'chat context or participants not found' USING ERRCODE = '42501';
  END IF;

  SELECT c.id INTO v_conversation_id
  FROM public.chat_conversations c
  WHERE ((p_context_type = 'order' AND c.order_id = p_order_id)
      OR (p_context_type = 'ride' AND c.ride_request_id = p_ride_request_id))
    AND c.conversation_type = p_conversation_type
  LIMIT 1;

  IF v_conversation_id IS NULL THEN
    INSERT INTO public.chat_conversations (
      context_type, order_id, ride_request_id, conversation_type
    )
    VALUES (p_context_type, p_order_id, p_ride_request_id, p_conversation_type)
    RETURNING id INTO v_conversation_id;
  END IF;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  SELECT v_conversation_id, p.user_id, p.role
  FROM public.chat_domain_participants(
    p_context_type, p_order_id, p_ride_request_id, p_conversation_type
  ) p
  WHERE p.user_id IS NOT NULL
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  SELECT count(*) INTO v_participant_count
  FROM public.chat_participants
  WHERE conversation_id = v_conversation_id AND left_at IS NULL;
  SELECT public.is_chat_conversation_participant(v_conversation_id, auth.uid())
    INTO v_caller_is_participant;

  IF NOT COALESCE(v_caller_is_participant, false) AND NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  RETURN v_conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_chat_conversation_read(
  p_conversation_id uuid,
  p_message_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_participants (
    conversation_id, user_id, role, last_read_at, last_read_message_id
  )
  SELECT p_conversation_id, auth.uid(), role, now(), p_message_id
  FROM public.chat_participants
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid()
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET last_read_at = now(), last_read_message_id = COALESCE(p_message_id, chat_participants.last_read_message_id);

  IF p_message_id IS NOT NULL THEN
    INSERT INTO public.chat_message_reads (message_id, user_id)
    SELECT p_message_id, auth.uid()
    WHERE EXISTS (
      SELECT 1 FROM public.chat_messages
      WHERE id = p_message_id AND conversation_id = p_conversation_id
    )
    ON CONFLICT (message_id, user_id) DO UPDATE SET read_at = now();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_chat_unread_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)
  FROM public.chat_messages m
  JOIN public.chat_participants p
    ON p.conversation_id = m.conversation_id
   AND p.user_id = auth.uid()
   AND p.left_at IS NULL
  WHERE m.sender_id <> auth.uid()
    AND m.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.chat_message_reads r
      WHERE r.message_id = m.id AND r.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.chat_touch_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL THEN
    UPDATE public.chat_conversations
    SET last_message_id = NEW.id,
        last_message_at = NEW.created_at,
        updated_at = now()
    WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_chat_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL AND (
    SELECT count(*)
    FROM public.chat_messages m
    WHERE m.sender_id = NEW.sender_id
      AND m.conversation_id IS NOT NULL
      AND m.created_at > now() - interval '1 minute'
  ) >= 30 THEN
    RAISE EXCEPTION 'chat rate limit exceeded' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_touch_conversation ON public.chat_messages;
CREATE TRIGGER chat_messages_touch_conversation
AFTER INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.chat_touch_conversation();

DROP TRIGGER IF EXISTS chat_messages_rate_limit ON public.chat_messages;
CREATE TRIGGER chat_messages_rate_limit
BEFORE INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.enforce_chat_rate_limit();

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recipient record;
  sender_name text;
  preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(p.full_name, ''),
    NULLIF(m.name, ''),
    NULLIF(c.name, ''),
    'Pengguna'
  )
  INTO sender_name
  FROM public.profiles p
  FULL JOIN public.merchants m ON m.user_id = NEW.sender_id
  FULL JOIN public.couriers c ON c.user_id = NEW.sender_id
  WHERE p.user_id = NEW.sender_id
     OR m.user_id = NEW.sender_id
     OR c.user_id = NEW.sender_id
  LIMIT 1;

  preview := left(
    regexp_replace(trim(COALESCE(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
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
    PERFORM public.send_notification(
      recipient.user_id,
      COALESCE(sender_name, 'Pesan baru'),
      preview,
      'chat',
      '/buyer/chat'
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_notify_recipient ON public.chat_messages;
CREATE TRIGGER chat_messages_notify_recipient
AFTER INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat participants can view conversations" ON public.chat_conversations;
CREATE POLICY "Chat participants can view conversations"
ON public.chat_conversations FOR SELECT
USING (
  public.is_chat_conversation_participant(id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Chat participants can view participant rows" ON public.chat_participants;
CREATE POLICY "Chat participants can view participant rows"
ON public.chat_participants FOR SELECT
USING (
  public.is_chat_conversation_participant(conversation_id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Users can update own chat read state" ON public.chat_participants;
CREATE POLICY "Users can update own chat read state"
ON public.chat_participants FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Chat participants can view message reads" ON public.chat_message_reads;
CREATE POLICY "Chat participants can view message reads"
ON public.chat_message_reads FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.chat_messages m
    WHERE m.id = message_id
      AND public.is_chat_conversation_participant(m.conversation_id, auth.uid())
  )
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Users can insert own message reads" ON public.chat_message_reads;
CREATE POLICY "Users can insert own message reads"
ON public.chat_message_reads FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Conversation participants can send messages" ON public.chat_messages;
CREATE POLICY "Conversation participants can send messages"
ON public.chat_messages FOR INSERT
WITH CHECK (
  auth.uid() = sender_id
  AND conversation_id IS NOT NULL
  AND public.is_chat_conversation_participant(conversation_id, auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.chat_conversations c
    WHERE c.id = conversation_id AND c.status = 'active'
  )
  AND COALESCE(body, message) IS NOT NULL
  AND length(trim(COALESCE(body, message))) BETWEEN 1 AND 4000
);

DROP POLICY IF EXISTS "Participants can view conversation messages" ON public.chat_messages;
CREATE POLICY "Participants can view conversation messages"
ON public.chat_messages FOR SELECT
USING (
  conversation_id IS NOT NULL
  AND (
    public.is_chat_conversation_participant(conversation_id, auth.uid())
    OR public.chat_is_admin(auth.uid())
  )
);

-- Canonical conversations use the conversation retention policy. Legacy
-- auto_delete_at stays untouched for the dual-read period.
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.chat_messages m
  USING public.chat_conversations c
  WHERE m.conversation_id = c.id
    AND c.retention_until IS NOT NULL
    AND c.retention_until <= now();

  DELETE FROM public.chat_messages
  WHERE conversation_id IS NULL
    AND auto_delete_at IS NOT NULL
    AND auto_delete_at <= now();
END;
$$;

-- Backfill order conversations and attach valid legacy messages.
DO $$
DECLARE
  r record;
  v_conversation_id uuid;
BEGIN
  FOR r IN
    SELECT DISTINCT
      m.order_id,
      COALESCE(m.chat_type, 'buyer_merchant') AS conversation_type
    FROM public.chat_messages m
    WHERE m.order_id IS NOT NULL
      AND COALESCE(m.chat_type, 'buyer_merchant') IN (
        'buyer_merchant', 'buyer_courier', 'merchant_courier'
      )
  LOOP
    SELECT c.id INTO v_conversation_id
    FROM public.chat_conversations c
    WHERE c.order_id = r.order_id
      AND c.conversation_type = r.conversation_type
    LIMIT 1;

    IF v_conversation_id IS NULL THEN
      INSERT INTO public.chat_conversations (
        context_type, order_id, conversation_type
      )
      SELECT 'order', r.order_id, r.conversation_type
      WHERE EXISTS (
        SELECT 1 FROM public.chat_domain_participants(
          'order', r.order_id, NULL, r.conversation_type
        )
      )
      RETURNING id INTO v_conversation_id;
    END IF;

    IF v_conversation_id IS NOT NULL THEN
      INSERT INTO public.chat_participants (conversation_id, user_id, role)
      SELECT v_conversation_id, p.user_id, p.role
      FROM public.chat_domain_participants(
        'order', r.order_id, NULL, r.conversation_type
      ) p
      WHERE p.user_id IS NOT NULL
      ON CONFLICT (conversation_id, user_id) DO NOTHING;

      UPDATE public.chat_messages
      SET conversation_id = v_conversation_id,
          body = COALESCE(body, message)
      WHERE order_id = r.order_id
        AND COALESCE(chat_type, 'buyer_merchant') = r.conversation_type
        AND conversation_id IS NULL;
    END IF;
  END LOOP;

  UPDATE public.chat_conversations c
  SET last_message_id = latest.id,
      last_message_at = latest.created_at,
      updated_at = now()
  FROM (
    SELECT DISTINCT ON (conversation_id)
      conversation_id, id, created_at
    FROM public.chat_messages
    WHERE conversation_id IS NOT NULL
    ORDER BY conversation_id, created_at DESC, id DESC
  ) latest
  WHERE c.id = latest.conversation_id;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_participants;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reads;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END;
$$;