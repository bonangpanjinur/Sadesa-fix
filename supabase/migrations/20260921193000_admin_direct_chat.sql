-- Admin direct chat: allow admins to start a conversation with an active merchant or approved courier.
-- This migration is intentionally independent from order/ride chat and does not require prior messages.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS direct_admin_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS direct_target_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_one_context;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_one_context CHECK (
  (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'direct' AND order_id IS NULL AND ride_request_id IS NULL AND (
    (merchant_id IS NOT NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
    OR (merchant_id IS NULL AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL)
  ))
);

ALTER TABLE public.chat_participants DROP CONSTRAINT IF EXISTS chat_participants_role_check;
ALTER TABLE public.chat_participants ADD CONSTRAINT chat_participants_role_check
  CHECK (role IN ('admin', 'buyer', 'merchant', 'courier', 'passenger'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier'));

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_admin_direct_uidx
  ON public.chat_conversations(direct_admin_user_id, direct_target_user_id, conversation_type)
  WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL;

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
$$;

REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated;

-- PostgREST caches database functions; reload immediately after migration.
NOTIFY pgrst, 'reload schema';
