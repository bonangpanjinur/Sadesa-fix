-- Direct in-app buyer/merchant chat.
-- This extends the canonical conversation model without changing order/ride chat.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE;

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'));

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_one_context;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL)
    OR
    (context_type = 'direct' AND merchant_id IS NOT NULL AND order_id IS NULL AND ride_request_id IS NULL)
  );

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_direct_merchant_uidx
  ON public.chat_conversations(merchant_id, conversation_type)
  WHERE context_type = 'direct' AND merchant_id IS NOT NULL;

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
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, merchant_id, conversation_type
  )
  VALUES ('direct', p_merchant_id, 'buyer_merchant')
  ON CONFLICT (merchant_id, conversation_type)
    WHERE context_type = 'direct' AND merchant_id IS NOT NULL
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

GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END;
$$;