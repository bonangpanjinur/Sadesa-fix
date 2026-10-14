-- =====================================================
-- 1. FIX RLS POLICIES FOR user_roles TABLE
-- =====================================================
-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles$bootstrap_sql_0d32db806c3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d32db806c3c$;

DO $bootstrap_do_3991f40591bf$
BEGIN
  EXECUTE $bootstrap_sql_3991f40591bf$DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles$bootstrap_sql_3991f40591bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3991f40591bf$;

DO $bootstrap_do_ed1c0821c321$
BEGIN
  EXECUTE $bootstrap_sql_ed1c0821c321$DROP POLICY IF EXISTS "Admins can manage user roles" ON public.user_roles$bootstrap_sql_ed1c0821c321$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed1c0821c321$;

DO $bootstrap_do_b332c5cb98c0$
BEGIN
  EXECUTE $bootstrap_sql_b332c5cb98c0$DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles$bootstrap_sql_b332c5cb98c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b332c5cb98c0$;

DO $bootstrap_do_4d634c11e13f$
BEGIN
  EXECUTE $bootstrap_sql_4d634c11e13f$DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles$bootstrap_sql_4d634c11e13f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d634c11e13f$;

DO $bootstrap_do_c94e8878380b$
BEGIN
  EXECUTE $bootstrap_sql_c94e8878380b$DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles$bootstrap_sql_c94e8878380b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c94e8878380b$;

DO $bootstrap_do_5ea43c0283e0$
BEGIN
  EXECUTE $bootstrap_sql_5ea43c0283e0$-- Recreate complete policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles$bootstrap_sql_5ea43c0283e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ea43c0283e0$;

DO $bootstrap_do_e799fcd95a56$
BEGIN
  EXECUTE $bootstrap_sql_e799fcd95a56$CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_e799fcd95a56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e799fcd95a56$;

DO $bootstrap_do_b29e64521784$
BEGIN
  EXECUTE $bootstrap_sql_b29e64521784$DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles$bootstrap_sql_b29e64521784$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b29e64521784$;

DO $bootstrap_do_fc16711ae0df$
BEGIN
  EXECUTE $bootstrap_sql_fc16711ae0df$CREATE POLICY "Admins can view all roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (is_admin())$bootstrap_sql_fc16711ae0df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc16711ae0df$;

DO $bootstrap_do_2bd83e5d9ad2$
BEGIN
  EXECUTE $bootstrap_sql_2bd83e5d9ad2$DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles$bootstrap_sql_2bd83e5d9ad2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bd83e5d9ad2$;

DO $bootstrap_do_e9c1f6b6355a$
BEGIN
  EXECUTE $bootstrap_sql_e9c1f6b6355a$CREATE POLICY "Admins can insert user roles"
  ON public.user_roles FOR INSERT
  TO authenticated
  WITH CHECK (is_admin())$bootstrap_sql_e9c1f6b6355a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e9c1f6b6355a$;

DO $bootstrap_do_5c135d1d4d04$
BEGIN
  EXECUTE $bootstrap_sql_5c135d1d4d04$DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles$bootstrap_sql_5c135d1d4d04$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c135d1d4d04$;

DO $bootstrap_do_940f99ca213e$
BEGIN
  EXECUTE $bootstrap_sql_940f99ca213e$CREATE POLICY "Admins can update user roles"
  ON public.user_roles FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin())$bootstrap_sql_940f99ca213e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_940f99ca213e$;

DO $bootstrap_do_4e7128d36c3e$
BEGIN
  EXECUTE $bootstrap_sql_4e7128d36c3e$DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles$bootstrap_sql_4e7128d36c3e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e7128d36c3e$;

DO $bootstrap_do_0ad5abbcd40f$
BEGIN
  EXECUTE $bootstrap_sql_0ad5abbcd40f$CREATE POLICY "Admins can delete user roles"
  ON public.user_roles FOR DELETE
  TO authenticated
  USING (is_admin())$bootstrap_sql_0ad5abbcd40f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ad5abbcd40f$;

DO $bootstrap_do_11d249aab0d8$
BEGIN
  EXECUTE $bootstrap_sql_11d249aab0d8$-- =====================================================
-- 2. POS (KASIR) SYSTEM TABLES
-- =====================================================

-- POS Packages (admin configures pricing)
CREATE TABLE IF NOT EXISTS public.pos_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  duration_months INTEGER NOT NULL DEFAULT 1,
  price INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_11d249aab0d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11d249aab0d8$;

DO $bootstrap_do_07a57aaf5bdc$
BEGIN
  EXECUTE $bootstrap_sql_07a57aaf5bdc$ALTER TABLE public.pos_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_07a57aaf5bdc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07a57aaf5bdc$;

DO $bootstrap_do_9c594c8b850a$
BEGIN
  EXECUTE $bootstrap_sql_9c594c8b850a$DROP POLICY IF EXISTS "Anyone can view active POS packages" ON public.pos_packages$bootstrap_sql_9c594c8b850a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c594c8b850a$;

DO $bootstrap_do_10543a366652$
BEGIN
  EXECUTE $bootstrap_sql_10543a366652$CREATE POLICY "Anyone can view active POS packages"
  ON public.pos_packages FOR SELECT
  USING (is_active = true)$bootstrap_sql_10543a366652$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10543a366652$;

DO $bootstrap_do_9be15471f1c5$
BEGIN
  EXECUTE $bootstrap_sql_9be15471f1c5$DROP POLICY IF EXISTS "Admins can manage POS packages" ON public.pos_packages$bootstrap_sql_9be15471f1c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9be15471f1c5$;

DO $bootstrap_do_88558320f44f$
BEGIN
  EXECUTE $bootstrap_sql_88558320f44f$CREATE POLICY "Admins can manage POS packages"
  ON public.pos_packages FOR ALL
  USING (is_admin())$bootstrap_sql_88558320f44f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88558320f44f$;

DO $bootstrap_do_1f6d83abd4e7$
BEGIN
  EXECUTE $bootstrap_sql_1f6d83abd4e7$-- POS Subscriptions (merchant subscriptions for POS feature)
CREATE TABLE IF NOT EXISTS public.pos_subscriptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id),
  package_id UUID REFERENCES public.pos_packages(id),
  status TEXT NOT NULL DEFAULT 'PENDING',
  payment_amount INTEGER NOT NULL DEFAULT 0,
  payment_proof_url TEXT,
  payment_status TEXT NOT NULL DEFAULT 'UNPAID',
  started_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  rejection_reason TEXT,
  is_trial BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_1f6d83abd4e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f6d83abd4e7$;

DO $bootstrap_do_7a8f41bf6f27$
BEGIN
  EXECUTE $bootstrap_sql_7a8f41bf6f27$ALTER TABLE public.pos_subscriptions ENABLE ROW LEVEL SECURITY$bootstrap_sql_7a8f41bf6f27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7a8f41bf6f27$;

DO $bootstrap_do_7e60eb4b4c7c$
BEGIN
  EXECUTE $bootstrap_sql_7e60eb4b4c7c$DROP POLICY IF EXISTS "Merchants can view own POS subscriptions" ON public.pos_subscriptions$bootstrap_sql_7e60eb4b4c7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e60eb4b4c7c$;

DO $bootstrap_do_5cb6856c51eb$
BEGIN
  EXECUTE $bootstrap_sql_5cb6856c51eb$CREATE POLICY "Merchants can view own POS subscriptions"
  ON public.pos_subscriptions FOR SELECT
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_5cb6856c51eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5cb6856c51eb$;

DO $bootstrap_do_b65af0c56021$
BEGIN
  EXECUTE $bootstrap_sql_b65af0c56021$DROP POLICY IF EXISTS "Merchants can create POS subscriptions" ON public.pos_subscriptions$bootstrap_sql_b65af0c56021$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b65af0c56021$;

DO $bootstrap_do_281eb945cae1$
BEGIN
  EXECUTE $bootstrap_sql_281eb945cae1$CREATE POLICY "Merchants can create POS subscriptions"
  ON public.pos_subscriptions FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_281eb945cae1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_281eb945cae1$;

DO $bootstrap_do_f2711e7945d1$
BEGIN
  EXECUTE $bootstrap_sql_f2711e7945d1$DROP POLICY IF EXISTS "Merchants can update own POS subscriptions" ON public.pos_subscriptions$bootstrap_sql_f2711e7945d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2711e7945d1$;

DO $bootstrap_do_d9fc7295fbef$
BEGIN
  EXECUTE $bootstrap_sql_d9fc7295fbef$CREATE POLICY "Merchants can update own POS subscriptions"
  ON public.pos_subscriptions FOR UPDATE
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_d9fc7295fbef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9fc7295fbef$;

DO $bootstrap_do_b0e470b837ea$
BEGIN
  EXECUTE $bootstrap_sql_b0e470b837ea$DROP POLICY IF EXISTS "Admins can manage all POS subscriptions" ON public.pos_subscriptions$bootstrap_sql_b0e470b837ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0e470b837ea$;

DO $bootstrap_do_f71496b8b188$
BEGIN
  EXECUTE $bootstrap_sql_f71496b8b188$CREATE POLICY "Admins can manage all POS subscriptions"
  ON public.pos_subscriptions FOR ALL
  USING (is_admin())$bootstrap_sql_f71496b8b188$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f71496b8b188$;

DO $bootstrap_do_c18230e260a4$
BEGIN
  EXECUTE $bootstrap_sql_c18230e260a4$-- POS Transactions (cashier transactions)
CREATE TABLE IF NOT EXISTS public.pos_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id),
  transaction_number TEXT NOT NULL,
  customer_name TEXT,
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  subtotal INTEGER NOT NULL DEFAULT 0,
  discount INTEGER NOT NULL DEFAULT 0,
  tax INTEGER NOT NULL DEFAULT 0,
  total INTEGER NOT NULL DEFAULT 0,
  payment_method TEXT NOT NULL DEFAULT 'CASH',
  payment_amount INTEGER NOT NULL DEFAULT 0,
  change_amount INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  cashier_name TEXT,
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_c18230e260a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c18230e260a4$;

DO $bootstrap_do_dfb2a15fcc26$
BEGIN
  EXECUTE $bootstrap_sql_dfb2a15fcc26$ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY$bootstrap_sql_dfb2a15fcc26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dfb2a15fcc26$;

DO $bootstrap_do_d7f620139b69$
BEGIN
  EXECUTE $bootstrap_sql_d7f620139b69$DROP POLICY IF EXISTS "Merchants can manage own POS transactions" ON public.pos_transactions$bootstrap_sql_d7f620139b69$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7f620139b69$;

DO $bootstrap_do_7c1a7bf6f843$
BEGIN
  EXECUTE $bootstrap_sql_7c1a7bf6f843$CREATE POLICY "Merchants can manage own POS transactions"
  ON public.pos_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_transactions.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_7c1a7bf6f843$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c1a7bf6f843$;

DO $bootstrap_do_f2bc902e385a$
BEGIN
  EXECUTE $bootstrap_sql_f2bc902e385a$DROP POLICY IF EXISTS "Admins can view all POS transactions" ON public.pos_transactions$bootstrap_sql_f2bc902e385a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2bc902e385a$;

DO $bootstrap_do_b7e72361dadf$
BEGIN
  EXECUTE $bootstrap_sql_b7e72361dadf$CREATE POLICY "Admins can view all POS transactions"
  ON public.pos_transactions FOR SELECT
  USING (is_admin())$bootstrap_sql_b7e72361dadf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b7e72361dadf$;

DO $bootstrap_do_a9aa020b5257$
BEGIN
  EXECUTE $bootstrap_sql_a9aa020b5257$-- POS Settings per merchant (invoice design, etc.)
CREATE TABLE IF NOT EXISTS public.pos_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL UNIQUE REFERENCES public.merchants(id),
  invoice_header TEXT,
  invoice_footer TEXT,
  show_logo BOOLEAN NOT NULL DEFAULT true,
  show_address BOOLEAN NOT NULL DEFAULT true,
  show_phone BOOLEAN NOT NULL DEFAULT true,
  paper_size TEXT NOT NULL DEFAULT '58mm',
  font_size TEXT NOT NULL DEFAULT 'normal',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_a9aa020b5257$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9aa020b5257$;

DO $bootstrap_do_4f5dfe581dfc$
BEGIN
  EXECUTE $bootstrap_sql_4f5dfe581dfc$ALTER TABLE public.pos_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_4f5dfe581dfc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f5dfe581dfc$;

DO $bootstrap_do_36fef2777fa0$
BEGIN
  EXECUTE $bootstrap_sql_36fef2777fa0$DROP POLICY IF EXISTS "Merchants can manage own POS settings" ON public.pos_settings$bootstrap_sql_36fef2777fa0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36fef2777fa0$;

DO $bootstrap_do_ce175d11675d$
BEGIN
  EXECUTE $bootstrap_sql_ce175d11675d$CREATE POLICY "Merchants can manage own POS settings"
  ON public.pos_settings FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_settings.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_ce175d11675d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce175d11675d$;

DO $bootstrap_do_eff04da01696$
BEGIN
  EXECUTE $bootstrap_sql_eff04da01696$DROP POLICY IF EXISTS "Admins can manage all POS settings" ON public.pos_settings$bootstrap_sql_eff04da01696$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eff04da01696$;

DO $bootstrap_do_ed32373fedf9$
BEGIN
  EXECUTE $bootstrap_sql_ed32373fedf9$CREATE POLICY "Admins can manage all POS settings"
  ON public.pos_settings FOR ALL
  USING (is_admin())$bootstrap_sql_ed32373fedf9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed32373fedf9$;

DO $bootstrap_do_ba7483dae138$
BEGIN
  EXECUTE $bootstrap_sql_ba7483dae138$-- App setting for POS config (trial days, etc.)
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'pos_config',
  '{"trial_days": 30, "is_enabled": true}'::jsonb,
  'features',
  'Konfigurasi fitur kasir POS'
) ON CONFLICT (key) DO NOTHING$bootstrap_sql_ba7483dae138$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba7483dae138$;

DO $bootstrap_do_a1e9a9fe403b$
BEGIN
  EXECUTE $bootstrap_sql_a1e9a9fe403b$-- Trigger for updated_at
CREATE OR REPLACE TRIGGER update_pos_packages_updated_at
  BEFORE UPDATE ON public.pos_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_a1e9a9fe403b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1e9a9fe403b$;

DO $bootstrap_do_4eef99597ddc$
BEGIN
  EXECUTE $bootstrap_sql_4eef99597ddc$CREATE OR REPLACE TRIGGER update_pos_subscriptions_updated_at
  BEFORE UPDATE ON public.pos_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_4eef99597ddc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4eef99597ddc$;

DO $bootstrap_do_3a61d33f6e37$
BEGIN
  EXECUTE $bootstrap_sql_3a61d33f6e37$CREATE OR REPLACE TRIGGER update_pos_settings_updated_at
  BEFORE UPDATE ON public.pos_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_3a61d33f6e37$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a61d33f6e37$;

DO $bootstrap_do_03a8d66459c8$
BEGIN
  EXECUTE $bootstrap_sql_03a8d66459c8$
