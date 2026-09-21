-- Route chat notifications to the correct inbox for admin recipients.
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
    WHEN 'admin' THEN '/admin/chat?conversationId=' || p_conversation_id::text
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN CASE
      WHEN c.context_type = 'ride' AND c.ride_request_id IS NOT NULL
        THEN '/courier/rides?conversationId=' || p_conversation_id::text
      ELSE '/courier/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'passenger' THEN CASE
      WHEN c.ride_request_id IS NOT NULL
        THEN '/ride/' || c.ride_request_id::text || '?conversationId=' || p_conversation_id::text
      ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'admin_desa' THEN '/desa/chat?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END
  FROM public.chat_conversations c
  WHERE c.id = p_conversation_id);
$$;

GRANT EXECUTE ON FUNCTION public.chat_notification_deep_link(uuid, uuid)
  TO service_role;

NOTIFY pgrst, 'reload schema';
