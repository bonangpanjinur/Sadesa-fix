-- Drop function with cascade (will also drop dependent policies)
DROP FUNCTION IF EXISTS public.is_chat_participant(uuid, uuid, text) CASCADE$bootstrap_sql_157eec0b55be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_157eec0b55be$;

DO $bootstrap_do_177168b65e7b$
BEGIN
  EXECUTE $bootstrap_sql_177168b65e7b$-- Recreate function
CREATE OR REPLACE FUNCTION public.is_chat_participant(user_uuid UUID, p_order_id UUID, p_chat_type TEXT)
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_177168b65e7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_177168b65e7b$;

DO $bootstrap_do_7e7158ce6392$
BEGIN
  EXECUTE $bootstrap_sql_7e7158ce6392$-- Recreate the policies that were dropped by CASCADE
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_7e7158ce6392$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e7158ce6392$;

DO $bootstrap_do_d330a6e41497$
BEGIN
  EXECUTE $bootstrap_sql_d330a6e41497$CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR is_chat_participant(auth.uid(), order_id, chat_type))$bootstrap_sql_d330a6e41497$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d330a6e41497$;

DO $bootstrap_do_2c7585d6cbd0$
BEGIN
  EXECUTE $bootstrap_sql_2c7585d6cbd0$DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_2c7585d6cbd0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c7585d6cbd0$;

DO $bootstrap_do_2dcbc59369e6$
BEGIN
  EXECUTE $bootstrap_sql_2dcbc59369e6$CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id AND is_chat_participant(auth.uid(), order_id, chat_type))$bootstrap_sql_2dcbc59369e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dcbc59369e6$;

DO $bootstrap_do_db5833b88f8a$
BEGIN
  EXECUTE $bootstrap_sql_db5833b88f8a$
