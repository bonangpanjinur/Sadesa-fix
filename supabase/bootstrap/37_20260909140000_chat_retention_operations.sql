-- Chat retention operations: idempotent redaction, hard-delete claims, and metrics.
-- Apply after 36_20260909130000_chat_rls_rpc_abuse_control.sql.

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS soft_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS hard_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

CREATE TABLE IF NOT EXISTS public.chat_retention_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  status text NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  soft_deleted integer NOT NULL DEFAULT 0,
  hard_delete_candidates integer NOT NULL DEFAULT 0,
  hard_deleted integer NOT NULL DEFAULT 0,
  attachment_objects_removed integer NOT NULL DEFAULT 0,
  error_code text,
  error_message text
);

CREATE INDEX IF NOT EXISTS chat_retention_runs_started_idx
  ON public.chat_retention_runs(started_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_retention_claims (
  message_id uuid PRIMARY KEY REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_retention_claims_claimed_idx
  ON public.chat_retention_claims(claimed_at);

CREATE OR REPLACE FUNCTION public.soft_delete_expired_chat_messages(p_limit integer DEFAULT 500)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 5000 THEN
    RAISE EXCEPTION 'retention batch limit must be between 1 and 5000' USING ERRCODE = '22023';
  END IF;

  WITH candidates AS (
    SELECT id FROM public.chat_messages
    WHERE deleted_at IS NULL
      AND soft_delete_at <= now()
      AND hard_delete_at > now()
    ORDER BY soft_delete_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE public.chat_messages m
  SET deleted_at = COALESCE(m.deleted_at, now()),
      deleted_reason = COALESCE(m.deleted_reason, 'retention_14_days'),
      body = '[Pesan dihapus otomatis]',
      message = '[Pesan dihapus otomatis]'
  FROM candidates c
  WHERE m.id = c.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_hard_expired_chat_messages(p_limit integer DEFAULT 500)
RETURNS TABLE(id uuid, attachment_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.chat_retention_claims(message_id)
  SELECT m.id FROM public.chat_messages m
  LEFT JOIN public.chat_retention_claims c ON c.message_id = m.id
  WHERE m.hard_delete_at <= now()
    AND (c.message_id IS NULL OR c.claimed_at < now() - interval '15 minutes')
  ORDER BY m.hard_delete_at, m.id
  FOR UPDATE OF m SKIP LOCKED
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000)
  ON CONFLICT (message_id) DO UPDATE SET claimed_at = now();

  RETURN QUERY
  SELECT m.id, m.attachment_path
  FROM public.chat_messages m
  JOIN public.chat_retention_claims c ON c.message_id = m.id
  WHERE m.hard_delete_at <= now()
    AND c.claimed_at >= now() - interval '15 minutes'
  ORDER BY m.hard_delete_at, m.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000);
END;
$$;

CREATE OR REPLACE FUNCTION public.hard_delete_chat_messages(p_message_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  IF p_message_ids IS NULL OR cardinality(p_message_ids) = 0 THEN RETURN 0; END IF;
  DELETE FROM public.chat_message_reads WHERE message_id = ANY(p_message_ids);
  DELETE FROM public.chat_messages m
  WHERE m.id = ANY(p_message_ids)
    AND m.hard_delete_at <= now()
    AND EXISTS (SELECT 1 FROM public.chat_retention_claims c WHERE c.message_id = m.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM public.chat_retention_claims WHERE message_id = ANY(p_message_ids);
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_chat_retention_run(
  p_run_id uuid, p_status text, p_soft_deleted integer DEFAULT 0,
  p_hard_delete_candidates integer DEFAULT 0, p_hard_deleted integer DEFAULT 0,
  p_attachment_objects_removed integer DEFAULT 0, p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.chat_retention_runs
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'failed') THEN now() ELSE completed_at END,
      soft_deleted = p_soft_deleted,
      hard_delete_candidates = p_hard_delete_candidates,
      hard_deleted = p_hard_deleted,
      attachment_objects_removed = p_attachment_objects_removed,
      error_code = p_error_code,
      error_message = left(p_error_message, 500)
  WHERE id = p_run_id;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- The legacy three-hour auto_delete_at policy is intentionally disabled.
  PERFORM public.soft_delete_expired_chat_messages(5000);
END;
$$;

REVOKE ALL ON TABLE public.chat_retention_runs, public.chat_retention_claims FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.soft_delete_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_hard_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hard_delete_chat_messages(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_chat_retention_run(uuid, text, integer, integer, integer, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.chat_retention_runs TO service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_hard_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.hard_delete_chat_messages(uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_chat_retention_run(uuid, text, integer, integer, integer, integer, text, text) TO service_role;
