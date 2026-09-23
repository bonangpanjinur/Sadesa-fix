-- Fix chat notification sender lookup for PostgreSQL compatibility.
-- The previous trigger used FULL JOIN with OR predicates, which PostgreSQL cannot plan.

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
    (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(m.name, '') FROM public.merchants m WHERE m.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = NEW.sender_id LIMIT 1),
    'Pengguna'
  )
  INTO sender_name;

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

NOTIFY pgrst, 'reload schema';
