-- Expose participant names only inside conversations the caller may access.
-- Profiles remain private; chat inboxes use this narrow SECURITY DEFINER RPC.

CREATE OR REPLACE FUNCTION public.get_chat_participant_profiles(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, full_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    target.user_id,
    COALESCE(
      NULLIF(trim(p.full_name), ''),
      NULLIF(trim(m.name), ''),
      NULLIF(trim(c.name), '')
    ) AS full_name
  FROM public.chat_participants target
  LEFT JOIN public.profiles p ON p.user_id = target.user_id
  LEFT JOIN public.merchants m ON m.user_id = target.user_id AND m.status = 'ACTIVE'
  LEFT JOIN public.couriers c ON c.user_id = target.user_id
  WHERE target.user_id = ANY(COALESCE(p_user_ids, ARRAY[]::uuid[]))
    AND target.left_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.chat_participants caller_membership
      JOIN public.chat_participants target_membership
        ON target_membership.conversation_id = caller_membership.conversation_id
       AND target_membership.user_id = target.user_id
       AND target_membership.left_at IS NULL
      WHERE caller_membership.user_id = auth.uid()
        AND caller_membership.left_at IS NULL
    );
$$;

REVOKE ALL ON FUNCTION public.get_chat_participant_profiles(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_participant_profiles(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_chat_participant_profiles(uuid[]) IS
  'Returns participant profile names only for conversations visible to the authenticated caller.';

GRANT EXECUTE ON FUNCTION public.get_chat_participant_profiles(uuid[]) TO service_role;
