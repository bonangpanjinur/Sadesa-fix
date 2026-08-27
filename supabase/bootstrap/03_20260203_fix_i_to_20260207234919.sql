-- DesaMart bootstrap bundle; generated from supabase/migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260203_fix_is_admin_and_packages.sql .. 20260207234919_3b703a60-74a4-4b19-914a-bce0c90381c7.sql


-- ===== BEGIN SOURCE: 20260203_fix_is_admin_and_packages.sql =====
-- ====================================================================
-- MIGRASI: FIX IS_ADMIN & UPDATE LOGIKA PAKET TRANSAKSI (FINAL)
-- ====================================================================

-- 1. Pastikan fungsi is_admin ada (untuk memperbaiki error 42883)
-- Fungsi ini mengecek apakah user memiliki role 'admin' di tabel user_roles
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'admin'
  );
$$;

-- 2. Pastikan tabel transaction_packages ada
CREATE TABLE IF NOT EXISTS public.transaction_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  price_per_transaction INTEGER NOT NULL DEFAULT 0,
  kas_fee INTEGER NOT NULL DEFAULT 0,
  transaction_quota INTEGER NOT NULL DEFAULT 100,
  validity_days INTEGER NOT NULL DEFAULT 30,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 3. Modifikasi tabel transaction_packages
-- Menghapus kolom classification_price jika ada
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='transaction_packages' AND column_name='classification_price') THEN
        ALTER TABLE public.transaction_packages DROP COLUMN classification_price;
    END IF;
END $$;

-- Menambahkan komentar untuk memperjelas fungsi kolom
COMMENT ON COLUMN public.transaction_packages.transaction_quota IS 'Total kuota transaksi (kredit) yang didapat dari paket ini';
COMMENT ON COLUMN public.transaction_packages.price_per_transaction IS 'Biaya per transaksi dalam paket ini';
COMMENT ON COLUMN public.transaction_packages.kas_fee IS 'Komisi kelompok/kas per transaksi';

-- 4. Pastikan tabel quota_tiers ada
CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL,
  max_price INTEGER, -- NULL berarti tidak ada batas atas
  credit_cost INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Aktifkan RLS
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;

-- 5. Kebijakan RLS untuk quota_tiers
DO $$ 
BEGIN
    -- Drop existing policies if any to avoid conflicts
    DROP POLICY IF EXISTS "Anyone can view quota tiers" ON public.quota_tiers;
    DROP POLICY IF EXISTS "Admins can manage quota tiers" ON public.quota_tiers;
    
    CREATE POLICY "Anyone can view quota tiers" ON public.quota_tiers FOR SELECT USING (true);
    CREATE POLICY "Admins can manage quota tiers" ON public.quota_tiers FOR ALL USING (public.is_admin());
END $$;

-- 6. Kebijakan RLS untuk transaction_packages
DO $$ 
BEGIN
    -- Drop existing policies if any to avoid conflicts
    DROP POLICY IF EXISTS "Anyone can view active packages" ON public.transaction_packages;
    DROP POLICY IF EXISTS "Admins can manage packages" ON public.transaction_packages;
    
    CREATE POLICY "Anyone can view active packages" ON public.transaction_packages FOR SELECT USING (is_active = true);
    CREATE POLICY "Admins can manage packages" ON public.transaction_packages FOR ALL USING (public.is_admin());
END $$;

-- 7. Update data paket default (General) sesuai permintaan user
DELETE FROM public.transaction_packages;
INSERT INTO public.transaction_packages (name, price_per_transaction, kas_fee, transaction_quota, validity_days, description, is_active) VALUES
('Paket Hemat', 500, 200, 50, 0, 'Paket dasar untuk pemula tanpa masa aktif', true),
('Paket Reguler', 450, 150, 100, 0, 'Paket standar untuk usaha menengah tanpa masa aktif', true),
('Paket Premium', 400, 100, 250, 0, 'Paket terbaik dengan biaya transaksi termurah tanpa masa aktif', true);

-- 8. Update data tier kuota default sesuai permintaan user
DELETE FROM public.quota_tiers;
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost) VALUES
(0, 3000, 1),
(3001, 5000, 1), -- Contoh user: > 3000 dan < 5000 menghabiskan 1 kuota
(5001, 10000, 2), -- Contoh user: > 5000 dan < 10000 menghabiskan 2 kuota
(10001, NULL, 3);

-- 9. Modifikasi tabel merchants
-- Menghapus kolom classification_price jika ada
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchants' AND column_name='classification_price') THEN
        ALTER TABLE public.merchants DROP COLUMN classification_price;
    END IF;
END $$;

-- 10. Update fungsi kalkulasi biaya kredit (kredit per transaksi)
CREATE OR REPLACE FUNCTION public.calculate_item_credit_cost(p_price INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_credit_cost INTEGER;
BEGIN
  SELECT credit_cost INTO v_credit_cost
  FROM public.quota_tiers
  WHERE p_price >= min_price 
    AND (max_price IS NULL OR p_price <= max_price)
  ORDER BY min_price DESC
  LIMIT 1;

  RETURN COALESCE(v_credit_cost, 1);
END;
$$;

-- 11. Update fungsi use_merchant_quota_v2 untuk mendukung pengurangan kuota dinamis
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub_id UUID;
BEGIN
  -- Cari langganan aktif yang memiliki sisa kuota cukup
  -- Tanpa mengecek expired_at jika validity_days di paket adalah 0 (tanpa masa aktif)
  SELECT ms.id INTO v_sub_id
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now())
    AND (ms.transaction_quota - ms.used_quota) >= p_credits
  ORDER BY ms.created_at ASC -- Gunakan paket yang paling lama dulu (FIFO)
  LIMIT 1;
  
  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;
  
  RETURN TRUE;
END;
$$;

-- 12. Update fungsi check_merchant_quota untuk mendukung logika baru
CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_quota INTEGER;
  v_used_quota INTEGER;
BEGIN
  -- Hitung total kuota dari semua paket aktif
  SELECT 
    COALESCE(SUM(ms.transaction_quota), 0),
    COALESCE(SUM(ms.used_quota), 0)
  INTO v_total_quota, v_used_quota
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now());
  
  IF v_total_quota = 0 OR (v_total_quota - v_used_quota) <= 0 THEN
    RETURN jsonb_build_object(
      'can_transact', false,
      'reason', 'Tidak ada kuota transaksi aktif. Silakan beli paket terlebih dahulu.',
      'remaining_quota', 0
    );
  END IF;
  
  RETURN jsonb_build_object(
    'can_transact', true,
    'remaining_quota', v_total_quota - v_used_quota
  );
END;
$$;

-- ===== END SOURCE: 20260203_fix_is_admin_and_packages.sql =====

-- ===== BEGIN SOURCE: 20260203_fix_user_roles_policies.sql =====
-- Add policies for user_roles to allow admins to manage roles
-- First, ensure the is_admin() function exists and is working correctly
-- (It should already exist based on previous migrations, but we use it in policies)

-- Policy for Admins to view all roles
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
CREATE POLICY "Admins can view all roles"
    ON public.user_roles FOR SELECT
    USING (public.is_admin());

-- Policy for Admins to insert roles
DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
CREATE POLICY "Admins can insert roles"
    ON public.user_roles FOR INSERT
    WITH CHECK (public.is_admin());

-- Policy for Admins to update roles
DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
CREATE POLICY "Admins can update roles"
    ON public.user_roles FOR UPDATE
    USING (public.is_admin());

-- Policy for Admins to delete roles
DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
CREATE POLICY "Admins can delete roles"
    ON public.user_roles FOR DELETE
    USING (public.is_admin());

-- Also add policy for profiles so admins can view all profiles
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles"
    ON public.profiles FOR SELECT
    USING (public.is_admin());

-- ===== END SOURCE: 20260203_fix_user_roles_policies.sql =====

-- ===== BEGIN SOURCE: 20260203_improve_refund_system.sql =====
-- 1. Perbarui tabel refund_requests dengan kolom baru
ALTER TABLE public.refund_requests 
ADD COLUMN IF NOT EXISTS evidence_urls text[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS refund_type text DEFAULT 'FULL';

-- 2. Isi data merchant_id untuk data refund yang sudah ada (jika ada)
UPDATE public.refund_requests rr
SET merchant_id = o.merchant_id
FROM public.orders o
WHERE rr.order_id = o.id AND rr.merchant_id IS NULL;

-- 3. Tambahkan index untuk performa pencarian merchant
CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant ON public.refund_requests(merchant_id);

-- 4. Tambahkan kebijakan keamanan (RLS) agar Merchant bisa melihat refund mereka sendiri
DROP POLICY IF EXISTS "Merchants can view own refunds" ON public.refund_requests;
CREATE POLICY "Merchants can view own refunds" ON public.refund_requests
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = refund_requests.merchant_id
    AND m.user_id = auth.uid()
  )
);

-- 5. Pastikan bucket storage tersedia untuk bukti refund (Opsional jika belum ada)
-- Jalankan ini jika Anda ingin memastikan folder storage bisa diakses
-- INSERT INTO storage.buckets (id, name, public) VALUES ('public_assets', 'public_assets', true) ON CONFLICT (id) DO NOTHING;

-- ===== END SOURCE: 20260203_improve_refund_system.sql =====

-- ===== BEGIN SOURCE: 20260203_new_quota_system.sql =====
-- New Quota System Migration

-- 0. Cleanup old rules if necessary
-- The old logic was hardcoded in the application and simple decrement in DB.
-- We will replace the use_merchant_quota function.

-- 1. Create table for Quota Tiers Configuration
CREATE TABLE public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL,
  max_price INTEGER, -- NULL means no upper limit
  credit_cost INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;

-- RLS for quota_tiers
CREATE POLICY "Anyone can view quota tiers" 
ON public.quota_tiers FOR SELECT 
USING (true);

CREATE POLICY "Admins can manage quota tiers" 
ON public.quota_tiers FOR ALL 
USING (is_admin());

-- Insert default tiers based on user request
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost) VALUES
(0, 3000, 1),
(3001, 4999, 2),
(5000, 9999, 3),
(10000, 14999, 5),
(15000, NULL, 10);

-- 2. Modify transaction_packages to use "credits" instead of "transactions"
-- We'll keep the column name transaction_quota but treat it as credits conceptually, 
-- or we can add a comment to clarify.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'transaction_packages'
      AND column_name = 'transaction_quota'
  ) THEN
    COMMENT ON COLUMN public.transaction_packages.transaction_quota IS 'Total credits provided by this package';
  END IF;
END $$;

-- 3. Create a function to calculate credit cost based on product price
CREATE OR REPLACE FUNCTION public.calculate_order_credit_cost(p_order_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_credits INTEGER := 0;
  v_item RECORD;
  v_tier_cost INTEGER;
BEGIN
  -- Loop through items in the order
  FOR v_item IN SELECT product_price, quantity FROM order_items WHERE order_id = p_order_id LOOP
    -- Find the matching tier for this product price
    SELECT credit_cost INTO v_tier_cost 
    FROM quota_tiers 
    WHERE v_item.product_price >= min_price 
      AND (max_price IS NULL OR v_item.product_price <= max_price)
    LIMIT 1;
    
    -- Default to 1 if no tier found (safety)
    IF v_tier_cost IS NULL THEN
      v_tier_cost := 1;
    END IF;
    
    v_total_credits := v_total_credits + (v_tier_cost * v_item.quantity);
  END LOOP;
  
  RETURN v_total_credits;
END;
$$;

-- 4. Update use_merchant_quota to accept credit amount
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub_id UUID;
BEGIN
  -- Find active subscription with enough quota
  SELECT id INTO v_sub_id
  FROM merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC -- Use the one expiring soonest first
  LIMIT 1;
  
  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;
  
  RETURN TRUE;
END;
$$;

-- 5. Keep the old use_merchant_quota for backward compatibility but update it to use 1 credit
CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN use_merchant_quota_v2(p_merchant_id, 1);
END;
$$;

-- ===== END SOURCE: 20260203_new_quota_system.sql =====

-- ===== BEGIN SOURCE: 20260203_update_package_logic.sql =====
-- ====================================================================
-- MIGRASI: UPDATE LOGIKA PAKET GENERAL & KLASIFIKASI HARGA DINAMIS (REVISI)
-- ====================================================================

-- 1. Pastikan tabel transaction_packages ada
CREATE TABLE IF NOT EXISTS public.transaction_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  price_per_transaction INTEGER NOT NULL DEFAULT 0,
  kas_fee INTEGER NOT NULL DEFAULT 0,
  transaction_quota INTEGER NOT NULL DEFAULT 100,
  validity_days INTEGER NOT NULL DEFAULT 30,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 2. Modifikasi tabel transaction_packages
-- Menghapus kolom classification_price jika ada
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='transaction_packages' AND column_name='classification_price') THEN
        ALTER TABLE public.transaction_packages DROP COLUMN classification_price;
    END IF;
END $$;

-- Menambahkan komentar untuk memperjelas fungsi kolom
COMMENT ON COLUMN public.transaction_packages.transaction_quota IS 'Total kuota transaksi (kredit) yang didapat dari paket ini';
COMMENT ON COLUMN public.transaction_packages.price_per_transaction IS 'Biaya per transaksi dalam paket ini';
COMMENT ON COLUMN public.transaction_packages.kas_fee IS 'Komisi kelompok/kas per transaksi';

-- 3. Pastikan tabel quota_tiers ada
CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL,
  max_price INTEGER, -- NULL berarti tidak ada batas atas
  credit_cost INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Aktifkan RLS
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;

-- Kebijakan RLS untuk quota_tiers
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quota_tiers' AND policyname = 'Anyone can view quota tiers') THEN
        CREATE POLICY "Anyone can view quota tiers" ON public.quota_tiers FOR SELECT USING (true);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quota_tiers' AND policyname = 'Admins can manage quota tiers') THEN
        CREATE POLICY "Admins can manage quota tiers" ON public.quota_tiers FOR ALL USING (is_admin());
    END IF;
END $$;

-- Kebijakan RLS untuk transaction_packages (jika belum ada)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transaction_packages' AND policyname = 'Anyone can view active packages') THEN
        CREATE POLICY "Anyone can view active packages" ON public.transaction_packages FOR SELECT USING (is_active = true);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transaction_packages' AND policyname = 'Admins can manage packages') THEN
        CREATE POLICY "Admins can manage packages" ON public.transaction_packages FOR ALL USING (is_admin());
    END IF;
END $$;

-- 4. Update data paket default (General)
DELETE FROM public.transaction_packages;
INSERT INTO public.transaction_packages (name, price_per_transaction, kas_fee, transaction_quota, validity_days, description, is_active) VALUES
('Paket Hemat', 500, 200, 50, 0, 'Paket dasar untuk pemula tanpa masa aktif', true),
('Paket Reguler', 450, 150, 100, 0, 'Paket standar untuk usaha menengah tanpa masa aktif', true),
('Paket Premium', 400, 100, 250, 0, 'Paket terbaik dengan biaya transaksi termurah tanpa masa aktif', true);

-- 5. Update data tier kuota default sesuai permintaan user
DELETE FROM public.quota_tiers;
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost) VALUES
(0, 3000, 1),
(3001, 5000, 1), -- Contoh user: > 3000 dan < 5000 menghabiskan 1 kuota
(5001, 10000, 2), -- Contoh user: > 5000 dan < 10000 menghabiskan 2 kuota
(10001, NULL, 3);

-- 6. Modifikasi tabel merchants
-- Menghapus kolom classification_price jika ada
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchants' AND column_name='classification_price') THEN
        ALTER TABLE public.merchants DROP COLUMN classification_price;
    END IF;
END $$;

-- 7. Update fungsi kalkulasi biaya kredit (kredit per transaksi)
CREATE OR REPLACE FUNCTION public.calculate_item_credit_cost(p_price INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_credit_cost INTEGER;
BEGIN
  SELECT credit_cost INTO v_credit_cost
  FROM public.quota_tiers
  WHERE p_price >= min_price 
    AND (max_price IS NULL OR p_price <= max_price)
  ORDER BY min_price DESC
  LIMIT 1;

  RETURN COALESCE(v_credit_cost, 1);
END;
$$;

-- 8. Update fungsi use_merchant_quota_v2 untuk mendukung pengurangan kuota dinamis
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub_id UUID;
BEGIN
  -- Cari langganan aktif yang memiliki sisa kuota cukup
  -- Tanpa mengecek expired_at jika validity_days di paket adalah 0 (tanpa masa aktif)
  SELECT ms.id INTO v_sub_id
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now())
    AND (ms.transaction_quota - ms.used_quota) >= p_credits
  ORDER BY ms.created_at ASC -- Gunakan paket yang paling lama dulu (FIFO)
  LIMIT 1;
  
  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;
  
  RETURN TRUE;
END;
$$;

-- 9. Update fungsi check_merchant_quota untuk mendukung logika baru
CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_quota INTEGER;
  v_used_quota INTEGER;
BEGIN
  -- Hitung total kuota dari semua paket aktif
  SELECT 
    COALESCE(SUM(ms.transaction_quota), 0),
    COALESCE(SUM(ms.used_quota), 0)
  INTO v_total_quota, v_used_quota
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now());
  
  IF v_total_quota = 0 OR (v_total_quota - v_used_quota) <= 0 THEN
    RETURN jsonb_build_object(
      'can_transact', false,
      'reason', 'Tidak ada kuota transaksi aktif. Silakan beli paket terlebih dahulu.',
      'remaining_quota', 0
    );
  END IF;
  
  RETURN jsonb_build_object(
    'can_transact', true,
    'remaining_quota', v_total_quota - v_used_quota
  );
END;
$$;

-- ===== END SOURCE: 20260203_update_package_logic.sql =====

-- ===== BEGIN SOURCE: 20260203_update_package_logic_v2.sql =====
-- ====================================================================
-- MIGRASI: UPDATE LOGIKA PAKET TRANSAKSI (HARGA TETAP & KOMISI PERSEN)
-- ====================================================================

-- 1. Modifikasi tabel transaction_packages
-- Tambahkan kolom total_price dan ubah kas_fee menjadi numerik untuk persentase
ALTER TABLE public.transaction_packages 
ADD COLUMN IF NOT EXISTS total_price INTEGER NOT NULL DEFAULT 0,
ALTER COLUMN kas_fee TYPE NUMERIC(5,2);

-- Update komentar kolom
COMMENT ON COLUMN public.transaction_packages.total_price IS 'Harga total paket yang dibayar oleh merchant';
COMMENT ON COLUMN public.transaction_packages.kas_fee IS 'Persentase komisi kelompok/kas (0-100)';

-- 2. Bersihkan data lama dan masukkan data baru sesuai logika baru
DELETE FROM public.transaction_packages;

-- Masukkan data paket dengan harga total dan komisi persen
-- Kita asumsikan harga total adalah (price_per_transaction * quota) dari data sebelumnya
INSERT INTO public.transaction_packages (name, total_price, kas_fee, transaction_quota, validity_days, description, is_active) VALUES
('Paket Hemat', 25000, 10.00, 50, 30, 'Paket dasar untuk pemula dengan masa aktif 30 hari', true),
('Paket Reguler', 45000, 7.50, 100, 30, 'Paket standar untuk usaha menengah dengan masa aktif 30 hari', true),
('Paket Premium', 100000, 5.00, 250, 30, 'Paket terbaik dengan biaya transaksi termurah dengan masa aktif 30 hari', true);

-- 3. Update fungsi merchant_subscriptions jika perlu (biasanya payment_amount diambil dari total_price)
-- Tidak ada perubahan fungsi yang diperlukan di sini jika aplikasi mengambil total_price dari tabel packages saat checkout.

-- ===== END SOURCE: 20260203_update_package_logic_v2.sql =====

-- ===== BEGIN SOURCE: 20260204052738_ce07a7c3-c7e6-47ff-b86c-c08e5700b24a.sql =====
-- ============================================================
-- FIX 1: Create SECURITY DEFINER functions to break RLS recursion
-- ============================================================

-- Function to check courier ownership without RLS
CREATE OR REPLACE FUNCTION public.get_user_courier_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.couriers WHERE user_id = _user_id LIMIT 1
$$;

-- Function to check merchant ownership without RLS
CREATE OR REPLACE FUNCTION public.get_user_merchant_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.merchants WHERE user_id = _user_id LIMIT 1
$$;

-- Function to check if user is courier for specific courier_id
CREATE OR REPLACE FUNCTION public.is_courier_owner(_user_id UUID, _courier_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.couriers 
    WHERE id = _courier_id AND user_id = _user_id
  )
$$;

-- Function to check if user is merchant for specific order
CREATE OR REPLACE FUNCTION public.is_order_merchant(_user_id UUID, _merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.merchants 
    WHERE id = _merchant_id AND user_id = _user_id
  )
$$;

-- ============================================================
-- FIX 2: Drop and recreate couriers RLS policies
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
DROP POLICY IF EXISTS "Authorized users can view courier info" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;

-- 1. Couriers can view their own data (simple, no recursion)
CREATE POLICY "Couriers can view own data"
ON public.couriers
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- 2. Admins can manage all couriers using security definer function
CREATE POLICY "Admins can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- 3. Verifikator can manage couriers
CREATE POLICY "Verifikator can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'verifikator'));

-- 4. Anyone can register as courier
CREATE POLICY "Anyone can register as courier"
ON public.couriers
FOR INSERT
TO authenticated
WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');

-- 5. Couriers can update own location
CREATE POLICY "Couriers can update own location"
ON public.couriers
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND status = 'ACTIVE');

-- 6. Public view for approved couriers (for order assignment)
CREATE POLICY "Public can view approved couriers"
ON public.couriers
FOR SELECT
TO authenticated
USING (registration_status = 'APPROVED' AND status = 'ACTIVE');

-- ============================================================
-- FIX 3: Drop and recreate orders RLS policies
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;

-- 1. Buyers can view and manage their own orders
CREATE POLICY "Buyers can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (auth.uid() = buyer_id);

CREATE POLICY "Buyers can create orders"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Buyers can update own pending orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (auth.uid() = buyer_id AND status = 'NEW');

-- 2. Admins can manage all orders
CREATE POLICY "Admins can manage all orders"
ON public.orders
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- 3. Couriers can view and update assigned orders using security definer
CREATE POLICY "Couriers can view assigned orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id));

CREATE POLICY "Couriers can update assigned orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id));

-- 4. Merchants can view and update their orders using security definer
CREATE POLICY "Merchants can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_order_merchant(auth.uid(), merchant_id));

CREATE POLICY "Merchants can update own orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_order_merchant(auth.uid(), merchant_id));

-- ============================================================
-- FIX 4: Create quota_tiers table for dynamic pricing
-- ============================================================

CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL DEFAULT 0,
  max_price INTEGER DEFAULT NULL,
  credit_cost INTEGER NOT NULL DEFAULT 1,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;

-- RLS policies for quota_tiers
CREATE POLICY "Anyone can view quota tiers"
ON public.quota_tiers
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage quota tiers"
ON public.quota_tiers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- Insert default tiers
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order) VALUES
(0, 3000, 1, 'Produk harga rendah (Rp 0 - Rp 3.000)', 1),
(3001, 5000, 2, 'Produk harga menengah bawah (Rp 3.001 - Rp 5.000)', 2),
(5001, 8000, 3, 'Produk harga menengah (Rp 5.001 - Rp 8.000)', 3),
(8001, 15000, 4, 'Produk harga menengah atas (Rp 8.001 - Rp 15.000)', 4),
(15001, NULL, 5, 'Produk harga tinggi (Rp 15.001+)', 5)
ON CONFLICT DO NOTHING;

-- Trigger for updated_at
CREATE TRIGGER update_quota_tiers_updated_at
BEFORE UPDATE ON public.quota_tiers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- FIX 5: Update transaction_packages table structure
-- ============================================================

-- Add missing columns if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_schema = 'public' 
                 AND table_name = 'transaction_packages' 
                 AND column_name = 'total_credits') THEN
    ALTER TABLE public.transaction_packages ADD COLUMN total_credits INTEGER NOT NULL DEFAULT 100;
  END IF;
END
$$;

-- Rename transaction_quota to total_credits if needed and update data
UPDATE public.transaction_packages SET total_credits = transaction_quota WHERE total_credits = 100;

-- ============================================================
-- FIX 6: Add location columns to merchants if missing
-- ============================================================

-- location_lat and location_lng already exist based on types.ts
-- ===== END SOURCE: 20260204052738_ce07a7c3-c7e6-47ff-b86c-c08e5700b24a.sql =====

-- ===== BEGIN SOURCE: 20260204064759_cea5feab-6b7c-4ce3-b808-9da7ea5f2003.sql =====
-- =====================================================
-- STEP 1: CREATE ALL SECURITY DEFINER FUNCTIONS FIRST
-- =====================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
$$;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.get_user_merchant_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.merchants WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.get_user_courier_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.couriers WHERE user_id = auth.uid() LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_order_merchant(_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = _order_id AND m.user_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION public.is_order_courier(_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = _order_id AND c.user_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION public.get_quota_cost(product_price INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT credit_cost FROM public.quota_tiers 
     WHERE is_active = true 
     AND product_price >= min_price 
     AND (max_price IS NULL OR product_price <= max_price)
     ORDER BY min_price DESC
     LIMIT 1),
    1
  )
$$;

CREATE OR REPLACE FUNCTION public.use_merchant_quota(
  _merchant_id UUID,
  _product_price INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _subscription_id UUID;
  _remaining_quota INTEGER;
  _cost INTEGER;
BEGIN
  _cost := public.get_quota_cost(_product_price);
  
  SELECT id, (transaction_quota - used_quota) INTO _subscription_id, _remaining_quota
  FROM public.merchant_subscriptions
  WHERE merchant_id = _merchant_id 
    AND status = 'ACTIVE' 
    AND expired_at > now()
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF _subscription_id IS NULL OR _remaining_quota < _cost THEN
    RETURN FALSE;
  END IF;
  
  UPDATE public.merchant_subscriptions
  SET used_quota = used_quota + _cost, updated_at = now()
  WHERE id = _subscription_id;
  
  RETURN TRUE;
END;
$$;

-- =====================================================
-- STEP 2: NOW CREATE POLICIES THAT USE THESE FUNCTIONS
-- =====================================================

-- Quota tiers policies
DROP POLICY IF EXISTS "quota_tiers_public_read" ON public.quota_tiers;
DROP POLICY IF EXISTS "quota_tiers_admin_all" ON public.quota_tiers;

CREATE POLICY "quota_tiers_public_read" ON public.quota_tiers
  FOR SELECT USING (true);

CREATE POLICY "quota_tiers_admin_all" ON public.quota_tiers
  FOR ALL USING (public.is_admin());

-- Couriers policies
DROP POLICY IF EXISTS "couriers_own_access" ON public.couriers;
DROP POLICY IF EXISTS "couriers_admin_access" ON public.couriers;
DROP POLICY IF EXISTS "couriers_public_read" ON public.couriers;

CREATE POLICY "couriers_public_read" ON public.couriers
  FOR SELECT USING (registration_status = 'APPROVED' AND status = 'ACTIVE');

CREATE POLICY "couriers_own_access" ON public.couriers
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "couriers_admin_access" ON public.couriers
  FOR ALL USING (public.is_admin());

-- Orders policies
DROP POLICY IF EXISTS "orders_buyer_access" ON public.orders;
DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;
DROP POLICY IF EXISTS "orders_courier_access" ON public.orders;
DROP POLICY IF EXISTS "orders_admin_access" ON public.orders;

CREATE POLICY "orders_buyer_access" ON public.orders
  FOR ALL USING (buyer_id = auth.uid());

CREATE POLICY "orders_merchant_access" ON public.orders
  FOR ALL USING (public.is_order_merchant(id));

CREATE POLICY "orders_courier_access" ON public.orders
  FOR ALL USING (public.is_order_courier(id));

CREATE POLICY "orders_admin_access" ON public.orders
  FOR ALL USING (public.is_admin());
-- ===== END SOURCE: 20260204064759_cea5feab-6b7c-4ce3-b808-9da7ea5f2003.sql =====

-- ===== BEGIN SOURCE: 20260205150025_e0784383-4b18-43b1-9030-7314c4fdd46f.sql =====
-- Add payment settings columns to merchants table
ALTER TABLE public.merchants 
ADD COLUMN IF NOT EXISTS payment_cod_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS payment_transfer_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS bank_name text,
ADD COLUMN IF NOT EXISTS bank_account_number text,
ADD COLUMN IF NOT EXISTS bank_account_name text;

-- Update existing merchants with default values
UPDATE public.merchants SET 
  payment_cod_enabled = true,
  payment_transfer_enabled = true
WHERE payment_cod_enabled IS NULL;

COMMENT ON COLUMN public.merchants.payment_cod_enabled IS 'Allow COD payment for this merchant';
COMMENT ON COLUMN public.merchants.payment_transfer_enabled IS 'Allow bank transfer payment for this merchant';
COMMENT ON COLUMN public.merchants.bank_name IS 'Bank name for transfer payments';
COMMENT ON COLUMN public.merchants.bank_account_number IS 'Bank account number';
COMMENT ON COLUMN public.merchants.bank_account_name IS 'Bank account holder name';
-- ===== END SOURCE: 20260205150025_e0784383-4b18-43b1-9030-7314c4fdd46f.sql =====

-- ===== BEGIN SOURCE: 20260206014800_6cba496d-c3a1-4ebf-9a61-dbe1348be492.sql =====
-- Drop and recreate the status check constraint to include all needed statuses
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders ADD CONSTRAINT orders_status_check 
CHECK (status = ANY (ARRAY[
  'NEW'::text, 
  'PENDING_CONFIRMATION'::text,
  'PENDING_PAYMENT'::text,
  'PROCESSED'::text, 
  'READY'::text,
  'ASSIGNED'::text,
  'PICKED_UP'::text,
  'SENT'::text, 
  'DONE'::text, 
  'CANCELED'::text,
  'REJECTED'::text,
  'REJECTED_BY_BUYER'::text,
  'REFUNDED'::text
]));
-- ===== END SOURCE: 20260206014800_6cba496d-c3a1-4ebf-9a61-dbe1348be492.sql =====

-- ===== BEGIN SOURCE: 20260206_add_province_to_villages.sql =====
-- Add province column to villages table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'villages' AND column_name = 'province') THEN
        ALTER TABLE public.villages ADD COLUMN province text;
    END IF;
END $$;

-- Update existing villages with a default province if needed
-- UPDATE public.villages SET province = 'Jawa Tengah' WHERE province IS NULL;

-- ===== END SOURCE: 20260206_add_province_to_villages.sql =====

-- ===== BEGIN SOURCE: 20260206_fix_products_bucket.sql =====
-- Create storage bucket for products if it doesn't exist
-- The roadmap mentioned 'products' bucket, but the code uses 'product-images'.
-- We will create 'products' as an alias or ensure both exist to be safe, 
-- but primarily we'll fix the code to use 'product-images' consistently or vice versa.
-- According to the roadmap, the user wants a bucket named 'products'.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('products', 'products', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING;

-- Set up RLS policies for the 'products' bucket
-- 1. Public: Anyone can view images
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'products');

-- 2. Authenticated (Merchant): Can upload images
CREATE POLICY "Merchant Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'products' 
  AND auth.role() = 'authenticated'
);

-- 3. Authenticated (Merchant): Can update own images
CREATE POLICY "Merchant Update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'products' 
  AND auth.role() = 'authenticated'
);

-- 4. Authenticated (Merchant): Can delete own images
CREATE POLICY "Merchant Delete"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'products' 
  AND auth.role() = 'authenticated'
);

-- ===== END SOURCE: 20260206_fix_products_bucket.sql =====

-- ===== BEGIN SOURCE: 20260206_merchant_auto_role.sql =====
-- 1. Trigger untuk otomatis mengisi user_id saat pendaftaran merchant (jika belum diisi)
-- Ini memastikan user_id selalu terhubung dengan user yang sedang login
CREATE OR REPLACE FUNCTION public.handle_merchant_user_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_merchant_signup ON public.merchants;
CREATE TRIGGER on_merchant_signup
  BEFORE INSERT ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_user_id();

-- 2. Trigger untuk otomatis mengubah role user menjadi 'merchant' saat disetujui
CREATE OR REPLACE FUNCTION public.handle_merchant_approval_role()
RETURNS TRIGGER AS $$
BEGIN
  -- Cek jika status berubah menjadi APPROVED
  IF (NEW.registration_status = 'APPROVED' AND OLD.registration_status != 'APPROVED') THEN
    -- Pastikan user_id ada
    IF NEW.user_id IS NOT NULL THEN
      -- Tambahkan role merchant ke tabel user_roles
      -- Menggunakan ON CONFLICT agar tidak error jika role sudah ada
      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'merchant')
      ON CONFLICT (user_id, role) DO NOTHING;
      
      -- Opsional: Jika ingin menghapus role 'buyer' saat menjadi merchant
      -- DELETE FROM public.user_roles WHERE user_id = NEW.user_id AND role = 'buyer';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_merchant_approval ON public.merchants;
CREATE TRIGGER on_merchant_approval
  AFTER UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role();

-- 3. Perbaikan RLS Policy agar user bisa mendaftar dengan aman
DROP POLICY IF EXISTS "merchants_register" ON public.merchants;
CREATE POLICY "merchants_register" ON public.merchants 
FOR INSERT 
WITH CHECK (
  auth.role() = 'authenticated' AND 
  (user_id = auth.uid() OR user_id IS NULL) -- Izinkan NULL karena akan diisi oleh trigger
);

-- ===== END SOURCE: 20260206_merchant_auto_role.sql =====

-- ===== BEGIN SOURCE: 20260206_package_transaction_fix.sql =====
-- Migration: Package Transaction Fix
-- 1. Add payment proof and status to merchant_subscriptions
-- 2. Add payment settings to app_settings
-- 3. Ensure price consistency and quota logic

-- Update merchant_subscriptions to handle payment flow
ALTER TABLE public.merchant_subscriptions 
ADD COLUMN IF NOT EXISTS payment_proof_url text,
ADD COLUMN IF NOT EXISTS admin_notes text;

-- Insert default payment settings if they don't exist
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
  'payment_settings', 
  '{"bank_name": "BCA", "account_number": "1234567890", "account_name": "Admin Desa Digital", "qris_url": ""}',
  'Pengaturan pembayaran untuk pembelian paket oleh merchant',
  'payment'
)
ON CONFLICT (key) DO NOTHING;

-- Trigger to automatically set payment_status to PENDING_APPROVAL when payment_proof_url is updated
CREATE OR REPLACE FUNCTION public.handle_subscription_payment_upload()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.payment_proof_url IS NOT NULL AND (OLD.payment_proof_url IS NULL OR NEW.payment_proof_url <> OLD.payment_proof_url) THEN
    NEW.payment_status := 'PENDING_APPROVAL';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_payment_proof_upload ON public.merchant_subscriptions;
CREATE TRIGGER on_payment_proof_upload
  BEFORE UPDATE ON public.merchant_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_subscription_payment_upload();

-- Trigger to automatically set merchant's current_subscription_id when a subscription is marked as PAID and ACTIVE
CREATE OR REPLACE FUNCTION public.handle_subscription_activation()
RETURNS TRIGGER AS $$
BEGIN
  -- If status becomes ACTIVE and payment_status is PAID
  IF (NEW.status = 'ACTIVE' AND NEW.payment_status = 'PAID') AND 
     (OLD.status <> 'ACTIVE' OR OLD.payment_status <> 'PAID') THEN
    
    -- Update merchant's current subscription
    UPDATE public.merchants 
    SET current_subscription_id = NEW.id
    WHERE id = NEW.merchant_id;
    
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_subscription_activation ON public.merchant_subscriptions;
CREATE TRIGGER on_subscription_activation
  AFTER UPDATE ON public.merchant_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_subscription_activation();

-- STORAGE POLICIES (Correct syntax for Supabase)
-- Allow authenticated users to upload files to 'merchants' bucket
DROP POLICY IF EXISTS "Allow merchants to upload payment proofs" ON storage.objects;
CREATE POLICY "Allow merchants to upload payment proofs"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'merchants' AND 
  (storage.foldername(name))[1] = 'payment-proofs'
);

-- Allow authenticated users to view files in 'merchants' bucket
DROP POLICY IF EXISTS "Allow authenticated to read payment proofs" ON storage.objects;
CREATE POLICY "Allow authenticated to read payment proofs"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'merchants');

-- ===== END SOURCE: 20260206_package_transaction_fix.sql =====

-- ===== BEGIN SOURCE: 20260207013055_fff3e882-ceb4-4434-9c1f-74c5a68f08ff.sql =====
-- Add cover_image_url column to merchants table
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS cover_image_url TEXT;
-- ===== END SOURCE: 20260207013055_fff3e882-ceb4-4434-9c1f-74c5a68f08ff.sql =====

-- ===== BEGIN SOURCE: 20260207013924_900c0746-192a-4019-88a0-4b60cf0c06a5.sql =====

-- Create a function to deduct a specific number of credits from merchant quota
-- This replaces the single-deduction version for tier-based quota costs
CREATE OR REPLACE FUNCTION public.deduct_merchant_quota(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_id UUID;
  v_remaining INTEGER;
BEGIN
  -- Find active subscription with enough remaining quota (FIFO by expiry)
  SELECT id, (transaction_quota - used_quota)
  INTO v_sub_id, v_remaining
  FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;

  RETURN TRUE;
END;
$$;

-- ===== END SOURCE: 20260207013924_900c0746-192a-4019-88a0-4b60cf0c06a5.sql =====

-- ===== BEGIN SOURCE: 20260207015104_25e6cd08-0288-4a3c-9c5a-8e02458f8468.sql =====
-- Add QRIS image URL to merchants table
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS qris_image_url TEXT;

-- Add admin default payment settings to app_settings if not exists
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'admin_payment_info',
  '{"bank_name": "", "bank_account_number": "", "bank_account_name": "", "qris_image_url": ""}',
  'payment',
  'Default payment info (bank & QRIS) used for merchants who have not set their own'
)
ON CONFLICT (key) DO NOTHING;
-- ===== END SOURCE: 20260207015104_25e6cd08-0288-4a3c-9c5a-8e02458f8468.sql =====

-- ===== BEGIN SOURCE: 20260207015951_1df8fd15-2a00-4322-85d4-2834aa2c2432.sql =====

-- Create village-images storage bucket for village main images
INSERT INTO storage.buckets (id, name, public)
VALUES ('village-images', 'village-images', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to village images
CREATE POLICY "Village images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'village-images');

-- Allow authenticated users to upload village images
CREATE POLICY "Authenticated users can upload village images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'village-images' AND auth.role() = 'authenticated');

-- Allow authenticated users to update village images
CREATE POLICY "Authenticated users can update village images"
ON storage.objects FOR UPDATE
USING (bucket_id = 'village-images' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete village images
CREATE POLICY "Authenticated users can delete village images"
ON storage.objects FOR DELETE
USING (bucket_id = 'village-images' AND auth.role() = 'authenticated');

-- ===== END SOURCE: 20260207015951_1df8fd15-2a00-4322-85d4-2834aa2c2432.sql =====

-- ===== BEGIN SOURCE: 20260207020515_3c3aeac4-7471-481b-8558-0ac246ddecb0.sql =====

-- Add auto_complete_at column to track when an order should be auto-completed
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS auto_complete_at TIMESTAMPTZ;

-- When courier marks as DELIVERED, set auto_complete_at to 24 hours later
CREATE OR REPLACE FUNCTION public.set_auto_complete_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- When status changes to DELIVERED, set auto-complete deadline to 24 hours later
  IF NEW.status = 'DELIVERED' AND (OLD.status IS NULL OR OLD.status <> 'DELIVERED') THEN
    NEW.auto_complete_at := NOW() + INTERVAL '24 hours';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trigger_set_auto_complete_deadline ON public.orders;
CREATE TRIGGER trigger_set_auto_complete_deadline
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_auto_complete_deadline();

-- Function to auto-complete orders past their deadline
-- This can be called periodically via pg_cron or an edge function
CREATE OR REPLACE FUNCTION public.auto_complete_delivered_orders()
RETURNS INTEGER AS $$
DECLARE
  completed_count INTEGER;
BEGIN
  UPDATE public.orders
  SET status = 'DONE',
      updated_at = NOW()
  WHERE status = 'DELIVERED'
    AND auto_complete_at IS NOT NULL
    AND auto_complete_at <= NOW();
  
  GET DIAGNOSTICS completed_count = ROW_COUNT;
  RETURN completed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Schedule the auto-complete function to run every hour
SELECT cron.schedule(
  'auto-complete-delivered-orders',
  '0 * * * *',  -- Every hour
  $$SELECT public.auto_complete_delivered_orders()$$
);

-- ===== END SOURCE: 20260207020515_3c3aeac4-7471-481b-8558-0ac246ddecb0.sql =====

-- ===== BEGIN SOURCE: 20260207021607_f6155972-67ae-4618-9c91-eed4b1ec3312.sql =====

-- Add payment_proof_url column to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_proof_url TEXT;

-- Create storage bucket for payment proofs
INSERT INTO storage.buckets (id, name, public) 
VALUES ('payment-proofs', 'payment-proofs', true)
ON CONFLICT (id) DO NOTHING;

-- RLS: Public read access for payment proof images
CREATE POLICY "Payment proofs are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'payment-proofs');

-- RLS: Authenticated users can upload payment proofs
CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

-- RLS: Users can update their own payment proofs
CREATE POLICY "Users can update their own payment proofs"
ON storage.objects FOR UPDATE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

-- RLS: Users can delete their own payment proofs
CREATE POLICY "Users can delete their own payment proofs"
ON storage.objects FOR DELETE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

-- ===== END SOURCE: 20260207021607_f6155972-67ae-4618-9c91-eed4b1ec3312.sql =====

-- ===== BEGIN SOURCE: 20260207224101_c73a8dac-4f53-4c9f-a31d-6a6b841704e2.sql =====
-- Add cancellation columns to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_by UUID;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_type TEXT;
-- ===== END SOURCE: 20260207224101_c73a8dac-4f53-4c9f-a31d-6a6b841704e2.sql =====

-- ===== BEGIN SOURCE: 20260207230832_d72c51f3-4ab4-4cd6-a02d-f6a1e981dac9.sql =====
-- Create promotions storage bucket for banner images
INSERT INTO storage.buckets (id, name, public) VALUES ('promotions', 'promotions', true)
ON CONFLICT (id) DO NOTHING;

-- Create admin-assets bucket for QRIS images etc
INSERT INTO storage.buckets (id, name, public) VALUES ('admin-assets', 'admin-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to promotions bucket
CREATE POLICY "Public can view promotion images"
ON storage.objects FOR SELECT
USING (bucket_id = 'promotions');

-- Allow authenticated users to upload to promotions bucket
CREATE POLICY "Authenticated users can upload promotion images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'promotions' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete promotion images
CREATE POLICY "Authenticated users can delete promotion images"
ON storage.objects FOR DELETE
USING (bucket_id = 'promotions' AND auth.role() = 'authenticated');

-- Allow public read access to admin-assets bucket
CREATE POLICY "Public can view admin assets"
ON storage.objects FOR SELECT
USING (bucket_id = 'admin-assets');

-- Allow authenticated users to upload to admin-assets bucket
CREATE POLICY "Authenticated users can upload admin assets"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'admin-assets' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete admin assets
CREATE POLICY "Authenticated users can delete admin assets"
ON storage.objects FOR DELETE
USING (bucket_id = 'admin-assets' AND auth.role() = 'authenticated');

-- ===== END SOURCE: 20260207230832_d72c51f3-4ab4-4cd6-a02d-f6a1e981dac9.sql =====

-- ===== BEGIN SOURCE: 20260207234919_3b703a60-74a4-4b19-914a-bce0c90381c7.sql =====

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
);

-- Enable RLS
ALTER TABLE public.quota_usage_logs ENABLE ROW LEVEL SECURITY;

-- Admin can see all
CREATE POLICY "Admin can view all quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- Merchant can see own logs
CREATE POLICY "Merchant can view own quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- System can insert logs (service role or triggers)
CREATE POLICY "System can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Create index for performance
CREATE INDEX idx_quota_usage_logs_merchant ON public.quota_usage_logs(merchant_id);
CREATE INDEX idx_quota_usage_logs_order ON public.quota_usage_logs(order_id);
CREATE INDEX idx_quota_usage_logs_created ON public.quota_usage_logs(created_at DESC);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.quota_usage_logs;

-- ===== END SOURCE: 20260207234919_3b703a60-74a4-4b19-914a-bce0c90381c7.sql =====
