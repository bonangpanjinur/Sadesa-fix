-- Fase 1: Upgrade tabel chat_messages untuk multi-tipe chat

-- Tambah kolom chat_type dan image_url
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS chat_type TEXT DEFAULT 'buyer_merchant',
  ADD COLUMN IF NOT EXISTS image_url TEXT$bootstrap_sql_5bcb06012886$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5bcb06012886$;

DO $bootstrap_do_b72a8272b03d$
BEGIN
  EXECUTE $bootstrap_sql_b72a8272b03d$-- Index untuk query berdasarkan chat_type
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_type ON public.chat_messages(order_id, chat_type)$bootstrap_sql_b72a8272b03d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b72a8272b03d$;

DO $bootstrap_do_cb12db4e00fe$
BEGIN
  EXECUTE $bootstrap_sql_cb12db4e00fe$-- Drop existing RLS policies yang akan di-update
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_cb12db4e00fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb12db4e00fe$;

DO $bootstrap_do_08570982884f$
BEGIN
  EXECUTE $bootstrap_sql_08570982884f$DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_08570982884f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08570982884f$;

DO $bootstrap_do_6a74df26800a$
BEGIN
  EXECUTE $bootstrap_sql_6a74df26800a$DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages$bootstrap_sql_6a74df26800a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a74df26800a$;

DO $bootstrap_do_ea28dfa05bd3$
BEGIN
  EXECUTE $bootstrap_sql_ea28dfa05bd3$-- Helper function: cek apakah user adalah kurir pada order tertentu
CREATE OR REPLACE FUNCTION public.is_chat_participant(
  _user_id uuid,
  _order_id uuid,
  _chat_type text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN _chat_type = 'buyer_merchant' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN merchants m ON o.merchant_id = m.id
        WHERE o.id = _order_id
          AND (o.buyer_id = _user_id OR m.user_id = _user_id)
      )
    WHEN _chat_type = 'buyer_courier' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN couriers c ON o.courier_id = c.id
        WHERE o.id = _order_id
          AND (o.buyer_id = _user_id OR c.user_id = _user_id)
      )
    WHEN _chat_type = 'merchant_courier' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN merchants m ON o.merchant_id = m.id
        LEFT JOIN couriers c ON o.courier_id = c.id
        WHERE o.id = _order_id
          AND (m.user_id = _user_id OR c.user_id = _user_id)
      )
    ELSE false
  END
$$$bootstrap_sql_ea28dfa05bd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea28dfa05bd3$;

DO $bootstrap_do_7322393589c8$
BEGIN
  EXECUTE $bootstrap_sql_7322393589c8$-- RLS: Users can view chat messages where they are participants
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_7322393589c8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7322393589c8$;

DO $bootstrap_do_5b43614e7ff0$
BEGIN
  EXECUTE $bootstrap_sql_5b43614e7ff0$CREATE POLICY "Users can view own chat messages"
ON public.chat_messages
FOR SELECT
USING (
  (auth.uid() = sender_id OR auth.uid() = receiver_id)
  OR is_chat_participant(auth.uid(), order_id, chat_type)
)$bootstrap_sql_5b43614e7ff0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b43614e7ff0$;

DO $bootstrap_do_8ce5bb822719$
BEGIN
  EXECUTE $bootstrap_sql_8ce5bb822719$-- RLS: Users can send chat messages if they are a participant
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_8ce5bb822719$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ce5bb822719$;

DO $bootstrap_do_c3370cc0f6c9$
BEGIN
  EXECUTE $bootstrap_sql_c3370cc0f6c9$CREATE POLICY "Users can send chat messages"
ON public.chat_messages
FOR INSERT
WITH CHECK (
  auth.uid() = sender_id
  AND is_chat_participant(auth.uid(), order_id, chat_type)
)$bootstrap_sql_c3370cc0f6c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3370cc0f6c9$;

DO $bootstrap_do_45a8474fb6d4$
BEGIN
  EXECUTE $bootstrap_sql_45a8474fb6d4$-- RLS: Users can update read status on messages they received
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages$bootstrap_sql_45a8474fb6d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45a8474fb6d4$;

DO $bootstrap_do_e5be123ee1c7$
BEGIN
  EXECUTE $bootstrap_sql_e5be123ee1c7$CREATE POLICY "Users can update own messages read status"
ON public.chat_messages
FOR UPDATE
USING (auth.uid() = receiver_id)$bootstrap_sql_e5be123ee1c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5be123ee1c7$;

DO $bootstrap_do_1c6d8463105f$
BEGIN
  EXECUTE $bootstrap_sql_1c6d8463105f$-- Create storage bucket for chat images
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-images', 'chat-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_1c6d8463105f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c6d8463105f$;

DO $bootstrap_do_916d0700bc9f$
BEGIN
  EXECUTE $bootstrap_sql_916d0700bc9f$-- Storage policies for chat images
DROP POLICY IF EXISTS "Authenticated users can upload chat images" ON storage.objects$bootstrap_sql_916d0700bc9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_916d0700bc9f$;

DO $bootstrap_do_5202facbef1b$
BEGIN
  EXECUTE $bootstrap_sql_5202facbef1b$CREATE POLICY "Authenticated users can upload chat images"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'chat-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_5202facbef1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5202facbef1b$;

DO $bootstrap_do_83daac2d4203$
BEGIN
  EXECUTE $bootstrap_sql_83daac2d4203$DROP POLICY IF EXISTS "Anyone can view chat images" ON storage.objects$bootstrap_sql_83daac2d4203$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83daac2d4203$;

DO $bootstrap_do_f3f2cc8ab2b1$
BEGIN
  EXECUTE $bootstrap_sql_f3f2cc8ab2b1$CREATE POLICY "Anyone can view chat images"
ON storage.objects
FOR SELECT
USING (bucket_id = 'chat-images')$bootstrap_sql_f3f2cc8ab2b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3f2cc8ab2b1$;

DO $bootstrap_do_157eec0b55be$
BEGIN
  EXECUTE $bootstrap_sql_157eec0b55be$
