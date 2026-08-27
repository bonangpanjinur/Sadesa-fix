-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260403082441_8d12e8c5-2d68-4b47-8660-023667cf0630.sql .. 20260804111713_21956d1a-8612-45c6-90a1-0d7523bf7480.sql


-- ===== BEGIN SOURCE: 20260403082441_8d12e8c5-2d68-4b47-8660-023667cf0630.sql =====

-- Function to notify available couriers when a new ride request is created
CREATE OR REPLACE FUNCTION public.notify_couriers_new_ride()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert notifications for all active, available couriers
  INSERT INTO public.notifications (user_id, title, message, type, link)
  SELECT 
    c.user_id,
    '🏍️ Pesanan Ojek Baru!',
    'Jemput di: ' || COALESCE(NEW.pickup_address, 'Lokasi tidak diketahui') || ' • Estimasi: Rp ' || COALESCE(NEW.estimated_fare::text, '0'),
    'ride',
    '/courier/rides'
  FROM public.couriers c
  WHERE c.user_id IS NOT NULL
    AND c.registration_status = 'APPROVED'
    AND c.status = 'ACTIVE'
    AND c.is_available = true;
  
  RETURN NEW;
END;
$$;

-- Create trigger on ride_requests for new ride notifications
DROP TRIGGER IF EXISTS trigger_notify_couriers_new_ride ON public.ride_requests;
CREATE TRIGGER trigger_notify_couriers_new_ride
  AFTER INSERT ON public.ride_requests
  FOR EACH ROW
  WHEN (NEW.status = 'SEARCHING')
  EXECUTE FUNCTION public.notify_couriers_new_ride();

-- ===== END SOURCE: 20260403082441_8d12e8c5-2d68-4b47-8660-023667cf0630.sql =====

-- ===== BEGIN SOURCE: 20260416025335_c7d8cc12-56f8-4c10-8105-fb50ca6597bf.sql =====
-- Fix 3 functions missing search_path

ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public;
ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public;
ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public;

-- Fix overly permissive RLS policy on rate_limits (WITH CHECK (true))
DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits;
CREATE POLICY "Rate limits insert via functions" ON public.rate_limits
  FOR INSERT TO authenticated
  WITH CHECK (identifier = auth.uid()::text OR public.is_admin());

DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits;
CREATE POLICY "Rate limits update via functions" ON public.rate_limits
  FOR UPDATE TO authenticated
  USING (identifier = auth.uid()::text OR public.is_admin())
  WITH CHECK (identifier = auth.uid()::text OR public.is_admin());
-- ===== END SOURCE: 20260416025335_c7d8cc12-56f8-4c10-8105-fb50ca6597bf.sql =====

-- ===== BEGIN SOURCE: 20260419155930_8d73519f-2835-42c4-b0dd-46f53c787876.sql =====
-- Fix overly permissive RLS policy on page_views (WITH CHECK true)
DROP POLICY IF EXISTS "Anyone can insert page views" ON public.page_views;

CREATE POLICY "Authenticated or anonymous can insert their own page view"
ON public.page_views
FOR INSERT
TO public
WITH CHECK (
  -- Anonymous viewer (no viewer_id) is allowed
  viewer_id IS NULL
  -- Or the viewer matches the authenticated user
  OR viewer_id = auth.uid()
);
-- ===== END SOURCE: 20260419155930_8d73519f-2835-42c4-b0dd-46f53c787876.sql =====

-- ===== BEGIN SOURCE: 20260419160116_b45d64ac-3359-4860-94e7-e8213dfbb3a6.sql =====
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_check;

-- Use a trigger-based validation instead of CHECK so we can reference categories table
CREATE OR REPLACE FUNCTION public.validate_product_category()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.category IS NULL OR NEW.category = '' THEN
    RAISE EXCEPTION 'Kategori produk wajib diisi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE slug = NEW.category AND is_active = true) THEN
    RAISE EXCEPTION 'Kategori "%" tidak valid atau tidak aktif', NEW.category;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_product_category ON public.products;
CREATE TRIGGER trg_validate_product_category
BEFORE INSERT OR UPDATE OF category ON public.products
FOR EACH ROW EXECUTE FUNCTION public.validate_product_category();
-- ===== END SOURCE: 20260419160116_b45d64ac-3359-4860-94e7-e8213dfbb3a6.sql =====

-- ===== BEGIN SOURCE: 20260419161037_08343087-5318-467f-a887-4238272bf30a.sql =====
-- Privatize the payment-proofs bucket
UPDATE storage.buckets SET public = false WHERE id = 'payment-proofs';

-- Drop old permissive policies
DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;

-- SELECT: buyer (owner of order), merchant of order, or admin
-- Path convention: orders/{order_id}/{filename}
CREATE POLICY "Buyer/merchant/admin can view payment proofs"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      LEFT JOIN public.merchants m ON o.merchant_id = m.id
      WHERE o.id::text = (storage.foldername(name))[2]
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid())
    )
  )
);

-- INSERT: any authenticated user (validated at app level via order ownership)
CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'payment-proofs');

-- UPDATE: only the buyer of the order
CREATE POLICY "Buyer can update own payment proofs"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id::text = (storage.foldername(name))[2]
      AND o.buyer_id = auth.uid()
  )
);

-- DELETE: only buyer or admin
CREATE POLICY "Buyer or admin can delete payment proofs"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[2]
        AND o.buyer_id = auth.uid()
    )
  )
);
-- ===== END SOURCE: 20260419161037_08343087-5318-467f-a887-4238272bf30a.sql =====

-- ===== BEGIN SOURCE: 20260502035656_0399f4e0-7366-4d83-a204-ffc75e712691.sql =====
-- =============================================
-- Phase 1: DB Hardening
-- =============================================

-- 1. DROP unused function overloads (keep the ones used by RLS policies & app code)
-- Keep: get_user_courier_id() no-arg (used in RLS)
DROP FUNCTION IF EXISTS public.get_user_courier_id(uuid);

-- Keep: get_user_merchant_id() no-arg
DROP FUNCTION IF EXISTS public.get_user_merchant_id(uuid);

-- Keep: use_merchant_quota(p_merchant_id uuid) — used by app via RPC
DROP FUNCTION IF EXISTS public.use_merchant_quota(uuid, integer);

-- Note: is_order_merchant has 2 overloads, BOTH are referenced by different RLS policies.
-- Keep both.

-- =============================================
-- 2. Privatize sensitive storage buckets
-- =============================================
UPDATE storage.buckets SET public = false WHERE id IN ('chat-images', 'pod-images');

-- RLS policies for chat-images: only chat participants can read/write
DROP POLICY IF EXISTS "Chat images: read by participants" ON storage.objects;
CREATE POLICY "Chat images: read by participants"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'chat-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1 FROM public.chat_messages cm
      WHERE cm.image_url LIKE '%' || storage.objects.name || '%'
        AND (cm.sender_id = auth.uid() OR cm.receiver_id = auth.uid())
    )
  )
);

DROP POLICY IF EXISTS "Chat images: upload by authenticated" ON storage.objects;
CREATE POLICY "Chat images: upload by authenticated"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'chat-images' AND auth.uid() IS NOT NULL);

-- RLS policies for pod-images: only buyer / merchant / courier of the order + admin
DROP POLICY IF EXISTS "POD images: read by order parties" ON storage.objects;
CREATE POLICY "POD images: read by order parties"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      LEFT JOIN public.couriers c ON c.id = o.courier_id
      WHERE o.pod_image_url LIKE '%' || storage.objects.name || '%'
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid() OR c.user_id = auth.uid())
    )
  )
);

DROP POLICY IF EXISTS "POD images: upload by courier or merchant" ON storage.objects;
CREATE POLICY "POD images: upload by courier or merchant"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'pod-images' AND auth.uid() IS NOT NULL);

-- ===== END SOURCE: 20260502035656_0399f4e0-7366-4d83-a204-ffc75e712691.sql =====

-- ===== BEGIN SOURCE: 20260508000000_phase1_pos_saas.sql =====
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
);

-- Outlet / Cabang
CREATE TABLE IF NOT EXISTS pos_outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  address text,
  phone text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- POS Users (role dalam sistem POS)
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
);

-- Kategori Produk
CREATE TABLE IF NOT EXISTS pos_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  parent_id uuid REFERENCES pos_categories(id),
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Brand
CREATE TABLE IF NOT EXISTS pos_brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Produk
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
);

-- Varian Produk
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
);

-- Stok per Produk per Outlet
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
);

-- Mutasi Stok
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
);

-- Customer
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
);

-- Supplier
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
);

-- Transaksi Penjualan (Header)
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
);

-- Item Transaksi Penjualan
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
);

-- Bill Ditahan (Hold Bill)
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
);

-- Retur Penjualan
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
);

CREATE TABLE IF NOT EXISTS pos_sale_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid REFERENCES pos_sale_returns(id) ON DELETE CASCADE NOT NULL,
  sale_item_id uuid REFERENCES pos_sale_items(id) NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  product_name text NOT NULL,
  qty numeric(15,3) NOT NULL,
  price numeric(15,2) NOT NULL,
  subtotal numeric(15,2) NOT NULL
);

-- RLS Policies
ALTER TABLE pos_tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_outlets ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_stock_mutations ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_held_bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sale_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sale_return_items ENABLE ROW LEVEL SECURITY;

-- Tenant owner can manage their own tenant
CREATE POLICY "tenant_owner_all" ON pos_tenants FOR ALL USING (user_id = auth.uid());

-- Users within a tenant can access tenant data
CREATE POLICY "tenant_users_select_outlets" ON pos_outlets FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_outlets" ON pos_outlets FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_categories" ON pos_categories FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_categories" ON pos_categories FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_brands" ON pos_brands FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_brands" ON pos_brands FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_products" ON pos_products FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_products" ON pos_products FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_variants" ON pos_product_variants FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_variants" ON pos_product_variants FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_stock" ON pos_stock FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_stock" ON pos_stock FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_mutations" ON pos_stock_mutations FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_mutations" ON pos_stock_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_customers" ON pos_customers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_customers" ON pos_customers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_suppliers" ON pos_suppliers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_suppliers" ON pos_suppliers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_sales" ON pos_sales FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_sales" ON pos_sales FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_sale_items" ON pos_sale_items FOR SELECT USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
);
CREATE POLICY "tenant_owner_manage_sale_items" ON pos_sale_items FOR ALL USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
);

CREATE POLICY "tenant_owner_manage_held_bills" ON pos_held_bills FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_users_select_held_bills" ON pos_held_bills FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

CREATE POLICY "tenant_users_select_pos_users" ON pos_users FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR user_id = auth.uid()
);
CREATE POLICY "tenant_owner_manage_pos_users" ON pos_users FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

CREATE POLICY "tenant_owner_manage_returns" ON pos_sale_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_owner_manage_return_items" ON pos_sale_return_items FOR ALL USING (
  return_id IN (SELECT id FROM pos_sale_returns WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
);

-- Indexes untuk performa
CREATE INDEX IF NOT EXISTS idx_pos_products_tenant ON pos_products(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_products_category ON pos_products(category_id);
CREATE INDEX IF NOT EXISTS idx_pos_stock_product_outlet ON pos_stock(product_id, outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_sales_tenant_created ON pos_sales(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_sales_outlet ON pos_sales(outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_stock_mutations_product ON pos_stock_mutations(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_customers_tenant ON pos_customers(tenant_id);

-- ===== END SOURCE: 20260508000000_phase1_pos_saas.sql =====

-- ===== BEGIN SOURCE: 20260509000000_phase2_pos_purchase_kas.sql =====
-- Phase 2: POS SaaS — Pembelian & Kas Harian
-- Purchase Orders + Cash Session Management

-- ============================================================
-- PURCHASE ORDERS (Pembelian ke Supplier)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  supplier_id uuid REFERENCES pos_suppliers(id),
  supplier_name text NOT NULL,
  po_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','partial','received','cancelled')),
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  received_date date,
  subtotal numeric(15,2) NOT NULL DEFAULT 0,
  discount_amount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  total numeric(15,2) NOT NULL DEFAULT 0,
  amount_paid numeric(15,2) DEFAULT 0,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id uuid REFERENCES pos_purchase_orders(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  variant_id uuid REFERENCES pos_product_variants(id),
  product_name text NOT NULL,
  sku text,
  unit text DEFAULT 'pcs',
  qty_ordered numeric(15,3) NOT NULL DEFAULT 0,
  qty_received numeric(15,3) DEFAULT 0,
  cost_price numeric(15,2) NOT NULL DEFAULT 0,
  discount numeric(15,2) DEFAULT 0,
  tax_amount numeric(15,2) DEFAULT 0,
  subtotal numeric(15,2) NOT NULL DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- Retur ke Supplier
CREATE TABLE IF NOT EXISTS pos_purchase_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  purchase_order_id uuid REFERENCES pos_purchase_orders(id),
  supplier_name text NOT NULL,
  return_number text NOT NULL,
  return_date date NOT NULL DEFAULT CURRENT_DATE,
  reason text,
  total_amount numeric(15,2) NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_purchase_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_return_id uuid REFERENCES pos_purchase_returns(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id),
  product_name text NOT NULL,
  qty numeric(15,3) NOT NULL,
  cost_price numeric(15,2) NOT NULL,
  subtotal numeric(15,2) NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- KAS HARIAN (Cash Management / Shift)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_cash_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  cashier_id uuid REFERENCES auth.users(id),
  cashier_name text NOT NULL,
  session_number text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','closed')),
  opening_balance numeric(15,2) NOT NULL DEFAULT 0,
  closing_balance numeric(15,2),
  expected_balance numeric(15,2),
  difference numeric(15,2),
  cash_sales_total numeric(15,2) DEFAULT 0,
  non_cash_sales_total numeric(15,2) DEFAULT 0,
  cash_in_total numeric(15,2) DEFAULT 0,
  cash_out_total numeric(15,2) DEFAULT 0,
  notes_open text,
  notes_close text,
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Mutasi kas manual (pemasukan & pengeluaran non-transaksi penjualan)
CREATE TABLE IF NOT EXISTS pos_cash_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  cash_session_id uuid REFERENCES pos_cash_sessions(id),
  type text NOT NULL CHECK (type IN ('in','out')),
  category text NOT NULL DEFAULT 'other',
  amount numeric(15,2) NOT NULL DEFAULT 0,
  description text NOT NULL,
  reference text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- RLS POLICIES
-- ============================================================

ALTER TABLE pos_purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_purchase_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_purchase_return_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_cash_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_cash_mutations ENABLE ROW LEVEL SECURITY;

-- Purchase Orders
CREATE POLICY "tenant_owner_manage_purchase_orders" ON pos_purchase_orders FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_select_purchase_orders" ON pos_purchase_orders FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_owner_manage_po_items" ON pos_purchase_order_items FOR ALL USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);
CREATE POLICY "tenant_users_select_po_items" ON pos_purchase_order_items FOR SELECT USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
);

-- Purchase Returns
CREATE POLICY "tenant_owner_manage_purchase_returns" ON pos_purchase_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_owner_manage_purchase_return_items" ON pos_purchase_return_items FOR ALL USING (
  purchase_return_id IN (
    SELECT id FROM pos_purchase_returns
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);

-- Cash Sessions
CREATE POLICY "tenant_owner_manage_cash_sessions" ON pos_cash_sessions FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_select_cash_sessions" ON pos_cash_sessions FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_users_manage_own_sessions" ON pos_cash_sessions FOR ALL USING (
  cashier_id = auth.uid()
);

-- Cash Mutations
CREATE POLICY "tenant_owner_manage_cash_mutations" ON pos_cash_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_select_cash_mutations" ON pos_cash_mutations FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_users_manage_own_mutations" ON pos_cash_mutations FOR INSERT WITH CHECK (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_tenant ON pos_purchase_orders(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_outlet ON pos_purchase_orders(outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_status ON pos_purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_pos_purchase_orders_supplier ON pos_purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_pos_po_items_po ON pos_purchase_order_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_tenant ON pos_cash_sessions(tenant_id, opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_outlet ON pos_cash_sessions(outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_cash_sessions_status ON pos_cash_sessions(status);
CREATE INDEX IF NOT EXISTS idx_pos_cash_mutations_session ON pos_cash_mutations(cash_session_id);
CREATE INDEX IF NOT EXISTS idx_pos_cash_mutations_tenant ON pos_cash_mutations(tenant_id, created_at DESC);

-- ===== END SOURCE: 20260509000000_phase2_pos_purchase_kas.sql =====

-- ===== BEGIN SOURCE: 20260510000000_phase2_bahan_baku_resep.sql =====
-- Phase 2: Bahan Baku (Raw Materials) & Resep/BOM

-- Tabel Bahan Baku
CREATE TABLE IF NOT EXISTS pos_raw_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  name text NOT NULL,
  unit text NOT NULL DEFAULT 'gram',
  current_stock numeric(15,3) DEFAULT 0,
  min_stock numeric(15,3) DEFAULT 0,
  cost_per_unit numeric(15,4) DEFAULT 0,
  description text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Tabel Resep / Bill of Materials (BOM)
CREATE TABLE IF NOT EXISTS pos_recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) ON DELETE CASCADE NOT NULL,
  raw_material_id uuid REFERENCES pos_raw_materials(id) ON DELETE CASCADE NOT NULL,
  qty_needed numeric(15,4) NOT NULL DEFAULT 0,
  unit text NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(product_id, raw_material_id)
);

-- Tabel Mutasi Bahan Baku
CREATE TABLE IF NOT EXISTS pos_raw_material_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  raw_material_id uuid REFERENCES pos_raw_materials(id) ON DELETE CASCADE NOT NULL,
  type text NOT NULL CHECK (type IN ('initial','purchase','usage','adjustment','waste','return')),
  qty numeric(15,4) NOT NULL,
  qty_before numeric(15,4) DEFAULT 0,
  qty_after numeric(15,4) DEFAULT 0,
  reference_id uuid,
  reference_type text,
  notes text,
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

-- RLS Policies
ALTER TABLE pos_raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_raw_material_mutations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_raw_materials" ON pos_raw_materials
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  );

CREATE POLICY "tenant_recipes" ON pos_recipes
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  );

CREATE POLICY "tenant_raw_material_mutations" ON pos_raw_material_mutations
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_raw_materials_tenant ON pos_raw_materials(tenant_id);
CREATE INDEX IF NOT EXISTS idx_raw_materials_outlet ON pos_raw_materials(outlet_id);
CREATE INDEX IF NOT EXISTS idx_recipes_product ON pos_recipes(product_id);
CREATE INDEX IF NOT EXISTS idx_recipes_material ON pos_recipes(raw_material_id);
CREATE INDEX IF NOT EXISTS idx_raw_mut_material ON pos_raw_material_mutations(raw_material_id);
CREATE INDEX IF NOT EXISTS idx_raw_mut_tenant ON pos_raw_material_mutations(tenant_id);

-- ===== END SOURCE: 20260510000000_phase2_bahan_baku_resep.sql =====

-- ===== BEGIN SOURCE: 20260510000000_phase4_multioutlet_audit.sql =====
-- Phase 4: Multi-outlet & Audit Trail
-- Transfer Stok, Audit Log, Notifikasi, Akses Per Outlet

-- ============================================================
-- TRANSFER STOK ANTAR OUTLET
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  transfer_number text NOT NULL,
  from_outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  to_outlet_id uuid REFERENCES pos_outlets(id) NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending','approved','completed','rejected','cancelled')),
  notes text,
  rejection_reason text,
  requested_by uuid REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  completed_by uuid REFERENCES auth.users(id),
  requested_at timestamptz DEFAULT now(),
  approved_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_stock_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid REFERENCES pos_stock_transfers(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES pos_products(id) NOT NULL,
  variant_id uuid REFERENCES pos_product_variants(id),
  product_name text NOT NULL,
  sku text,
  unit text DEFAULT 'pcs',
  qty_requested numeric(15,3) NOT NULL DEFAULT 0,
  qty_sent numeric(15,3) DEFAULT 0,
  qty_received numeric(15,3) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- AUDIT LOG (Jejak Aktivitas User)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id),
  user_id uuid REFERENCES auth.users(id),
  user_name text,
  action text NOT NULL,
  module text NOT NULL,
  entity_type text,
  entity_id text,
  description text NOT NULL,
  old_values jsonb,
  new_values jsonb,
  ip_address text,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- NOTIFIKASI IN-APP
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id),
  user_id uuid REFERENCES auth.users(id),
  type text NOT NULL DEFAULT 'info'
    CHECK (type IN ('info','warning','error','success')),
  category text NOT NULL DEFAULT 'system',
  title text NOT NULL,
  message text NOT NULL,
  link text,
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- AKSES USER PER OUTLET (granular)
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_user_outlet_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  pos_user_id uuid REFERENCES pos_users(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE NOT NULL,
  role text NOT NULL DEFAULT 'kasir'
    CHECK (role IN ('owner','manager','kasir','staff_gudang','purchasing','finance','auditor')),
  is_active boolean DEFAULT true,
  granted_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(pos_user_id, outlet_id)
);

-- ============================================================
-- RLS POLICIES
-- ============================================================

ALTER TABLE pos_stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_stock_transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_user_outlet_access ENABLE ROW LEVEL SECURITY;

-- Stock Transfers
CREATE POLICY "tenant_owner_manage_transfers" ON pos_stock_transfers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_select_transfers" ON pos_stock_transfers FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_users_create_transfers" ON pos_stock_transfers FOR INSERT WITH CHECK (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

CREATE POLICY "tenant_owner_manage_transfer_items" ON pos_stock_transfer_items FOR ALL USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);
CREATE POLICY "tenant_users_select_transfer_items" ON pos_stock_transfer_items FOR SELECT USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
);

-- Audit Logs (read-only untuk semua, insert untuk semua)
CREATE POLICY "tenant_owner_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
CREATE POLICY "tenant_users_write_audit" ON pos_audit_logs FOR INSERT WITH CHECK (
  tenant_id IN (
    SELECT id FROM pos_tenants WHERE user_id = auth.uid()
    UNION
    SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true
  )
);

-- Notifications
CREATE POLICY "tenant_owner_manage_notif" ON pos_notifications FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "user_own_notif" ON pos_notifications FOR ALL USING (
  user_id = auth.uid()
);

-- User Outlet Access
CREATE POLICY "tenant_owner_manage_access" ON pos_user_outlet_access FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
CREATE POLICY "tenant_users_read_access" ON pos_user_outlet_access FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pos_transfers_tenant ON pos_stock_transfers(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_transfers_from ON pos_stock_transfers(from_outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_transfers_to ON pos_stock_transfers(to_outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_transfers_status ON pos_stock_transfers(status);
CREATE INDEX IF NOT EXISTS idx_pos_transfer_items ON pos_stock_transfer_items(transfer_id);
CREATE INDEX IF NOT EXISTS idx_pos_audit_tenant ON pos_audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_audit_user ON pos_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_pos_audit_module ON pos_audit_logs(module);
CREATE INDEX IF NOT EXISTS idx_pos_notif_user ON pos_notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_pos_notif_tenant ON pos_notifications(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_outlet_access ON pos_user_outlet_access(pos_user_id);
CREATE INDEX IF NOT EXISTS idx_pos_outlet_access_outlet ON pos_user_outlet_access(outlet_id);

-- ===== END SOURCE: 20260510000000_phase4_multioutlet_audit.sql =====

-- ===== BEGIN SOURCE: 20260511000000_phase5_loyalty_promosi.sql =====
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
);

CREATE INDEX IF NOT EXISTS idx_pos_promotions_tenant ON public.pos_promotions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_promotions_active ON public.pos_promotions(tenant_id, is_active);

ALTER TABLE public.pos_promotions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_promotions_tenant_access" ON public.pos_promotions
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

CREATE INDEX IF NOT EXISTS idx_pos_vouchers_tenant ON public.pos_vouchers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_vouchers_code ON public.pos_vouchers(tenant_id, code);

ALTER TABLE public.pos_vouchers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_vouchers_tenant_access" ON public.pos_vouchers
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

ALTER TABLE public.pos_voucher_usages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_voucher_usages_access" ON public.pos_voucher_usages
  USING (voucher_id IN (
    SELECT id FROM public.pos_vouchers
    WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
  ));

-- ============================================================
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
);

ALTER TABLE public.pos_loyalty_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_loyalty_programs_access" ON public.pos_loyalty_programs
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

CREATE INDEX IF NOT EXISTS idx_pos_loyalty_points_tenant ON public.pos_loyalty_points(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_points_customer ON public.pos_loyalty_points(customer_id);

ALTER TABLE public.pos_loyalty_points ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_loyalty_points_access" ON public.pos_loyalty_points
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

CREATE INDEX IF NOT EXISTS idx_pos_loyalty_tx_customer ON public.pos_loyalty_transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_tx_tenant ON public.pos_loyalty_transactions(tenant_id);

ALTER TABLE public.pos_loyalty_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_loyalty_transactions_access" ON public.pos_loyalty_transactions
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
  ADD COLUMN IF NOT EXISTS loyalty_discount NUMERIC DEFAULT 0;

-- Tambah kolom poin ke pos_customers
ALTER TABLE public.pos_customers
  ADD COLUMN IF NOT EXISTS loyalty_points INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS loyalty_tier TEXT DEFAULT 'Bronze';

-- ===== END SOURCE: 20260511000000_phase5_loyalty_promosi.sql =====

-- ===== BEGIN SOURCE: 20260512000000_phase2b_meja_kds.sql =====
-- Phase 2B: Manajemen Meja & Kitchen Display System

-- Tabel Meja Restoran
CREATE TABLE IF NOT EXISTS pos_tables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  name text NOT NULL,
  section text DEFAULT 'Utama',
  capacity int DEFAULT 4,
  status text DEFAULT 'available' CHECK (status IN ('available','occupied','reserved','cleaning')),
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Tabel Pesanan per Meja (antrian dapur)
CREATE TABLE IF NOT EXISTS pos_table_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES pos_tenants(id) ON DELETE CASCADE NOT NULL,
  outlet_id uuid REFERENCES pos_outlets(id) ON DELETE CASCADE,
  table_id uuid REFERENCES pos_tables(id) ON DELETE SET NULL,
  table_name text,
  order_number text NOT NULL,
  status text DEFAULT 'pending' CHECK (status IN ('pending','cooking','ready','served','paid','cancelled')),
  items jsonb NOT NULL DEFAULT '[]',
  notes text,
  customer_name text,
  cashier_name text,
  sale_id uuid REFERENCES pos_sales(id) ON DELETE SET NULL,
  priority int DEFAULT 0,
  cooking_started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE pos_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_table_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_tables" ON pos_tables
  FOR ALL USING (tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()));

CREATE POLICY "tenant_table_orders" ON pos_table_orders
  FOR ALL USING (tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_pos_tables_tenant ON pos_tables(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_tables_outlet ON pos_tables(outlet_id);
CREATE INDEX IF NOT EXISTS idx_pos_table_orders_tenant ON pos_table_orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_table_orders_table ON pos_table_orders(table_id);
CREATE INDEX IF NOT EXISTS idx_pos_table_orders_status ON pos_table_orders(status);

-- Enable realtime for KDS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_table_orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_table_orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pos_tables'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE pos_tables;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260512000000_phase2b_meja_kds.sql =====

-- ===== BEGIN SOURCE: 20260512000000_phase6_marketplace_integration.sql =====
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
);

CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_tenant ON public.pos_marketplace_sync(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_status ON public.pos_marketplace_sync(tenant_id, sync_status);

ALTER TABLE public.pos_marketplace_sync ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_marketplace_sync_access" ON public.pos_marketplace_sync
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

ALTER TABLE public.pos_sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_sync_logs_access" ON public.pos_sync_logs
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

CREATE INDEX IF NOT EXISTS idx_pos_marketplace_orders_tenant ON public.pos_marketplace_orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pos_marketplace_orders_status ON public.pos_marketplace_orders(tenant_id, status);

ALTER TABLE public.pos_marketplace_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_marketplace_orders_access" ON public.pos_marketplace_orders
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ============================================================
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
);

ALTER TABLE public.pos_integration_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pos_integration_settings_access" ON public.pos_integration_settings
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- ===== END SOURCE: 20260512000000_phase6_marketplace_integration.sql =====

-- ===== BEGIN SOURCE: 20260601000000_push_subscriptions.sql =====
-- P2-05: Push Notification — push_subscriptions table
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID NOT NULL,
  endpoint    TEXT NOT NULL UNIQUE,
  p256dh      TEXT,
  auth        TEXT,
  created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage all push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
  ON public.push_subscriptions (user_id);

-- ===== END SOURCE: 20260601000000_push_subscriptions.sql =====

-- ===== BEGIN SOURCE: 20260601000001_api_keys_value.sql =====
-- P4-04: Add key_value column to api_keys table for public API validation
-- The AdminApiKeysPage already manages api_keys table; this adds the hashed key value for server validation.
ALTER TABLE public.api_keys ADD COLUMN IF NOT EXISTS key_value TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_api_keys_key_value ON public.api_keys (key_value) WHERE key_value IS NOT NULL;

-- ===== END SOURCE: 20260601000001_api_keys_value.sql =====

-- ===== BEGIN SOURCE: 20260602000000_merchant_operating_hours.sql =====
-- P3-04: Merchant Operating Hours
-- Tabel jadwal operasional per hari untuk setiap merchant.

CREATE TABLE IF NOT EXISTS public.merchant_operating_hours (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id   uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  day_of_week   smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  -- 0 = Minggu, 1 = Senin, 2 = Selasa, 3 = Rabu, 4 = Kamis, 5 = Jumat, 6 = Sabtu
  open_time     time NOT NULL DEFAULT '08:00:00',
  close_time    time NOT NULL DEFAULT '21:00:00',
  is_closed     boolean NOT NULL DEFAULT false,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now(),
  UNIQUE (merchant_id, day_of_week)
);

ALTER TABLE public.merchant_operating_hours ENABLE ROW LEVEL SECURITY;

-- Merchant bisa baca dan kelola jam operasional miliknya sendiri
CREATE POLICY "merchant_own_hours" ON public.merchant_operating_hours
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- Admin bisa baca semua
CREATE POLICY "admin_read_hours" ON public.merchant_operating_hours
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE user_id = auth.uid() AND role = 'admin')
  );

-- Publik bisa baca (untuk menampilkan jadwal di halaman toko)
CREATE POLICY "public_read_hours" ON public.merchant_operating_hours
  FOR SELECT USING (true);

-- Seed default 7-hari untuk setiap merchant yang sudah ada (opsional, jalankan sekali)
-- INSERT INTO public.merchant_operating_hours (merchant_id, day_of_week)
-- SELECT m.id, d.day FROM public.merchants m CROSS JOIN generate_series(0,6) AS d(day)
-- ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

-- ===== END SOURCE: 20260602000000_merchant_operating_hours.sql =====

-- ===== BEGIN SOURCE: 20260720042853_bb1f350c-f224-41e8-9db8-373c68364801.sql =====
-- ============================================================
-- FILE 01: FOUNDATION & AUTH
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'buyer', 'verifikator', 'merchant', 'courier', 'admin_desa');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  full_name text NOT NULL DEFAULT '',
  email text, phone text, address text, address_detail text, avatar_url text,
  village text, village_id text, village_name text,
  province_id text, province_name text, city_id text, city_name text,
  district_id text, district_name text,
  trust_score integer DEFAULT 100,
  cod_enabled boolean DEFAULT true,
  cod_fail_count integer DEFAULT 0,
  is_verified_buyer boolean DEFAULT false,
  is_blocked boolean DEFAULT false,
  blocked_by uuid, blocked_at timestamptz, block_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'buyer',
  UNIQUE (user_id, role)
);

CREATE TABLE IF NOT EXISTS public.password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  token text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier text NOT NULL,
  action text NOT NULL,
  count integer DEFAULT 1,
  window_start timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  UNIQUE (identifier, action, window_start)
);

CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_email ON public.password_reset_tokens(email);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token ON public.password_reset_tokens(token);

GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.password_reset_tokens TO anon, authenticated;
GRANT ALL ON public.password_reset_tokens TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.rate_limits TO authenticated;
GRANT ALL ON public.rate_limits TO service_role;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.has_any_role(_user_id uuid, _roles public.app_role[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = ANY(_roles))
$$;

CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id uuid)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(array_agg(role::text), ARRAY[]::text[]) FROM public.user_roles WHERE user_id = _user_id
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin')
$$;

CREATE OR REPLACE FUNCTION public.is_merchant()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'merchant') $$;

CREATE OR REPLACE FUNCTION public.is_courier()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'courier') $$;

CREATE OR REPLACE FUNCTION public.is_verifikator()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'verifikator') $$;

CREATE OR REPLACE FUNCTION public.is_admin_desa()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$ SELECT public.has_role(auth.uid(), 'admin_desa') $$;

CREATE OR REPLACE FUNCTION public.check_rate_limit(p_identifier text, p_action text, p_max_requests integer DEFAULT 10, p_window_seconds integer DEFAULT 60)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_window_start timestamptz; v_current_count integer;
BEGIN
  v_window_start := date_trunc('minute', now());
  SELECT count INTO v_current_count FROM public.rate_limits WHERE identifier = p_identifier AND action = p_action AND window_start = v_window_start;
  IF v_current_count IS NULL THEN
    INSERT INTO public.rate_limits (identifier, action, count, window_start) VALUES (p_identifier, p_action, 1, v_window_start)
    ON CONFLICT (identifier, action, window_start) DO UPDATE SET count = rate_limits.count + 1;
    RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - 1);
  END IF;
  IF v_current_count >= p_max_requests THEN RETURN jsonb_build_object('allowed', false, 'remaining', 0, 'retry_after', p_window_seconds); END IF;
  UPDATE public.rate_limits SET count = count + 1 WHERE identifier = p_identifier AND action = p_action AND window_start = v_window_start;
  RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - v_current_count - 1);
END; $$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name, email)
  VALUES (NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email)
  ON CONFLICT (user_id) DO UPDATE SET full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'buyer')
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = user_id AND is_blocked = false);
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
CREATE POLICY "Admins can update any profile" ON public.profiles FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
CREATE POLICY "Admins can view all roles" ON public.user_roles FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles;
CREATE POLICY "Admins can insert user roles" ON public.user_roles FOR INSERT WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles;
CREATE POLICY "Admins can update user roles" ON public.user_roles FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles;
CREATE POLICY "Admins can delete user roles" ON public.user_roles FOR DELETE USING (public.is_admin());

DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens;
CREATE POLICY "Users can verify their tokens" ON public.password_reset_tokens FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens;
CREATE POLICY "Password reset token insert" ON public.password_reset_tokens FOR INSERT TO anon, authenticated WITH CHECK (email IS NOT NULL AND token IS NOT NULL AND expires_at > now());
DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens;
CREATE POLICY "Tokens can be marked as used" ON public.password_reset_tokens FOR UPDATE TO anon, authenticated USING (used_at IS NULL AND expires_at > now());

DROP POLICY IF EXISTS "Rate limits managed by functions" ON public.rate_limits;
CREATE POLICY "Rate limits managed by functions" ON public.rate_limits FOR SELECT USING (identifier = auth.uid()::text OR public.is_admin());
DROP POLICY IF EXISTS "Users can insert own rate limits" ON public.rate_limits;
CREATE POLICY "Users can insert own rate limits" ON public.rate_limits FOR INSERT TO authenticated WITH CHECK (identifier = auth.uid()::text);
DROP POLICY IF EXISTS "Users can update own rate limits" ON public.rate_limits;
CREATE POLICY "Users can update own rate limits" ON public.rate_limits FOR UPDATE TO authenticated USING (identifier = auth.uid()::text);

-- ===== END SOURCE: 20260720042853_bb1f350c-f224-41e8-9db8-373c68364801.sql =====

-- ===== BEGIN SOURCE: 20260720043223_fc91699f-4662-4d5f-93b0-3fb9481b3db0.sql =====
-- Drop overloads that will cause ambiguity when policies call the no-arg form
DROP FUNCTION IF EXISTS public.get_user_courier_id(uuid);
DROP FUNCTION IF EXISTS public.get_user_merchant_id(uuid);

-- Recreate with SINGLE signature (no default arg to avoid overload conflict)
CREATE OR REPLACE FUNCTION public.get_user_merchant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.merchants WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.get_user_courier_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM public.couriers WHERE user_id = auth.uid() LIMIT 1
$$;

-- ===== END SOURCE: 20260720043223_fc91699f-4662-4d5f-93b0-3fb9481b3db0.sql =====

-- ===== BEGIN SOURCE: 20260720043515_16f47887-0a32-4a9d-a579-abb9d2771b97.sql =====
CREATE TABLE IF NOT EXISTS public.villages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, province text,
  district text NOT NULL, regency text NOT NULL, subdistrict text,
  description text, image_url text,
  is_active boolean NOT NULL DEFAULT true,
  location_lat numeric, location_lng numeric,
  contact_name text, contact_phone text, contact_email text,
  registration_status text NOT NULL DEFAULT 'PENDING',
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.user_villages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  role text DEFAULT 'admin_desa',
  created_at timestamptz DEFAULT now(),
  UNIQUE (user_id, village_id)
);
CREATE TABLE IF NOT EXISTS public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL, slug text NOT NULL UNIQUE,
  description text, icon text,
  is_active boolean DEFAULT true, sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.trade_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  verifikator_id uuid NOT NULL,
  monthly_fee integer NOT NULL DEFAULT 10000,
  description text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.transaction_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  classification_price text NOT NULL DEFAULT '',
  price_per_transaction integer NOT NULL DEFAULT 0,
  total_price integer NOT NULL DEFAULT 0,
  group_commission_percent numeric NOT NULL DEFAULT 5,
  kas_fee numeric(5,2) DEFAULT 0,
  transaction_quota integer NOT NULL DEFAULT 100,
  total_credits integer NOT NULL DEFAULT 100,
  validity_days integer NOT NULL DEFAULT 30,
  description text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  min_price integer NOT NULL DEFAULT 0, max_price integer,
  credit_cost integer NOT NULL DEFAULT 1,
  description text, is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.tourism (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL, description text, image_url text,
  location_lat numeric, location_lng numeric,
  wa_link text, sosmed_link text,
  facilities text[] DEFAULT '{}',
  is_active boolean NOT NULL DEFAULT true,
  view_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.merchants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, address text, phone text,
  province text, city text, district text, subdistrict text,
  village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  image_url text, cover_image_url text, ktp_url text, slug text,
  business_category text DEFAULT 'kuliner',
  business_description text, classification_price text,
  trade_group text, verifikator_code text,
  open_time time, close_time time,
  is_open boolean NOT NULL DEFAULT true,
  order_mode text NOT NULL DEFAULT 'ADMIN_ASSISTED',
  status text NOT NULL DEFAULT 'ACTIVE',
  registration_status text NOT NULL DEFAULT 'PENDING',
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  badge text, rating_avg numeric DEFAULT 0, rating_count integer DEFAULT 0,
  is_verified boolean DEFAULT false, verified_at timestamptz, verified_by uuid,
  verifikator_id uuid,
  group_id uuid REFERENCES public.trade_groups(id) ON DELETE SET NULL,
  current_subscription_id uuid,
  location_lat numeric, location_lng numeric,
  qris_image_url text,
  payment_cod_enabled boolean DEFAULT true,
  payment_transfer_enabled boolean DEFAULT true,
  cod_max_amount integer DEFAULT 75000,
  cod_max_distance_km numeric DEFAULT 3,
  bank_name text, bank_account_number text, bank_account_name text,
  available_balance integer DEFAULT 0, pending_balance integer DEFAULT 0,
  total_withdrawn integer DEFAULT 0,
  halal_certificate_url text, halal_status text DEFAULT 'NONE',
  notification_sound_enabled boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_slug ON public.merchants(slug) WHERE slug IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.merchant_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id uuid NOT NULL REFERENCES public.transaction_packages(id),
  transaction_quota integer NOT NULL DEFAULT 0,
  used_quota integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'ACTIVE',
  payment_status text NOT NULL DEFAULT 'UNPAID',
  payment_amount integer NOT NULL DEFAULT 0,
  paid_at timestamptz,
  started_at timestamptz NOT NULL DEFAULT now(),
  expired_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
DO $$ BEGIN
  ALTER TABLE public.merchants
    ADD CONSTRAINT merchants_current_subscription_id_fkey
    FOREIGN KEY (current_subscription_id) REFERENCES public.merchant_subscriptions(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
CREATE TABLE IF NOT EXISTS public.merchant_gallery (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  image_url text NOT NULL, caption text, sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.merchant_favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, merchant_id)
);
CREATE TABLE IF NOT EXISTS public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'ACTIVE',
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, merchant_id)
);
CREATE TABLE IF NOT EXISTS public.kas_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  amount integer NOT NULL,
  payment_month integer NOT NULL, payment_year integer NOT NULL,
  status text NOT NULL DEFAULT 'UNPAID',
  payment_date timestamptz, collected_by uuid,
  notes text, invoice_note text, sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, merchant_id, payment_month, payment_year)
);
CREATE TABLE IF NOT EXISTS public.group_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES public.trade_groups(id),
  verifikator_id uuid, title text NOT NULL, message text NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.verifikator_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  code text NOT NULL UNIQUE,
  trade_group text NOT NULL, description text,
  is_active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0, max_usage integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.verifikator_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id),
  package_id uuid NOT NULL REFERENCES public.transaction_packages(id),
  package_amount integer NOT NULL,
  commission_percent numeric NOT NULL,
  commission_amount integer NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.verifikator_withdrawals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  amount integer NOT NULL,
  bank_name text NOT NULL, account_number text NOT NULL, account_holder text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  admin_notes text, proof_image_url text,
  processed_by uuid, processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.couriers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid, name text NOT NULL, phone text NOT NULL, email text,
  province text NOT NULL, city text NOT NULL, district text NOT NULL,
  subdistrict text NOT NULL, address text NOT NULL,
  ktp_number text NOT NULL, ktp_image_url text NOT NULL, photo_url text NOT NULL,
  vehicle_type text NOT NULL DEFAULT 'motor',
  vehicle_plate text, vehicle_image_url text NOT NULL,
  village_id uuid REFERENCES public.villages(id),
  status text NOT NULL DEFAULT 'INACTIVE',
  registration_status text NOT NULL DEFAULT 'PENDING',
  is_available boolean NOT NULL DEFAULT false,
  current_lat numeric, current_lng numeric, last_location_update timestamptz,
  registered_at timestamptz DEFAULT now(),
  approved_at timestamptz, approved_by uuid, rejection_reason text,
  bank_name text, bank_account_name text, bank_account_number text,
  available_balance numeric DEFAULT 0, pending_balance numeric DEFAULT 0,
  total_withdrawn numeric DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.courier_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid, amount integer NOT NULL DEFAULT 0,
  type text NOT NULL DEFAULT 'DELIVERY',
  status text NOT NULL DEFAULT 'PENDING',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.courier_withdrawal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id),
  amount numeric NOT NULL,
  bank_name text NOT NULL, account_number text NOT NULL, account_holder text NOT NULL,
  status text DEFAULT 'PENDING', admin_notes text,
  processed_by uuid, processed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.courier_deposits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  amount numeric NOT NULL DEFAULT 0, proof_url text,
  status text NOT NULL DEFAULT 'PENDING',
  admin_notes text, approved_by uuid, processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.courier_balance_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid, type text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  balance_before numeric NOT NULL DEFAULT 0,
  balance_after numeric NOT NULL DEFAULT 0,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_merchants_location ON public.merchants(location_lat, location_lng);
CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_code ON public.merchants(verifikator_code);
CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_merchant ON public.merchant_subscriptions(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_status ON public.merchant_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_merchant_gallery_merchant ON public.merchant_gallery(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_favorites_user ON public.merchant_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_merchant_favorites_merchant ON public.merchant_favorites(merchant_id);
CREATE INDEX IF NOT EXISTS idx_courier_deposits_courier ON public.courier_deposits(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_balance_logs_courier ON public.courier_balance_logs(courier_id);

GRANT SELECT ON public.villages TO anon;
GRANT SELECT, INSERT, UPDATE ON public.villages TO authenticated;
GRANT ALL ON public.villages TO service_role;
GRANT SELECT, INSERT ON public.user_villages TO authenticated;
GRANT ALL ON public.user_villages TO service_role;
GRANT SELECT ON public.categories TO anon, authenticated;
GRANT ALL ON public.categories TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.trade_groups TO authenticated;
GRANT ALL ON public.trade_groups TO service_role;
GRANT SELECT ON public.transaction_packages TO anon, authenticated;
GRANT ALL ON public.transaction_packages TO service_role;
GRANT SELECT ON public.quota_tiers TO anon, authenticated;
GRANT ALL ON public.quota_tiers TO service_role;
GRANT SELECT ON public.tourism TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tourism TO authenticated;
GRANT ALL ON public.tourism TO service_role;
GRANT SELECT ON public.merchants TO anon;
GRANT SELECT, INSERT, UPDATE ON public.merchants TO authenticated;
GRANT ALL ON public.merchants TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.merchant_subscriptions TO authenticated;
GRANT ALL ON public.merchant_subscriptions TO service_role;
GRANT SELECT ON public.merchant_gallery TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.merchant_gallery TO authenticated;
GRANT ALL ON public.merchant_gallery TO service_role;
GRANT SELECT, INSERT, DELETE ON public.merchant_favorites TO authenticated;
GRANT ALL ON public.merchant_favorites TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.group_members TO authenticated;
GRANT ALL ON public.group_members TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.kas_payments TO authenticated;
GRANT ALL ON public.kas_payments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.group_announcements TO authenticated;
GRANT ALL ON public.group_announcements TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.verifikator_codes TO authenticated;
GRANT ALL ON public.verifikator_codes TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.verifikator_earnings TO authenticated;
GRANT ALL ON public.verifikator_earnings TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.verifikator_withdrawals TO authenticated;
GRANT ALL ON public.verifikator_withdrawals TO service_role;
GRANT SELECT ON public.couriers TO anon, authenticated;
GRANT INSERT, UPDATE ON public.couriers TO authenticated;
GRANT ALL ON public.couriers TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.courier_earnings TO authenticated;
GRANT ALL ON public.courier_earnings TO service_role;
GRANT SELECT, INSERT ON public.courier_withdrawal_requests TO authenticated;
GRANT ALL ON public.courier_withdrawal_requests TO service_role;
GRANT SELECT, INSERT ON public.courier_deposits TO authenticated;
GRANT ALL ON public.courier_deposits TO service_role;
GRANT SELECT ON public.courier_balance_logs TO authenticated;
GRANT ALL ON public.courier_balance_logs TO service_role;

ALTER TABLE public.villages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_villages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trade_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_gallery ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kas_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verifikator_withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_balance_logs ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_courier_owner(_user_id uuid, _courier_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.couriers WHERE id = _courier_id AND user_id = _user_id)
$$;

CREATE OR REPLACE FUNCTION public.generate_merchant_slug(merchant_name text)
RETURNS text LANGUAGE plpgsql SET search_path = public AS $$
DECLARE base_slug text; final_slug text; counter integer := 0;
BEGIN
  base_slug := lower(regexp_replace(merchant_name, '[^a-zA-Z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  final_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM public.merchants WHERE slug = final_slug) LOOP
    counter := counter + 1;
    final_slug := base_slug || '-' || counter;
  END LOOP;
  RETURN final_slug;
END; $$;

CREATE OR REPLACE FUNCTION public.get_quota_cost(product_price integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(
    (SELECT credit_cost FROM public.quota_tiers
     WHERE is_active = true AND product_price >= min_price
       AND (max_price IS NULL OR product_price <= max_price)
     ORDER BY min_price DESC LIMIT 1), 1)
$$;

CREATE OR REPLACE FUNCTION public.calculate_quota_cost(p_product_price integer)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v_cost integer;
BEGIN
  SELECT credit_cost INTO v_cost FROM public.quota_tiers
  WHERE p_product_price >= min_price
    AND (max_price IS NULL OR p_product_price <= max_price)
    AND is_active = true
  ORDER BY min_price DESC LIMIT 1;
  RETURN COALESCE(v_cost, 1);
END; $$;

CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_subscription RECORD;
BEGIN
  SELECT * INTO v_subscription FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now() AND used_quota < transaction_quota
  ORDER BY expired_at DESC LIMIT 1;
  IF v_subscription IS NULL THEN
    RETURN jsonb_build_object('can_transact', false, 'reason', 'Tidak ada kuota transaksi aktif.', 'remaining_quota', 0);
  END IF;
  RETURN jsonb_build_object('can_transact', true,
    'remaining_quota', v_subscription.transaction_quota - v_subscription.used_quota,
    'subscription_id', v_subscription.id);
END; $$;

CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.merchant_subscriptions SET used_quota = used_quota + 1, updated_at = now()
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now() AND used_quota < transaction_quota;
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION public.deduct_merchant_quota(p_merchant_id uuid, p_credits integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_sub_id uuid;
BEGIN
  SELECT id INTO v_sub_id FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC LIMIT 1;
  IF v_sub_id IS NULL THEN RETURN FALSE; END IF;
  UPDATE public.merchant_subscriptions SET used_quota = used_quota + p_credits, updated_at = now() WHERE id = v_sub_id;
  RETURN TRUE;
END; $$;

CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_code RECORD; v_group RECORD;
BEGIN
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    SELECT * INTO v_code FROM public.verifikator_codes WHERE code = NEW.verifikator_code AND is_active = true LIMIT 1;
    IF v_code IS NOT NULL THEN
      SELECT * INTO v_group FROM public.trade_groups WHERE verifikator_id = v_code.verifikator_id AND is_active = true LIMIT 1;
      IF v_group IS NOT NULL THEN
        NEW.group_id := v_group.id;
        INSERT INTO public.group_members (group_id, merchant_id, status)
        VALUES (v_group.id, NEW.id, 'ACTIVE') ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.generate_monthly_kas(p_group_id uuid, p_month integer, p_year integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_group RECORD; v_member RECORD; v_count integer := 0;
BEGIN
  SELECT * INTO v_group FROM public.trade_groups WHERE id = p_group_id;
  IF v_group IS NULL THEN RETURN 0; END IF;
  FOR v_member IN SELECT * FROM public.group_members WHERE group_id = p_group_id AND status = 'ACTIVE' LOOP
    INSERT INTO public.kas_payments (group_id, merchant_id, amount, payment_month, payment_year, status)
    VALUES (p_group_id, v_member.merchant_id, v_group.monthly_fee, p_month, p_year, 'UNPAID')
    ON CONFLICT (group_id, merchant_id, payment_month, payment_year) DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.record_verifikator_commission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_merchant RECORD; v_package RECORD; v_commission integer;
BEGIN
  IF NEW.payment_status = 'PAID' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'PAID') THEN
    SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
    IF v_merchant.verifikator_id IS NOT NULL THEN
      SELECT * INTO v_package FROM public.transaction_packages WHERE id = NEW.package_id;
      v_commission := FLOOR(NEW.payment_amount * v_package.group_commission_percent / 100);
      IF v_commission > 0 THEN
        INSERT INTO public.verifikator_earnings (verifikator_id, merchant_id, subscription_id, package_id,
          package_amount, commission_percent, commission_amount, status)
        VALUES (v_merchant.verifikator_id, NEW.merchant_id, NEW.id, NEW.package_id,
          NEW.payment_amount, v_package.group_commission_percent, v_commission, 'PENDING');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.process_verifikator_withdrawal(p_withdrawal_id uuid, p_status text, p_admin_notes text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_withdrawal RECORD; v_total_pending integer;
BEGIN
  SELECT * INTO v_withdrawal FROM public.verifikator_withdrawals WHERE id = p_withdrawal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal not found'; END IF;
  IF v_withdrawal.status != 'PENDING' THEN RAISE EXCEPTION 'Already processed'; END IF;
  IF p_status = 'APPROVED' THEN
    SELECT COALESCE(SUM(commission_amount), 0) INTO v_total_pending
    FROM public.verifikator_earnings WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING';
    IF v_total_pending < v_withdrawal.amount THEN RAISE EXCEPTION 'Insufficient balance'; END IF;
    WITH earnings_to_pay AS (
      SELECT id, commission_amount, SUM(commission_amount) OVER (ORDER BY created_at) AS running_total
      FROM public.verifikator_earnings WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING'
      ORDER BY created_at
    ) UPDATE public.verifikator_earnings SET status = 'PAID', paid_at = now()
      WHERE id IN (SELECT id FROM earnings_to_pay WHERE running_total <= v_withdrawal.amount);
  END IF;
  UPDATE public.verifikator_withdrawals
  SET status = p_status, admin_notes = p_admin_notes, processed_by = auth.uid(), processed_at = now(), updated_at = now()
  WHERE id = p_withdrawal_id;
  RETURN TRUE;
END; $$;

CREATE OR REPLACE FUNCTION public.approve_quota_subscription(p_subscription_id uuid, p_admin_notes text DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sub RECORD;
BEGIN
  SELECT * INTO v_sub FROM public.merchant_subscriptions WHERE id = p_subscription_id;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'message', 'Subscription tidak ditemukan'); END IF;
  IF v_sub.payment_status = 'PAID' AND v_sub.status = 'ACTIVE' THEN
    RETURN json_build_object('success', false, 'message', 'Subscription sudah aktif');
  END IF;
  UPDATE public.merchant_subscriptions SET status='ACTIVE', payment_status='PAID', paid_at=now(), updated_at=now() WHERE id = p_subscription_id;
  UPDATE public.merchants SET current_subscription_id = p_subscription_id, updated_at=now() WHERE id = v_sub.merchant_id;
  RETURN json_build_object('success', true, 'message', 'Subscription berhasil disetujui dan diaktifkan');
END; $$;

CREATE OR REPLACE FUNCTION public.reject_quota_subscription(p_subscription_id uuid, p_admin_notes text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_admin_notes IS NULL OR p_admin_notes = '' THEN
    RETURN json_build_object('success', false, 'message', 'Catatan admin wajib diisi saat menolak');
  END IF;
  UPDATE public.merchant_subscriptions SET status='INACTIVE', payment_status='REJECTED', updated_at=now() WHERE id = p_subscription_id;
  RETURN json_build_object('success', true, 'message', 'Subscription berhasil ditolak');
END; $$;

DROP TRIGGER IF EXISTS update_villages_updated_at ON public.villages;
CREATE TRIGGER update_villages_updated_at BEFORE UPDATE ON public.villages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_merchants_updated_at ON public.merchants;
CREATE TRIGGER update_merchants_updated_at BEFORE UPDATE ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_merchant_subscriptions_updated_at ON public.merchant_subscriptions;
CREATE TRIGGER update_merchant_subscriptions_updated_at BEFORE UPDATE ON public.merchant_subscriptions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_couriers_updated_at ON public.couriers;
CREATE TRIGGER update_couriers_updated_at BEFORE UPDATE ON public.couriers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_trade_groups_updated_at ON public.trade_groups;
CREATE TRIGGER update_trade_groups_updated_at BEFORE UPDATE ON public.trade_groups FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_transaction_packages_updated_at ON public.transaction_packages;
CREATE TRIGGER update_transaction_packages_updated_at BEFORE UPDATE ON public.transaction_packages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_quota_tiers_updated_at ON public.quota_tiers;
CREATE TRIGGER update_quota_tiers_updated_at BEFORE UPDATE ON public.quota_tiers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_kas_payments_updated_at ON public.kas_payments;
CREATE TRIGGER update_kas_payments_updated_at BEFORE UPDATE ON public.kas_payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants;
CREATE TRIGGER trigger_auto_assign_merchant_group BEFORE INSERT OR UPDATE ON public.merchants FOR EACH ROW EXECUTE FUNCTION public.auto_assign_merchant_to_group();
DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON public.merchant_subscriptions;
CREATE TRIGGER trigger_record_verifikator_commission AFTER INSERT OR UPDATE ON public.merchant_subscriptions FOR EACH ROW EXECUTE FUNCTION public.record_verifikator_commission();

DROP VIEW IF EXISTS public.public_merchants CASCADE;
CREATE VIEW public.public_merchants WITH (security_invoker=on) AS
SELECT id, name, image_url, business_category, business_description, village_id,
  CASE WHEN phone IS NOT NULL THEN CONCAT('****', RIGHT(phone, 4)) END AS phone_masked,
  city, district, province,
  CASE WHEN location_lat IS NOT NULL THEN ROUND(location_lat::numeric, 2) END AS location_lat_approx,
  CASE WHEN location_lng IS NOT NULL THEN ROUND(location_lng::numeric, 2) END AS location_lng_approx,
  is_open, open_time, close_time, rating_avg, rating_count, is_verified, badge, order_mode
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

DROP VIEW IF EXISTS public.public_couriers CASCADE;
CREATE VIEW public.public_couriers WITH (security_invoker=on) AS
SELECT id, name,
  CASE WHEN phone IS NOT NULL THEN CONCAT('****', RIGHT(phone, 4)) END AS phone_masked,
  photo_url, vehicle_type,
  CASE WHEN current_lat IS NOT NULL THEN ROUND(current_lat, 3) END AS current_lat_approx,
  CASE WHEN current_lng IS NOT NULL THEN ROUND(current_lng, 3) END AS current_lng_approx,
  is_available, status, village_id
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

GRANT SELECT ON public.public_merchants TO anon, authenticated;
GRANT SELECT ON public.public_couriers TO anon, authenticated;

DROP POLICY IF EXISTS "Anyone can view active villages" ON public.villages;
CREATE POLICY "Anyone can view active villages" ON public.villages FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Authenticated users can register village" ON public.villages;
CREATE POLICY "Authenticated users can register village" ON public.villages FOR INSERT TO authenticated WITH CHECK (registration_status = 'PENDING' AND is_active = false);
DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages;
CREATE POLICY "Admins can manage villages" ON public.villages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Village owners can update own village" ON public.villages;
CREATE POLICY "Village owners can update own village" ON public.villages FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Admin desa can update own village" ON public.villages;
CREATE POLICY "Admin desa can update own village" ON public.villages FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = villages.id AND uv.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins manage village assignments" ON public.user_villages;
CREATE POLICY "Admins manage village assignments" ON public.user_villages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages;
CREATE POLICY "Users view own village assignments" ON public.user_villages FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Users can register own village assignment" ON public.user_villages;
CREATE POLICY "Users can register own village assignment" ON public.user_villages FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Anyone can view active categories" ON public.categories;
CREATE POLICY "Anyone can view active categories" ON public.categories FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories;
CREATE POLICY "Admins can manage categories" ON public.categories FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active groups" ON public.trade_groups;
CREATE POLICY "Anyone can view active groups" ON public.trade_groups FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage all groups" ON public.trade_groups;
CREATE POLICY "Admins can manage all groups" ON public.trade_groups FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikators can manage own groups" ON public.trade_groups;
CREATE POLICY "Verifikators can manage own groups" ON public.trade_groups FOR ALL USING (verifikator_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active packages" ON public.transaction_packages;
CREATE POLICY "Anyone can view active packages" ON public.transaction_packages FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage packages" ON public.transaction_packages;
CREATE POLICY "Admins can manage packages" ON public.transaction_packages FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Anyone can view quota tiers" ON public.quota_tiers;
CREATE POLICY "Anyone can view quota tiers" ON public.quota_tiers FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins can manage quota tiers" ON public.quota_tiers;
CREATE POLICY "Admins can manage quota tiers" ON public.quota_tiers FOR ALL TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active tourism" ON public.tourism;
CREATE POLICY "Anyone can view active tourism" ON public.tourism FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage tourism" ON public.tourism;
CREATE POLICY "Admins can manage tourism" ON public.tourism FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Admin desa can manage tourism" ON public.tourism;
CREATE POLICY "Admin desa can manage tourism" ON public.tourism FOR ALL USING (EXISTS (SELECT 1 FROM public.villages WHERE villages.id = tourism.village_id AND villages.registration_status = 'APPROVED') AND public.is_admin_desa()) WITH CHECK (EXISTS (SELECT 1 FROM public.villages WHERE villages.id = tourism.village_id AND villages.registration_status = 'APPROVED') AND public.is_admin_desa());

DROP POLICY IF EXISTS "Admins can manage merchants" ON public.merchants;
CREATE POLICY "Admins can manage merchants" ON public.merchants FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants;
CREATE POLICY "Verifikator can manage merchants" ON public.merchants FOR ALL USING (public.is_verifikator());
DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants;
CREATE POLICY "Merchants can update own data" ON public.merchants FOR UPDATE USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Anyone can register merchant" ON public.merchants;
CREATE POLICY "Anyone can register merchant" ON public.merchants FOR INSERT WITH CHECK (registration_status = 'PENDING');
DROP POLICY IF EXISTS "Authenticated users view active merchants" ON public.merchants;
CREATE POLICY "Authenticated users view active merchants" ON public.merchants FOR SELECT USING ((user_id = auth.uid()) OR ((status = 'ACTIVE' AND registration_status = 'APPROVED' AND auth.uid() IS NOT NULL)) OR public.is_admin() OR public.is_verifikator());
DROP POLICY IF EXISTS "Anon can view basic merchant info" ON public.merchants;
CREATE POLICY "Anon can view basic merchant info" ON public.merchants FOR SELECT TO anon USING (status = 'ACTIVE' AND registration_status = 'APPROVED');

DROP POLICY IF EXISTS "Admins can manage all subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Admins can manage all subscriptions" ON public.merchant_subscriptions FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can view own subscriptions" ON public.merchant_subscriptions FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_subscriptions.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can create subscriptions" ON public.merchant_subscriptions FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Public can view merchant gallery" ON public.merchant_gallery;
CREATE POLICY "Public can view merchant gallery" ON public.merchant_gallery FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_gallery.merchant_id AND merchants.status='ACTIVE' AND merchants.registration_status='APPROVED'));
DROP POLICY IF EXISTS "Merchants can manage own gallery" ON public.merchant_gallery;
CREATE POLICY "Merchants can manage own gallery" ON public.merchant_gallery FOR ALL USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = merchant_gallery.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins can manage all galleries" ON public.merchant_gallery;
CREATE POLICY "Admins can manage all galleries" ON public.merchant_gallery FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Users can view their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can view their own favorites" ON public.merchant_favorites FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can insert their own favorites" ON public.merchant_favorites FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can delete their own favorites" ON public.merchant_favorites FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can manage all members" ON public.group_members;
CREATE POLICY "Admins can manage all members" ON public.group_members FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own membership" ON public.group_members;
CREATE POLICY "Merchants can view own membership" ON public.group_members FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = group_members.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Verifikators can manage group members" ON public.group_members;
CREATE POLICY "Verifikators can manage group members" ON public.group_members FOR ALL USING (EXISTS (SELECT 1 FROM public.trade_groups WHERE trade_groups.id = group_members.group_id AND (trade_groups.verifikator_id = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS "Admins can manage all payments" ON public.kas_payments;
CREATE POLICY "Admins can manage all payments" ON public.kas_payments FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own payments" ON public.kas_payments;
CREATE POLICY "Merchants can view own payments" ON public.kas_payments FOR SELECT USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = kas_payments.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Verifikators can manage payments in their groups" ON public.kas_payments;
CREATE POLICY "Verifikators can manage payments in their groups" ON public.kas_payments FOR ALL USING (EXISTS (SELECT 1 FROM public.trade_groups WHERE trade_groups.id = kas_payments.group_id AND (trade_groups.verifikator_id = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS "Verifikator can manage own announcements" ON public.group_announcements;
CREATE POLICY "Verifikator can manage own announcements" ON public.group_announcements FOR ALL USING (verifikator_id = auth.uid());
DROP POLICY IF EXISTS "Group members can read announcements" ON public.group_announcements;
CREATE POLICY "Group members can read announcements" ON public.group_announcements FOR SELECT USING (EXISTS (SELECT 1 FROM public.group_members gm JOIN public.merchants m ON m.id = gm.merchant_id WHERE gm.group_id = group_announcements.group_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view active codes" ON public.verifikator_codes;
CREATE POLICY "Anyone can view active codes" ON public.verifikator_codes FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admin can manage all codes" ON public.verifikator_codes;
CREATE POLICY "Admin can manage all codes" ON public.verifikator_codes FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikator can manage own codes" ON public.verifikator_codes;
CREATE POLICY "Verifikator can manage own codes" ON public.verifikator_codes FOR ALL USING (verifikator_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Admins can manage all earnings" ON public.verifikator_earnings;
CREATE POLICY "Admins can manage all earnings" ON public.verifikator_earnings FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikators can view own earnings" ON public.verifikator_earnings;
CREATE POLICY "Verifikators can view own earnings" ON public.verifikator_earnings FOR SELECT USING (verifikator_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Admins manage withdrawals" ON public.verifikator_withdrawals FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators can create withdrawals" ON public.verifikator_withdrawals FOR INSERT WITH CHECK (verifikator_id = auth.uid() AND status = 'PENDING');
DROP POLICY IF EXISTS "Verifikators view own withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators view own withdrawals" ON public.verifikator_withdrawals FOR SELECT USING (verifikator_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
CREATE POLICY "Admins can manage couriers" ON public.couriers FOR ALL TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;
CREATE POLICY "Verifikator can manage couriers" ON public.couriers FOR ALL TO authenticated USING (public.is_verifikator());
DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
CREATE POLICY "Anyone can register as courier" ON public.couriers FOR INSERT TO authenticated WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');
DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
CREATE POLICY "Couriers can view own data" ON public.couriers FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
CREATE POLICY "Couriers can update own location" ON public.couriers FOR UPDATE TO authenticated USING (user_id = auth.uid() AND status = 'ACTIVE');
DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers;
CREATE POLICY "Public can view approved couriers" ON public.couriers FOR SELECT USING (registration_status = 'APPROVED' AND status = 'ACTIVE');

DROP POLICY IF EXISTS "Admins can manage courier earnings" ON public.courier_earnings;
CREATE POLICY "Admins can manage courier earnings" ON public.courier_earnings FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Couriers can view own earnings" ON public.courier_earnings;
CREATE POLICY "Couriers can view own earnings" ON public.courier_earnings FOR SELECT USING (EXISTS (SELECT 1 FROM public.couriers WHERE couriers.id = courier_earnings.courier_id AND couriers.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins full access courier withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Admins full access courier withdrawals" ON public.courier_withdrawal_requests FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Couriers can view own withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Couriers can view own withdrawals" ON public.courier_withdrawal_requests FOR SELECT USING (courier_id = public.get_user_courier_id());
DROP POLICY IF EXISTS "Couriers can create own withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Couriers can create own withdrawals" ON public.courier_withdrawal_requests FOR INSERT WITH CHECK (courier_id = public.get_user_courier_id());

DROP POLICY IF EXISTS "Couriers can view own deposits" ON public.courier_deposits;
CREATE POLICY "Couriers can view own deposits" ON public.courier_deposits FOR SELECT USING (courier_id = public.get_user_courier_id());
DROP POLICY IF EXISTS "Couriers can create own deposits" ON public.courier_deposits;
CREATE POLICY "Couriers can create own deposits" ON public.courier_deposits FOR INSERT WITH CHECK (courier_id = public.get_user_courier_id());
DROP POLICY IF EXISTS "Admins full access courier deposits" ON public.courier_deposits;
CREATE POLICY "Admins full access courier deposits" ON public.courier_deposits FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Couriers can view own balance logs" ON public.courier_balance_logs;
CREATE POLICY "Couriers can view own balance logs" ON public.courier_balance_logs FOR SELECT USING (courier_id = public.get_user_courier_id());
DROP POLICY IF EXISTS "Admins full access balance logs" ON public.courier_balance_logs;
CREATE POLICY "Admins full access balance logs" ON public.courier_balance_logs FOR ALL USING (public.is_admin());

-- ===== END SOURCE: 20260720043515_16f47887-0a32-4a9d-a579-abb9d2771b97.sql =====

-- ===== BEGIN SOURCE: 20260723060205_ff87f8be-ac0e-4efd-8098-7efd39797d2f.sql =====
-- Add missing columns to existing tables so policies compile

ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id);
ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS refund_type text DEFAULT 'FULL';
ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS evidence_urls text[] DEFAULT '{}';

-- Tables (idempotent)
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name text NOT NULL, description text, price integer NOT NULL,
  stock integer NOT NULL DEFAULT 0, category text NOT NULL, image_url text,
  is_active boolean NOT NULL DEFAULT true, is_promo boolean NOT NULL DEFAULT false,
  discount_percent integer DEFAULT 0, discount_end_date timestamptz,
  min_stock_alert integer DEFAULT 5, low_stock_threshold integer DEFAULT 5,
  view_count integer DEFAULT 0, order_count integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.product_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url text NOT NULL, is_primary boolean DEFAULT false,
  sort_order integer DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name text NOT NULL, price_adjustment integer DEFAULT 0, stock integer DEFAULT 0,
  sku text, is_active boolean DEFAULT true, sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_buyer ON public.orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant ON public.orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON public.orders(courier_id);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON public.product_images(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_flash_sales_merchant ON public.flash_sales(merchant_id);
CREATE INDEX IF NOT EXISTS idx_flash_sales_status_end ON public.flash_sales(status, end_time);
CREATE INDEX IF NOT EXISTS idx_ride_requests_passenger ON public.ride_requests(passenger_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_driver ON public.ride_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON public.ride_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant ON public.refund_requests(merchant_id);

-- Grants
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT ALL ON public.products TO service_role;
GRANT SELECT ON public.product_images TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_images TO authenticated;
GRANT ALL ON public.product_images TO service_role;
GRANT SELECT ON public.product_variants TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_variants TO authenticated;
GRANT ALL ON public.product_variants TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;
GRANT SELECT, INSERT ON public.order_items TO authenticated;
GRANT ALL ON public.order_items TO service_role;
GRANT SELECT ON public.flash_sales TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.flash_sales TO authenticated;
GRANT ALL ON public.flash_sales TO service_role;
GRANT SELECT ON public.reviews TO anon, authenticated;
GRANT INSERT, UPDATE ON public.reviews TO authenticated;
GRANT ALL ON public.reviews TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.refund_requests TO authenticated;
GRANT ALL ON public.refund_requests TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.withdrawal_requests TO authenticated;
GRANT ALL ON public.withdrawal_requests TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.platform_fees TO authenticated;
GRANT ALL ON public.platform_fees TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.insurance_fund TO authenticated;
GRANT ALL ON public.insurance_fund TO service_role;
GRANT SELECT ON public.vouchers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.vouchers TO authenticated;
GRANT ALL ON public.vouchers TO service_role;
GRANT SELECT, INSERT ON public.voucher_usages TO authenticated;
GRANT ALL ON public.voucher_usages TO service_role;
GRANT SELECT ON public.promotions TO anon, authenticated;
GRANT INSERT, UPDATE ON public.promotions TO authenticated;
GRANT ALL ON public.promotions TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.ride_requests TO authenticated;
GRANT ALL ON public.ride_requests TO service_role;

-- Enable RLS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flash_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_fund ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voucher_usages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

-- Helpers
CREATE OR REPLACE FUNCTION public.is_order_merchant(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = _order_id AND m.user_id = auth.uid()) $$;
CREATE OR REPLACE FUNCTION public.is_order_courier(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = _order_id AND c.user_id = auth.uid()) $$;

-- Triggers
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_reviews_updated_at ON public.reviews;
CREATE TRIGGER update_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON public.refund_requests;
CREATE TRIGGER update_refund_requests_updated_at BEFORE UPDATE ON public.refund_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_ride_requests_updated_at ON public.ride_requests;
CREATE TRIGGER update_ride_requests_updated_at BEFORE UPDATE ON public.ride_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Policies
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products;
CREATE POLICY "Anyone can view active products" ON public.products FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
CREATE POLICY "Admins can manage products" ON public.products FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage own products" ON public.products;
CREATE POLICY "Merchants can manage own products" ON public.products FOR ALL
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view product images" ON public.product_images;
CREATE POLICY "Anyone can view product images" ON public.product_images FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins can manage all product images" ON public.product_images;
CREATE POLICY "Admins can manage all product images" ON public.product_images FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their product images" ON public.product_images;
CREATE POLICY "Merchants can manage their product images" ON public.product_images FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_images.product_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view active product variants" ON public.product_variants;
CREATE POLICY "Anyone can view active product variants" ON public.product_variants FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage all product variants" ON public.product_variants;
CREATE POLICY "Admins can manage all product variants" ON public.product_variants FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their product variants" ON public.product_variants;
CREATE POLICY "Merchants can manage their product variants" ON public.product_variants FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_variants.product_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
CREATE POLICY "Admins can manage all orders" ON public.orders FOR ALL TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
CREATE POLICY "Buyers can create orders" ON public.orders FOR INSERT TO authenticated WITH CHECK (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
CREATE POLICY "Buyers can view own orders" ON public.orders FOR SELECT TO authenticated USING (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders;
CREATE POLICY "Buyers can update own orders" ON public.orders FOR UPDATE
  USING (auth.uid() = buyer_id AND status IN ('NEW','PENDING_PAYMENT','DELIVERED'))
  WITH CHECK (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;
CREATE POLICY "Merchants can view own orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id));
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
CREATE POLICY "Merchants can update own orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id));
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
CREATE POLICY "Couriers can view assigned orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id));
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
CREATE POLICY "Couriers can update assigned orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id));

DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items;
CREATE POLICY "Users can insert order items for own orders" ON public.order_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
CREATE POLICY "Users can view own order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND (orders.buyer_id = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS "Merchants can view order items" ON public.order_items;
CREATE POLICY "Merchants can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = order_items.order_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Couriers can view order items" ON public.order_items;
CREATE POLICY "Couriers can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = order_items.order_id AND c.user_id = auth.uid()));

DROP POLICY IF EXISTS "Public can view active flash sales" ON public.flash_sales;
CREATE POLICY "Public can view active flash sales" ON public.flash_sales FOR SELECT
  USING (status = 'ACTIVE' AND end_time > now());
DROP POLICY IF EXISTS "Admins can manage all flash sales" ON public.flash_sales;
CREATE POLICY "Admins can manage all flash sales" ON public.flash_sales FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their flash sales" ON public.flash_sales;
CREATE POLICY "Merchants can manage their flash sales" ON public.flash_sales FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view visible reviews" ON public.reviews;
CREATE POLICY "Anyone can view visible reviews" ON public.reviews FOR SELECT USING (is_visible = true);
DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews;
CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants can reply to their reviews" ON public.reviews;
CREATE POLICY "Merchants can reply to their reviews" ON public.reviews FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = reviews.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins can manage reviews" ON public.reviews;
CREATE POLICY "Admins can manage reviews" ON public.reviews FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can manage refunds" ON public.refund_requests;
CREATE POLICY "Admins can manage refunds" ON public.refund_requests FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests;
CREATE POLICY "Buyers can create refund requests" ON public.refund_requests FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Buyers can view own refunds" ON public.refund_requests;
CREATE POLICY "Buyers can view own refunds" ON public.refund_requests FOR SELECT USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants can view own refunds" ON public.refund_requests;
CREATE POLICY "Merchants can view own refunds" ON public.refund_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = refund_requests.merchant_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can create withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()) AND status = 'PENDING');
DROP POLICY IF EXISTS "Merchants can view own withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage platform_fees" ON public.platform_fees;
CREATE POLICY "Admins can manage platform_fees" ON public.platform_fees FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own fees" ON public.platform_fees;
CREATE POLICY "Merchants can view own fees" ON public.platform_fees FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = platform_fees.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage insurance fund" ON public.insurance_fund;
CREATE POLICY "Admins can manage insurance fund" ON public.insurance_fund FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own insurance" ON public.insurance_fund;
CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Merchants can create claims" ON public.insurance_fund;
CREATE POLICY "Merchants can create claims" ON public.insurance_fund FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid())
    AND type = 'claim' AND status = 'PENDING');

DROP POLICY IF EXISTS "Vouchers viewable by everyone" ON public.vouchers;
CREATE POLICY "Vouchers viewable by everyone" ON public.vouchers FOR SELECT
  USING (is_active = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()));
DROP POLICY IF EXISTS "Admins manage all vouchers" ON public.vouchers;
CREATE POLICY "Admins manage all vouchers" ON public.vouchers FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants manage own vouchers" ON public.vouchers;
CREATE POLICY "Merchants manage own vouchers" ON public.vouchers FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());

DROP POLICY IF EXISTS "Users can use vouchers" ON public.voucher_usages;
CREATE POLICY "Users can use vouchers" ON public.voucher_usages FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Users view own usage" ON public.voucher_usages;
CREATE POLICY "Users view own usage" ON public.voucher_usages FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active promotions" ON public.promotions;
CREATE POLICY "Anyone can view active promotions" ON public.promotions FOR SELECT
  USING (is_active = true AND is_approved = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()));
DROP POLICY IF EXISTS "Admins can manage promotions" ON public.promotions;
CREATE POLICY "Admins can manage promotions" ON public.promotions FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can create own promotions" ON public.promotions;
CREATE POLICY "Merchants can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'merchant' AND is_approved = false);
DROP POLICY IF EXISTS "Villages can create own promotions" ON public.promotions;
CREATE POLICY "Villages can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'village' AND is_approved = false);

DROP POLICY IF EXISTS "Passengers can create ride requests" ON public.ride_requests;
CREATE POLICY "Passengers can create ride requests" ON public.ride_requests FOR INSERT TO authenticated
  WITH CHECK (passenger_id = auth.uid());
DROP POLICY IF EXISTS "Passengers can view own rides" ON public.ride_requests;
CREATE POLICY "Passengers can view own rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (passenger_id = auth.uid());
DROP POLICY IF EXISTS "Couriers can view searching rides" ON public.ride_requests;
CREATE POLICY "Couriers can view searching rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (status = 'SEARCHING' AND EXISTS (SELECT 1 FROM public.couriers
    WHERE user_id = auth.uid() AND status = 'ACTIVE' AND is_available = true));
DROP POLICY IF EXISTS "Couriers can view assigned rides" ON public.ride_requests;
CREATE POLICY "Couriers can view assigned rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Couriers can update assigned rides" ON public.ride_requests;
CREATE POLICY "Couriers can update assigned rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins can manage all rides" ON public.ride_requests;
CREATE POLICY "Admins can manage all rides" ON public.ride_requests FOR ALL TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Passengers can update own rides" ON public.ride_requests;
CREATE POLICY "Passengers can update own rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (passenger_id = auth.uid() AND status IN ('SEARCHING', 'ACCEPTED'));
-- ===== END SOURCE: 20260723060205_ff87f8be-ac0e-4efd-8098-7efd39797d2f.sql =====

-- ===== BEGIN SOURCE: 20260725102650_0450b83b-8c52-43e7-9f9d-958d687d2513.sql =====
-- FILE 05: ADMIN SETTINGS, AUDIT, BACKUP, REALTIME & SEED (idempotent)

CREATE TABLE IF NOT EXISTS public.app_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  category text NOT NULL DEFAULT 'general',
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  description text,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.app_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.app_settings TO authenticated;
GRANT ALL ON public.app_settings TO service_role;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings;
CREATE POLICY "Anyone can view settings" ON public.app_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins can manage settings" ON public.app_settings;
CREATE POLICY "Admins can manage settings" ON public.app_settings FOR ALL USING (public.is_admin());

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.admin_audit_logs TO authenticated;
GRANT ALL ON public.admin_audit_logs TO service_role;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can view logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can view logs" ON public.admin_audit_logs FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins can insert logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs FOR INSERT WITH CHECK (public.is_admin());
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id);

CREATE TABLE IF NOT EXISTS public.backup_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type text NOT NULL DEFAULT 'manual',
  status text NOT NULL DEFAULT 'pending',
  file_url text,
  file_size integer,
  tables_included text[],
  error_message text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz
);
GRANT SELECT, INSERT, UPDATE ON public.backup_logs TO authenticated;
GRANT ALL ON public.backup_logs TO service_role;
ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins view backups" ON public.backup_logs;
CREATE POLICY "Admins view backups" ON public.backup_logs FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins create backups" ON public.backup_logs;
CREATE POLICY "Admins create backups" ON public.backup_logs FOR INSERT WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.backup_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  schedule_type text NOT NULL DEFAULT 'daily',
  schedule_time time NOT NULL DEFAULT '02:00:00',
  schedule_day integer,
  tables_included text[] DEFAULT ARRAY['merchants','products','orders','villages','tourism','couriers']::text[],
  is_active boolean NOT NULL DEFAULT true,
  last_run_at timestamptz,
  next_run_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.backup_schedules TO authenticated;
GRANT ALL ON public.backup_schedules TO service_role;
ALTER TABLE public.backup_schedules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can manage backup schedules" ON public.backup_schedules;
CREATE POLICY "Admins can manage backup schedules" ON public.backup_schedules FOR ALL USING (public.is_admin());

CREATE TABLE IF NOT EXISTS public.seo_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path text NOT NULL UNIQUE,
  title text, description text, keywords text,
  og_image text, og_title text, og_description text,
  canonical_url text, robots text DEFAULT 'index, follow',
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
GRANT SELECT ON public.seo_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.seo_settings TO authenticated;
GRANT ALL ON public.seo_settings TO service_role;
ALTER TABLE public.seo_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view SEO settings" ON public.seo_settings;
CREATE POLICY "Anyone can view SEO settings" ON public.seo_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins manage SEO" ON public.seo_settings;
CREATE POLICY "Admins manage SEO" ON public.seo_settings FOR ALL USING (public.is_admin());

-- Realtime publications
DO $$
DECLARE t text;
  tables text[] := ARRAY['orders','order_items','notifications','chat_messages','ride_requests','couriers','merchants','products','saved_addresses','courier_deposits','courier_balance_logs','push_subscriptions','flash_sales','reviews'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t)
       AND NOT EXISTS (SELECT 1 FROM pg_publication_rel pr
         JOIN pg_publication p ON pr.prpubid=p.oid
         JOIN pg_class c ON pr.prrelid=c.oid
         JOIN pg_namespace n ON c.relnamespace=n.oid
         WHERE p.pubname='supabase_realtime' AND n.nspname='public' AND c.relname=t) THEN
      BEGIN EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Skipped % : %', t, SQLERRM; END;
    END IF;
  END LOOP;
END $$;

-- Seed: kategori
INSERT INTO public.categories (slug, name, icon, sort_order, is_active) VALUES
  ('makanan','Makanan','🍔',1,true),
  ('minuman','Minuman','🥤',2,true),
  ('sembako','Sembako','🛒',3,true),
  ('sayuran','Sayuran & Buah','🥬',4,true),
  ('fashion','Fashion','👕',5,true),
  ('elektronik','Elektronik','📱',6,true),
  ('rumah-tangga','Rumah Tangga','🏠',7,true),
  ('kerajinan','Kerajinan','🎨',8,true),
  ('kesehatan','Kesehatan','💊',9,true),
  ('lainnya','Lainnya','📦',99,true)
ON CONFLICT (slug) DO NOTHING;

-- Seed: app_settings
INSERT INTO public.app_settings (key, category, value, description) VALUES
  ('cod_settings','payment','{"max_amount":75000,"max_distance_km":3,"min_trust_score":50,"penalty_points":50,"success_bonus_points":1}'::jsonb,'Aturan Cash On Delivery'),
  ('platform_fee','finance','{"percent":5,"min_amount":500,"max_amount":10000}'::jsonb,'Biaya platform per transaksi'),
  ('courier_minimum_balance','courier','{"amount":50000}'::jsonb,'Saldo minimum tersisa saat kurir menarik dana'),
  ('shipping_defaults','shipping','{"base_fee":5000,"per_km":2000,"free_shipping_threshold":100000}'::jsonb,'Default ongkir'),
  ('site_info','general','{"name":"DesaMart","tagline":"Marketplace Desa Indonesia","support_email":"support@desa-karya-nusantara.id"}'::jsonb,'Informasi umum situs')
ON CONFLICT (key) DO NOTHING;

-- Seed: POS packages
INSERT INTO public.pos_packages (name, description, price, duration_months, is_active, sort_order) VALUES
  ('POS Basic','Fitur kasir dasar untuk UMKM',50000,1,true,1),
  ('POS Pro','Fitur lengkap untuk toko berkembang',150000,1,true,2),
  ('POS Enterprise','Fitur enterprise untuk multi-outlet',350000,1,true,3)
ON CONFLICT DO NOTHING;

-- Seed: transaction packages
INSERT INTO public.transaction_packages (name, description, classification_price, price_per_transaction, transaction_quota, validity_days, total_credits, group_commission_percent, is_active) VALUES
  ('Paket Starter','100 transaksi selama 30 hari','UNDER_5K',250,100,30,100,5,true),
  ('Paket Bisnis','500 transaksi selama 30 hari','FROM_5K_TO_10K',200,500,30,500,5,true),
  ('Paket Premium','2000 transaksi selama 30 hari','ABOVE_20K',175,2000,30,2000,5,true)
ON CONFLICT DO NOTHING;

-- Seed: halal regulations
INSERT INTO public.halal_regulations (content)
SELECT 'Semua produk makanan & minuman yang dijual wajib mencantumkan status sertifikasi halal jika berlaku. Merchant bertanggung jawab atas kebenaran informasi.'
WHERE NOT EXISTS (SELECT 1 FROM public.halal_regulations);
-- ===== END SOURCE: 20260725102650_0450b83b-8c52-43e7-9f9d-958d687d2513.sql =====

-- ===== BEGIN SOURCE: 20260802091854_330e1c0c-2ef7-404e-9b15-0368a81abf14.sql =====
DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants;
DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
-- ===== END SOURCE: 20260802091854_330e1c0c-2ef7-404e-9b15-0368a81abf14.sql =====

-- ===== BEGIN SOURCE: 20260804111713_21956d1a-8612-45c6-90a1-0d7523bf7480.sql =====
CREATE TABLE IF NOT EXISTS public.pos_tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  store_name text,
  logo_url text,
  phone text,
  address text,
  currency text NOT NULL DEFAULT 'IDR',
  timezone text NOT NULL DEFAULT 'Asia/Jakarta',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS pos_tenants_user_id_key ON public.pos_tenants(user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_tenants TO authenticated;
GRANT ALL ON public.pos_tenants TO service_role;

ALTER TABLE public.pos_tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage their POS tenant" ON public.pos_tenants;
CREATE POLICY "Owners manage their POS tenant" ON public.pos_tenants
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view POS tenants" ON public.pos_tenants;
CREATE POLICY "Admins can view POS tenants" ON public.pos_tenants
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE TABLE IF NOT EXISTS public.pos_outlets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pos_outlets_tenant_id_idx ON public.pos_outlets(tenant_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_outlets TO authenticated;
GRANT ALL ON public.pos_outlets TO service_role;

ALTER TABLE public.pos_outlets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners manage their POS outlets" ON public.pos_outlets;
CREATE POLICY "Owners manage their POS outlets" ON public.pos_outlets
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view POS outlets" ON public.pos_outlets;
CREATE POLICY "Admins can view POS outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP TRIGGER IF EXISTS update_pos_tenants_updated_at ON public.pos_tenants;
CREATE TRIGGER update_pos_tenants_updated_at
  BEFORE UPDATE ON public.pos_tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_pos_outlets_updated_at ON public.pos_outlets;
CREATE TRIGGER update_pos_outlets_updated_at
  BEFORE UPDATE ON public.pos_outlets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== END SOURCE: 20260804111713_21956d1a-8612-45c6-90a1-0d7523bf7480.sql =====
