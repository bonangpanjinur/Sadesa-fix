-- Courier deposits table
CREATE TABLE public.courier_deposits (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  proof_url TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  approved_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE
)$bootstrap_sql_c04afc15f93e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c04afc15f93e$;

DO $bootstrap_do_82969dab5049$
BEGIN
  EXECUTE $bootstrap_sql_82969dab5049$ALTER TABLE public.courier_deposits ENABLE ROW LEVEL SECURITY$bootstrap_sql_82969dab5049$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82969dab5049$;

DO $bootstrap_do_60cb984702a0$
BEGIN
  EXECUTE $bootstrap_sql_60cb984702a0$DROP POLICY IF EXISTS "Couriers can create own deposits" ON public.courier_deposits$bootstrap_sql_60cb984702a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60cb984702a0$;

DO $bootstrap_do_e984d0af5adc$
BEGIN
  EXECUTE $bootstrap_sql_e984d0af5adc$CREATE POLICY "Couriers can create own deposits" ON public.courier_deposits
  FOR INSERT WITH CHECK (courier_id = get_user_courier_id())$bootstrap_sql_e984d0af5adc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e984d0af5adc$;

DO $bootstrap_do_e9536d78d1b3$
BEGIN
  EXECUTE $bootstrap_sql_e9536d78d1b3$DROP POLICY IF EXISTS "Couriers can view own deposits" ON public.courier_deposits$bootstrap_sql_e9536d78d1b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e9536d78d1b3$;

DO $bootstrap_do_d3caa5588776$
BEGIN
  EXECUTE $bootstrap_sql_d3caa5588776$CREATE POLICY "Couriers can view own deposits" ON public.courier_deposits
  FOR SELECT USING (courier_id = get_user_courier_id())$bootstrap_sql_d3caa5588776$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3caa5588776$;

DO $bootstrap_do_6a9756445159$
BEGIN
  EXECUTE $bootstrap_sql_6a9756445159$DROP POLICY IF EXISTS "Admins full access courier deposits" ON public.courier_deposits$bootstrap_sql_6a9756445159$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a9756445159$;

DO $bootstrap_do_5c7723c0fc79$
BEGIN
  EXECUTE $bootstrap_sql_5c7723c0fc79$CREATE POLICY "Admins full access courier deposits" ON public.courier_deposits
  FOR ALL USING (is_admin())$bootstrap_sql_5c7723c0fc79$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c7723c0fc79$;

DO $bootstrap_do_8c069efbd201$
BEGIN
  EXECUTE $bootstrap_sql_8c069efbd201$-- Courier balance logs table
CREATE TABLE public.courier_balance_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id),
  type TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  balance_before NUMERIC NOT NULL DEFAULT 0,
  balance_after NUMERIC NOT NULL DEFAULT 0,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_8c069efbd201$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c069efbd201$;

DO $bootstrap_do_9a4227229c1b$
BEGIN
  EXECUTE $bootstrap_sql_9a4227229c1b$ALTER TABLE public.courier_balance_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_9a4227229c1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a4227229c1b$;

DO $bootstrap_do_b9a35144f280$
BEGIN
  EXECUTE $bootstrap_sql_b9a35144f280$DROP POLICY IF EXISTS "Couriers can view own balance logs" ON public.courier_balance_logs$bootstrap_sql_b9a35144f280$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9a35144f280$;

DO $bootstrap_do_42111be0bac9$
BEGIN
  EXECUTE $bootstrap_sql_42111be0bac9$CREATE POLICY "Couriers can view own balance logs" ON public.courier_balance_logs
  FOR SELECT USING (courier_id = get_user_courier_id())$bootstrap_sql_42111be0bac9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42111be0bac9$;

DO $bootstrap_do_aa5fccb46106$
BEGIN
  EXECUTE $bootstrap_sql_aa5fccb46106$DROP POLICY IF EXISTS "Admins full access balance logs" ON public.courier_balance_logs$bootstrap_sql_aa5fccb46106$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa5fccb46106$;

DO $bootstrap_do_3ddeb10a0273$
BEGIN
  EXECUTE $bootstrap_sql_3ddeb10a0273$CREATE POLICY "Admins full access balance logs" ON public.courier_balance_logs
  FOR ALL USING (is_admin())$bootstrap_sql_3ddeb10a0273$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ddeb10a0273$;

DO $bootstrap_do_7cdcd3090171$
BEGIN
  EXECUTE $bootstrap_sql_7cdcd3090171$-- Insert courier minimum balance setting
INSERT INTO public.app_settings (key, category, value, description)
VALUES ('courier_minimum_balance', 'courier', '{"amount": 50000}', 'Saldo minimum yang harus tersisa saat kurir melakukan penarikan')
ON CONFLICT (key) DO NOTHING$bootstrap_sql_7cdcd3090171$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cdcd3090171$;

DO $bootstrap_do_aa13aab1ad0a$
BEGIN
  EXECUTE $bootstrap_sql_aa13aab1ad0a$-- Enable realtime for balance logs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'courier_deposits'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_deposits;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_aa13aab1ad0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa13aab1ad0a$;

DO $bootstrap_do_c5f72963b75d$
BEGIN
  EXECUTE $bootstrap_sql_c5f72963b75d$DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'courier_balance_logs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_balance_logs;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_c5f72963b75d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5f72963b75d$;

DO $bootstrap_do_870015384dc4$
BEGIN
  EXECUTE $bootstrap_sql_870015384dc4$
