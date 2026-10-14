-- Create chat_messages table if not exists
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL,
  receiver_id UUID NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  chat_type TEXT DEFAULT 'buyer_merchant',
  image_url TEXT,
  auto_delete_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_db5833b88f8a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db5833b88f8a$;

DO $bootstrap_do_a50995a1b6d3$
BEGIN
  EXECUTE $bootstrap_sql_a50995a1b6d3$-- Enable RLS
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY$bootstrap_sql_a50995a1b6d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a50995a1b6d3$;

DO $bootstrap_do_c9b12f9c7965$
BEGIN
  EXECUTE $bootstrap_sql_c9b12f9c7965$-- Add columns if they don't exist (for cases where table exists but columns don't)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='chat_type') THEN
    ALTER TABLE public.chat_messages ADD COLUMN chat_type TEXT DEFAULT 'buyer_merchant';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='image_url') THEN
    ALTER TABLE public.chat_messages ADD COLUMN image_url TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='auto_delete_at') THEN
    ALTER TABLE public.chat_messages ADD COLUMN auto_delete_at TIMESTAMP WITH TIME ZONE;
  END IF;
END$$$bootstrap_sql_c9b12f9c7965$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9b12f9c7965$;

DO $bootstrap_do_995740fb36df$
BEGIN
  EXECUTE $bootstrap_sql_995740fb36df$-- Drop and recreate function
DROP FUNCTION IF EXISTS public.is_chat_participant(uuid, uuid, text) CASCADE$bootstrap_sql_995740fb36df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_995740fb36df$;

DO $bootstrap_do_228d91b8761b$
BEGIN
  EXECUTE $bootstrap_sql_228d91b8761b$CREATE OR REPLACE FUNCTION public.is_chat_participant(user_uuid UUID, p_order_id UUID, p_chat_type TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_chat_type = 'buyer_merchant' THEN
    RETURN EXISTS (
      SELECT 1 FROM orders o
      LEFT JOIN merchants m ON o.merchant_id = m.id
      WHERE o.id = p_order_id AND (o.buyer_id = user_uuid OR m.user_id = user_uuid)
    );
  ELSIF p_chat_type = 'buyer_courier' THEN
    RETURN EXISTS (
      SELECT 1 FROM orders o
      LEFT JOIN couriers c ON o.courier_id = c.id
      WHERE o.id = p_order_id AND (o.buyer_id = user_uuid OR c.user_id = user_uuid)
    );
  ELSIF p_chat_type = 'merchant_courier' THEN
    RETURN EXISTS (
      SELECT 1 FROM orders o
      LEFT JOIN merchants m ON o.merchant_id = m.id
      LEFT JOIN couriers c ON o.courier_id = c.id
      WHERE o.id = p_order_id AND (m.user_id = user_uuid OR c.user_id = user_uuid)
    );
  END IF;
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_228d91b8761b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_228d91b8761b$;

DO $bootstrap_do_154218d09d47$
BEGIN
  EXECUTE $bootstrap_sql_154218d09d47$-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_154218d09d47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_154218d09d47$;

DO $bootstrap_do_b536243c2ab9$
BEGIN
  EXECUTE $bootstrap_sql_b536243c2ab9$DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_b536243c2ab9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b536243c2ab9$;

DO $bootstrap_do_723b5d8f3d01$
BEGIN
  EXECUTE $bootstrap_sql_723b5d8f3d01$DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages$bootstrap_sql_723b5d8f3d01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_723b5d8f3d01$;

DO $bootstrap_do_21d2ec0d7c65$
BEGIN
  EXECUTE $bootstrap_sql_21d2ec0d7c65$DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages$bootstrap_sql_21d2ec0d7c65$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_21d2ec0d7c65$;

DO $bootstrap_do_abb7d3f08dd0$
BEGIN
  EXECUTE $bootstrap_sql_abb7d3f08dd0$-- Create policies
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_abb7d3f08dd0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_abb7d3f08dd0$;

DO $bootstrap_do_5eb348c8517a$
BEGIN
  EXECUTE $bootstrap_sql_5eb348c8517a$CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR is_chat_participant(auth.uid(), order_id, chat_type))$bootstrap_sql_5eb348c8517a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5eb348c8517a$;

DO $bootstrap_do_4368c7cb5589$
BEGIN
  EXECUTE $bootstrap_sql_4368c7cb5589$DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_4368c7cb5589$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4368c7cb5589$;

DO $bootstrap_do_f80aca2c1f40$
BEGIN
  EXECUTE $bootstrap_sql_f80aca2c1f40$CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id AND is_chat_participant(auth.uid(), order_id, chat_type))$bootstrap_sql_f80aca2c1f40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f80aca2c1f40$;

DO $bootstrap_do_54faca77db09$
BEGIN
  EXECUTE $bootstrap_sql_54faca77db09$DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages$bootstrap_sql_54faca77db09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54faca77db09$;

DO $bootstrap_do_ade8269d7b32$
BEGIN
  EXECUTE $bootstrap_sql_ade8269d7b32$CREATE POLICY "Users can update own messages read status"
ON public.chat_messages FOR UPDATE
USING (auth.uid() = receiver_id)$bootstrap_sql_ade8269d7b32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ade8269d7b32$;

DO $bootstrap_do_1c6497220cd7$
BEGIN
  EXECUTE $bootstrap_sql_1c6497220cd7$DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages$bootstrap_sql_1c6497220cd7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c6497220cd7$;

DO $bootstrap_do_5eb4d8d95289$
BEGIN
  EXECUTE $bootstrap_sql_5eb4d8d95289$CREATE POLICY "Admins can manage all chat messages"
ON public.chat_messages FOR ALL
USING (is_admin())$bootstrap_sql_5eb4d8d95289$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5eb4d8d95289$;

DO $bootstrap_do_cef8c715d011$
BEGIN
  EXECUTE $bootstrap_sql_cef8c715d011$-- Enable realtime (ignore error if already added)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END$$$bootstrap_sql_cef8c715d011$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cef8c715d011$;

DO $bootstrap_do_ec23981a074e$
BEGIN
  EXECUTE $bootstrap_sql_ec23981a074e$-- Auto-delete trigger
CREATE OR REPLACE FUNCTION public.set_chat_auto_delete()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status NOT IN ('DONE', 'DELIVERED') THEN
    UPDATE chat_messages
    SET auto_delete_at = now() + interval '3 hours'
    WHERE order_id = NEW.id AND auto_delete_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_ec23981a074e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec23981a074e$;

DO $bootstrap_do_c4967a7c7383$
BEGIN
  EXECUTE $bootstrap_sql_c4967a7c7383$DROP TRIGGER IF EXISTS trigger_set_chat_auto_delete ON public.orders$bootstrap_sql_c4967a7c7383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c4967a7c7383$;

DO $bootstrap_do_2b4a15e55e88$
BEGIN
  EXECUTE $bootstrap_sql_2b4a15e55e88$CREATE TRIGGER trigger_set_chat_auto_delete
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_chat_auto_delete()$bootstrap_sql_2b4a15e55e88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b4a15e55e88$;

DO $bootstrap_do_ec4791dfb98a$
BEGIN
  EXECUTE $bootstrap_sql_ec4791dfb98a$-- Cleanup function
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void AS $$
BEGIN
  DELETE FROM chat_messages WHERE auto_delete_at IS NOT NULL AND auto_delete_at <= now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_ec4791dfb98a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec4791dfb98a$;

DO $bootstrap_do_30ee508ed7f9$
BEGIN
  EXECUTE $bootstrap_sql_30ee508ed7f9$
