-- Phase 6: Integrasi Marketplace & API Publik
-- Run this in Supabase Dashboard → SQL Editor

-- ============================================================
-- TABEL SINKRONISASI PRODUK POS ↔ MARKETPLACE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_marketplace_sync (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  pos_product_id UUID NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  marketplace_product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  -- pending, synced, error, unlinked
  sync_direction TEXT NOT NULL DEFAULT 'pos_to_market',
  -- pos_to_market, market_to_pos, both
  last_synced_at TIMESTAMP WITH TIME ZONE,
  sync_stock BOOLEAN NOT NULL DEFAULT true,
  sync_price BOOLEAN NOT NULL DEFAULT true,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, pos_product_id)
)$bootstrap_sql_8ef9eaa9331c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ef9eaa9331c$;

DO $bootstrap_do_66c275cd3922$
BEGIN
  EXECUTE $bootstrap_sql_66c275cd3922$CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_tenant ON public.pos_marketplace_sync(tenant_id)$bootstrap_sql_66c275cd3922$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66c275cd3922$;

DO $bootstrap_do_5e60c2b19a5f$
BEGIN
  EXECUTE $bootstrap_sql_5e60c2b19a5f$CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_status ON public.pos_marketplace_sync(tenant_id, sync_status)$bootstrap_sql_5e60c2b19a5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e60c2b19a5f$;

DO $bootstrap_do_ebe42367d349$
BEGIN
  EXECUTE $bootstrap_sql_ebe42367d349$ALTER TABLE public.pos_marketplace_sync ENABLE ROW LEVEL SECURITY$bootstrap_sql_ebe42367d349$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ebe42367d349$;

DO $bootstrap_do_fd766274a125$
BEGIN
  EXECUTE $bootstrap_sql_fd766274a125$DROP POLICY IF EXISTS "pos_marketplace_sync_access" ON public.pos_marketplace_sync$bootstrap_sql_fd766274a125$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd766274a125$;

DO $bootstrap_do_eddb85e8dfa8$
BEGIN
  EXECUTE $bootstrap_sql_eddb85e8dfa8$CREATE POLICY "pos_marketplace_sync_access" ON public.pos_marketplace_sync
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_eddb85e8dfa8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eddb85e8dfa8$;

DO $bootstrap_do_d825448ae461$
BEGIN
  EXECUTE $bootstrap_sql_d825448ae461$-- ============================================================
-- TABEL LOG SINKRONISASI
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_sync_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  sync_type TEXT NOT NULL,
  -- product_sync, stock_sync, order_import, price_sync
  status TEXT NOT NULL DEFAULT 'success',
  items_processed INTEGER DEFAULT 0,
  items_success INTEGER DEFAULT 0,
  items_failed INTEGER DEFAULT 0,
  error_details JSONB,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  finished_at TIMESTAMP WITH TIME ZONE
)$bootstrap_sql_d825448ae461$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d825448ae461$;

DO $bootstrap_do_84044b218e44$
BEGIN
  EXECUTE $bootstrap_sql_84044b218e44$ALTER TABLE public.pos_sync_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_84044b218e44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_84044b218e44$;

DO $bootstrap_do_0eab800ab38c$
BEGIN
  EXECUTE $bootstrap_sql_0eab800ab38c$DROP POLICY IF EXISTS "pos_sync_logs_access" ON public.pos_sync_logs$bootstrap_sql_0eab800ab38c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0eab800ab38c$;

DO $bootstrap_do_22a0535ddc43$
BEGIN
  EXECUTE $bootstrap_sql_22a0535ddc43$CREATE POLICY "pos_sync_logs_access" ON public.pos_sync_logs
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_22a0535ddc43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22a0535ddc43$;

DO $bootstrap_do_4c52299d7b25$
BEGIN
  EXECUTE $bootstrap_sql_4c52299d7b25$-- ============================================================
-- TABEL ORDER MARKETPLACE YANG MASUK KE POS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_marketplace_orders (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  outlet_id UUID,
  marketplace_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  pos_sale_id UUID,
  order_number TEXT NOT NULL,
  customer_name TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  subtotal NUMERIC NOT NULL DEFAULT 0,
  shipping_cost NUMERIC NOT NULL DEFAULT 0,
  discount NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0,
  payment_method TEXT DEFAULT 'marketplace',
  status TEXT NOT NULL DEFAULT 'pending',
  -- pending, processed, completed, cancelled
  items JSONB NOT NULL DEFAULT '[]',
  notes TEXT,
  imported_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_4c52299d7b25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c52299d7b25$;

DO $bootstrap_do_021be72f3202$
BEGIN
  EXECUTE $bootstrap_sql_021be72f3202$CREATE INDEX IF NOT EXISTS idx_pos_marketplace_orders_tenant ON public.pos_marketplace_orders(tenant_id)$bootstrap_sql_021be72f3202$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_021be72f3202$;

DO $bootstrap_do_3813968f3ef3$
BEGIN
  EXECUTE $bootstrap_sql_3813968f3ef3$CREATE INDEX IF NOT EXISTS idx_pos_marketplace_orders_status ON public.pos_marketplace_orders(tenant_id, status)$bootstrap_sql_3813968f3ef3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3813968f3ef3$;

DO $bootstrap_do_2e9b0acd98ed$
BEGIN
  EXECUTE $bootstrap_sql_2e9b0acd98ed$ALTER TABLE public.pos_marketplace_orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_2e9b0acd98ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e9b0acd98ed$;

DO $bootstrap_do_c172a1bc2bf6$
BEGIN
  EXECUTE $bootstrap_sql_c172a1bc2bf6$DROP POLICY IF EXISTS "pos_marketplace_orders_access" ON public.pos_marketplace_orders$bootstrap_sql_c172a1bc2bf6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c172a1bc2bf6$;

DO $bootstrap_do_f635786dfc39$
BEGIN
  EXECUTE $bootstrap_sql_f635786dfc39$CREATE POLICY "pos_marketplace_orders_access" ON public.pos_marketplace_orders
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_f635786dfc39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f635786dfc39$;

DO $bootstrap_do_d6091f4615a8$
BEGIN
  EXECUTE $bootstrap_sql_d6091f4615a8$-- ============================================================
-- TABEL PENGATURAN INTEGRASI
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_integration_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL UNIQUE,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
  auto_import_orders BOOLEAN NOT NULL DEFAULT false,
  auto_sync_stock BOOLEAN NOT NULL DEFAULT false,
  auto_sync_price BOOLEAN NOT NULL DEFAULT false,
  sync_interval_minutes INTEGER NOT NULL DEFAULT 60,
  webhook_secret TEXT,
  api_key TEXT,
  is_connected BOOLEAN NOT NULL DEFAULT false,
  last_sync_at TIMESTAMP WITH TIME ZONE,
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_d6091f4615a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6091f4615a8$;

DO $bootstrap_do_14e569cbc6a7$
BEGIN
  EXECUTE $bootstrap_sql_14e569cbc6a7$ALTER TABLE public.pos_integration_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_14e569cbc6a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14e569cbc6a7$;

DO $bootstrap_do_479dcf51b1f4$
BEGIN
  EXECUTE $bootstrap_sql_479dcf51b1f4$DROP POLICY IF EXISTS "pos_integration_settings_access" ON public.pos_integration_settings$bootstrap_sql_479dcf51b1f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_479dcf51b1f4$;

DO $bootstrap_do_bf4d80355f45$
BEGIN
  EXECUTE $bootstrap_sql_bf4d80355f45$CREATE POLICY "pos_integration_settings_access" ON public.pos_integration_settings
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_bf4d80355f45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf4d80355f45$;

DO $bootstrap_do_50b10ca73a91$
BEGIN
  EXECUTE $bootstrap_sql_50b10ca73a91$
