-- Chat phase 3: database-owned authorization, canonical writes, and abuse control.
-- Apply after 35_20260909120000_chat_message_retention.sql.
--
-- Authenticated clients may read rows allowed by RLS, but all chat writes go
-- through SECURITY DEFINER RPCs. Message identity and content are immutable;
-- retention is the only supported message update.

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reads ENABLE ROW LEVEL SECURITY;

-- Remove legacy policies that allowed broad row mutation. The policies below
-- are recreated explicitly so older database states fail closed as well.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'chat_conversations',
        'chat_participants',
        'chat_messages',
        'chat_message_reads'
      )
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  END LOOP;
END;
$$;

REVOKE ALL ON public.chat_conversations FROM anon, authenticated;
REVOKE ALL ON public.chat_participants FROM anon, authenticated;
REVOKE ALL ON public.chat_messages FROM anon, authenticated;
REVOKE ALL ON public.chat_message_reads FROM anon, authenticated;

GRANT SELECT ON public.chat_conversations TO authenticated;
GRANT SELECT ON public.chat_participants TO authenticated;
GRANT SELECT ON public.chat_messages TO authenticated;
GRANT SELECT ON public.chat_message_reads TO authenticated;

CREATE POLICY "Chat participants can view conversations"
ON public.chat_conversations FOR SELECT
USING (
  public.is_chat_conversation_participant(id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

CREATE POLICY "Chat participants can view participant rows"
ON public.chat_participants FOR SELECT
USING (
  public.is_chat_conversation_participant(conversation_id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

CREATE POLICY "Participants can view conversation messages"
ON public.chat_messages FOR SELECT
USING (
  conversation_id IS NOT NULL
  AND (
    public.is_chat_conversation_participant(conversation_id, auth.uid())
    OR public.chat_is_admin(auth.uid())
  )
);

CREATE POLICY "Chat participants can view message reads"
ON public.chat_message_reads FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.chat_messages m
    WHERE m.id = message_id
      AND public.is_chat_conversation_participant(m.conversation_id, auth.uid())
  )
  OR public.chat_is_admin(auth.uid())
);

-- Keep the old function name, but validate the caller before creating or
-- reactivating any participant rows.
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
  v_caller_is_participant boolean;
BEGIN
  IF auth.uid() IS NULL
     OR p_context_type NOT IN ('order', 'ride')
     OR (p_context_type = 'order' AND p_order_id IS NULL)
     OR (p_context_type = 'ride' AND p_ride_request_id IS NULL)
     OR (p_context_type = 'order' AND p_ride_request_id IS NOT NULL)
     OR (p_context_type = 'ride' AND p_order_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'invalid chat context' USING ERRCODE = '22023';
  END IF;

  IF p_context_type = 'order'
     AND p_conversation_type NOT IN (
       'buyer_merchant', 'buyer_courier', 'merchant_courier'
     )
  THEN
    RAISE EXCEPTION 'invalid order conversation type' USING ERRCODE = '22023';
  END IF;

  IF p_context_type = 'ride'
     AND p_conversation_type <> 'passenger_courier'
  THEN
    RAISE EXCEPTION 'invalid ride conversation type' USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.chat_domain_participants(
      p_context_type,
      p_order_id,
      p_ride_request_id,
      p_conversation_type
    ) domain_participant
    WHERE domain_participant.user_id = auth.uid()
  )
  INTO v_caller_is_participant;

  IF NOT COALESCE(v_caller_is_participant, false)
     AND NOT public.chat_is_admin(auth.uid())
  THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  SELECT c.id
  INTO v_conversation_id
  FROM public.chat_conversations c
  WHERE (
    (
      p_context_type = 'order'
      AND c.order_id = p_order_id
      AND c.conversation_type = p_conversation_type
    )
    OR (
      p_context_type = 'ride'
      AND c.ride_request_id = p_ride_request_id
      AND c.conversation_type = p_conversation_type
    )
  )
  ORDER BY c.created_at
  LIMIT 1;

  IF v_conversation_id IS NULL THEN
    INSERT INTO public.chat_conversations (
      context_type,
      order_id,
      ride_request_id,
      conversation_type
    )
    VALUES (p_context_type, p_order_id, p_ride_request_id, p_conversation_type)
    RETURNING id INTO v_conversation_id;
  END IF;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  SELECT v_conversation_id, p.user_id, p.role
  FROM public.chat_domain_participants(
    p_context_type,
    p_order_id,
    p_ride_request_id,
    p_conversation_type
  ) p
  WHERE p.user_id IS NOT NULL
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$;

-- Direct chat remains pair-scoped and can only be opened by a buyer account.
CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_merchant_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat participant' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.id = p_merchant_id
      AND m.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'merchant cannot open buyer direct chat' USING ERRCODE = '42501';
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.user_id IS NOT NULL
    AND m.user_id <> auth.uid()
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type,
    merchant_id,
    buyer_user_id,
    conversation_type
  )
  VALUES ('direct', p_merchant_id, auth.uid(), 'buyer_merchant')
  ON CONFLICT (buyer_user_id, merchant_id, conversation_type)
    WHERE context_type = 'direct'
      AND buyer_user_id IS NOT NULL
      AND merchant_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$;

-- The read RPC is the only user write path for read cursors. A cursor may not
-- point at a different conversation or at a message the caller cannot read.
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
  IF auth.uid() IS NULL
     OR NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
  THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  IF p_message_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.chat_messages m
       WHERE m.id = p_message_id
         AND m.conversation_id = p_conversation_id
         AND m.deleted_at IS NULL
     )
  THEN
    RAISE EXCEPTION 'message does not belong to conversation' USING ERRCODE = '22023';
  END IF;

  UPDATE public.chat_participants
  SET last_read_at = now(),
      last_read_message_id = COALESCE(
        p_message_id,
        last_read_message_id
      )
  WHERE conversation_id = p_conversation_id
    AND user_id = auth.uid()
    AND left_at IS NULL;

  IF p_message_id IS NOT NULL THEN
    INSERT INTO public.chat_message_reads (message_id, user_id)
    VALUES (p_message_id, auth.uid())
    ON CONFLICT (message_id, user_id) DO UPDATE
    SET read_at = now();
  END IF;
END;
$$;

-- Canonical, idempotent message write. Sender, order context, message type,
-- and participant membership are derived or checked in the database.
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id uuid,
  p_receiver_id uuid,
  p_body text,
  p_client_message_id uuid
)
RETURNS public.chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.chat_messages%ROWTYPE;
  v_conversation public.chat_conversations%ROWTYPE;
  v_body text;
BEGIN
  IF auth.uid() IS NULL
     OR p_conversation_id IS NULL
     OR p_receiver_id IS NULL
     OR p_client_message_id IS NULL
  THEN
    RAISE EXCEPTION 'invalid chat message request' USING ERRCODE = '22023';
  END IF;

  v_body := btrim(COALESCE(p_body, ''));
  IF length(v_body) < 1 OR length(v_body) > 4000 THEN
    RAISE EXCEPTION 'chat message must contain 1 to 4000 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_conversation
  FROM public.chat_conversations c
  WHERE c.id = p_conversation_id
    AND c.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'conversation is not active' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
     OR NOT public.is_chat_conversation_participant(p_conversation_id, p_receiver_id)
     OR p_receiver_id = auth.uid()
  THEN
    RAISE EXCEPTION 'sender or receiver is not an active participant'
      USING ERRCODE = '42501';
  END IF;

  -- A retry with the same client ID returns the original row, but reusing it
  -- for a different conversation, recipient, or body is rejected.
  SELECT *
  INTO v_message
  FROM public.chat_messages m
  WHERE m.sender_id = auth.uid()
    AND m.client_message_id = p_client_message_id
  LIMIT 1;

  IF FOUND THEN
    IF v_message.conversation_id <> p_conversation_id
       OR v_message.receiver_id <> p_receiver_id
       OR btrim(COALESCE(v_message.body, v_message.message)) <> v_body
    THEN
      RAISE EXCEPTION 'client message ID was already used with different data'
        USING ERRCODE = '23505';
    END IF;
    RETURN v_message;
  END IF;

  INSERT INTO public.chat_messages (
    conversation_id,
    order_id,
    sender_id,
    receiver_id,
    message,
    body,
    message_type,
    client_message_id,
    chat_type
  )
  VALUES (
    p_conversation_id,
    v_conversation.order_id,
    auth.uid(),
    p_receiver_id,
    v_body,
    v_body,
    'text',
    p_client_message_id,
    v_conversation.conversation_type
  )
  ON CONFLICT (sender_id, client_message_id)
    WHERE client_message_id IS NOT NULL
  DO NOTHING
  RETURNING * INTO v_message;

  IF NOT FOUND THEN
    SELECT *
    INTO v_message
    FROM public.chat_messages m
    WHERE m.sender_id = auth.uid()
      AND m.client_message_id = p_client_message_id
    LIMIT 1;
  END IF;

  RETURN v_message;
END;
$$;

-- Prevent any future grant/policy regression from making messages mutable.
CREATE OR REPLACE FUNCTION public.protect_chat_message_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
     OR NEW.order_id IS DISTINCT FROM OLD.order_id
     OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.receiver_id IS DISTINCT FROM OLD.receiver_id
     OR NEW.message IS DISTINCT FROM OLD.message
     OR NEW.body IS DISTINCT FROM OLD.body
     OR NEW.message_type IS DISTINCT FROM OLD.message_type
     OR NEW.client_message_id IS DISTINCT FROM OLD.client_message_id
     OR NEW.chat_type IS DISTINCT FROM OLD.chat_type
     OR NEW.is_read IS DISTINCT FROM OLD.is_read
     OR NEW.image_url IS DISTINCT FROM OLD.image_url
     OR NEW.attachment_path IS DISTINCT FROM OLD.attachment_path
     OR NEW.auto_delete_at IS DISTINCT FROM OLD.auto_delete_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.soft_delete_at IS DISTINCT FROM OLD.soft_delete_at
     OR NEW.hard_delete_at IS DISTINCT FROM OLD.hard_delete_at
  THEN
    RAISE EXCEPTION 'chat messages are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_protect_immutability ON public.chat_messages;
CREATE TRIGGER chat_messages_protect_immutability
BEFORE UPDATE ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.protect_chat_message_immutability();

-- Re-check payload rules at the trigger boundary, including direct inserts
-- from trusted server jobs or a future privileged integration.
CREATE OR REPLACE FUNCTION public.validate_chat_message_payload()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NULL
     OR NEW.sender_id IS NULL
     OR NEW.receiver_id IS NULL
     OR NEW.client_message_id IS NULL
     OR length(btrim(COALESCE(NEW.body, NEW.message, ''))) NOT BETWEEN 1 AND 4000
  THEN
    RAISE EXCEPTION 'invalid chat message payload' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_validate_payload ON public.chat_messages;
CREATE TRIGGER chat_messages_validate_payload
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.validate_chat_message_payload();

-- Explicit grants keep PostgREST from exposing the RPCs to anonymous callers.
REVOKE ALL ON FUNCTION public.get_or_create_chat_conversation(text, uuid, uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_or_create_direct_chat(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_chat_conversation_read(uuid, uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_chat_message(uuid, uuid, text, uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_or_create_chat_conversation(text, uuid, uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_chat_conversation_read(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_chat_message(uuid, uuid, text, uuid)
  TO authenticated;

-- Unread count is read-only, but must not be callable anonymously.
REVOKE ALL ON FUNCTION public.get_chat_unread_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_unread_count() TO authenticated;