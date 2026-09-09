-- Chat security hardening: pair-scoped direct conversations and immutable messages.
-- Apply after 33_20260909100000_direct_chat_realtime.sql.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS buyer_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

-- Existing direct conversations must have exactly one buyer before the new
-- pair-scoped key can be enabled. Ambiguous rows fail closed for manual repair.
DO $$
DECLARE
  ambiguous_count integer;
BEGIN
  UPDATE public.chat_conversations c
  SET buyer_user_id = buyers.user_id
  FROM (
    SELECT cp.conversation_id, (array_agg(cp.user_id ORDER BY cp.user_id))[1] AS user_id
    FROM public.chat_participants cp
    JOIN public.chat_conversations dc ON dc.id = cp.conversation_id
    WHERE dc.context_type = 'direct'
      AND cp.role = 'buyer'
      AND cp.left_at IS NULL
    GROUP BY cp.conversation_id
    HAVING count(*) = 1
  ) buyers
  WHERE c.id = buyers.conversation_id
    AND c.context_type = 'direct'
    AND c.buyer_user_id IS NULL;

  SELECT count(*)
  INTO ambiguous_count
  FROM public.chat_conversations c
  WHERE c.context_type = 'direct'
    AND c.buyer_user_id IS NULL;

  IF ambiguous_count > 0 THEN
    RAISE EXCEPTION 'direct chat migration blocked: % conversation(s) have no unique buyer participant', ambiguous_count
      USING ERRCODE = '23514';
  END IF;
END;
$$;

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_one_context;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND buyer_user_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND buyer_user_id IS NULL)
    OR
    (context_type = 'direct' AND merchant_id IS NOT NULL AND buyer_user_id IS NOT NULL AND order_id IS NULL AND ride_request_id IS NULL)
  );

DROP INDEX IF EXISTS public.chat_conversations_direct_merchant_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_direct_pair_uidx
  ON public.chat_conversations(buyer_user_id, merchant_id, conversation_type)
  WHERE context_type = 'direct'
    AND buyer_user_id IS NOT NULL
    AND merchant_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS chat_conversations_direct_buyer_idx
  ON public.chat_conversations(buyer_user_id, merchant_id)
  WHERE context_type = 'direct';

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
    context_type, merchant_id, buyer_user_id, conversation_type
  )
  VALUES ('direct', p_merchant_id, auth.uid(), 'buyer_merchant')
  ON CONFLICT (buyer_user_id, merchant_id, conversation_type)
    WHERE context_type = 'direct'
      AND buyer_user_id IS NOT NULL
      AND merchant_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  IF NOT public.is_chat_conversation_participant(v_conversation_id, auth.uid())
     AND NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  RETURN v_conversation_id;
END;
$$;

-- Users must not mutate message rows to mark read. Read state is written only
-- through mark_chat_conversation_read, while admin/service jobs retain access.
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update own chat messages read status" ON public.chat_messages;

CREATE OR REPLACE FUNCTION public.validate_chat_message_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.is_chat_conversation_participant(NEW.conversation_id, NEW.sender_id)
     OR NEW.sender_id <> auth.uid() THEN
    RAISE EXCEPTION 'sender is not an active conversation participant' USING ERRCODE = '42501';
  END IF;

  IF NEW.receiver_id IS NULL
     OR NOT public.is_chat_conversation_participant(NEW.conversation_id, NEW.receiver_id)
     OR NEW.receiver_id = NEW.sender_id THEN
    RAISE EXCEPTION 'receiver is not a different active conversation participant' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_validate_participants ON public.chat_messages;
CREATE TRIGGER chat_messages_validate_participants
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.validate_chat_message_participants();

REVOKE UPDATE ON public.chat_messages FROM authenticated;
GRANT UPDATE ON public.chat_messages TO authenticated;
