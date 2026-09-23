-- Admin-user direct chat: one private thread per admin/user pair.
-- Non-admin users may reply only inside a thread created by an admin.

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier', 'admin_user'));

CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
  p_target_user_id uuid,
  p_target_role text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_type text;
  v_target_exists boolean;
  v_participant_role text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid()
     OR p_target_role NOT IN ('merchant', 'courier', 'buyer') THEN
    RAISE EXCEPTION 'invalid chat target' USING ERRCODE = '22023';
  END IF;

  IF p_target_role = 'merchant' THEN
    SELECT EXISTS (SELECT 1 FROM public.merchants WHERE user_id = p_target_user_id AND status = 'ACTIVE') INTO v_target_exists;
    v_type := 'admin_merchant';
    v_participant_role := 'merchant';
  ELSIF p_target_role = 'courier' THEN
    SELECT EXISTS (SELECT 1 FROM public.couriers WHERE user_id = p_target_user_id AND registration_status = 'APPROVED') INTO v_target_exists;
    v_type := 'admin_courier';
    v_participant_role := 'courier';
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = p_target_user_id
        AND NOT public.chat_is_admin(u.id)
    ) INTO v_target_exists;
    v_type := 'admin_user';
    v_participant_role := 'buyer';
  END IF;
  IF NOT v_target_exists THEN
    RAISE EXCEPTION 'chat target account not found or inactive' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, conversation_type, direct_admin_user_id, direct_target_user_id
  )
  VALUES ('direct', v_type, auth.uid(), p_target_user_id)
  ON CONFLICT (direct_admin_user_id, direct_target_user_id, conversation_type)
    WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES (v_conversation_id, auth.uid(), 'admin'), (v_conversation_id, p_target_user_id, v_participant_role)
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET left_at = NULL, role = EXCLUDED.role;
  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
