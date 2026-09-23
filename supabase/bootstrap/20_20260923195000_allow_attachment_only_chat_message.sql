-- Allow image-only chat messages.
-- send_chat_message_with_attachment already accepts an attachment without text,
-- but the generic payload trigger still required a non-empty message body.

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
     OR (
       length(btrim(COALESCE(NEW.body, NEW.message, ''))) NOT BETWEEN 1 AND 4000
       AND NEW.attachment_path IS NULL
     )
  THEN
    RAISE EXCEPTION 'invalid chat message payload' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
