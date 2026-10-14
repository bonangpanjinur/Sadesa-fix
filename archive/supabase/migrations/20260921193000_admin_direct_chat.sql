-- Admin direct chat: allow admins to start a conversation with an active merchant or approved courier.
-- This migration is intentionally independent from order/ride chat and does not require prior messages.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS direct_admin_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS direct_target_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE$bootstrap_sql_20a9f65def78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20a9f65def78$;

DO $bootstrap_do_0f08908dcb9d$
BEGIN
  EXECUTE $bootstrap_sql_0f08908dcb9d$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check$bootstrap_sql_0f08908dcb9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f08908dcb9d$;

DO $bootstrap_do_9e8ff7bfaf6c$
BEGIN
  EXECUTE $bootstrap_sql_9e8ff7bfaf6c$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'))$bootstrap_sql_9e8ff7bfaf6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e8ff7bfaf6c$;

DO $bootstrap_do_614f706d97b8$
BEGIN
  EXECUTE $bootstrap_sql_614f706d97b8$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_one_context$bootstrap_sql_614f706d97b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_614f706d97b8$;

DO $bootstrap_do_b45c82576699$
BEGIN
  EXECUTE $bootstrap_sql_b45c82576699$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_one_context CHECK (
  (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'direct' AND order_id IS NULL AND ride_request_id IS NULL AND (
    (merchant_id IS NOT NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
    OR (merchant_id IS NULL AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL)
  ))
)$bootstrap_sql_b45c82576699$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b45c82576699$;

DO $bootstrap_do_438fe93a5ccf$
BEGIN
  EXECUTE $bootstrap_sql_438fe93a5ccf$ALTER TABLE public.chat_participants DROP CONSTRAINT IF EXISTS chat_participants_role_check$bootstrap_sql_438fe93a5ccf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_438fe93a5ccf$;

DO $bootstrap_do_71f1d0006ea1$
BEGIN
  EXECUTE $bootstrap_sql_71f1d0006ea1$ALTER TABLE public.chat_participants ADD CONSTRAINT chat_participants_role_check
  CHECK (role IN ('admin', 'buyer', 'merchant', 'courier', 'passenger'))$bootstrap_sql_71f1d0006ea1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71f1d0006ea1$;

DO $bootstrap_do_627f636f3c60$
BEGIN
  EXECUTE $bootstrap_sql_627f636f3c60$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check$bootstrap_sql_627f636f3c60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_627f636f3c60$;

DO $bootstrap_do_f4e4a03c6eeb$
BEGIN
  EXECUTE $bootstrap_sql_f4e4a03c6eeb$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier'))$bootstrap_sql_f4e4a03c6eeb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4e4a03c6eeb$;

DO $bootstrap_do_930769e6c0da$
BEGIN
  EXECUTE $bootstrap_sql_930769e6c0da$CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_admin_direct_uidx
  ON public.chat_conversations(direct_admin_user_id, direct_target_user_id, conversation_type)
  WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL$bootstrap_sql_930769e6c0da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_930769e6c0da$;

DO $bootstrap_do_a2dc0b53d21a$
BEGIN
  EXECUTE $bootstrap_sql_a2dc0b53d21a$CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
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
BEGIN
  IF auth.uid() IS NULL OR NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid() OR p_target_role NOT IN ('merchant', 'courier') THEN
    RAISE EXCEPTION 'invalid chat target' USING ERRCODE = '22023';
  END IF;

  IF p_target_role = 'merchant' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.merchants
      WHERE user_id = p_target_user_id AND status = 'ACTIVE'
    ) INTO v_target_exists;
    v_type := 'admin_merchant';
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.couriers
      WHERE user_id = p_target_user_id AND registration_status = 'APPROVED'
    ) INTO v_target_exists;
    v_type := 'admin_courier';
  END IF;
  IF NOT v_target_exists THEN
    RAISE EXCEPTION 'chat target account not found or inactive' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, conversation_type, direct_admin_user_id, direct_target_user_id
  )
  VALUES ('direct', v_type, auth.uid(), p_target_user_id)
  ON CONFLICT (direct_admin_user_id, direct_target_user_id, conversation_type)
    WHERE context_type = 'direct'
      AND direct_admin_user_id IS NOT NULL
      AND direct_target_user_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'admin'),
    (v_conversation_id, p_target_user_id, p_target_role)
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$$bootstrap_sql_a2dc0b53d21a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2dc0b53d21a$;

DO $bootstrap_do_953d9ef82ae1$
BEGIN
  EXECUTE $bootstrap_sql_953d9ef82ae1$REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon$bootstrap_sql_953d9ef82ae1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_953d9ef82ae1$;

DO $bootstrap_do_8b2e5a441f03$
BEGIN
  EXECUTE $bootstrap_sql_8b2e5a441f03$GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated$bootstrap_sql_8b2e5a441f03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b2e5a441f03$;

DO $bootstrap_do_3dbed7ed6a34$
BEGIN
  EXECUTE $bootstrap_sql_3dbed7ed6a34$-- PostgREST caches database functions; reload immediately after migration.
NOTIFY pgrst, 'reload schema'$bootstrap_sql_3dbed7ed6a34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3dbed7ed6a34$;

DO $bootstrap_do_5e3316414fde$
BEGIN
  EXECUTE $bootstrap_sql_5e3316414fde$
