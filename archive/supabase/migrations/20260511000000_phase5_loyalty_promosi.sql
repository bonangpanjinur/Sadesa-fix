-- Phase 5: Loyalty, Promosi & Diskon
-- Run this in Supabase Dashboard → SQL Editor

-- ============================================================
-- TABEL PROMOSI
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  outlet_id UUID,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL DEFAULT 'discount_percent',
  -- types: discount_percent, discount_amount, buy_x_get_y, bundle, happy_hour
  discount_percent NUMERIC DEFAULT 0,
  discount_amount NUMERIC DEFAULT 0,
  min_purchase NUMERIC DEFAULT 0,
  max_discount NUMERIC,
  -- buy_x_get_y config
  buy_qty INTEGER DEFAULT 0,
  get_qty INTEGER DEFAULT 0,
  get_product_id UUID,
  -- bundle: array of product IDs
  bundle_product_ids JSONB DEFAULT '[]',
  bundle_price NUMERIC,
  -- happy_hour
  happy_hour_start TIME,
  happy_hour_end TIME,
  happy_hour_days JSONB DEFAULT '[0,1,2,3,4,5,6]',
  -- scope
  applies_to TEXT NOT NULL DEFAULT 'all',
  -- all, specific_products, specific_categories
  product_ids JSONB DEFAULT '[]',
  category_ids JSONB DEFAULT '[]',
  -- validity
  start_date TIMESTAMP WITH TIME ZONE,
  end_date TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  usage_limit INTEGER,
  used_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_7c2f6a5bde6f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c2f6a5bde6f$;

DO $bootstrap_do_282681d9dd2d$
BEGIN
  EXECUTE $bootstrap_sql_282681d9dd2d$CREATE INDEX IF NOT EXISTS idx_pos_promotions_tenant ON public.pos_promotions(tenant_id)$bootstrap_sql_282681d9dd2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_282681d9dd2d$;

DO $bootstrap_do_c309bdf1c268$
BEGIN
  EXECUTE $bootstrap_sql_c309bdf1c268$CREATE INDEX IF NOT EXISTS idx_pos_promotions_active ON public.pos_promotions(tenant_id, is_active)$bootstrap_sql_c309bdf1c268$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c309bdf1c268$;

DO $bootstrap_do_4f95923cc675$
BEGIN
  EXECUTE $bootstrap_sql_4f95923cc675$ALTER TABLE public.pos_promotions ENABLE ROW LEVEL SECURITY$bootstrap_sql_4f95923cc675$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f95923cc675$;

DO $bootstrap_do_6015cf5af802$
BEGIN
  EXECUTE $bootstrap_sql_6015cf5af802$DROP POLICY IF EXISTS "pos_promotions_tenant_access" ON public.pos_promotions$bootstrap_sql_6015cf5af802$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6015cf5af802$;

DO $bootstrap_do_87a58f272586$
BEGIN
  EXECUTE $bootstrap_sql_87a58f272586$CREATE POLICY "pos_promotions_tenant_access" ON public.pos_promotions
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_87a58f272586$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_87a58f272586$;

DO $bootstrap_do_527f72ac1d8d$
BEGIN
  EXECUTE $bootstrap_sql_527f72ac1d8d$-- ============================================================
-- TABEL VOUCHER / KODE KUPON
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_vouchers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL DEFAULT 'discount_percent',
  -- types: discount_percent, discount_amount, free_shipping
  discount_percent NUMERIC DEFAULT 0,
  discount_amount NUMERIC DEFAULT 0,
  min_purchase NUMERIC DEFAULT 0,
  max_discount NUMERIC,
  start_date TIMESTAMP WITH TIME ZONE,
  end_date TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  usage_limit INTEGER,
  used_count INTEGER NOT NULL DEFAULT 0,
  per_customer_limit INTEGER DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
)$bootstrap_sql_527f72ac1d8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_527f72ac1d8d$;

DO $bootstrap_do_790000e5575e$
BEGIN
  EXECUTE $bootstrap_sql_790000e5575e$CREATE INDEX IF NOT EXISTS idx_pos_vouchers_tenant ON public.pos_vouchers(tenant_id)$bootstrap_sql_790000e5575e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_790000e5575e$;

DO $bootstrap_do_9e2fe670699b$
BEGIN
  EXECUTE $bootstrap_sql_9e2fe670699b$CREATE INDEX IF NOT EXISTS idx_pos_vouchers_code ON public.pos_vouchers(tenant_id, code)$bootstrap_sql_9e2fe670699b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e2fe670699b$;

DO $bootstrap_do_74511fce2ae5$
BEGIN
  EXECUTE $bootstrap_sql_74511fce2ae5$ALTER TABLE public.pos_vouchers ENABLE ROW LEVEL SECURITY$bootstrap_sql_74511fce2ae5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_74511fce2ae5$;

DO $bootstrap_do_7350fc39d020$
BEGIN
  EXECUTE $bootstrap_sql_7350fc39d020$DROP POLICY IF EXISTS "pos_vouchers_tenant_access" ON public.pos_vouchers$bootstrap_sql_7350fc39d020$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7350fc39d020$;

DO $bootstrap_do_600a2f2b30c7$
BEGIN
  EXECUTE $bootstrap_sql_600a2f2b30c7$CREATE POLICY "pos_vouchers_tenant_access" ON public.pos_vouchers
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_600a2f2b30c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_600a2f2b30c7$;

DO $bootstrap_do_2b88549a6996$
BEGIN
  EXECUTE $bootstrap_sql_2b88549a6996$-- ============================================================
-- TABEL RIWAYAT PENGGUNAAN VOUCHER
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_voucher_usages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  voucher_id UUID NOT NULL REFERENCES public.pos_vouchers(id) ON DELETE CASCADE,
  sale_id UUID,
  customer_id UUID,
  customer_name TEXT,
  discount_given NUMERIC NOT NULL DEFAULT 0,
  used_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_2b88549a6996$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b88549a6996$;

DO $bootstrap_do_d03f0ff58649$
BEGIN
  EXECUTE $bootstrap_sql_d03f0ff58649$ALTER TABLE public.pos_voucher_usages ENABLE ROW LEVEL SECURITY$bootstrap_sql_d03f0ff58649$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d03f0ff58649$;

DO $bootstrap_do_fc64c8f9bae2$
BEGIN
  EXECUTE $bootstrap_sql_fc64c8f9bae2$DROP POLICY IF EXISTS "pos_voucher_usages_access" ON public.pos_voucher_usages$bootstrap_sql_fc64c8f9bae2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc64c8f9bae2$;

DO $bootstrap_do_7816184fe299$
BEGIN
  EXECUTE $bootstrap_sql_7816184fe299$CREATE POLICY "pos_voucher_usages_access" ON public.pos_voucher_usages
  USING (voucher_id IN (
    SELECT id FROM public.pos_vouchers
    WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
  ))$bootstrap_sql_7816184fe299$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7816184fe299$;

DO $bootstrap_do_0f18c9020e39$
BEGIN
  EXECUTE $bootstrap_sql_0f18c9020e39$-- ============================================================
-- TABEL PROGRAM POIN LOYALTY
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_loyalty_programs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT 'Program Poin',
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  -- earn: berapa rupiah untuk 1 poin
  earn_per_rupiah INTEGER NOT NULL DEFAULT 10000,
  -- redeem: berapa poin = 1 rupiah
  redeem_rate INTEGER NOT NULL DEFAULT 100,
  min_redeem_points INTEGER NOT NULL DEFAULT 100,
  max_redeem_percent INTEGER NOT NULL DEFAULT 50,
  -- point expiry in days (0 = no expiry)
  point_expiry_days INTEGER NOT NULL DEFAULT 0,
  -- tiers
  tiers JSONB DEFAULT '[
    {"name":"Bronze","min_points":0,"discount_percent":0,"color":"#92400e"},
    {"name":"Silver","min_points":500,"discount_percent":2,"color":"#6b7280"},
    {"name":"Gold","min_points":2000,"discount_percent":5,"color":"#d97706"},
    {"name":"Platinum","min_points":5000,"discount_percent":8,"color":"#7c3aed"}
  ]',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_0f18c9020e39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f18c9020e39$;

DO $bootstrap_do_1c5eefb97196$
BEGIN
  EXECUTE $bootstrap_sql_1c5eefb97196$ALTER TABLE public.pos_loyalty_programs ENABLE ROW LEVEL SECURITY$bootstrap_sql_1c5eefb97196$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c5eefb97196$;

DO $bootstrap_do_9c60fc9e3fa1$
BEGIN
  EXECUTE $bootstrap_sql_9c60fc9e3fa1$DROP POLICY IF EXISTS "pos_loyalty_programs_access" ON public.pos_loyalty_programs$bootstrap_sql_9c60fc9e3fa1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c60fc9e3fa1$;

DO $bootstrap_do_63847f4a9073$
BEGIN
  EXECUTE $bootstrap_sql_63847f4a9073$CREATE POLICY "pos_loyalty_programs_access" ON public.pos_loyalty_programs
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_63847f4a9073$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63847f4a9073$;

DO $bootstrap_do_85be238aba33$
BEGIN
  EXECUTE $bootstrap_sql_85be238aba33$-- ============================================================
-- TABEL POIN PELANGGAN
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_loyalty_points (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  customer_id UUID NOT NULL REFERENCES public.pos_customers(id) ON DELETE CASCADE,
  total_points INTEGER NOT NULL DEFAULT 0,
  used_points INTEGER NOT NULL DEFAULT 0,
  expired_points INTEGER NOT NULL DEFAULT 0,
  tier TEXT NOT NULL DEFAULT 'Bronze',
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, customer_id)
)$bootstrap_sql_85be238aba33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_85be238aba33$;

DO $bootstrap_do_ec3cb926edb7$
BEGIN
  EXECUTE $bootstrap_sql_ec3cb926edb7$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_points_tenant ON public.pos_loyalty_points(tenant_id)$bootstrap_sql_ec3cb926edb7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec3cb926edb7$;

DO $bootstrap_do_f1dd4f41e209$
BEGIN
  EXECUTE $bootstrap_sql_f1dd4f41e209$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_points_customer ON public.pos_loyalty_points(customer_id)$bootstrap_sql_f1dd4f41e209$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1dd4f41e209$;

DO $bootstrap_do_4a5fbe515ad2$
BEGIN
  EXECUTE $bootstrap_sql_4a5fbe515ad2$ALTER TABLE public.pos_loyalty_points ENABLE ROW LEVEL SECURITY$bootstrap_sql_4a5fbe515ad2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a5fbe515ad2$;

DO $bootstrap_do_28bff56a3901$
BEGIN
  EXECUTE $bootstrap_sql_28bff56a3901$DROP POLICY IF EXISTS "pos_loyalty_points_access" ON public.pos_loyalty_points$bootstrap_sql_28bff56a3901$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_28bff56a3901$;

DO $bootstrap_do_9e806d4504f8$
BEGIN
  EXECUTE $bootstrap_sql_9e806d4504f8$CREATE POLICY "pos_loyalty_points_access" ON public.pos_loyalty_points
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_9e806d4504f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e806d4504f8$;

DO $bootstrap_do_33b7236549f5$
BEGIN
  EXECUTE $bootstrap_sql_33b7236549f5$-- ============================================================
-- TABEL RIWAYAT TRANSAKSI POIN
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pos_loyalty_transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL,
  customer_id UUID NOT NULL REFERENCES public.pos_customers(id) ON DELETE CASCADE,
  sale_id UUID,
  type TEXT NOT NULL,
  -- earn, redeem, adjust, expire
  points INTEGER NOT NULL,
  -- positive = earn, negative = redeem/expire
  balance_before INTEGER NOT NULL DEFAULT 0,
  balance_after INTEGER NOT NULL DEFAULT 0,
  description TEXT,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_33b7236549f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33b7236549f5$;

DO $bootstrap_do_e21697dcccc2$
BEGIN
  EXECUTE $bootstrap_sql_e21697dcccc2$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_tx_customer ON public.pos_loyalty_transactions(customer_id)$bootstrap_sql_e21697dcccc2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e21697dcccc2$;

DO $bootstrap_do_b61052e7b09e$
BEGIN
  EXECUTE $bootstrap_sql_b61052e7b09e$CREATE INDEX IF NOT EXISTS idx_pos_loyalty_tx_tenant ON public.pos_loyalty_transactions(tenant_id)$bootstrap_sql_b61052e7b09e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b61052e7b09e$;

DO $bootstrap_do_8ceb657710d6$
BEGIN
  EXECUTE $bootstrap_sql_8ceb657710d6$ALTER TABLE public.pos_loyalty_transactions ENABLE ROW LEVEL SECURITY$bootstrap_sql_8ceb657710d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ceb657710d6$;

DO $bootstrap_do_77823eb1979e$
BEGIN
  EXECUTE $bootstrap_sql_77823eb1979e$DROP POLICY IF EXISTS "pos_loyalty_transactions_access" ON public.pos_loyalty_transactions$bootstrap_sql_77823eb1979e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77823eb1979e$;

DO $bootstrap_do_d3d067e83636$
BEGIN
  EXECUTE $bootstrap_sql_d3d067e83636$CREATE POLICY "pos_loyalty_transactions_access" ON public.pos_loyalty_transactions
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_d3d067e83636$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3d067e83636$;

DO $bootstrap_do_2b5ef3f5676c$
BEGIN
  EXECUTE $bootstrap_sql_2b5ef3f5676c$-- ============================================================
-- Tambah kolom ke pos_sales untuk support loyalty & promo
-- ============================================================
ALTER TABLE public.pos_sales
  ADD COLUMN IF NOT EXISTS promotion_id UUID,
  ADD COLUMN IF NOT EXISTS voucher_id UUID,
  ADD COLUMN IF NOT EXISTS voucher_code TEXT,
  ADD COLUMN IF NOT EXISTS promotion_discount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS voucher_discount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_points_earned INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_points_redeemed INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_discount NUMERIC DEFAULT 0$bootstrap_sql_2b5ef3f5676c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b5ef3f5676c$;

DO $bootstrap_do_de526a9a8e58$
BEGIN
  EXECUTE $bootstrap_sql_de526a9a8e58$-- Tambah kolom poin ke pos_customers
ALTER TABLE public.pos_customers
  ADD COLUMN IF NOT EXISTS loyalty_points INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_tier TEXT DEFAULT 'Bronze'$bootstrap_sql_de526a9a8e58$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de526a9a8e58$;

DO $bootstrap_do_d404e550d39d$
BEGIN
  EXECUTE $bootstrap_sql_d404e550d39d$
