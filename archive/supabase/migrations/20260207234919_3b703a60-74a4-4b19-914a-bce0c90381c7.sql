-- Create quota_usage_logs table for tracking per-order quota usage
CREATE TABLE IF NOT EXISTS public.quota_usage_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  subscription_id UUID REFERENCES public.merchant_subscriptions(id) ON DELETE SET NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  order_total NUMERIC NOT NULL DEFAULT 0,
  credits_used INTEGER NOT NULL DEFAULT 1,
  remaining_quota INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_05868736d28a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05868736d28a$;

DO $bootstrap_do_81a00507c5b3$
BEGIN
  EXECUTE $bootstrap_sql_81a00507c5b3$-- Enable RLS
ALTER TABLE public.quota_usage_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_81a00507c5b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_81a00507c5b3$;

DO $bootstrap_do_54612656b4de$
BEGIN
  EXECUTE $bootstrap_sql_54612656b4de$-- Policies are recreated safely when a bootstrap is retried.
DROP POLICY IF EXISTS "Admin can view all quota logs" ON public.quota_usage_logs$bootstrap_sql_54612656b4de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54612656b4de$;

DO $bootstrap_do_fc52e2fb6399$
BEGIN
  EXECUTE $bootstrap_sql_fc52e2fb6399$CREATE POLICY "Admin can view all quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_fc52e2fb6399$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc52e2fb6399$;

DO $bootstrap_do_3e56c20f9ed8$
BEGIN
  EXECUTE $bootstrap_sql_3e56c20f9ed8$DROP POLICY IF EXISTS "Merchant can view own quota logs" ON public.quota_usage_logs$bootstrap_sql_3e56c20f9ed8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e56c20f9ed8$;

DO $bootstrap_do_15e519fa80fb$
BEGIN
  EXECUTE $bootstrap_sql_15e519fa80fb$CREATE POLICY "Merchant can view own quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  )$bootstrap_sql_15e519fa80fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15e519fa80fb$;

DO $bootstrap_do_8b26f2c711d1$
BEGIN
  EXECUTE $bootstrap_sql_8b26f2c711d1$DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs$bootstrap_sql_8b26f2c711d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b26f2c711d1$;

DO $bootstrap_do_b8e896ed5ba4$
BEGIN
  EXECUTE $bootstrap_sql_b8e896ed5ba4$CREATE POLICY "System can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (true)$bootstrap_sql_b8e896ed5ba4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b8e896ed5ba4$;

DO $bootstrap_do_5dd8042e897f$
BEGIN
  EXECUTE $bootstrap_sql_5dd8042e897f$-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_merchant ON public.quota_usage_logs(merchant_id)$bootstrap_sql_5dd8042e897f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5dd8042e897f$;

DO $bootstrap_do_ca0b04963cf7$
BEGIN
  EXECUTE $bootstrap_sql_ca0b04963cf7$CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_order ON public.quota_usage_logs(order_id)$bootstrap_sql_ca0b04963cf7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca0b04963cf7$;

DO $bootstrap_do_a17d728572d0$
BEGIN
  EXECUTE $bootstrap_sql_a17d728572d0$CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_created ON public.quota_usage_logs(created_at DESC)$bootstrap_sql_a17d728572d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a17d728572d0$;

DO $bootstrap_do_70dc87a3c5ca$
BEGIN
  EXECUTE $bootstrap_sql_70dc87a3c5ca$-- Enable realtime only when the table is not already a member.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'quota_usage_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.quota_usage_logs;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_70dc87a3c5ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70dc87a3c5ca$;

DO $bootstrap_do_feb66cbc3b00$
BEGIN
  EXECUTE $bootstrap_sql_feb66cbc3b00$
