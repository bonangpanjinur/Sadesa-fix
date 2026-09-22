-- Chat image attachments: private storage + atomic message write.
-- Files are stored under <conversation_id>/<sender_id>/<uuid>.<ext>.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments',
  'chat-attachments',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[];

DROP POLICY IF EXISTS "Chat participants upload attachments" ON storage.objects;
CREATE POLICY "Chat participants upload attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments'
  AND public.is_chat_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
  AND (storage.foldername(name))[2] = auth.uid()::text
);

DROP POLICY IF EXISTS "Chat participants read attachments" ON storage.objects;
CREATE POLICY "Chat participants read attachments"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND public.is_chat_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
);

DROP POLICY IF EXISTS "Users delete own chat attachments" ON storage.objects;
CREATE POLICY "Users delete own chat attachments"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_attachment_path_check
  CHECK (attachment_path IS NULL OR attachment_path LIKE '%/%/%') NOT VALID;

-- Five-argument variant keeps the existing four-argument RPC backwards compatible.
CREATE OR REPLACE FUNCTION public.send_chat_message_with_attachment(
  p_conversation_id uuid,
  p_receiver_id uuid,
  p_body text,
  p_client_message_id uuid,
  p_attachment_path text DEFAULT NULL
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
  IF length(v_body) > 4000 THEN
    RAISE EXCEPTION 'chat message must contain at most 4000 characters' USING ERRCODE = '22023';
  END IF;
  IF length(v_body) = 0 AND p_attachment_path IS NULL THEN
    RAISE EXCEPTION 'chat message must contain text or an image' USING ERRCODE = '22023';
  END IF;
  IF p_attachment_path IS NOT NULL AND (
    p_attachment_path !~ '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]+$'
    OR p_attachment_path LIKE '%..%'
  ) THEN
    RAISE EXCEPTION 'invalid chat attachment path' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_conversation
  FROM public.chat_conversations
  WHERE id = p_conversation_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'conversation is not active' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
     OR NOT public.is_chat_conversation_participant(p_conversation_id, p_receiver_id)
     OR p_receiver_id = auth.uid()
  THEN
    RAISE EXCEPTION 'sender or receiver is not an active participant' USING ERRCODE = '42501';
  END IF;
  IF p_attachment_path IS NOT NULL
     AND split_part(p_attachment_path, '/', 1) <> p_conversation_id::text
  THEN
    RAISE EXCEPTION 'attachment does not belong to conversation' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_message
  FROM public.chat_messages
  WHERE sender_id = auth.uid() AND client_message_id = p_client_message_id
  LIMIT 1;
  IF FOUND THEN
    IF v_message.conversation_id <> p_conversation_id
       OR v_message.receiver_id <> p_receiver_id
       OR btrim(COALESCE(v_message.body, v_message.message)) <> COALESCE(v_body, '')
       OR v_message.attachment_path IS DISTINCT FROM p_attachment_path
    THEN
      RAISE EXCEPTION 'client message ID was already used with different data' USING ERRCODE = '23505';
    END IF;
    RETURN v_message;
  END IF;

  INSERT INTO public.chat_messages (
    conversation_id, order_id, sender_id, receiver_id, message, body,
    message_type, client_message_id, chat_type, attachment_path
  ) VALUES (
    p_conversation_id, v_conversation.order_id, auth.uid(), p_receiver_id,
    COALESCE(NULLIF(v_body, ''), 'Gambar'), v_body,
    CASE WHEN p_attachment_path IS NULL THEN 'text' ELSE 'image' END,
    p_client_message_id, v_conversation.conversation_type, p_attachment_path
  )
  RETURNING * INTO v_message;
  RETURN v_message;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message_with_attachment(uuid, uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message_with_attachment(uuid, uuid, text, uuid, text) TO authenticated;

COMMENT ON FUNCTION public.send_chat_message_with_attachment IS
  'Atomically writes a chat text/image message after validating conversation membership and attachment path.';

NOTIFY pgrst, 'reload schema';

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;
ALTER TABLE public.chat_messages ADD CONSTRAINT chat_messages_message_type_check
  CHECK (message_type IN ('text', 'image')) NOT VALID;
