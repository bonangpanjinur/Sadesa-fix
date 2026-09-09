-- Dual-role accounts may act as buyer and merchant in separate chat contexts.
-- A merchant user is blocked only from opening a chat with their own store.

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

REVOKE ALL ON FUNCTION public.get_or_create_direct_chat(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;
