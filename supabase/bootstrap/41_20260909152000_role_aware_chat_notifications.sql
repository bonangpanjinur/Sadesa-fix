-- Role-aware chat badges and notification destinations for dual-role accounts.

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
   AND p.role = 'buyer'
   AND p.left_at IS NULL
  WHERE m.sender_id <> auth.uid()
    AND m.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.chat_message_reads r
      WHERE r.message_id = m.id
        AND r.user_id = auth.uid()
    );
$$;

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

  -- Resolve display names with independent lookups. PostgreSQL rejects
  -- disjunctive outer-join plans in this trigger path (SQLSTATE 0A000),
  -- which rolls back the message INSERT and surfaces as an RPC 400.
  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '')
     FROM public.profiles p
     WHERE p.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(m.name, '')
     FROM public.merchants m
     WHERE m.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(c.name, '')
     FROM public.couriers c
     WHERE c.user_id = NEW.sender_id
     LIMIT 1),
    'Pengguna'
  )
  INTO sender_name;

  preview := left(
    regexp_replace(trim(COALESCE(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
    120
  );

  FOR recipient IN
    SELECT p.user_id, p.role
    FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id
      AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL
      AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    PERFORM public.send_chat_notification(
      recipient.user_id,
      NEW.conversation_id,
      NEW.id,
      COALESCE(sender_name, 'Pesan baru'),
      preview
    );
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.get_chat_unread_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_unread_count() TO authenticated;
