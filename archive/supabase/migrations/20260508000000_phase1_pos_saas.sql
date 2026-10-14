-- Phase 1: POS SaaS Tables
-- Platform UMKM - POS, Master Data, Stok Dasar

-- Tenant (usaha / bisnis)
CREATE TABLE IF NOT EXISTS pos_tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  logo_url text,
  phone text,
  address text,
  timezone text DEFAULT 'Asia/Jakarta',
  language text DEFAULT 'id',
  currency text DEFAULT 'IDR',
  receipt_header text,
  receipt_footer text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_4c712e16488b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c712e16488b$;

DO $bootstrap_do_2f67b56568d2$
BEGIN
  EXECUTE $bootstrap_sql_2f67b56568d2$-- Outlet / Cabang
CREATE TABLE IF NOT EXISTS pos_outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  address text,
  phone text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_2f67b56568d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f67b56568d2$;

DO $bootstrap_do_02ec101e0a29$
BEGIN
  EXECUTE $bootstrap_sql_02ec101e0a29$-- POS Users (role dalam sistem POS)
CREATE TABLE IF NOT EXISTS pos_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  role text NOT NULL DEFAULT 'kasir' CHECK (role IN ('owner','manager','kasir','staff_gudang','purchasing','finance','auditor')),
  pin text,
  outlet_id uuid REFERENCES pos_outlets(id),
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_02ec101e0a29$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_02ec101e0a29$;

DO $bootstrap_do_070658875a9e$
BEGIN
  EXECUTE $bootstrap_sql_070658875a9e$-- Kategori Produk
CREATE TABLE IF NOT EXISTS pos_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  parent_id uuid REFERENCES pos_categories(id),
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_070658875a9e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_070658875a9e$;

DO $bootstrap_do_7cdd6e4663bc$
BEGIN
  EXECUTE $bootstrap_sql_7cdd6e4663bc$-- Brand
CREATE TABLE IF NOT EXISTS pos_brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_7cdd6e4663bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cdd6e4663bc$;

DO $bootstrap_do_09a997ebe413$
BEGIN
  EXECUTE $bootstrap_sql_09a997ebe413$-- Produk
CREATE TABLE IF NOT EXISTS pos_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  category_id uuid REFERENCES pos_categories(id),
  brand_id uuid REFERENCES pos_brands(id),
  name text NOT NULL,
  sku text,
  barcode text,
  unit text DEFAULT 'pcs',
  price numeric(15,2) NOT NULL DEFAULT 0,
  cost_price numeric(15,2) DEFAULT 0,
  tax_rate numeric(5,2) DEFAULT 0,
  is_stock_tracked boolean DEFAULT true,
  has_variants boolean DEFAULT false,
  image_url text,
  description text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_09a997ebe413$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09a997ebe413$;

DO $bootstrap_do_68a3ffd5af4c$
BEGIN
  EXECUTE $bootstrap_sql_68a3ffd5af4c$-- Varian Produk
CREATE TABLE IF NOT EXISTS pos_product_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES pos_products(id) ON DELETE CASCADE NOT NULL,
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  sku text,
  barcode text,
  price numeric(15,2),
  cost_price numeric(15,2),
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_68a3ffd5af4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68a3ffd5af4c$;

DO $bootstrap_do_d5fc671924c7$
BEGIN
  EXECUTE $bootstrap_sql_d5fc671924c7$-- Stok per Produk per Outlet
CREATE TABLE IF NOT EXISTS pos_stock (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) ON DELETE CASCADE NOT NULL,
  variant_id uuid REFERENCES pos_product_variants(id),
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  quantity numeric(15,3) DEFAULT 0,
  min_stock numeric(15,3) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(product_id, variant_id, outlet_id)
)$bootstrap_sql_d5fc671924c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5fc671924c7$;

DO $bootstrap_do_eae7a6f0e4d6$
BEGIN
  EXECUTE $bootstrap_sql_eae7a6f0e4d6$-- Mutasi Stok
CREATE TABLE IF NOT EXISTS pos_stock_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) NOT NULL,
  variant_id uuid REFERENCES pos_product_variants(id),
  outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  type text NOT NULL CHECK (type IN ('initial','purchase','sale','adjustment','return_sale','return_purchase','transfer_in','transfer_out','opname')),
  quantity numeric(15,3) NOT NULL,
  quantity_before numeric(15,3),
  quantity_after numeric(15,3),
  reference_id uuid,
  reference_type text,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_eae7a6f0e4d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eae7a6f0e4d6$;

DO $bootstrap_do_4b25f65c39c5$
BEGIN
  EXECUTE $bootstrap_sql_4b25f65c39c5$-- Customer
CREATE TABLE IF NOT EXISTS pos_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  is_member boolean DEFAULT false,
  total_purchase numeric(15,2) DEFAULT 0,
  transaction_count int DEFAULT 0,
  last_purchase_at timestamptz,
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_4b25f65c39c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b25f65c39c5$;

DO $bootstrap_do_a864af5ea5a5$
BEGIN
  EXECUTE $bootstrap_sql_a864af5ea5a5$-- Supplier
CREATE TABLE IF NOT EXISTS pos_suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  contact_person text,
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_a864af5ea5a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a864af5ea5a5$;

DO $bootstrap_do_22e6e5b9b3af$
BEGIN
  EXECUTE $bootstrap_sql_22e6e5b9b3af$-- Transaksi Penjualan (Header)
CREATE TABLE IF NOT EXISTS pos_sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  sale_number text NOT NULL,
  cashier_id uuid REFERENCES auth.users(id),
  cashier_name text,
  customer_id uuid REFERENCES pos_customers(id),
  customer_name text,
  subtotal numeric(15,2) NOT NULL DEFAULT 0,
  discount_amount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  total numeric(15,2) NOT NULL DEFAULT 0,
  payment_method text DEFAULT 'cash' CHECK (payment_method IN ('cash','qris','transfer','debit','credit','split')),
  payment_amount numeric(15,2) DEFAULT 0,
  change_amount numeric(15,2) DEFAULT 0,
  status text DEFAULT 'completed' CHECK (status IN ('completed','void','refunded')),
  notes text,
  voided_by uuid REFERENCES auth.users(id),
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_22e6e5b9b3af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22e6e5b9b3af$;

DO $bootstrap_do_731905d84de2$
BEGIN
  EXECUTE $bootstrap_sql_731905d84de2$-- Item Transaksi Penjualan
CREATE TABLE IF NOT EXISTS pos_sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid REFERENCES pos_sales(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  variant_id uuid REFERENCES pos_product_variants(id),
  product_name text NOT NULL,
  variant_name text,
  sku text,
  qty numeric(15,3) NOT NULL DEFAULT 1,
  price numeric(15,2) NOT NULL,
  cost_price numeric(15,2) DEFAULT 0,
  discount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  subtotal numeric(15,2) NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_731905d84de2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_731905d84de2$;

DO $bootstrap_do_ed20cf1cf890$
BEGIN
  EXECUTE $bootstrap_sql_ed20cf1cf890$-- Bill Ditahan (Hold Bill)
CREATE TABLE IF NOT EXISTS pos_held_bills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  cashier_id uuid REFERENCES auth.users(id),
  label text,
  customer_name text,
  customer_id uuid REFERENCES pos_customers(id),
  items jsonb NOT NULL DEFAULT '[]',
  discount_amount numeric(15,2) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_ed20cf1cf890$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed20cf1cf890$;

DO $bootstrap_do_e79e8469fe8c$
BEGIN
  EXECUTE $bootstrap_sql_e79e8469fe8c$-- Retur Penjualan
CREATE TABLE IF NOT EXISTS pos_sale_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  sale_id uuid REFERENCES pos_sales(id) NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  return_number text NOT NULL,
  reason text,
  refund_method text DEFAULT 'cash' CHECK (refund_method IN ('cash','store_credit')),
  total_refund numeric(15,2) NOT NULL DEFAULT 0,
  restock boolean DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
)$bootstrap_sql_e79e8469fe8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e79e8469fe8c$;

DO $bootstrap_do_ab34f7d6716b$
BEGIN
  EXECUTE $bootstrap_sql_ab34f7d6716b$CREATE TABLE IF NOT EXISTS pos_sale_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid REFERENCES pos_sale_returns(id) ON DELETE CASCADE NOT NULL,
  sale_item_id uuid REFERENCES pos_sale_items(id) NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  product_name text NOT NULL,
  qty numeric(15,3) NOT NULL,
  price numeric(15,2) NOT NULL,
  subtotal numeric(15,2) NOT NULL
)$bootstrap_sql_ab34f7d6716b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab34f7d6716b$;

DO $bootstrap_do_4dd9b72d7d60$
BEGIN
  EXECUTE $bootstrap_sql_4dd9b72d7d60$-- RLS Policies
ALTER TABLE pos_tenants ENABLE ROW LEVEL SECURITY$bootstrap_sql_4dd9b72d7d60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dd9b72d7d60$;

DO $bootstrap_do_35142388e360$
BEGIN
  EXECUTE $bootstrap_sql_35142388e360$ALTER TABLE pos_outlets ENABLE ROW LEVEL SECURITY$bootstrap_sql_35142388e360$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_35142388e360$;

DO $bootstrap_do_7fd343917a14$
BEGIN
  EXECUTE $bootstrap_sql_7fd343917a14$ALTER TABLE pos_users ENABLE ROW LEVEL SECURITY$bootstrap_sql_7fd343917a14$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7fd343917a14$;

DO $bootstrap_do_d7b5a4aa83c9$
BEGIN
  EXECUTE $bootstrap_sql_d7b5a4aa83c9$ALTER TABLE pos_categories ENABLE ROW LEVEL SECURITY$bootstrap_sql_d7b5a4aa83c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7b5a4aa83c9$;

DO $bootstrap_do_aa39f7d268f3$
BEGIN
  EXECUTE $bootstrap_sql_aa39f7d268f3$ALTER TABLE pos_brands ENABLE ROW LEVEL SECURITY$bootstrap_sql_aa39f7d268f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa39f7d268f3$;

DO $bootstrap_do_f08530cd9102$
BEGIN
  EXECUTE $bootstrap_sql_f08530cd9102$ALTER TABLE pos_products ENABLE ROW LEVEL SECURITY$bootstrap_sql_f08530cd9102$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f08530cd9102$;

DO $bootstrap_do_ae7fdf601c42$
BEGIN
  EXECUTE $bootstrap_sql_ae7fdf601c42$ALTER TABLE pos_product_variants ENABLE ROW LEVEL SECURITY$bootstrap_sql_ae7fdf601c42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae7fdf601c42$;

DO $bootstrap_do_a5fa8eba064a$
BEGIN
  EXECUTE $bootstrap_sql_a5fa8eba064a$ALTER TABLE pos_stock ENABLE ROW LEVEL SECURITY$bootstrap_sql_a5fa8eba064a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5fa8eba064a$;

DO $bootstrap_do_c97067a30184$
BEGIN
  EXECUTE $bootstrap_sql_c97067a30184$ALTER TABLE pos_stock_mutations ENABLE ROW LEVEL SECURITY$bootstrap_sql_c97067a30184$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c97067a30184$;

DO $bootstrap_do_f40d48890ec6$
BEGIN
  EXECUTE $bootstrap_sql_f40d48890ec6$ALTER TABLE pos_customers ENABLE ROW LEVEL SECURITY$bootstrap_sql_f40d48890ec6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f40d48890ec6$;

DO $bootstrap_do_2b0fbeed5f19$
BEGIN
  EXECUTE $bootstrap_sql_2b0fbeed5f19$ALTER TABLE pos_suppliers ENABLE ROW LEVEL SECURITY$bootstrap_sql_2b0fbeed5f19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b0fbeed5f19$;

DO $bootstrap_do_103c7451bd43$
BEGIN
  EXECUTE $bootstrap_sql_103c7451bd43$ALTER TABLE pos_sales ENABLE ROW LEVEL SECURITY$bootstrap_sql_103c7451bd43$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_103c7451bd43$;

DO $bootstrap_do_4dbaeefc7885$
BEGIN
  EXECUTE $bootstrap_sql_4dbaeefc7885$ALTER TABLE pos_sale_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_4dbaeefc7885$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dbaeefc7885$;

DO $bootstrap_do_732894e80ac8$
BEGIN
  EXECUTE $bootstrap_sql_732894e80ac8$ALTER TABLE pos_held_bills ENABLE ROW LEVEL SECURITY$bootstrap_sql_732894e80ac8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_732894e80ac8$;

DO $bootstrap_do_cbc3bf8e3d9c$
BEGIN
  EXECUTE $bootstrap_sql_cbc3bf8e3d9c$ALTER TABLE pos_sale_returns ENABLE ROW LEVEL SECURITY$bootstrap_sql_cbc3bf8e3d9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cbc3bf8e3d9c$;

DO $bootstrap_do_c40df8f815ce$
BEGIN
  EXECUTE $bootstrap_sql_c40df8f815ce$ALTER TABLE pos_sale_return_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_c40df8f815ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c40df8f815ce$;

DO $bootstrap_do_c1d2cd120d5d$
BEGIN
  EXECUTE $bootstrap_sql_c1d2cd120d5d$-- Tenant owner can manage their own tenant
DROP POLICY IF EXISTS "tenant_owner_all" ON pos_tenants$bootstrap_sql_c1d2cd120d5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1d2cd120d5d$;

DO $bootstrap_do_28cfbb2059a7$
BEGIN
  EXECUTE $bootstrap_sql_28cfbb2059a7$CREATE POLICY "tenant_owner_all" ON pos_tenants FOR ALL USING (user_id = auth.uid())$bootstrap_sql_28cfbb2059a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_28cfbb2059a7$;

DO $bootstrap_do_6f2e95b62b83$
BEGIN
  EXECUTE $bootstrap_sql_6f2e95b62b83$-- Users within a tenant can access tenant data
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON pos_outlets$bootstrap_sql_6f2e95b62b83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f2e95b62b83$;

DO $bootstrap_do_843c5a49032b$
BEGIN
  EXECUTE $bootstrap_sql_843c5a49032b$CREATE POLICY "tenant_users_select_outlets" ON pos_outlets FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_843c5a49032b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_843c5a49032b$;

DO $bootstrap_do_50dfa607cb1e$
BEGIN
  EXECUTE $bootstrap_sql_50dfa607cb1e$DROP POLICY IF EXISTS "tenant_owner_manage_outlets" ON pos_outlets$bootstrap_sql_50dfa607cb1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50dfa607cb1e$;

DO $bootstrap_do_a5a4eb858d47$
BEGIN
  EXECUTE $bootstrap_sql_a5a4eb858d47$CREATE POLICY "tenant_owner_manage_outlets" ON pos_outlets FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_a5a4eb858d47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5a4eb858d47$;

DO $bootstrap_do_b74dce2e6f4a$
BEGIN
  EXECUTE $bootstrap_sql_b74dce2e6f4a$DROP POLICY IF EXISTS "tenant_users_select_categories" ON pos_categories$bootstrap_sql_b74dce2e6f4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b74dce2e6f4a$;

DO $bootstrap_do_cc5e77b7357d$
BEGIN
  EXECUTE $bootstrap_sql_cc5e77b7357d$CREATE POLICY "tenant_users_select_categories" ON pos_categories FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_cc5e77b7357d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc5e77b7357d$;

DO $bootstrap_do_e0dc08ed4b9d$
BEGIN
  EXECUTE $bootstrap_sql_e0dc08ed4b9d$DROP POLICY IF EXISTS "tenant_owner_manage_categories" ON pos_categories$bootstrap_sql_e0dc08ed4b9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e0dc08ed4b9d$;

DO $bootstrap_do_07a741a6259b$
BEGIN
  EXECUTE $bootstrap_sql_07a741a6259b$CREATE POLICY "tenant_owner_manage_categories" ON pos_categories FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_07a741a6259b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07a741a6259b$;

DO $bootstrap_do_ccbfc467d35a$
BEGIN
  EXECUTE $bootstrap_sql_ccbfc467d35a$DROP POLICY IF EXISTS "tenant_users_select_brands" ON pos_brands$bootstrap_sql_ccbfc467d35a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ccbfc467d35a$;

DO $bootstrap_do_c382d4d7b06c$
BEGIN
  EXECUTE $bootstrap_sql_c382d4d7b06c$CREATE POLICY "tenant_users_select_brands" ON pos_brands FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_c382d4d7b06c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c382d4d7b06c$;

DO $bootstrap_do_e1792754609a$
BEGIN
  EXECUTE $bootstrap_sql_e1792754609a$DROP POLICY IF EXISTS "tenant_owner_manage_brands" ON pos_brands$bootstrap_sql_e1792754609a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1792754609a$;

DO $bootstrap_do_9f3200b0ad6e$
BEGIN
  EXECUTE $bootstrap_sql_9f3200b0ad6e$CREATE POLICY "tenant_owner_manage_brands" ON pos_brands FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_9f3200b0ad6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f3200b0ad6e$;

DO $bootstrap_do_e2b6f591d82e$
BEGIN
  EXECUTE $bootstrap_sql_e2b6f591d82e$DROP POLICY IF EXISTS "tenant_users_select_products" ON pos_products$bootstrap_sql_e2b6f591d82e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e2b6f591d82e$;

DO $bootstrap_do_f2639b1e5bdc$
BEGIN
  EXECUTE $bootstrap_sql_f2639b1e5bdc$CREATE POLICY "tenant_users_select_products" ON pos_products FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_f2639b1e5bdc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2639b1e5bdc$;

DO $bootstrap_do_485fb2030bec$
BEGIN
  EXECUTE $bootstrap_sql_485fb2030bec$DROP POLICY IF EXISTS "tenant_owner_manage_products" ON pos_products$bootstrap_sql_485fb2030bec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_485fb2030bec$;

DO $bootstrap_do_a33fa45c5db0$
BEGIN
  EXECUTE $bootstrap_sql_a33fa45c5db0$CREATE POLICY "tenant_owner_manage_products" ON pos_products FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_a33fa45c5db0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a33fa45c5db0$;

DO $bootstrap_do_251d0318b398$
BEGIN
  EXECUTE $bootstrap_sql_251d0318b398$DROP POLICY IF EXISTS "tenant_users_select_variants" ON pos_product_variants$bootstrap_sql_251d0318b398$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_251d0318b398$;

DO $bootstrap_do_193a92cd878d$
BEGIN
  EXECUTE $bootstrap_sql_193a92cd878d$CREATE POLICY "tenant_users_select_variants" ON pos_product_variants FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_193a92cd878d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_193a92cd878d$;

DO $bootstrap_do_f17d25e81ee7$
BEGIN
  EXECUTE $bootstrap_sql_f17d25e81ee7$DROP POLICY IF EXISTS "tenant_owner_manage_variants" ON pos_product_variants$bootstrap_sql_f17d25e81ee7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f17d25e81ee7$;

DO $bootstrap_do_b9a90e80ac78$
BEGIN
  EXECUTE $bootstrap_sql_b9a90e80ac78$CREATE POLICY "tenant_owner_manage_variants" ON pos_product_variants FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_b9a90e80ac78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9a90e80ac78$;

DO $bootstrap_do_8862ad437368$
BEGIN
  EXECUTE $bootstrap_sql_8862ad437368$DROP POLICY IF EXISTS "tenant_users_select_stock" ON pos_stock$bootstrap_sql_8862ad437368$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8862ad437368$;

DO $bootstrap_do_1e07d851a520$
BEGIN
  EXECUTE $bootstrap_sql_1e07d851a520$CREATE POLICY "tenant_users_select_stock" ON pos_stock FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_1e07d851a520$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e07d851a520$;

DO $bootstrap_do_00994285baa5$
BEGIN
  EXECUTE $bootstrap_sql_00994285baa5$DROP POLICY IF EXISTS "tenant_owner_manage_stock" ON pos_stock$bootstrap_sql_00994285baa5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00994285baa5$;

DO $bootstrap_do_dc335d26b67c$
BEGIN
  EXECUTE $bootstrap_sql_dc335d26b67c$CREATE POLICY "tenant_owner_manage_stock" ON pos_stock FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_dc335d26b67c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc335d26b67c$;

DO $bootstrap_do_f1f8fac0d933$
BEGIN
  EXECUTE $bootstrap_sql_f1f8fac0d933$DROP POLICY IF EXISTS "tenant_users_select_mutations" ON pos_stock_mutations$bootstrap_sql_f1f8fac0d933$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1f8fac0d933$;

DO $bootstrap_do_0f33d7c5e4a6$
BEGIN
  EXECUTE $bootstrap_sql_0f33d7c5e4a6$CREATE POLICY "tenant_users_select_mutations" ON pos_stock_mutations FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_0f33d7c5e4a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f33d7c5e4a6$;

DO $bootstrap_do_d15e388a1314$
BEGIN
  EXECUTE $bootstrap_sql_d15e388a1314$DROP POLICY IF EXISTS "tenant_owner_manage_mutations" ON pos_stock_mutations$bootstrap_sql_d15e388a1314$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d15e388a1314$;

DO $bootstrap_do_741c4ecb764c$
BEGIN
  EXECUTE $bootstrap_sql_741c4ecb764c$CREATE POLICY "tenant_owner_manage_mutations" ON pos_stock_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_741c4ecb764c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_741c4ecb764c$;

DO $bootstrap_do_bfe249647228$
BEGIN
  EXECUTE $bootstrap_sql_bfe249647228$DROP POLICY IF EXISTS "tenant_users_select_customers" ON pos_customers$bootstrap_sql_bfe249647228$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfe249647228$;

DO $bootstrap_do_c1bd13c46c5b$
BEGIN
  EXECUTE $bootstrap_sql_c1bd13c46c5b$CREATE POLICY "tenant_users_select_customers" ON pos_customers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_c1bd13c46c5b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1bd13c46c5b$;

DO $bootstrap_do_2d4f4bc54d6a$
BEGIN
  EXECUTE $bootstrap_sql_2d4f4bc54d6a$DROP POLICY IF EXISTS "tenant_owner_manage_customers" ON pos_customers$bootstrap_sql_2d4f4bc54d6a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d4f4bc54d6a$;

DO $bootstrap_do_9ee00e0f8486$
BEGIN
  EXECUTE $bootstrap_sql_9ee00e0f8486$CREATE POLICY "tenant_owner_manage_customers" ON pos_customers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_9ee00e0f8486$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ee00e0f8486$;

DO $bootstrap_do_8e4e15d61c67$
BEGIN
  EXECUTE $bootstrap_sql_8e4e15d61c67$DROP POLICY IF EXISTS "tenant_users_select_suppliers" ON pos_suppliers$bootstrap_sql_8e4e15d61c67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e4e15d61c67$;

DO $bootstrap_do_f068991b5d88$
BEGIN
  EXECUTE $bootstrap_sql_f068991b5d88$CREATE POLICY "tenant_users_select_suppliers" ON pos_suppliers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_f068991b5d88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f068991b5d88$;

DO $bootstrap_do_b5bcc4d35a7d$
BEGIN
  EXECUTE $bootstrap_sql_b5bcc4d35a7d$DROP POLICY IF EXISTS "tenant_owner_manage_suppliers" ON pos_suppliers$bootstrap_sql_b5bcc4d35a7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5bcc4d35a7d$;

DO $bootstrap_do_f2e8c467411d$
BEGIN
  EXECUTE $bootstrap_sql_f2e8c467411d$CREATE POLICY "tenant_owner_manage_suppliers" ON pos_suppliers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_f2e8c467411d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2e8c467411d$;

DO $bootstrap_do_45bfcb5eb383$
BEGIN
  EXECUTE $bootstrap_sql_45bfcb5eb383$DROP POLICY IF EXISTS "tenant_users_select_sales" ON pos_sales$bootstrap_sql_45bfcb5eb383$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45bfcb5eb383$;

DO $bootstrap_do_9e0998d7de66$
BEGIN
  EXECUTE $bootstrap_sql_9e0998d7de66$CREATE POLICY "tenant_users_select_sales" ON pos_sales FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_9e0998d7de66$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e0998d7de66$;

DO $bootstrap_do_6da8a000009e$
BEGIN
  EXECUTE $bootstrap_sql_6da8a000009e$DROP POLICY IF EXISTS "tenant_owner_manage_sales" ON pos_sales$bootstrap_sql_6da8a000009e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6da8a000009e$;

DO $bootstrap_do_8765f712765c$
BEGIN
  EXECUTE $bootstrap_sql_8765f712765c$CREATE POLICY "tenant_owner_manage_sales" ON pos_sales FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_8765f712765c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8765f712765c$;

DO $bootstrap_do_4ee98f4daf9f$
BEGIN
  EXECUTE $bootstrap_sql_4ee98f4daf9f$DROP POLICY IF EXISTS "tenant_users_select_sale_items" ON pos_sale_items$bootstrap_sql_4ee98f4daf9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ee98f4daf9f$;

DO $bootstrap_do_4d25d24bef9f$
BEGIN
  EXECUTE $bootstrap_sql_4d25d24bef9f$CREATE POLICY "tenant_users_select_sale_items" ON pos_sale_items FOR SELECT USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
)$bootstrap_sql_4d25d24bef9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d25d24bef9f$;

DO $bootstrap_do_38b9ec6af6f0$
BEGIN
  EXECUTE $bootstrap_sql_38b9ec6af6f0$DROP POLICY IF EXISTS "tenant_owner_manage_sale_items" ON pos_sale_items$bootstrap_sql_38b9ec6af6f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_38b9ec6af6f0$;

DO $bootstrap_do_8cab4822d225$
BEGIN
  EXECUTE $bootstrap_sql_8cab4822d225$CREATE POLICY "tenant_owner_manage_sale_items" ON pos_sale_items FOR ALL USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
)$bootstrap_sql_8cab4822d225$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cab4822d225$;

DO $bootstrap_do_e604497faa9b$
BEGIN
  EXECUTE $bootstrap_sql_e604497faa9b$DROP POLICY IF EXISTS "tenant_owner_manage_held_bills" ON pos_held_bills$bootstrap_sql_e604497faa9b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e604497faa9b$;

DO $bootstrap_do_96314bd299bc$
BEGIN
  EXECUTE $bootstrap_sql_96314bd299bc$CREATE POLICY "tenant_owner_manage_held_bills" ON pos_held_bills FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_96314bd299bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_96314bd299bc$;

DO $bootstrap_do_65c52489c108$
BEGIN
  EXECUTE $bootstrap_sql_65c52489c108$DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON pos_held_bills$bootstrap_sql_65c52489c108$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_65c52489c108$;

DO $bootstrap_do_429f898a5dd4$
BEGIN
  EXECUTE $bootstrap_sql_429f898a5dd4$CREATE POLICY "tenant_users_select_held_bills" ON pos_held_bills FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
)$bootstrap_sql_429f898a5dd4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_429f898a5dd4$;

DO $bootstrap_do_161beb74d944$
BEGIN
  EXECUTE $bootstrap_sql_161beb74d944$DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON pos_users$bootstrap_sql_161beb74d944$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_161beb74d944$;

DO $bootstrap_do_1fad4dd9bfac$
BEGIN
  EXECUTE $bootstrap_sql_1fad4dd9bfac$CREATE POLICY "tenant_users_select_pos_users" ON pos_users FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR user_id = auth.uid()
)$bootstrap_sql_1fad4dd9bfac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1fad4dd9bfac$;

DO $bootstrap_do_455bdedb1e20$
BEGIN
  EXECUTE $bootstrap_sql_455bdedb1e20$DROP POLICY IF EXISTS "tenant_owner_manage_pos_users" ON pos_users$bootstrap_sql_455bdedb1e20$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_455bdedb1e20$;

DO $bootstrap_do_ef840a905987$
BEGIN
  EXECUTE $bootstrap_sql_ef840a905987$CREATE POLICY "tenant_owner_manage_pos_users" ON pos_users FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_ef840a905987$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef840a905987$;

DO $bootstrap_do_c8898af4dcff$
BEGIN
  EXECUTE $bootstrap_sql_c8898af4dcff$DROP POLICY IF EXISTS "tenant_owner_manage_returns" ON pos_sale_returns$bootstrap_sql_c8898af4dcff$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8898af4dcff$;

DO $bootstrap_do_819a3cd69b8e$
BEGIN
  EXECUTE $bootstrap_sql_819a3cd69b8e$CREATE POLICY "tenant_owner_manage_returns" ON pos_sale_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
)$bootstrap_sql_819a3cd69b8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_819a3cd69b8e$;

DO $bootstrap_do_cdf8b73034a6$
BEGIN
  EXECUTE $bootstrap_sql_cdf8b73034a6$DROP POLICY IF EXISTS "tenant_owner_manage_return_items" ON pos_sale_return_items$bootstrap_sql_cdf8b73034a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cdf8b73034a6$;

DO $bootstrap_do_aea42f99ff5b$
BEGIN
  EXECUTE $bootstrap_sql_aea42f99ff5b$CREATE POLICY "tenant_owner_manage_return_items" ON pos_sale_return_items FOR ALL USING (
  return_id IN (SELECT id FROM pos_sale_returns WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
)$bootstrap_sql_aea42f99ff5b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aea42f99ff5b$;

DO $bootstrap_do_a689731acc10$
BEGIN
  EXECUTE $bootstrap_sql_a689731acc10$-- Indexes untuk performa
CREATE INDEX IF NOT EXISTS idx_pos_products_tenant ON pos_products(tenant_id)$bootstrap_sql_a689731acc10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a689731acc10$;

DO $bootstrap_do_584c4a8c0872$
BEGIN
  EXECUTE $bootstrap_sql_584c4a8c0872$CREATE INDEX IF NOT EXISTS idx_pos_products_category ON pos_products(category_id)$bootstrap_sql_584c4a8c0872$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_584c4a8c0872$;

DO $bootstrap_do_a4f138d65095$
BEGIN
  EXECUTE $bootstrap_sql_a4f138d65095$CREATE INDEX IF NOT EXISTS idx_pos_stock_product_outlet ON pos_stock(product_id, outlet_id)$bootstrap_sql_a4f138d65095$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4f138d65095$;

DO $bootstrap_do_78c709d43415$
BEGIN
  EXECUTE $bootstrap_sql_78c709d43415$CREATE INDEX IF NOT EXISTS idx_pos_sales_tenant_created ON pos_sales(tenant_id, created_at DESC)$bootstrap_sql_78c709d43415$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78c709d43415$;

DO $bootstrap_do_fc77939a79f8$
BEGIN
  EXECUTE $bootstrap_sql_fc77939a79f8$CREATE INDEX IF NOT EXISTS idx_pos_sales_outlet ON pos_sales(outlet_id)$bootstrap_sql_fc77939a79f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc77939a79f8$;

DO $bootstrap_do_235c3eb9aad8$
BEGIN
  EXECUTE $bootstrap_sql_235c3eb9aad8$CREATE INDEX IF NOT EXISTS idx_pos_stock_mutations_product ON pos_stock_mutations(product_id, created_at DESC)$bootstrap_sql_235c3eb9aad8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_235c3eb9aad8$;

DO $bootstrap_do_fbe5da93f531$
BEGIN
  EXECUTE $bootstrap_sql_fbe5da93f531$CREATE INDEX IF NOT EXISTS idx_pos_customers_tenant ON pos_customers(tenant_id)$bootstrap_sql_fbe5da93f531$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbe5da93f531$;

DO $bootstrap_do_8addaf4e8b54$
BEGIN
  EXECUTE $bootstrap_sql_8addaf4e8b54$
