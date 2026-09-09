-- Chat message retention: soft delete at day 14, hard delete at day 30.
-- Apply after 34_20260909110000_chat_security_pair_isolation.sql.

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS soft_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS hard_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

-- Existing messages receive deterministic expiry dates based on created_at.
UPDATE public.chat_messages
SET soft_delete_at = created_at + interval '14 days',
    hard_delete_at = created_at + interval '30 days'
WHERE soft_delete_at IS NULL OR hard_delete_at IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_retention_order_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_retention_order_check
      CHECK (hard_delete_at > soft_delete_at);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS chat_messages_soft_delete_idx
  ON public.chat_messages(soft_delete_at, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS chat_messages_hard_delete_idx
  ON public.chat_messages(hard_delete_at, id);

CREATE OR REPLACE FUNCTION public.set_chat_message_retention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.created_at IS NULL THEN
    NEW.created_at := now();
  END IF;
  IF NEW.soft_delete_at IS NULL THEN
    NEW.soft_delete_at := NEW.created_at + interval '14 days';
  END IF;
  IF NEW.hard_delete_at IS NULL THEN
    NEW.hard_delete_at := NEW.created_at + interval '30 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_set_retention ON public.chat_messages;
CREATE TRIGGER chat_messages_set_retention
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.set_chat_message_retention();

CREATE OR REPLACE FUNCTION public.soft_delete_expired_chat_messages(
  p_limit integer DEFAULT 500
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 5000 THEN
    RAISE EXCEPTION 'retention batch limit must be between 1 and 5000' USING ERRCODE = '22023';
  END IF;

  WITH candidates AS (
    SELECT id
    FROM public.chat_messages
    WHERE deleted_at IS NULL
      AND soft_delete_at <= now()
      AND hard_delete_at > now()
    ORDER BY soft_delete_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE public.chat_messages m
  SET deleted_at = now(),
      deleted_reason = 'retention_14_days'
  FROM candidates c
  WHERE m.id = c.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_hard_expired_chat_messages(
  p_limit integer DEFAULT 500
)
RETURNS TABLE(id uuid, attachment_path text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.id, m.attachment_path
  FROM public.chat_messages m
  WHERE m.hard_delete_at <= now()
  ORDER BY m.hard_delete_at, m.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000);
$$;

CREATE OR REPLACE FUNCTION public.hard_delete_chat_messages(
  p_message_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_message_ids IS NULL OR cardinality(p_message_ids) = 0 THEN
    RETURN 0;
  END IF;

  DELETE FROM public.chat_messages
  WHERE id = ANY(p_message_ids)
    AND hard_delete_at <= now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.soft_delete_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_hard_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hard_delete_chat_messages(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.soft_delete_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_hard_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.hard_delete_chat_messages(uuid[]) TO service_role;

-- Canonical cleanup is now delegated to the retention worker. Keep the legacy
-- function name as a compatibility wrapper for existing operational tooling.
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.soft_delete_expired_chat_messages(5000);
  DELETE FROM public.chat_messages
  WHERE conversation_id IS NULL
    AND auto_delete_at IS NOT NULL
    AND auto_delete_at <= now();
END;
$$;
