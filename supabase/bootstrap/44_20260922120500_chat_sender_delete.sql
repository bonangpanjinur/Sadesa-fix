-- Allow a sender (including admin direct-chat senders) to retract their own message.
-- This is a soft-delete: the row remains for retention/audit and realtime update.
CREATE OR REPLACE FUNCTION public.delete_chat_message(p_message_id uuid)
RETURNS public.chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.chat_messages%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat delete request' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_message
  FROM public.chat_messages
  WHERE id = p_message_id
    AND sender_id = auth.uid()
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'message not found or not owned by current user' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_messages
  SET deleted_at = now(),
      deleted_reason = 'sender_deleted'
  WHERE id = p_message_id
  RETURNING * INTO v_message;

  RETURN v_message;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_chat_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_chat_message(uuid) TO authenticated;
COMMENT ON FUNCTION public.delete_chat_message IS
  'Soft-deletes a chat message only when the authenticated user is its sender.';
NOTIFY pgrst, 'reload schema';
