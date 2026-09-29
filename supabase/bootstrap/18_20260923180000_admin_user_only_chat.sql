-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_49bbf867036a$
BEGIN
  EXECUTE $bootstrap_sql_49bbf867036a$-- Admin-user direct chat: one private thread per admin/user pair.
-- Non-admin users may reply only inside a thread created by an admin.

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check$bootstrap_sql_49bbf867036a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49bbf867036a$;

DO $bootstrap_do_8136453c8fdf$
BEGIN
  EXECUTE $bootstrap_sql_8136453c8fdf$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier', 'admin_user'))$bootstrap_sql_8136453c8fdf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8136453c8fdf$;

DO $bootstrap_do_43a67e06570f$
BEGIN
  EXECUTE $bootstrap_sql_43a67e06570f$CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
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
$$$bootstrap_sql_43a67e06570f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43a67e06570f$;

DO $bootstrap_do_3c5792cdceb0$
BEGIN
  EXECUTE $bootstrap_sql_3c5792cdceb0$REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon$bootstrap_sql_3c5792cdceb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c5792cdceb0$;

DO $bootstrap_do_a9d375237823$
BEGIN
  EXECUTE $bootstrap_sql_a9d375237823$GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated$bootstrap_sql_a9d375237823$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9d375237823$;

DO $bootstrap_do_ba98448527db$
BEGIN
  EXECUTE $bootstrap_sql_ba98448527db$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ba98448527db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba98448527db$;
