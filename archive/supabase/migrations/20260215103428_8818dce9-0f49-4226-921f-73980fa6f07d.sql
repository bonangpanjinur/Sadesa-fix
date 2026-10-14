-- Chat messages table
CREATE TABLE public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  receiver_id uuid NOT NULL,
  message text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  auto_delete_at timestamptz
)$bootstrap_sql_94c79a2cfb07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94c79a2cfb07$;

DO $bootstrap_do_d19294240791$
BEGIN
  EXECUTE $bootstrap_sql_d19294240791$-- Index for fast lookups
CREATE INDEX idx_chat_messages_order_id ON public.chat_messages(order_id)$bootstrap_sql_d19294240791$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d19294240791$;

DO $bootstrap_do_db427c090c74$
BEGIN
  EXECUTE $bootstrap_sql_db427c090c74$CREATE INDEX idx_chat_messages_auto_delete ON public.chat_messages(auto_delete_at) WHERE auto_delete_at IS NOT NULL$bootstrap_sql_db427c090c74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db427c090c74$;

DO $bootstrap_do_8d89d927d6bb$
BEGIN
  EXECUTE $bootstrap_sql_8d89d927d6bb$-- Enable RLS
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY$bootstrap_sql_8d89d927d6bb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d89d927d6bb$;

DO $bootstrap_do_4fe5ca19c511$
BEGIN
  EXECUTE $bootstrap_sql_4fe5ca19c511$-- Policies: only sender/receiver can access
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages$bootstrap_sql_4fe5ca19c511$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fe5ca19c511$;

DO $bootstrap_do_81f74def16ca$
BEGIN
  EXECUTE $bootstrap_sql_81f74def16ca$CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id)$bootstrap_sql_81f74def16ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_81f74def16ca$;

DO $bootstrap_do_4145defedc53$
BEGIN
  EXECUTE $bootstrap_sql_4145defedc53$DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages$bootstrap_sql_4145defedc53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4145defedc53$;

DO $bootstrap_do_627557b499f8$
BEGIN
  EXECUTE $bootstrap_sql_627557b499f8$CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id)$bootstrap_sql_627557b499f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_627557b499f8$;

DO $bootstrap_do_175b29db1c9e$
BEGIN
  EXECUTE $bootstrap_sql_175b29db1c9e$DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages$bootstrap_sql_175b29db1c9e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_175b29db1c9e$;

DO $bootstrap_do_456362b64b2d$
BEGIN
  EXECUTE $bootstrap_sql_456362b64b2d$CREATE POLICY "Users can update own messages read status"
ON public.chat_messages FOR UPDATE
USING (auth.uid() = receiver_id)$bootstrap_sql_456362b64b2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_456362b64b2d$;

DO $bootstrap_do_e804359d0b6f$
BEGIN
  EXECUTE $bootstrap_sql_e804359d0b6f$DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages$bootstrap_sql_e804359d0b6f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e804359d0b6f$;

DO $bootstrap_do_c00891424d78$
BEGIN
  EXECUTE $bootstrap_sql_c00891424d78$CREATE POLICY "Admins can manage all chat messages"
ON public.chat_messages FOR ALL
USING (is_admin())$bootstrap_sql_c00891424d78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c00891424d78$;

DO $bootstrap_do_b712ed0330ae$
BEGIN
  EXECUTE $bootstrap_sql_b712ed0330ae$-- Enable realtime for chat
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_b712ed0330ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b712ed0330ae$;

DO $bootstrap_do_a59aa84176ab$
BEGIN
  EXECUTE $bootstrap_sql_a59aa84176ab$-- Page views tracking table
CREATE TABLE public.page_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  viewer_id uuid,
  page_type text NOT NULL DEFAULT 'product',
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_a59aa84176ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a59aa84176ab$;

DO $bootstrap_do_090edc1c47a2$
BEGIN
  EXECUTE $bootstrap_sql_090edc1c47a2$CREATE INDEX idx_page_views_merchant ON public.page_views(merchant_id, created_at)$bootstrap_sql_090edc1c47a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_090edc1c47a2$;

DO $bootstrap_do_8cfcbbbea3e5$
BEGIN
  EXECUTE $bootstrap_sql_8cfcbbbea3e5$CREATE INDEX idx_page_views_product ON public.page_views(product_id, created_at)$bootstrap_sql_8cfcbbbea3e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cfcbbbea3e5$;

DO $bootstrap_do_4f913195d260$
BEGIN
  EXECUTE $bootstrap_sql_4f913195d260$ALTER TABLE public.page_views ENABLE ROW LEVEL SECURITY$bootstrap_sql_4f913195d260$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f913195d260$;

DO $bootstrap_do_7ef3469a6c69$
BEGIN
  EXECUTE $bootstrap_sql_7ef3469a6c69$-- Anyone can insert page views (anonymous tracking)
DROP POLICY IF EXISTS "Anyone can insert page views" ON public.page_views$bootstrap_sql_7ef3469a6c69$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ef3469a6c69$;

DO $bootstrap_do_01435c742b3d$
BEGIN
  EXECUTE $bootstrap_sql_01435c742b3d$CREATE POLICY "Anyone can insert page views"
ON public.page_views FOR INSERT
WITH CHECK (true)$bootstrap_sql_01435c742b3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01435c742b3d$;

DO $bootstrap_do_2cc372eb6428$
BEGIN
  EXECUTE $bootstrap_sql_2cc372eb6428$-- Merchants can view their own page views
DROP POLICY IF EXISTS "Merchants can view own page views" ON public.page_views$bootstrap_sql_2cc372eb6428$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2cc372eb6428$;

DO $bootstrap_do_7b1d25885b4c$
BEGIN
  EXECUTE $bootstrap_sql_7b1d25885b4c$CREATE POLICY "Merchants can view own page views"
ON public.page_views FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = page_views.merchant_id
    AND merchants.user_id = auth.uid()
  )
  OR is_admin()
)$bootstrap_sql_7b1d25885b4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b1d25885b4c$;

DO $bootstrap_do_189f16b7b05b$
BEGIN
  EXECUTE $bootstrap_sql_189f16b7b05b$-- Function to set auto_delete_at when order is completed
CREATE OR REPLACE FUNCTION public.set_chat_auto_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status NOT IN ('DONE', 'DELIVERED') THEN
    UPDATE chat_messages
    SET auto_delete_at = now() + interval '3 hours'
    WHERE order_id = NEW.id AND auto_delete_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_189f16b7b05b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_189f16b7b05b$;

DO $bootstrap_do_5846fa9adfac$
BEGIN
  EXECUTE $bootstrap_sql_5846fa9adfac$DROP TRIGGER IF EXISTS trigger_set_chat_auto_delete ON public.orders$bootstrap_sql_5846fa9adfac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5846fa9adfac$;

DO $bootstrap_do_b60779126ecc$
BEGIN
  EXECUTE $bootstrap_sql_b60779126ecc$CREATE TRIGGER trigger_set_chat_auto_delete
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.set_chat_auto_delete()$bootstrap_sql_b60779126ecc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b60779126ecc$;

DO $bootstrap_do_d1c2b0014c94$
BEGIN
  EXECUTE $bootstrap_sql_d1c2b0014c94$-- Function to clean up expired chat messages (called by cron)
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM chat_messages WHERE auto_delete_at IS NOT NULL AND auto_delete_at <= now();
END;
$$$bootstrap_sql_d1c2b0014c94$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d1c2b0014c94$;

DO $bootstrap_do_4df7a459726a$
BEGIN
  EXECUTE $bootstrap_sql_4df7a459726a$
