-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 01_20260127034916_to_20260127080732.sql .. 16_20260907020000_pos_marketplace_stock_guard.sql

-- ===== BEGIN BUNDLE: 01_20260127034916_to_20260127080732.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260127034916_79ea4061-eab6-4151-9591-63293a92b7fe.sql .. 20260127080732_36fd1d8b-6207-4fed-8758-87368ec25e10.sql


-- ===== BEGIN SOURCE: 20260127034916_79ea4061-eab6-4151-9591-63293a92b7fe.sql =====
-- ============================================
-- DESA WISATA & UMKM - DATABASE SCHEMA
-- ============================================

-- 1. Create app_role enum for user roles.
-- The bootstrap may be retried after a partial run, so tolerate an existing type.
DO $$
BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'buyer');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 2. Create user_roles table (separate from profiles for security)
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL DEFAULT 'buyer',
    UNIQUE (user_id, role)
);

-- 3. Create profiles table
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    full_name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    address TEXT,
    village TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 4. Create villages table
CREATE TABLE public.villages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    district TEXT NOT NULL,
    regency TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 5. Create merchants table
CREATE TABLE public.merchants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    village_id UUID REFERENCES public.villages(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    open_time TIME,
    close_time TIME,
    classification_price TEXT CHECK (classification_price IN ('UNDER_5K', 'FROM_5K_TO_10K', 'FROM_10K_TO_20K', 'ABOVE_20K')),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    order_mode TEXT NOT NULL DEFAULT 'ADMIN_ASSISTED' CHECK (order_mode IN ('SELF', 'ADMIN_ASSISTED')),
    rating_avg DECIMAL(2,1) DEFAULT 0,
    rating_count INTEGER DEFAULT 0,
    badge TEXT CHECK (badge IN ('VERIFIED', 'POPULAR', 'NEW')),
    image_url TEXT,
    is_open BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 6. Create products table
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    price INTEGER NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    image_url TEXT,
    category TEXT NOT NULL CHECK (category IN ('kuliner', 'fashion', 'kriya')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_promo BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 7. Create tourism table
CREATE TABLE public.tourism (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    village_id UUID REFERENCES public.villages(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    wa_link TEXT,
    sosmed_link TEXT,
    facilities TEXT[] DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    view_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 8. Create orders table
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW', 'PROCESSED', 'SENT', 'DONE', 'CANCELED')),
    handled_by TEXT NOT NULL DEFAULT 'ADMIN' CHECK (handled_by IN ('ADMIN', 'MERCHANT')),
    delivery_type TEXT NOT NULL DEFAULT 'PICKUP' CHECK (delivery_type IN ('PICKUP', 'INTERNAL')),
    delivery_address TEXT,
    delivery_phone TEXT,
    delivery_name TEXT,
    shipping_cost INTEGER NOT NULL DEFAULT 0,
    subtotal INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 9. Create order_items table
CREATE TABLE public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    product_price INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    subtotal INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to check if user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- Function to check if current user is admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'admin')
$$;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-update timestamps
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_merchants_updated_at ON public.merchants;
CREATE TRIGGER update_merchants_updated_at
    BEFORE UPDATE ON public.merchants
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create profile and buyer role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (user_id, full_name)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''));

    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'buyer');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- RLS POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.villages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- USER_ROLES policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
CREATE POLICY "Users can view own roles"
    ON public.user_roles FOR SELECT
    USING (auth.uid() = user_id);

-- PROFILES policies
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- VILLAGES policies (public read)
DROP POLICY IF EXISTS "Anyone can view active villages" ON public.villages;
CREATE POLICY "Anyone can view active villages"
    ON public.villages FOR SELECT
    USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages;
CREATE POLICY "Admins can manage villages"
    ON public.villages FOR ALL
    USING (public.is_admin());

-- MERCHANTS policies (public read)
DROP POLICY IF EXISTS "Anyone can view active merchants" ON public.merchants;
CREATE POLICY "Anyone can view active merchants"
    ON public.merchants FOR SELECT
    USING (status = 'ACTIVE');

DROP POLICY IF EXISTS "Admins can manage merchants" ON public.merchants;
CREATE POLICY "Admins can manage merchants"
    ON public.merchants FOR ALL
    USING (public.is_admin());

-- PRODUCTS policies (public read)
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products;
CREATE POLICY "Anyone can view active products"
    ON public.products FOR SELECT
    USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
CREATE POLICY "Admins can manage products"
    ON public.products FOR ALL
    USING (public.is_admin());

-- TOURISM policies (public read)
DROP POLICY IF EXISTS "Anyone can view active tourism" ON public.tourism;
CREATE POLICY "Anyone can view active tourism"
    ON public.tourism FOR SELECT
    USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage tourism" ON public.tourism;
CREATE POLICY "Admins can manage tourism"
    ON public.tourism FOR ALL
    USING (public.is_admin());

-- ORDERS policies
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
CREATE POLICY "Buyers can view own orders"
    ON public.orders FOR SELECT
    USING (auth.uid() = buyer_id OR public.is_admin());

DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
CREATE POLICY "Buyers can create orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = buyer_id);

DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;
CREATE POLICY "Buyers can update own pending orders"
    ON public.orders FOR UPDATE
    USING (auth.uid() = buyer_id AND status = 'NEW');

DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
CREATE POLICY "Admins can manage all orders"
    ON public.orders FOR ALL
    USING (public.is_admin());

-- ORDER_ITEMS policies
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
CREATE POLICY "Users can view own order items"
    ON public.order_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND (orders.buyer_id = auth.uid() OR public.is_admin())
        )
    );

DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items;
CREATE POLICY "Users can insert order items for own orders"
    ON public.order_items FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND orders.buyer_id = auth.uid()
        )
    );

-- ============================================
-- SEED DATA
-- ============================================

-- Insert sample villages
INSERT INTO public.villages (id, name, district, regency, description, is_active) VALUES
('11111111-1111-1111-1111-111111111111', 'Desa Bojong', 'Megamendung', 'Bogor', 'Desa wisata dengan pemandangan sawah terasering yang memukau dan udara sejuk pegunungan.', true),
('22222222-2222-2222-2222-222222222222', 'Desa Sukamaju', 'Cisarua', 'Sukabumi', 'Desa dengan kebun teh yang indah dan arsitektur tradisional Sunda yang masih terjaga.', true);

-- Insert sample merchants
INSERT INTO public.merchants (id, village_id, name, address, phone, open_time, close_time, classification_price, status, order_mode, rating_avg, rating_count, badge, is_open) VALUES
('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Warung Bu Siti', 'Jl. Sawah Indah No. 5', '081234567890', '08:00', '17:00', 'UNDER_5K', 'ACTIVE', 'ADMIN_ASSISTED', 4.8, 124, 'VERIFIED', true),
('aaaa2222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Kopi Desa', 'Jl. Perkebunan No. 12', '081234567891', '07:00', '20:00', 'FROM_10K_TO_20K', 'ACTIVE', 'SELF', 4.9, 89, 'POPULAR', true),
('aaaa3333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Kerajinan Mandiri', 'Kampung Kriya Rt 03/02', '081234567892', '09:00', '16:00', 'ABOVE_20K', 'ACTIVE', 'ADMIN_ASSISTED', 4.7, 56, 'VERIFIED', true),
('aaaa4444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Dapur Emak', 'Jl. Kuliner Desa No. 8', '081234567893', '06:00', '18:00', 'FROM_5K_TO_10K', 'ACTIVE', 'ADMIN_ASSISTED', 4.6, 203, NULL, true);

-- Insert sample products
INSERT INTO public.products (id, merchant_id, name, description, price, stock, category, is_active, is_promo) VALUES
('bbbb1111-1111-1111-1111-111111111111', 'aaaa1111-1111-1111-1111-111111111111', 'Keripik Pisang Manis', 'Keripik pisang renyah dengan rasa manis gurih khas desa. Dibuat dari pisang pilihan yang diolah dengan cara tradisional.', 15000, 50, 'kuliner', true, true),
('bbbb2222-2222-2222-2222-222222222222', 'aaaa2222-2222-2222-2222-222222222222', 'Kopi Bubuk Robusta', 'Kopi robusta pilihan dari kebun kopi desa, digiling halus dengan aroma yang kuat dan rasa yang nikmat.', 35000, 30, 'kuliner', true, false),
('bbbb3333-3333-3333-3333-333333333333', 'aaaa3333-3333-3333-3333-333333333333', 'Tas Anyaman Bambu', 'Tas anyaman bambu buatan tangan dengan desain modern namun tetap tradisional. Cocok untuk berbagai acara.', 75000, 15, 'kriya', true, false),
('bbbb4444-4444-4444-4444-444444444444', 'aaaa4444-4444-4444-4444-444444444444', 'Sambal Bawang Botol', 'Sambal bawang pedas gurih dalam kemasan botol, tahan lama dan cocok untuk oleh-oleh.', 20000, 100, 'kuliner', true, true);

-- Insert sample tourism
INSERT INTO public.tourism (id, village_id, name, description, wa_link, sosmed_link, facilities, is_active, view_count) VALUES
('cccc1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Kampung Awan & Sawah', 'Menawarkan pengalaman otentik hidup di desa dengan pemandangan sawah terasering yang memukau mata. Udara sejuk pegunungan dan keramahan warga lokal akan membuat liburan Anda tak terlupakan.', 'https://wa.me/6281234567890', 'https://instagram.com/kampungawan', ARRAY['Area Parkir Luas', 'Toilet Bersih', 'Spot Foto', 'Warung Makan', 'Mushola', 'Penginapan'], true, 1523),
('cccc2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Kebun Teh Panorama', 'Hamparan kebun teh yang hijau dengan pemandangan pegunungan. Udara segar dan suasana tenang cocok untuk melepas penat.', 'https://wa.me/6281234567891', NULL, ARRAY['Parkir', 'Toilet', 'Warung', 'Spot Foto'], true, 892);

-- ===== END SOURCE: 20260127034916_79ea4061-eab6-4151-9591-63293a92b7fe.sql =====

-- ===== BEGIN SOURCE: 20260127040144_c74a27a5-34d0-4b71-8b2e-458908a16583.sql =====
-- Step 1: Add 'verifikator' role to the enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'verifikator';

-- ===== END SOURCE: 20260127040144_c74a27a5-34d0-4b71-8b2e-458908a16583.sql =====

-- ===== BEGIN SOURCE: 20260127040154_47ea7885-7f85-461b-b087-44645cbb6ef2.sql =====
-- Update merchants table to have proper registration status
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS registration_status text NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS registered_at timestamp with time zone DEFAULT now(),
ADD COLUMN IF NOT EXISTS approved_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS approved_by uuid,
ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Update villages table to have proper registration status
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS registration_status text NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS registered_at timestamp with time zone DEFAULT now(),
ADD COLUMN IF NOT EXISTS approved_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS approved_by uuid,
ADD COLUMN IF NOT EXISTS rejection_reason text,
ADD COLUMN IF NOT EXISTS contact_name text,
ADD COLUMN IF NOT EXISTS contact_phone text,
ADD COLUMN IF NOT EXISTS contact_email text;

-- Create helper function to check if user is verifikator
CREATE OR REPLACE FUNCTION public.is_verifikator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'verifikator')
$$;

-- Allow anyone to register a village (pending approval by admin)
DROP POLICY IF EXISTS "Anyone can register village" ON public.villages;
CREATE POLICY "Anyone can register village"
ON public.villages
FOR INSERT
WITH CHECK (
  registration_status = 'PENDING' AND
  is_active = false
);

-- Allow anyone to register a merchant (pending approval by verifikator)
DROP POLICY IF EXISTS "Anyone can register merchant" ON public.merchants;
CREATE POLICY "Anyone can register merchant"
ON public.merchants
FOR INSERT
WITH CHECK (
  registration_status = 'PENDING' AND
  status = 'PENDING'
);

-- Verifikator can manage merchants (approve/reject)
DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants;
CREATE POLICY "Verifikator can manage merchants"
ON public.merchants
FOR ALL
USING (is_verifikator());

-- Update existing merchants to have APPROVED status
UPDATE public.merchants SET registration_status = 'APPROVED' WHERE registration_status = 'PENDING';

-- Update existing villages to have APPROVED status
UPDATE public.villages SET registration_status = 'APPROVED' WHERE registration_status = 'PENDING';

-- ===== END SOURCE: 20260127040154_47ea7885-7f85-461b-b087-44645cbb6ef2.sql =====

-- ===== BEGIN SOURCE: 20260127040954_2216fe5d-dd36-41c3-9878-7c471cf71795.sql =====
-- Add verifikator referral system
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS verifikator_code text,
ADD COLUMN IF NOT EXISTS verifikator_id uuid,
ADD COLUMN IF NOT EXISTS trade_group text,
ADD COLUMN IF NOT EXISTS province text,
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS district text,
ADD COLUMN IF NOT EXISTS subdistrict text,
ADD COLUMN IF NOT EXISTS business_category text DEFAULT 'kuliner',
ADD COLUMN IF NOT EXISTS business_description text;

-- Create verifikator_codes table for referral system
CREATE TABLE IF NOT EXISTS public.verifikator_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  code text NOT NULL UNIQUE,
  trade_group text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0,
  max_usage integer,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.verifikator_codes ENABLE ROW LEVEL SECURITY;

-- Anyone can view active codes (for validation)
DROP POLICY IF EXISTS "Anyone can view active codes" ON public.verifikator_codes;
CREATE POLICY "Anyone can view active codes"
ON public.verifikator_codes
FOR SELECT
USING (is_active = true);

-- Verifikator can manage their own codes
DROP POLICY IF EXISTS "Verifikator can manage own codes" ON public.verifikator_codes;
CREATE POLICY "Verifikator can manage own codes"
ON public.verifikator_codes
FOR ALL
USING (
  verifikator_id = auth.uid() OR
  is_admin()
);

-- Admin can manage all codes
DROP POLICY IF EXISTS "Admin can manage all codes" ON public.verifikator_codes;
CREATE POLICY "Admin can manage all codes"
ON public.verifikator_codes
FOR ALL
USING (is_admin());

-- Update villages to include subdistrict for matching
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS subdistrict text;

-- Update existing villages with subdistrict from district if not set
UPDATE public.villages
SET subdistrict = district
WHERE subdistrict IS NULL;

-- Insert sample verifikator codes for testing
INSERT INTO public.verifikator_codes (verifikator_id, code, trade_group, description)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'KULINER2024', 'Kelompok Kuliner Desa', 'Kode referral untuk pedagang kuliner'),
  ('00000000-0000-0000-0000-000000000000', 'KRIYA2024', 'Kelompok Kerajinan Tangan', 'Kode referral untuk pengrajin'),
  ('00000000-0000-0000-0000-000000000000', 'FASHION2024', 'Kelompok Fashion Lokal', 'Kode referral untuk pedagang fashion')
ON CONFLICT (code) DO NOTHING;

-- ===== END SOURCE: 20260127040954_2216fe5d-dd36-41c3-9878-7c471cf71795.sql =====

-- ===== BEGIN SOURCE: 20260127042912_2ef5eeb6-1027-4e85-b3b2-f10eb734fb29.sql =====
-- Create promotions/ads table for various ad types
CREATE TABLE public.promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('banner', 'wisata_populer', 'produk_populer', 'promo_spesial')),
  title TEXT NOT NULL,
  subtitle TEXT,
  image_url TEXT,
  link_url TEXT,
  link_type TEXT CHECK (link_type IN ('product', 'tourism', 'village', 'merchant', 'external', 'category')),
  link_id UUID,

  -- Who is advertising
  advertiser_type TEXT CHECK (advertiser_type IN ('admin', 'village', 'merchant')),
  advertiser_id UUID,

  -- Scheduling
  start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  end_date TIMESTAMP WITH TIME ZONE,

  -- Pricing & Status
  price INTEGER DEFAULT 0,
  is_paid BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  is_approved BOOLEAN DEFAULT false,

  -- Ordering
  sort_order INTEGER DEFAULT 0,

  -- Stats
  view_count INTEGER DEFAULT 0,
  click_count INTEGER DEFAULT 0,

  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

-- Anyone can view active & approved promotions within date range
DROP POLICY IF EXISTS "Anyone can view active promotions" ON public.promotions;
CREATE POLICY "Anyone can view active promotions"
ON public.promotions
FOR SELECT
USING (
  is_active = true
  AND is_approved = true
  AND start_date <= now()
  AND (end_date IS NULL OR end_date >= now())
);

-- Admin can manage all promotions
DROP POLICY IF EXISTS "Admins can manage promotions" ON public.promotions;
CREATE POLICY "Admins can manage promotions"
ON public.promotions
FOR ALL
USING (is_admin());

-- Villages can create promotions for themselves
DROP POLICY IF EXISTS "Villages can create own promotions" ON public.promotions;
CREATE POLICY "Villages can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'village'
  AND is_approved = false
);

-- Merchants can create promotions for themselves
DROP POLICY IF EXISTS "Merchants can create own promotions" ON public.promotions;
CREATE POLICY "Merchants can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'merchant'
  AND is_approved = false
);

-- Add trigger for updated_at
DROP TRIGGER IF EXISTS update_promotions_updated_at ON public.promotions;
CREATE TRIGGER update_promotions_updated_at
BEFORE UPDATE ON public.promotions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Insert sample banner promotions
INSERT INTO public.promotions (type, title, subtitle, image_url, link_url, link_type, advertiser_type, is_approved, sort_order) VALUES
('banner', 'Jelajahi Produk Asli Desa', 'Dukung UMKM lokal & ekonomi desa Indonesia', NULL, '/products', 'category', 'admin', true, 1),
('banner', 'Wisata Desa Bojong', 'Nikmati keindahan alam dan budaya desa', NULL, '/tourism', 'category', 'admin', true, 2),
('banner', 'Promo Spesial Akhir Bulan', 'Diskon hingga 30% untuk produk pilihan', NULL, '/products', 'category', 'admin', true, 3);

-- ===== END SOURCE: 20260127042912_2ef5eeb6-1027-4e85-b3b2-f10eb734fb29.sql =====

-- ===== BEGIN SOURCE: 20260127050757_6ed5af1f-fcf8-4b26-9e1a-d9a52e1c4341.sql =====
-- Create couriers table for village delivery persons
CREATE TABLE public.couriers (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT,
    -- Address fields
    province TEXT NOT NULL,
    city TEXT NOT NULL,
    district TEXT NOT NULL,
    subdistrict TEXT NOT NULL,
    address TEXT NOT NULL,
    -- Documents
    ktp_number TEXT NOT NULL,
    ktp_image_url TEXT NOT NULL,
    photo_url TEXT NOT NULL,
    vehicle_type TEXT NOT NULL DEFAULT 'motor',
    vehicle_plate TEXT,
    vehicle_image_url TEXT NOT NULL,
    -- Status
    registration_status TEXT NOT NULL DEFAULT 'PENDING',
    status TEXT NOT NULL DEFAULT 'INACTIVE',
    is_available BOOLEAN NOT NULL DEFAULT false,
    -- Tracking
    current_lat NUMERIC,
    current_lng NUMERIC,
    last_location_update TIMESTAMP WITH TIME ZONE,
    -- Metadata
    village_id UUID REFERENCES public.villages(id),
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create app_settings table for dynamic configuration
CREATE TABLE public.app_settings (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    value JSONB NOT NULL DEFAULT '{}',
    description TEXT,
    category TEXT NOT NULL DEFAULT 'general',
    updated_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- RLS policies for couriers
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
CREATE POLICY "Admins can manage couriers" ON public.couriers
FOR ALL USING (is_admin());

DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;
CREATE POLICY "Verifikator can manage couriers" ON public.couriers
FOR ALL USING (is_verifikator());

DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
CREATE POLICY "Anyone can register as courier" ON public.couriers
FOR INSERT WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');

DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers;
CREATE POLICY "Active couriers visible to authenticated" ON public.couriers
FOR SELECT USING (status = 'ACTIVE' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
CREATE POLICY "Couriers can view own data" ON public.couriers
FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
CREATE POLICY "Couriers can update own location" ON public.couriers
FOR UPDATE USING (user_id = auth.uid() AND status = 'ACTIVE');

-- RLS policies for app_settings
DROP POLICY IF EXISTS "Admins can manage settings" ON public.app_settings;
CREATE POLICY "Admins can manage settings" ON public.app_settings
FOR ALL USING (is_admin());

DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings;
CREATE POLICY "Anyone can view settings" ON public.app_settings
FOR SELECT USING (true);

-- Update trigger for couriers
DROP TRIGGER IF EXISTS update_couriers_updated_at ON public.couriers;
CREATE TRIGGER update_couriers_updated_at
BEFORE UPDATE ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Update trigger for app_settings
DROP TRIGGER IF EXISTS update_app_settings_updated_at ON public.app_settings;
CREATE TRIGGER update_app_settings_updated_at
BEFORE UPDATE ON public.app_settings
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Insert default settings
INSERT INTO public.app_settings (key, value, description, category) VALUES
('registration_village', '{"enabled": true}', 'Enable/disable village registration', 'registration'),
('registration_merchant', '{"enabled": true}', 'Enable/disable merchant registration', 'registration'),
('registration_courier', '{"enabled": true}', 'Enable/disable courier registration', 'registration'),
('address_api', '{"provider": "emsifa", "base_url": "https://emsifa.github.io/api-wilayah-indonesia/api"}', 'Address API configuration', 'integration'),
('payment_midtrans', '{"enabled": false, "server_key": "", "client_key": "", "is_production": false}', 'Midtrans payment gateway', 'payment'),
('payment_xendit', '{"enabled": false, "secret_key": "", "public_key": ""}', 'Xendit payment gateway', 'payment');

-- ===== END SOURCE: 20260127050757_6ed5af1f-fcf8-4b26-9e1a-d9a52e1c4341.sql =====

-- ===== BEGIN SOURCE: 20260127050807_5424a090-976a-43a6-a53b-fc9048a993a0.sql =====
-- Create storage bucket for courier documents
INSERT INTO storage.buckets (id, name, public) VALUES ('courier-documents', 'courier-documents', false);

-- Storage policies for courier-documents bucket (safe to retry)
DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects;

DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
CREATE POLICY "Anyone can upload courier documents" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'courier-documents');

DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
CREATE POLICY "Admins can view all courier documents" ON storage.objects
FOR SELECT USING (bucket_id = 'courier-documents' AND (is_admin() OR is_verifikator()));

DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects;
CREATE POLICY "Couriers can view own documents" ON storage.objects
FOR SELECT USING (
    bucket_id = 'courier-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects;
CREATE POLICY "Admins can delete courier documents" ON storage.objects
FOR DELETE USING (bucket_id = 'courier-documents' AND is_admin());

-- ===== END SOURCE: 20260127050807_5424a090-976a-43a6-a53b-fc9048a993a0.sql =====

-- ===== BEGIN SOURCE: 20260127051948_615b5ca5-49e7-42cd-8576-7cb91864be50.sql =====
-- Add address component columns to profiles table for auto-fill functionality
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS province_id TEXT,
ADD COLUMN IF NOT EXISTS province_name TEXT,
ADD COLUMN IF NOT EXISTS city_id TEXT,
ADD COLUMN IF NOT EXISTS city_name TEXT,
ADD COLUMN IF NOT EXISTS district_id TEXT,
ADD COLUMN IF NOT EXISTS district_name TEXT,
ADD COLUMN IF NOT EXISTS village_id TEXT,
ADD COLUMN IF NOT EXISTS village_name TEXT,
ADD COLUMN IF NOT EXISTS address_detail TEXT;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id);

-- ===== END SOURCE: 20260127051948_615b5ca5-49e7-42cd-8576-7cb91864be50.sql =====

-- ===== BEGIN SOURCE: 20260127052521_5e73eccb-ebdb-4515-8bc4-65ce1ad4a2c4.sql =====
-- Add courier assignment to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS courier_id UUID REFERENCES public.couriers(id),
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS delivery_lat NUMERIC,
ADD COLUMN IF NOT EXISTS delivery_lng NUMERIC;

-- Create index for courier lookups
CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON public.orders(courier_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);

-- Update RLS policies for couriers to view assigned orders
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
CREATE POLICY "Couriers can view assigned orders"
ON public.orders
FOR SELECT
USING (courier_id IN (SELECT id FROM couriers WHERE user_id = auth.uid()));

-- Couriers can update assigned orders (status changes)
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
CREATE POLICY "Couriers can update assigned orders"
ON public.orders
FOR UPDATE
USING (courier_id IN (SELECT id FROM couriers WHERE user_id = auth.uid()));

-- ===== END SOURCE: 20260127052521_5e73eccb-ebdb-4515-8bc4-65ce1ad4a2c4.sql =====

-- ===== BEGIN SOURCE: 20260127053454_d2fca9ce-0e9b-4e21-807b-3e480403c35f.sql =====
-- Add new roles to app_role enum
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'merchant';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'courier';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'admin_desa';

-- ===== END SOURCE: 20260127053454_d2fca9ce-0e9b-4e21-807b-3e480403c35f.sql =====

-- ===== BEGIN SOURCE: 20260127053503_93b80401-116b-40a6-b26a-21a80229bed4.sql =====
-- Create helper functions for role checking
CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id uuid)
RETURNS text[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(role::text), ARRAY[]::text[])
  FROM public.user_roles
  WHERE user_id = _user_id
$$;

CREATE OR REPLACE FUNCTION public.has_any_role(_user_id uuid, _roles app_role[])
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = ANY(_roles)
  )
$$;

-- Function to check if user is merchant
CREATE OR REPLACE FUNCTION public.is_merchant()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'merchant')
$$;

-- Function to check if user is courier
CREATE OR REPLACE FUNCTION public.is_courier()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'courier')
$$;

-- Function to check if user is admin desa
CREATE OR REPLACE FUNCTION public.is_admin_desa()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'admin_desa')
$$;

-- ===== END SOURCE: 20260127053503_93b80401-116b-40a6-b26a-21a80229bed4.sql =====

-- ===== BEGIN SOURCE: 20260127054855_541d780b-df94-4ab1-9cd8-7306ea1c7256.sql =====
-- Allow merchants to manage their own products
DROP POLICY IF EXISTS "Merchants can manage own products" ON public.products;
CREATE POLICY "Merchants can manage own products"
ON public.products
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = products.merchant_id
    AND merchants.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = products.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

-- Allow merchants to view their own orders
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;
CREATE POLICY "Merchants can view own orders"
ON public.orders
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = orders.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

-- Allow merchants to update their own orders
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
CREATE POLICY "Merchants can update own orders"
ON public.orders
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = orders.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

-- Allow merchants to view own data
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants;
CREATE POLICY "Merchants can view own data"
ON public.merchants
FOR SELECT
USING (user_id = auth.uid());

-- Allow merchants to update own data
DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants;
CREATE POLICY "Merchants can update own data"
ON public.merchants
FOR UPDATE
USING (user_id = auth.uid());

-- Allow admin desa to manage tourism in their village
DROP POLICY IF EXISTS "Admin desa can manage tourism" ON public.tourism;
CREATE POLICY "Admin desa can manage tourism"
ON public.tourism
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.villages
    WHERE villages.id = tourism.village_id
    AND villages.registration_status = 'APPROVED'
  )
  AND is_admin_desa()
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.villages
    WHERE villages.id = tourism.village_id
    AND villages.registration_status = 'APPROVED'
  )
  AND is_admin_desa()
);

-- ===== END SOURCE: 20260127054855_541d780b-df94-4ab1-9cd8-7306ea1c7256.sql =====

-- ===== BEGIN SOURCE: 20260127060039_0394bf48-8830-43b0-b2d8-e5ddcb18a716.sql =====
-- Create storage buckets for images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('product-images', 'product-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('tourism-images', 'tourism-images', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('profile-images', 'profile-images', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('merchant-images', 'merchant-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING;

-- RLS for product-images: Merchants can upload to their own folder
DROP POLICY IF EXISTS "Anyone can view product images" ON storage.objects;
CREATE POLICY "Anyone can view product images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Merchants can upload product images" ON storage.objects;
CREATE POLICY "Merchants can upload product images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
      AND merchants.status = 'ACTIVE'
    )
  )
);

DROP POLICY IF EXISTS "Merchants can update own product images" ON storage.objects;
CREATE POLICY "Merchants can update own product images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "Merchants can delete own product images" ON storage.objects;
CREATE POLICY "Merchants can delete own product images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
);

-- RLS for tourism-images: Admin desa can upload
DROP POLICY IF EXISTS "Anyone can view tourism images" ON storage.objects;
CREATE POLICY "Anyone can view tourism images"
ON storage.objects FOR SELECT
USING (bucket_id = 'tourism-images');

DROP POLICY IF EXISTS "Admin desa can upload tourism images" ON storage.objects;
CREATE POLICY "Admin desa can upload tourism images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
);

DROP POLICY IF EXISTS "Admin desa can update tourism images" ON storage.objects;
CREATE POLICY "Admin desa can update tourism images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
);

DROP POLICY IF EXISTS "Admin desa can delete tourism images" ON storage.objects;
CREATE POLICY "Admin desa can delete tourism images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
);

-- RLS for profile-images: Users can upload their own
DROP POLICY IF EXISTS "Anyone can view profile images" ON storage.objects;
CREATE POLICY "Anyone can view profile images"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-images');

DROP POLICY IF EXISTS "Users can upload own profile image" ON storage.objects;
CREATE POLICY "Users can upload own profile image"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'profile-images'
  AND auth.uid() IS NOT NULL
);

DROP POLICY IF EXISTS "Users can update own profile image" ON storage.objects;
CREATE POLICY "Users can update own profile image"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'profile-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can delete own profile image" ON storage.objects;
CREATE POLICY "Users can delete own profile image"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'profile-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS for merchant-images: Merchants can upload their store image
DROP POLICY IF EXISTS "Anyone can view merchant images" ON storage.objects;
CREATE POLICY "Anyone can view merchant images"
ON storage.objects FOR SELECT
USING (bucket_id = 'merchant-images');

DROP POLICY IF EXISTS "Merchants can upload merchant images" ON storage.objects;
CREATE POLICY "Merchants can upload merchant images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    auth.uid() IS NOT NULL
  )
);

DROP POLICY IF EXISTS "Merchants can update own merchant images" ON storage.objects;
CREATE POLICY "Merchants can update own merchant images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "Merchants can delete own merchant images" ON storage.objects;
CREATE POLICY "Merchants can delete own merchant images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
);

-- Add avatar_url to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- ===== END SOURCE: 20260127060039_0394bf48-8830-43b0-b2d8-e5ddcb18a716.sql =====

-- ===== BEGIN SOURCE: 20260127060220_ac30b0ec-8474-4fdb-8e3e-548787ed7e88.sql =====
-- Insert shipping and platform fee settings into app_settings
INSERT INTO public.app_settings (key, category, value, description) VALUES
  ('shipping_base_fee', 'shipping', '{"base_fee": 5000, "per_km_fee": 2000, "min_fee": 5000, "max_fee": 50000, "free_shipping_min_order": 100000}'::jsonb, 'Pengaturan biaya kirim dasar'),
  ('platform_fee', 'platform', '{"percentage": 5, "min_fee": 1000, "max_fee": 50000, "enabled": true}'::jsonb, 'Pengaturan biaya platform/komisi'),
  ('shipping_zones', 'shipping', '{"zones": [{"name": "Dalam Desa", "max_distance_km": 5, "fee": 5000}, {"name": "Antar Desa", "max_distance_km": 15, "fee": 10000}, {"name": "Luar Kecamatan", "max_distance_km": 30, "fee": 20000}]}'::jsonb, 'Zona pengiriman berdasarkan jarak')
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260127060220_ac30b0ec-8474-4fdb-8e3e-548787ed7e88.sql =====

-- ===== BEGIN SOURCE: 20260127061057_063aa236-597e-45b1-8825-327291dbdcb7.sql =====
-- Add payment columns to orders table
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'UNPAID',
ADD COLUMN IF NOT EXISTS payment_invoice_id TEXT,
ADD COLUMN IF NOT EXISTS payment_invoice_url TEXT,
ADD COLUMN IF NOT EXISTS payment_paid_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS payment_method TEXT,
ADD COLUMN IF NOT EXISTS payment_channel TEXT;

-- Add index for payment status
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status);

-- Comment for documentation
COMMENT ON COLUMN public.orders.payment_status IS 'Payment status: UNPAID, PENDING, PAID, EXPIRED, REFUNDED';
COMMENT ON COLUMN public.orders.payment_invoice_id IS 'Xendit invoice ID';
COMMENT ON COLUMN public.orders.payment_invoice_url IS 'URL for payment page';

-- ===== END SOURCE: 20260127061057_063aa236-597e-45b1-8825-327291dbdcb7.sql =====

-- ===== BEGIN SOURCE: 20260127062119_a67ab6c0-5e7b-4072-8099-8c4df996af78.sql =====
-- Add blocking fields to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_blocked boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS blocked_at timestamp with time zone,
ADD COLUMN IF NOT EXISTS blocked_by uuid,
ADD COLUMN IF NOT EXISTS block_reason text;

-- Create refund_requests table
CREATE TABLE public.refund_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
    buyer_id uuid NOT NULL,
    amount integer NOT NULL,
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'PENDING',
    admin_notes text,
    processed_by uuid,
    processed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Create admin_audit_logs table
CREATE TABLE public.admin_audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id uuid NOT NULL,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    old_value jsonb,
    new_value jsonb,
    ip_address text,
    user_agent text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS for refund_requests
DROP POLICY IF EXISTS "Admins can manage refunds" ON public.refund_requests;
CREATE POLICY "Admins can manage refunds" ON public.refund_requests
FOR ALL USING (is_admin());

DROP POLICY IF EXISTS "Buyers can view own refunds" ON public.refund_requests;
CREATE POLICY "Buyers can view own refunds" ON public.refund_requests
FOR SELECT USING (buyer_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests;
CREATE POLICY "Buyers can create refund requests" ON public.refund_requests
FOR INSERT WITH CHECK (buyer_id = auth.uid() AND status = 'PENDING');

-- RLS for admin_audit_logs (admin only)
DROP POLICY IF EXISTS "Admins can view logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can view logs" ON public.admin_audit_logs
FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS "Admins can insert logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs
FOR INSERT WITH CHECK (is_admin());

-- Update profiles RLS to allow admin to update block status
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE USING (auth.uid() = user_id AND is_blocked = false);

DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
CREATE POLICY "Admins can update any profile" ON public.profiles
FOR ALL USING (is_admin());

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_refund_requests_status ON public.refund_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_buyer ON public.refund_requests(buyer_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON public.refund_requests;
CREATE TRIGGER update_refund_requests_updated_at
BEFORE UPDATE ON public.refund_requests
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260127062119_a67ab6c0-5e7b-4072-8099-8c4df996af78.sql =====

-- ===== BEGIN SOURCE: 20260127062432_f542c2e2-d473-4f9c-92bc-ea76247d5faf.sql =====
-- Add foreign key for admin_audit_logs to profiles
ALTER TABLE public.admin_audit_logs
ADD CONSTRAINT admin_audit_logs_admin_id_fkey
FOREIGN KEY (admin_id) REFERENCES auth.users(id);

-- Add foreign key for refund_requests buyer_id to auth.users
ALTER TABLE public.refund_requests
ADD CONSTRAINT refund_requests_buyer_id_fkey
FOREIGN KEY (buyer_id) REFERENCES auth.users(id);

-- ===== END SOURCE: 20260127062432_f542c2e2-d473-4f9c-92bc-ea76247d5faf.sql =====

-- ===== BEGIN SOURCE: 20260127062918_7e2d4642-c9d9-4461-8244-ee1dcf9f0d5f.sql =====
-- =============================================
-- MERCHANT DASHBOARD & COD SECURITY SCHEMA
-- =============================================

-- 1. Add product analytics columns
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS order_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS discount_percent INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS discount_end_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS min_stock_alert INTEGER DEFAULT 5;

-- 2. Add COD security fields to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS cod_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS trust_score INTEGER DEFAULT 100,
ADD COLUMN IF NOT EXISTS cod_fail_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_verified_buyer BOOLEAN DEFAULT false;

-- 3. Create reviews table
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  buyer_id UUID NOT NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  image_urls TEXT[] DEFAULT '{}',
  merchant_reply TEXT,
  merchant_replied_at TIMESTAMP WITH TIME ZONE,
  is_visible BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 4. Create withdrawal_requests table
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 5. Create insurance_fund table for COD protection
CREATE TABLE IF NOT EXISTS public.insurance_fund (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  type TEXT NOT NULL, -- 'contribution' or 'claim'
  status TEXT DEFAULT 'PENDING', -- For claims: PENDING, APPROVED, REJECTED
  claim_reason TEXT,
  evidence_urls TEXT[] DEFAULT '{}',
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 6. Add COD-related fields to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS confirmation_deadline TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS is_flash_sale BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS flash_sale_discount INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cod_service_fee INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS buyer_distance_km NUMERIC;

-- 7. Add merchant balance tracking
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS available_balance INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS pending_balance INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_withdrawn INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cod_max_amount INTEGER DEFAULT 75000,
ADD COLUMN IF NOT EXISTS cod_max_distance_km NUMERIC DEFAULT 3;

-- Enable RLS on new tables
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_fund ENABLE ROW LEVEL SECURITY;

-- Reviews policies
DROP POLICY IF EXISTS "Anyone can view visible reviews" ON public.reviews;
CREATE POLICY "Anyone can view visible reviews" ON public.reviews
FOR SELECT USING (is_visible = true);

DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews;
CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews
FOR INSERT WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "Merchants can reply to their reviews" ON public.reviews;
CREATE POLICY "Merchants can reply to their reviews" ON public.reviews
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = reviews.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can manage reviews" ON public.reviews;
CREATE POLICY "Admins can manage reviews" ON public.reviews
FOR ALL USING (is_admin());

-- Withdrawal requests policies
DROP POLICY IF EXISTS "Merchants can view own withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = withdrawal_requests.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Merchants can create withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = withdrawal_requests.merchant_id
    AND merchants.user_id = auth.uid()
  ) AND status = 'PENDING'
);

DROP POLICY IF EXISTS "Admins can manage withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests
FOR ALL USING (is_admin());

-- Insurance fund policies
DROP POLICY IF EXISTS "Merchants can view own insurance" ON public.insurance_fund;
CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = insurance_fund.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Merchants can create claims" ON public.insurance_fund;
CREATE POLICY "Merchants can create claims" ON public.insurance_fund
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = insurance_fund.merchant_id
    AND merchants.user_id = auth.uid()
  ) AND type = 'claim' AND status = 'PENDING'
);

DROP POLICY IF EXISTS "Admins can manage insurance fund" ON public.insurance_fund;
CREATE POLICY "Admins can manage insurance fund" ON public.insurance_fund
FOR ALL USING (is_admin());

-- Function to check COD eligibility
CREATE OR REPLACE FUNCTION public.check_cod_eligibility(
  p_buyer_id UUID,
  p_merchant_id UUID,
  p_total_amount INTEGER,
  p_distance_km NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile RECORD;
  v_merchant RECORD;
  v_result JSONB;
BEGIN
  -- Get buyer profile
  SELECT cod_enabled, trust_score, cod_fail_count
  INTO v_profile
  FROM profiles
  WHERE user_id = p_buyer_id;

  -- Get merchant settings
  SELECT cod_max_amount, cod_max_distance_km
  INTO v_merchant
  FROM merchants
  WHERE id = p_merchant_id;

  -- Check eligibility
  IF v_profile.cod_enabled = false THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Akun Anda tidak dapat menggunakan fitur COD.');
  END IF;

  IF v_profile.trust_score < 50 THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Skor kepercayaan Anda terlalu rendah untuk COD.');
  END IF;

  IF p_total_amount > COALESCE(v_merchant.cod_max_amount, 75000) THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Nominal terlalu besar untuk COD. Maks: Rp ' || COALESCE(v_merchant.cod_max_amount, 75000));
  END IF;

  IF p_distance_km IS NOT NULL AND p_distance_km > COALESCE(v_merchant.cod_max_distance_km, 3) THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Jarak terlalu jauh untuk COD. Maks: ' || COALESCE(v_merchant.cod_max_distance_km, 3) || ' KM');
  END IF;

  RETURN jsonb_build_object('eligible', true, 'reason', NULL);
END;
$$;

-- Function to update trust score after COD result
CREATE OR REPLACE FUNCTION public.update_trust_score()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If order was rejected by buyer (COD failed)
  IF NEW.status = 'REJECTED_BY_BUYER' AND OLD.status != 'REJECTED_BY_BUYER' THEN
    UPDATE profiles
    SET
      trust_score = GREATEST(0, trust_score - 50),
      cod_fail_count = cod_fail_count + 1,
      cod_enabled = CASE WHEN trust_score - 50 < 50 THEN false ELSE cod_enabled END
    WHERE user_id = NEW.buyer_id;
  END IF;

  -- If COD order completed successfully
  IF NEW.status = 'DONE' AND OLD.status != 'DONE' AND NEW.payment_method = 'COD' THEN
    UPDATE profiles
    SET trust_score = LEAST(100, trust_score + 1)
    WHERE user_id = NEW.buyer_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger for trust score updates
DROP TRIGGER IF EXISTS trigger_update_trust_score ON orders;
CREATE TRIGGER trigger_update_trust_score
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION update_trust_score();

-- Function to auto-cancel pending confirmation orders
CREATE OR REPLACE FUNCTION public.auto_cancel_pending_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE orders
  SET
    status = 'CANCELED',
    notes = COALESCE(notes, '') || ' [Auto-canceled: Tidak dikonfirmasi dalam 15 menit]',
    updated_at = now()
  WHERE
    status = 'PENDING_CONFIRMATION'
    AND confirmation_deadline < now();
END;
$$;

-- Update updated_at trigger for new tables
DROP TRIGGER IF EXISTS update_reviews_updated_at ON public.reviews;
CREATE TRIGGER update_reviews_updated_at
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_withdrawal_requests_updated_at ON public.withdrawal_requests;
CREATE TRIGGER update_withdrawal_requests_updated_at
  BEFORE UPDATE ON public.withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260127062918_7e2d4642-c9d9-4461-8244-ee1dcf9f0d5f.sql =====

-- ===== BEGIN SOURCE: 20260127064118_a0730db2-7f53-430f-bfda-8a26acdce4a7.sql =====
-- Add COD settings to app_settings
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
  'cod_settings',
  '{"enabled": true, "max_amount": 75000, "max_distance_km": 3, "service_fee": 0, "min_trust_score": 50, "confirmation_timeout_minutes": 15, "penalty_points": 50, "success_bonus_points": 1}',
  'Pengaturan fitur COD (Cash on Delivery)',
  'payment'
) ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260127064118_a0730db2-7f53-430f-bfda-8a26acdce4a7.sql =====

-- ===== BEGIN SOURCE: 20260127065414_f4156ac7-8d42-4a89-9671-344dc88be763.sql =====
-- Create notifications table for realtime notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info', -- info, success, warning, error, order, withdrawal, verification
  link TEXT, -- Optional link to navigate to
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  read_at TIMESTAMP WITH TIME ZONE
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
CREATE POLICY "System can insert notifications" ON public.notifications
FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Admins can manage all notifications" ON public.notifications;
CREATE POLICY "Admins can manage all notifications" ON public.notifications
FOR ALL USING (is_admin());

-- Enable realtime for notifications
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- Create function to send notification
CREATE OR REPLACE FUNCTION public.send_notification(
  p_user_id UUID,
  p_title TEXT,
  p_message TEXT,
  p_type TEXT DEFAULT 'info',
  p_link TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  notification_id UUID;
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, link)
  VALUES (p_user_id, p_title, p_message, p_type, p_link)
  RETURNING id INTO notification_id;

  RETURN notification_id;
END;
$$;

-- Trigger to notify merchant when order status changes
CREATE OR REPLACE FUNCTION public.notify_order_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merchant_user_id UUID;
  order_status_text TEXT;
BEGIN
  -- Get merchant user_id
  SELECT user_id INTO merchant_user_id
  FROM merchants
  WHERE id = NEW.merchant_id;

  -- Map status to readable text
  CASE NEW.status
    WHEN 'NEW' THEN order_status_text := 'Pesanan Baru';
    WHEN 'PENDING_CONFIRMATION' THEN order_status_text := 'Menunggu Konfirmasi';
    WHEN 'PROCESSED' THEN order_status_text := 'Sedang Diproses';
    WHEN 'SENT' THEN order_status_text := 'Sedang Dikirim';
    WHEN 'DONE' THEN order_status_text := 'Selesai';
    WHEN 'CANCELED' THEN order_status_text := 'Dibatalkan';
    ELSE order_status_text := NEW.status;
  END CASE;

  -- Notify buyer on status change
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM send_notification(
      NEW.buyer_id,
      'Status Pesanan Diperbarui',
      'Pesanan #' || LEFT(NEW.id::TEXT, 8) || ' ' || order_status_text,
      'order',
      '/orders/' || NEW.id
    );
  END IF;

  -- Notify merchant on new order
  IF TG_OP = 'INSERT' AND merchant_user_id IS NOT NULL THEN
    PERFORM send_notification(
      merchant_user_id,
      'Pesanan Baru',
      'Anda menerima pesanan baru senilai Rp ' || NEW.total::TEXT,
      'order',
      '/merchant/orders'
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS order_notification_trigger ON orders;

-- Create trigger for order notifications
CREATE TRIGGER order_notification_trigger
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_order_change();

-- Trigger to notify merchant on withdrawal status change
CREATE OR REPLACE FUNCTION public.notify_withdrawal_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merchant_user_id UUID;
  status_text TEXT;
BEGIN
  -- Get merchant user_id
  SELECT user_id INTO merchant_user_id
  FROM merchants
  WHERE id = NEW.merchant_id;

  IF merchant_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Map status
  CASE NEW.status
    WHEN 'APPROVED' THEN status_text := 'disetujui';
    WHEN 'REJECTED' THEN status_text := 'ditolak';
    WHEN 'COMPLETED' THEN status_text := 'telah ditransfer';
    ELSE status_text := NEW.status;
  END CASE;

  -- Notify on status change
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status != 'PENDING' THEN
    PERFORM send_notification(
      merchant_user_id,
      'Penarikan Saldo ' || INITCAP(status_text),
      'Permintaan penarikan Rp ' || NEW.amount::TEXT || ' telah ' || status_text,
      'withdrawal',
      '/merchant/withdrawal'
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger for withdrawal notifications
DROP TRIGGER IF EXISTS withdrawal_notification_trigger ON withdrawal_requests;
CREATE TRIGGER withdrawal_notification_trigger
AFTER UPDATE ON withdrawal_requests
FOR EACH ROW
EXECUTE FUNCTION notify_withdrawal_change();

-- Trigger to notify on merchant verification
CREATE OR REPLACE FUNCTION public.notify_merchant_verification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND TG_OP = 'UPDATE' AND OLD.registration_status IS DISTINCT FROM NEW.registration_status THEN
    IF NEW.registration_status = 'APPROVED' THEN
      PERFORM send_notification(
        NEW.user_id,
        'Pendaftaran Merchant Disetujui',
        'Selamat! Toko ' || NEW.name || ' telah diverifikasi. Anda dapat mulai berjualan.',
        'success',
        '/merchant'
      );
    ELSIF NEW.registration_status = 'REJECTED' THEN
      PERFORM send_notification(
        NEW.user_id,
        'Pendaftaran Merchant Ditolak',
        'Maaf, pendaftaran toko ' || NEW.name || ' ditolak. Alasan: ' || COALESCE(NEW.rejection_reason, 'Tidak memenuhi syarat'),
        'error',
        '/register/merchant'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger for merchant verification notifications
DROP TRIGGER IF EXISTS merchant_verification_trigger ON merchants;
CREATE TRIGGER merchant_verification_trigger
AFTER UPDATE ON merchants
FOR EACH ROW
EXECUTE FUNCTION notify_merchant_verification();

-- Trigger to notify admin on new withdrawal request
CREATE OR REPLACE FUNCTION public.notify_admin_new_withdrawal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_id UUID;
  merchant_name TEXT;
BEGIN
  -- Get merchant name
  SELECT name INTO merchant_name FROM merchants WHERE id = NEW.merchant_id;

  -- Notify all admins
  FOR admin_id IN SELECT user_id FROM user_roles WHERE role = 'admin'
  LOOP
    PERFORM send_notification(
      admin_id,
      'Permintaan Penarikan Baru',
      merchant_name || ' mengajukan penarikan Rp ' || NEW.amount::TEXT,
      'withdrawal',
      '/admin/withdrawals'
    );
  END LOOP;

  RETURN NEW;
END;
$$;

-- Create trigger for new withdrawal notifications to admin
DROP TRIGGER IF EXISTS admin_withdrawal_notification_trigger ON withdrawal_requests;
CREATE TRIGGER admin_withdrawal_notification_trigger
AFTER INSERT ON withdrawal_requests
FOR EACH ROW
EXECUTE FUNCTION notify_admin_new_withdrawal();

-- ===== END SOURCE: 20260127065414_f4156ac7-8d42-4a89-9671-344dc88be763.sql =====

-- ===== BEGIN SOURCE: 20260127071956_a27ddf22-3789-42c9-bd9c-1f5a0286e319.sql =====
-- Transaction Packages Table (paket_transaksi)
CREATE TABLE public.transaction_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  classification_price TEXT NOT NULL,
  price_per_transaction INTEGER NOT NULL DEFAULT 0,
  kas_fee INTEGER NOT NULL DEFAULT 0,
  transaction_quota INTEGER NOT NULL DEFAULT 100,
  validity_days INTEGER NOT NULL DEFAULT 30,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Merchant Subscriptions Table (langganan pedagang)
CREATE TABLE public.merchant_subscriptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID NOT NULL REFERENCES public.transaction_packages(id),
  transaction_quota INTEGER NOT NULL DEFAULT 0,
  used_quota INTEGER NOT NULL DEFAULT 0,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  expired_at TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  payment_status TEXT NOT NULL DEFAULT 'UNPAID',
  payment_amount INTEGER NOT NULL DEFAULT 0,
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS for transaction_packages (public read, admin manage)
DROP POLICY IF EXISTS "Anyone can view active packages" ON public.transaction_packages;
CREATE POLICY "Anyone can view active packages"
ON public.transaction_packages FOR SELECT
USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage packages" ON public.transaction_packages;
CREATE POLICY "Admins can manage packages"
ON public.transaction_packages FOR ALL
USING (is_admin());

-- RLS for merchant_subscriptions
DROP POLICY IF EXISTS "Merchants can view own subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can view own subscriptions"
ON public.merchant_subscriptions FOR SELECT
USING (EXISTS (
  SELECT 1 FROM merchants
  WHERE merchants.id = merchant_subscriptions.merchant_id
  AND merchants.user_id = auth.uid()
));

DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Merchants can create subscriptions"
ON public.merchant_subscriptions FOR INSERT
WITH CHECK (EXISTS (
  SELECT 1 FROM merchants
  WHERE merchants.id = merchant_subscriptions.merchant_id
  AND merchants.user_id = auth.uid()
) AND status = 'PENDING');

DROP POLICY IF EXISTS "Admins can manage all subscriptions" ON public.merchant_subscriptions;
CREATE POLICY "Admins can manage all subscriptions"
ON public.merchant_subscriptions FOR ALL
USING (is_admin());

-- Add current_subscription_id to merchants table for quick access
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS current_subscription_id UUID REFERENCES public.merchant_subscriptions(id);

-- Create indexes
CREATE INDEX idx_merchant_subscriptions_merchant ON public.merchant_subscriptions(merchant_id);
CREATE INDEX idx_merchant_subscriptions_status ON public.merchant_subscriptions(status);
CREATE INDEX idx_transaction_packages_classification ON public.transaction_packages(classification_price);

-- Insert default packages based on classification
INSERT INTO public.transaction_packages (name, classification_price, price_per_transaction, kas_fee, transaction_quota, validity_days, description) VALUES
('Paket UMKM Mikro', 'UNDER_5K', 500, 1000, 50, 30, 'Untuk produk harga dibawah Rp 5.000'),
('Paket UMKM Kecil', 'FROM_5K_TO_10K', 750, 1500, 75, 30, 'Untuk produk harga Rp 5.000 - 10.000'),
('Paket UMKM Menengah', 'FROM_10K_TO_20K', 1000, 2000, 100, 30, 'Untuk produk harga Rp 10.000 - 20.000'),
('Paket UMKM Premium', 'ABOVE_20K', 1500, 2500, 150, 30, 'Untuk produk harga diatas Rp 20.000');

-- Function to check and decrement quota
CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_subscription RECORD;
BEGIN
  -- Get active subscription
  SELECT * INTO v_subscription
  FROM merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND used_quota < transaction_quota
  ORDER BY expired_at DESC
  LIMIT 1;

  IF v_subscription IS NULL THEN
    RETURN jsonb_build_object(
      'can_transact', false,
      'reason', 'Tidak ada kuota transaksi aktif. Silakan beli paket terlebih dahulu.',
      'remaining_quota', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'can_transact', true,
    'remaining_quota', v_subscription.transaction_quota - v_subscription.used_quota,
    'subscription_id', v_subscription.id
  );
END;
$$;

-- Function to use quota (call after successful order)
CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE merchant_subscriptions
  SET used_quota = used_quota + 1, updated_at = now()
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND used_quota < transaction_quota;

  RETURN FOUND;
END;
$$;

-- Trigger to update timestamps
DROP TRIGGER IF EXISTS update_transaction_packages_updated_at ON public.transaction_packages;
CREATE TRIGGER update_transaction_packages_updated_at
BEFORE UPDATE ON public.transaction_packages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_merchant_subscriptions_updated_at ON public.merchant_subscriptions;
CREATE TRIGGER update_merchant_subscriptions_updated_at
BEFORE UPDATE ON public.merchant_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260127071956_a27ddf22-3789-42c9-bd9c-1f5a0286e319.sql =====

-- ===== BEGIN SOURCE: 20260127072850_7a511ad2-eadc-4846-a7e1-92aa7c608460.sql =====
-- Create trade_groups table
CREATE TABLE public.trade_groups (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  verifikator_id UUID NOT NULL,
  monthly_fee INTEGER NOT NULL DEFAULT 10000,
  village_id UUID REFERENCES public.villages(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true
);

-- Create group_members table (linking merchants to groups)
CREATE TABLE public.group_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  UNIQUE(group_id, merchant_id)
);

-- Create kas_payments table for monthly fee tracking
CREATE TABLE public.kas_payments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL,
  payment_month INTEGER NOT NULL,
  payment_year INTEGER NOT NULL,
  payment_date TIMESTAMP WITH TIME ZONE,
  status TEXT NOT NULL DEFAULT 'UNPAID',
  notes TEXT,
  collected_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(group_id, merchant_id, payment_month, payment_year)
);

-- Enable RLS
ALTER TABLE public.trade_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kas_payments ENABLE ROW LEVEL SECURITY;

-- Trade Groups Policies
DROP POLICY IF EXISTS "Verifikators can manage own groups" ON public.trade_groups;
CREATE POLICY "Verifikators can manage own groups"
ON public.trade_groups FOR ALL
USING (verifikator_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Admins can manage all groups" ON public.trade_groups;
CREATE POLICY "Admins can manage all groups"
ON public.trade_groups FOR ALL
USING (is_admin());

DROP POLICY IF EXISTS "Anyone can view active groups" ON public.trade_groups;
CREATE POLICY "Anyone can view active groups"
ON public.trade_groups FOR SELECT
USING (is_active = true);

-- Group Members Policies
DROP POLICY IF EXISTS "Verifikators can manage group members" ON public.group_members;
CREATE POLICY "Verifikators can manage group members"
ON public.group_members FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups
    WHERE trade_groups.id = group_members.group_id
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
);

DROP POLICY IF EXISTS "Merchants can view own membership" ON public.group_members;
CREATE POLICY "Merchants can view own membership"
ON public.group_members FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = group_members.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can manage all members" ON public.group_members;
CREATE POLICY "Admins can manage all members"
ON public.group_members FOR ALL
USING (is_admin());

-- Kas Payments Policies
DROP POLICY IF EXISTS "Verifikators can manage payments in their groups" ON public.kas_payments;
CREATE POLICY "Verifikators can manage payments in their groups"
ON public.kas_payments FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups
    WHERE trade_groups.id = kas_payments.group_id
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
);

DROP POLICY IF EXISTS "Merchants can view own payments" ON public.kas_payments;
CREATE POLICY "Merchants can view own payments"
ON public.kas_payments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = kas_payments.merchant_id
    AND merchants.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can manage all payments" ON public.kas_payments;
CREATE POLICY "Admins can manage all payments"
ON public.kas_payments FOR ALL
USING (is_admin());

-- Create function to generate monthly kas records for all group members
CREATE OR REPLACE FUNCTION public.generate_monthly_kas(p_group_id UUID, p_month INTEGER, p_year INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_member RECORD;
  v_count INTEGER := 0;
BEGIN
  -- Get group info
  SELECT * INTO v_group FROM trade_groups WHERE id = p_group_id;

  IF v_group IS NULL THEN
    RETURN 0;
  END IF;

  -- Insert kas records for all active members
  FOR v_member IN
    SELECT * FROM group_members
    WHERE group_id = p_group_id AND status = 'ACTIVE'
  LOOP
    INSERT INTO kas_payments (group_id, merchant_id, amount, payment_month, payment_year, status)
    VALUES (p_group_id, v_member.merchant_id, v_group.monthly_fee, p_month, p_year, 'UNPAID')
    ON CONFLICT (group_id, merchant_id, payment_month, payment_year) DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Create updated_at trigger for new tables
DROP TRIGGER IF EXISTS update_trade_groups_updated_at ON public.trade_groups;
CREATE TRIGGER update_trade_groups_updated_at
  BEFORE UPDATE ON public.trade_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_kas_payments_updated_at ON public.kas_payments;
CREATE TRIGGER update_kas_payments_updated_at
  BEFORE UPDATE ON public.kas_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260127072850_7a511ad2-eadc-4846-a7e1-92aa7c608460.sql =====

-- ===== BEGIN SOURCE: 20260127073300_6cb5784e-39e2-4626-8d8d-8bdc12a2a2e4.sql =====
-- Rename kas_fee to group_commission_percent in transaction_packages
ALTER TABLE public.transaction_packages
  DROP COLUMN kas_fee,
  ADD COLUMN group_commission_percent numeric NOT NULL DEFAULT 5;

-- Add comment for clarity
COMMENT ON COLUMN public.transaction_packages.group_commission_percent IS 'Percentage of package price that goes to the trade group/verifikator';

-- Create table to track verifikator earnings from package purchases
CREATE TABLE public.verifikator_earnings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  verifikator_id UUID NOT NULL,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  package_id UUID NOT NULL REFERENCES public.transaction_packages(id) ON DELETE CASCADE,
  package_amount INTEGER NOT NULL,
  commission_percent NUMERIC NOT NULL,
  commission_amount INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.verifikator_earnings ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Admins can manage all earnings" ON public.verifikator_earnings;
CREATE POLICY "Admins can manage all earnings"
  ON public.verifikator_earnings FOR ALL
  USING (is_admin());

DROP POLICY IF EXISTS "Verifikators can view own earnings" ON public.verifikator_earnings;
CREATE POLICY "Verifikators can view own earnings"
  ON public.verifikator_earnings FOR SELECT
  USING (verifikator_id = auth.uid());

-- Add group_id to merchants to track their trade group membership
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.trade_groups(id) ON DELETE SET NULL;

-- Function to auto-assign merchant to trade group when registering with verifikator code
CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS TRIGGER AS $$
DECLARE
  v_code RECORD;
  v_group RECORD;
BEGIN
  -- If merchant has verifikator_code, find the group and assign
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    -- Get verifikator code info
    SELECT * INTO v_code FROM verifikator_codes
    WHERE code = NEW.verifikator_code AND is_active = true
    LIMIT 1;

    IF v_code IS NOT NULL THEN
      -- Find trade group by verifikator
      SELECT * INTO v_group FROM trade_groups
      WHERE verifikator_id = v_code.verifikator_id AND is_active = true
      LIMIT 1;

      IF v_group IS NOT NULL THEN
        NEW.group_id := v_group.id;

        -- Also insert into group_members if not exists
        INSERT INTO group_members (group_id, merchant_id, status)
        VALUES (v_group.id, NEW.id, 'ACTIVE')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON merchants;
DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants;
CREATE TRIGGER trigger_auto_assign_merchant_group
  BEFORE INSERT OR UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_merchant_to_group();

-- Function to calculate and record commission when subscription is paid
CREATE OR REPLACE FUNCTION public.record_verifikator_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_merchant RECORD;
  v_package RECORD;
  v_commission INTEGER;
BEGIN
  -- Only process when payment status changes to PAID
  IF NEW.payment_status = 'PAID' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'PAID') THEN
    -- Get merchant info
    SELECT * INTO v_merchant FROM merchants WHERE id = NEW.merchant_id;

    IF v_merchant.verifikator_id IS NOT NULL THEN
      -- Get package info
      SELECT * INTO v_package FROM transaction_packages WHERE id = NEW.package_id;

      -- Calculate commission
      v_commission := FLOOR(NEW.payment_amount * v_package.group_commission_percent / 100);

      IF v_commission > 0 THEN
        INSERT INTO verifikator_earnings (
          verifikator_id,
          merchant_id,
          subscription_id,
          package_id,
          package_amount,
          commission_percent,
          commission_amount,
          status
        ) VALUES (
          v_merchant.verifikator_id,
          NEW.merchant_id,
          NEW.id,
          NEW.package_id,
          NEW.payment_amount,
          v_package.group_commission_percent,
          v_commission,
          'PENDING'
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for commission recording
DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON merchant_subscriptions;
DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON public.merchant_subscriptions;
CREATE TRIGGER trigger_record_verifikator_commission
  AFTER INSERT OR UPDATE ON public.merchant_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.record_verifikator_commission();

-- ===== END SOURCE: 20260127073300_6cb5784e-39e2-4626-8d8d-8bdc12a2a2e4.sql =====

-- ===== BEGIN SOURCE: 20260127073715_302d2dda-ebfa-4711-a1e0-71fb26487401.sql =====
-- Create verifikator_withdrawals table for withdrawal requests
CREATE TABLE IF NOT EXISTS public.verifikator_withdrawals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  verifikator_id UUID NOT NULL,
  amount INTEGER NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.verifikator_withdrawals ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Verifikators can view own withdrawals" ON public.verifikator_withdrawals;
DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals;
DROP POLICY IF EXISTS "Admins can manage all withdrawals" ON public.verifikator_withdrawals;

DROP POLICY IF EXISTS "Verifikators can view own withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators can view own withdrawals" ON public.verifikator_withdrawals
  FOR SELECT USING (verifikator_id = auth.uid());

DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators can create withdrawals" ON public.verifikator_withdrawals
  FOR INSERT WITH CHECK (verifikator_id = auth.uid() AND status = 'PENDING');

DROP POLICY IF EXISTS "Admins can manage all withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Admins can manage all withdrawals" ON public.verifikator_withdrawals
  FOR ALL USING (is_admin());

-- Add balance columns to track verifikator earnings
ALTER TABLE public.verifikator_earnings ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE;

-- Function to process verifikator withdrawal
CREATE OR REPLACE FUNCTION process_verifikator_withdrawal(
  p_withdrawal_id UUID,
  p_status TEXT,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_withdrawal RECORD;
  v_total_pending INTEGER;
BEGIN
  -- Get the withdrawal
  SELECT * INTO v_withdrawal FROM verifikator_withdrawals WHERE id = p_withdrawal_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Withdrawal not found';
  END IF;

  IF v_withdrawal.status != 'PENDING' THEN
    RAISE EXCEPTION 'Withdrawal already processed';
  END IF;

  IF p_status = 'APPROVED' THEN
    -- Calculate total pending earnings for this verifikator
    SELECT COALESCE(SUM(commission_amount), 0) INTO v_total_pending
    FROM verifikator_earnings
    WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING';

    IF v_total_pending < v_withdrawal.amount THEN
      RAISE EXCEPTION 'Insufficient pending balance';
    END IF;

    -- Mark earnings as PAID up to the withdrawal amount
    WITH earnings_to_pay AS (
      SELECT id, commission_amount,
        SUM(commission_amount) OVER (ORDER BY created_at) as running_total
      FROM verifikator_earnings
      WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING'
      ORDER BY created_at
    )
    UPDATE verifikator_earnings
    SET status = 'PAID', paid_at = now()
    WHERE id IN (
      SELECT id FROM earnings_to_pay WHERE running_total <= v_withdrawal.amount
    );
  END IF;

  -- Update withdrawal status
  UPDATE verifikator_withdrawals
  SET
    status = p_status,
    admin_notes = p_admin_notes,
    processed_by = auth.uid(),
    processed_at = now(),
    updated_at = now()
  WHERE id = p_withdrawal_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ===== END SOURCE: 20260127073715_302d2dda-ebfa-4711-a1e0-71fb26487401.sql =====

-- ===== BEGIN SOURCE: 20260127080732_36fd1d8b-6207-4fed-8758-87368ec25e10.sql =====
-- ========================================
-- 7. STORAGE BUCKET FOR PRODUCT IMAGES
-- ========================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for product images (safe to retry)
DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects;
DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects;
DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects;
DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects;

DROP POLICY IF EXISTS "Public view product images bucket" ON storage.objects;
CREATE POLICY "Public view product images bucket" ON storage.objects
  FOR SELECT USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Auth users upload product images" ON storage.objects;
CREATE POLICY "Auth users upload product images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Auth users update product images" ON storage.objects;
CREATE POLICY "Auth users update product images" ON storage.objects
  FOR UPDATE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Auth users delete product images" ON storage.objects;
CREATE POLICY "Auth users delete product images" ON storage.objects
  FOR DELETE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

-- ========================================
-- 8. ENABLE REALTIME FOR COURIER TRACKING
-- ========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'couriers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.couriers;
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
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260127080732_36fd1d8b-6207-4fed-8758-87368ec25e10.sql =====
-- ===== END BUNDLE: 01_20260127034916_to_20260127080732.sql =====

-- ===== BEGIN BUNDLE: 02_20260127083146_to_20260203_new_q.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260127083146_13a5ef36-3e48-43a4-a47a-05830b75bafb.sql .. 20260203_new_quota_system.sql


-- ===== BEGIN SOURCE: 20260127083146_13a5ef36-3e48-43a4-a47a-05830b75bafb.sql =====
-- Add POD (Proof of Delivery) columns to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS pod_image_url TEXT,
ADD COLUMN IF NOT EXISTS pod_notes TEXT,
ADD COLUMN IF NOT EXISTS pod_uploaded_at TIMESTAMP WITH TIME ZONE;

-- Create platform_fees table for financial tracking
CREATE TABLE IF NOT EXISTS public.platform_fees (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
  order_total INTEGER NOT NULL DEFAULT 0,
  shipping_cost INTEGER NOT NULL DEFAULT 0,
  platform_fee INTEGER NOT NULL DEFAULT 0,
  platform_fee_percent NUMERIC NOT NULL DEFAULT 0,
  courier_fee INTEGER NOT NULL DEFAULT 0,
  merchant_revenue INTEGER NOT NULL DEFAULT 0,
  fee_type TEXT NOT NULL DEFAULT 'ORDER',
  status TEXT NOT NULL DEFAULT 'PENDING',
  collected_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY;

-- RLS policies for platform_fees
DROP POLICY IF EXISTS "Admins can manage platform_fees" ON public.platform_fees;
CREATE POLICY "Admins can manage platform_fees" ON public.platform_fees
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS "Merchants can view own fees" ON public.platform_fees;
CREATE POLICY "Merchants can view own fees" ON public.platform_fees
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id = platform_fees.merchant_id
      AND merchants.user_id = auth.uid()
    )
  );

-- Create broadcast_notifications table
CREATE TABLE IF NOT EXISTS public.broadcast_notifications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  target_audience TEXT NOT NULL DEFAULT 'ALL',
  target_roles TEXT[] DEFAULT '{}',
  scheduled_at TIMESTAMP WITH TIME ZONE,
  sent_at TIMESTAMP WITH TIME ZONE,
  sent_count INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  created_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.broadcast_notifications ENABLE ROW LEVEL SECURITY;

-- RLS policies for broadcast_notifications
DROP POLICY IF EXISTS "Admins can manage broadcasts" ON public.broadcast_notifications;
CREATE POLICY "Admins can manage broadcasts" ON public.broadcast_notifications
  FOR ALL USING (is_admin());

-- Add courier earnings table
CREATE TABLE IF NOT EXISTS public.courier_earnings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  amount INTEGER NOT NULL DEFAULT 0,
  type TEXT NOT NULL DEFAULT 'DELIVERY',
  status TEXT NOT NULL DEFAULT 'PENDING',
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.courier_earnings ENABLE ROW LEVEL SECURITY;

-- RLS policies for courier_earnings
DROP POLICY IF EXISTS "Admins can manage courier earnings" ON public.courier_earnings;
CREATE POLICY "Admins can manage courier earnings" ON public.courier_earnings
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS "Couriers can view own earnings" ON public.courier_earnings;
CREATE POLICY "Couriers can view own earnings" ON public.courier_earnings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM couriers
      WHERE couriers.id = courier_earnings.courier_id
      AND couriers.user_id = auth.uid()
    )
  );

-- Create storage bucket for POD images
INSERT INTO storage.buckets (id, name, public)
VALUES ('pod-images', 'pod-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for POD images (safe to retry)
DROP POLICY IF EXISTS "Anyone can view POD images" ON storage.objects;
DROP POLICY IF EXISTS "Couriers can upload POD images" ON storage.objects;

CREATE POLICY "Anyone can view POD images" ON storage.objects
  FOR SELECT USING (bucket_id = 'pod-images');

CREATE POLICY "Couriers can upload POD images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'pod-images' AND auth.uid() IS NOT NULL);

-- Enable realtime for orders (for courier tracking)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'courier_earnings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_earnings;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260127083146_13a5ef36-3e48-43a4-a47a-05830b75bafb.sql =====

-- ===== BEGIN SOURCE: 20260127084919_5b7afc29-bd66-47fc-89ad-ac3ae63cffe9.sql =====
-- Create wishlists table for buyer wishlist functionality
CREATE TABLE IF NOT EXISTS public.wishlists (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE(user_id, product_id)
);

-- Enable RLS on wishlists
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

-- RLS policies for wishlists
DROP POLICY IF EXISTS "Users can view own wishlists" ON public.wishlists;
CREATE POLICY "Users can view own wishlists"
    ON public.wishlists
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can add to own wishlist" ON public.wishlists;
CREATE POLICY "Users can add to own wishlist"
    ON public.wishlists
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can remove from own wishlist" ON public.wishlists;
CREATE POLICY "Users can remove from own wishlist"
    ON public.wishlists
    FOR DELETE
    USING (auth.uid() = user_id);

-- Create index for better query performance
CREATE INDEX idx_wishlists_user_id ON public.wishlists(user_id);
CREATE INDEX idx_wishlists_product_id ON public.wishlists(product_id);

-- ===== END SOURCE: 20260127084919_5b7afc29-bd66-47fc-89ad-ac3ae63cffe9.sql =====

-- ===== BEGIN SOURCE: 20260127090723_55ce443e-9544-4fb0-9804-21846e7790d7.sql =====
-- =============================================
-- FIX SECURITY: Couriers Table
-- =============================================

-- Drop the overly permissive policy that exposes all courier data to authenticated users
DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers;

-- Create a more restrictive policy: Only allow viewing couriers if:
-- 1. User is an admin
-- 2. User is a verifikator
-- 3. User is the courier themselves
-- 4. User is a merchant with an order assigned to that courier
-- 5. User is a buyer with an order assigned to that courier
DROP POLICY IF EXISTS "Authorized users can view courier info" ON public.couriers;
CREATE POLICY "Authorized users can view courier info"
ON public.couriers
FOR SELECT
USING (
  is_admin() OR
  is_verifikator() OR
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.courier_id = couriers.id
    AND m.user_id = auth.uid()
  ) OR
  EXISTS (
    SELECT 1 FROM orders o
    WHERE o.courier_id = couriers.id
    AND o.buyer_id = auth.uid()
  )
);

-- =============================================
-- FIX SECURITY: Merchants Table
-- =============================================

-- Drop the overly permissive policy
DROP POLICY IF EXISTS "Anyone can view active merchants" ON public.merchants;

-- Create policy: Only expose limited merchant data to unauthenticated users
-- For full data access, require authentication and specific roles
DROP POLICY IF EXISTS "Authenticated users can view active merchants" ON public.merchants;
CREATE POLICY "Authenticated users can view active merchants"
ON public.merchants
FOR SELECT
USING (
  status = 'ACTIVE' AND auth.uid() IS NOT NULL
);

-- Create a secure view for public merchant listing (limited columns)
CREATE OR REPLACE VIEW public.public_merchants AS
SELECT
  id,
  name,
  business_category,
  business_description,
  image_url,
  is_open,
  open_time,
  close_time,
  badge,
  rating_avg,
  rating_count,
  classification_price,
  village_id,
  -- Only show city-level location, not full address
  city,
  province
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

-- Grant public access to the view
GRANT SELECT ON public.public_merchants TO anon;
GRANT SELECT ON public.public_merchants TO authenticated;

-- =============================================
-- Create a secure view for public courier info (for order tracking)
-- =============================================
CREATE OR REPLACE VIEW public.public_couriers AS
SELECT
  id,
  name,
  -- Only expose first name for privacy
  SPLIT_PART(name, ' ', 1) as first_name,
  vehicle_type,
  photo_url,
  status,
  is_available,
  current_lat,
  current_lng,
  last_location_update
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

-- Grant access only to authenticated users
GRANT SELECT ON public.public_couriers TO authenticated;

-- ===== END SOURCE: 20260127090723_55ce443e-9544-4fb0-9804-21846e7790d7.sql =====

-- ===== BEGIN SOURCE: 20260127090737_76e14436-230a-4f14-b565-21d7d485ec75.sql =====
-- Fix Security Definer View warnings by using SECURITY INVOKER

-- Drop and recreate public_merchants view with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_merchants;
CREATE VIEW public.public_merchants
WITH (security_invoker = true)
AS
SELECT
  id,
  name,
  business_category,
  business_description,
  image_url,
  is_open,
  open_time,
  close_time,
  badge,
  rating_avg,
  rating_count,
  classification_price,
  village_id,
  city,
  province
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

-- Grant access to the view
GRANT SELECT ON public.public_merchants TO anon;
GRANT SELECT ON public.public_merchants TO authenticated;

-- Drop and recreate public_couriers view with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_couriers;
CREATE VIEW public.public_couriers
WITH (security_invoker = true)
AS
SELECT
  id,
  name,
  SPLIT_PART(name, ' ', 1) as first_name,
  vehicle_type,
  photo_url,
  status,
  is_available,
  current_lat,
  current_lng,
  last_location_update
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

-- Grant access only to authenticated users
GRANT SELECT ON public.public_couriers TO authenticated;

-- Also add policy for anon users to view public merchants (via view)
-- We need a basic SELECT policy for the underlying table to work with the view
DROP POLICY IF EXISTS "Anon can view basic merchant info" ON public.merchants;
CREATE POLICY "Anon can view basic merchant info"
ON public.merchants
FOR SELECT
TO anon
USING (status = 'ACTIVE' AND registration_status = 'APPROVED');

-- ===== END SOURCE: 20260127090737_76e14436-230a-4f14-b565-21d7d485ec75.sql =====

-- ===== BEGIN SOURCE: 20260128080908_a67fbfdf-ef96-4108-b095-2632c9293551.sql =====
-- Create push_subscriptions table for storing web push subscriptions
CREATE TABLE public.push_subscriptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);

-- Enable RLS
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can manage their own subscriptions
DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can view their own push subscriptions"
ON public.push_subscriptions FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can insert their own push subscriptions"
ON public.push_subscriptions FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can delete their own push subscriptions"
ON public.push_subscriptions FOR DELETE
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can update their own push subscriptions"
ON public.push_subscriptions FOR UPDATE
USING (auth.uid() = user_id);

-- Create password_reset_tokens table
CREATE TABLE public.password_reset_tokens (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS (no user access needed, only edge functions)
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- Only service role can access this table (no policies = denied for anon/authenticated)

-- Create index for faster lookups
CREATE INDEX idx_push_subscriptions_user_id ON public.push_subscriptions(user_id);
CREATE INDEX idx_password_reset_tokens_token ON public.password_reset_tokens(token);
CREATE INDEX idx_password_reset_tokens_email ON public.password_reset_tokens(email);

-- ===== END SOURCE: 20260128080908_a67fbfdf-ef96-4108-b095-2632c9293551.sql =====

-- ===== BEGIN SOURCE: 20260128081633_675e947a-dd50-4d7f-bf42-32ecd93b18a0.sql =====
-- Create saved_addresses table for storing multiple addresses per user
CREATE TABLE public.saved_addresses (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  label TEXT NOT NULL DEFAULT 'Rumah',
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  province_id TEXT,
  province_name TEXT,
  city_id TEXT,
  city_name TEXT,
  district_id TEXT,
  district_name TEXT,
  village_id TEXT,
  village_name TEXT,
  address_detail TEXT,
  full_address TEXT,
  lat NUMERIC,
  lng NUMERIC,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

-- Users can view their own addresses
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
CREATE POLICY "Users can view own addresses"
ON public.saved_addresses
FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own addresses
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users can insert own addresses"
ON public.saved_addresses
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own addresses
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses"
ON public.saved_addresses
FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete their own addresses
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users can delete own addresses"
ON public.saved_addresses
FOR DELETE
USING (auth.uid() = user_id);

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER update_saved_addresses_updated_at
BEFORE UPDATE ON public.saved_addresses
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260128081633_675e947a-dd50-4d7f-bf42-32ecd93b18a0.sql =====

-- ===== BEGIN SOURCE: 20260128112244_98c8bd6c-406f-4141-8f06-9b93e2fa8ce6.sql =====
-- Create vouchers/coupons table
CREATE TABLE public.vouchers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  discount_type TEXT NOT NULL DEFAULT 'percentage' CHECK (discount_type IN ('percentage', 'fixed')),
  discount_value INTEGER NOT NULL DEFAULT 0,
  min_order_amount INTEGER DEFAULT 0,
  max_discount INTEGER,
  usage_limit INTEGER,
  used_count INTEGER DEFAULT 0,
  start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  end_date TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_by UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create voucher usage tracking
CREATE TABLE public.voucher_usages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voucher_id UUID NOT NULL REFERENCES public.vouchers(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  order_id UUID REFERENCES public.orders(id),
  discount_amount INTEGER NOT NULL DEFAULT 0,
  used_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create SEO settings table
CREATE TABLE public.seo_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path TEXT NOT NULL UNIQUE,
  title TEXT,
  description TEXT,
  keywords TEXT,
  og_image TEXT,
  og_title TEXT,
  og_description TEXT,
  canonical_url TEXT,
  robots TEXT DEFAULT 'index, follow',
  updated_by UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create backup logs table
CREATE TABLE public.backup_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type TEXT NOT NULL DEFAULT 'manual',
  status TEXT NOT NULL DEFAULT 'pending',
  file_url TEXT,
  file_size INTEGER,
  tables_included TEXT[],
  error_message TEXT,
  created_by UUID,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Create rate limit tracking table
CREATE TABLE public.rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier TEXT NOT NULL,
  action TEXT NOT NULL,
  count INTEGER DEFAULT 1,
  window_start TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Add unique constraint for rate limits
CREATE UNIQUE INDEX idx_rate_limits_unique ON public.rate_limits(identifier, action, window_start);

-- Add index for cleanup
CREATE INDEX idx_rate_limits_window ON public.rate_limits(window_start);

-- Enable RLS
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voucher_usages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- Voucher policies
DROP POLICY IF EXISTS "Vouchers viewable by everyone" ON public.vouchers;
CREATE POLICY "Vouchers viewable by everyone" ON public.vouchers
  FOR SELECT USING (is_active = true AND (start_date <= now()) AND (end_date IS NULL OR end_date >= now()));

DROP POLICY IF EXISTS "Merchants manage own vouchers" ON public.vouchers;
CREATE POLICY "Merchants manage own vouchers" ON public.vouchers
  FOR ALL USING (
    merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "Admins manage all vouchers" ON public.vouchers;
CREATE POLICY "Admins manage all vouchers" ON public.vouchers
  FOR ALL USING (public.is_admin());

-- Voucher usage policies
DROP POLICY IF EXISTS "Users view own usage" ON public.voucher_usages;
CREATE POLICY "Users view own usage" ON public.voucher_usages
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Users can use vouchers" ON public.voucher_usages;
CREATE POLICY "Users can use vouchers" ON public.voucher_usages
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- SEO policies (admin only)
DROP POLICY IF EXISTS "Anyone can view SEO settings" ON public.seo_settings;
CREATE POLICY "Anyone can view SEO settings" ON public.seo_settings
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins manage SEO" ON public.seo_settings;
CREATE POLICY "Admins manage SEO" ON public.seo_settings
  FOR ALL USING (public.is_admin());

-- Backup policies (admin only)
DROP POLICY IF EXISTS "Admins view backups" ON public.backup_logs;
CREATE POLICY "Admins view backups" ON public.backup_logs
  FOR SELECT USING (public.is_admin());

DROP POLICY IF EXISTS "Admins create backups" ON public.backup_logs;
CREATE POLICY "Admins create backups" ON public.backup_logs
  FOR INSERT WITH CHECK (public.is_admin());

-- Rate limits policies
DROP POLICY IF EXISTS "Rate limits public" ON public.rate_limits;
CREATE POLICY "Rate limits public" ON public.rate_limits
  FOR ALL USING (true);

-- Add realtime for vouchers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'vouchers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.vouchers;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- Function to check and increment rate limit
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_identifier TEXT,
  p_action TEXT,
  p_max_requests INTEGER DEFAULT 10,
  p_window_seconds INTEGER DEFAULT 60
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_window_start TIMESTAMP WITH TIME ZONE;
  v_current_count INTEGER;
BEGIN
  v_window_start := date_trunc('minute', now());

  -- Get current count for this window
  SELECT count INTO v_current_count
  FROM rate_limits
  WHERE identifier = p_identifier
    AND action = p_action
    AND window_start = v_window_start;

  IF v_current_count IS NULL THEN
    -- First request in this window
    INSERT INTO rate_limits (identifier, action, count, window_start)
    VALUES (p_identifier, p_action, 1, v_window_start)
    ON CONFLICT (identifier, action, window_start) DO UPDATE SET count = rate_limits.count + 1;

    RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - 1);
  END IF;

  IF v_current_count >= p_max_requests THEN
    RETURN jsonb_build_object('allowed', false, 'remaining', 0, 'retry_after', p_window_seconds);
  END IF;

  -- Increment count
  UPDATE rate_limits
  SET count = count + 1
  WHERE identifier = p_identifier
    AND action = p_action
    AND window_start = v_window_start;

  RETURN jsonb_build_object('allowed', true, 'remaining', p_max_requests - v_current_count - 1);
END;
$$;

-- Function to apply voucher
CREATE OR REPLACE FUNCTION public.apply_voucher(
  p_code TEXT,
  p_user_id UUID,
  p_order_total INTEGER,
  p_merchant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_voucher RECORD;
  v_usage_count INTEGER;
  v_discount INTEGER;
BEGIN
  -- Find voucher
  SELECT * INTO v_voucher
  FROM vouchers
  WHERE UPPER(code) = UPPER(p_code)
    AND is_active = true
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());

  IF v_voucher IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kode voucher tidak ditemukan atau sudah kadaluarsa');
  END IF;

  -- Check merchant specific
  IF v_voucher.merchant_id IS NOT NULL AND v_voucher.merchant_id != p_merchant_id THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Voucher tidak berlaku untuk toko ini');
  END IF;

  -- Check minimum order
  IF p_order_total < v_voucher.min_order_amount THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Minimum belanja Rp ' || v_voucher.min_order_amount);
  END IF;

  -- Check usage limit
  IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Voucher sudah habis');
  END IF;

  -- Check if user already used
  SELECT COUNT(*) INTO v_usage_count
  FROM voucher_usages
  WHERE voucher_id = v_voucher.id AND user_id = p_user_id;

  IF v_usage_count > 0 THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Anda sudah menggunakan voucher ini');
  END IF;

  -- Calculate discount
  IF v_voucher.discount_type = 'percentage' THEN
    v_discount := FLOOR(p_order_total * v_voucher.discount_value / 100);
    IF v_voucher.max_discount IS NOT NULL AND v_discount > v_voucher.max_discount THEN
      v_discount := v_voucher.max_discount;
    END IF;
  ELSE
    v_discount := v_voucher.discount_value;
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'voucher_id', v_voucher.id,
    'discount', v_discount,
    'voucher_name', v_voucher.name
  );
END;
$$;

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_vouchers_updated_at ON public.vouchers;
CREATE TRIGGER update_vouchers_updated_at
  BEFORE UPDATE ON public.vouchers
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_seo_settings_updated_at ON public.seo_settings;
CREATE TRIGGER update_seo_settings_updated_at
  BEFORE UPDATE ON public.seo_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260128112244_98c8bd6c-406f-4141-8f06-9b93e2fa8ce6.sql =====

-- ===== BEGIN SOURCE: 20260128112256_d0cfd142-d893-4f05-9c1d-2f43ed686887.sql =====
-- Fix rate_limits RLS policy to be more restrictive
DROP POLICY IF EXISTS "Rate limits public" ON public.rate_limits;

-- Rate limits should only allow insert/update from server (via security definer function)
-- No direct public access needed
DROP POLICY IF EXISTS "Rate limits managed by functions" ON public.rate_limits;
CREATE POLICY "Rate limits managed by functions" ON public.rate_limits
  FOR SELECT USING (identifier = auth.uid()::text OR public.is_admin());

DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits;
CREATE POLICY "Rate limits insert via functions" ON public.rate_limits
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits;
CREATE POLICY "Rate limits update via functions" ON public.rate_limits
  FOR UPDATE USING (true);

-- ===== END SOURCE: 20260128112256_d0cfd142-d893-4f05-9c1d-2f43ed686887.sql =====

-- ===== BEGIN SOURCE: 20260128115030_30a887fa-9eed-41a0-9f35-c6cf6ed702fd.sql =====
-- ============================================
-- Backup Schedules Table (only if not exists)
-- ============================================
CREATE TABLE IF NOT EXISTS public.backup_schedules (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    schedule_type TEXT NOT NULL DEFAULT 'daily',
    schedule_time TIME NOT NULL DEFAULT '02:00',
    schedule_day INTEGER,
    tables_included TEXT[] DEFAULT ARRAY['merchants', 'products', 'orders', 'villages', 'tourism', 'couriers'],
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.backup_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage backup schedules" ON public.backup_schedules;
CREATE POLICY "Admins can manage backup schedules" ON public.backup_schedules
    FOR ALL USING (is_admin());

-- ============================================
-- Add proof_image_url to verifikator_withdrawals if not exists
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'verifikator_withdrawals' AND column_name = 'proof_image_url') THEN
        ALTER TABLE public.verifikator_withdrawals ADD COLUMN proof_image_url TEXT;
    END IF;
END $$;

-- ============================================
-- Add COD columns to orders if not exists
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_confirmed_at') THEN
        ALTER TABLE public.orders ADD COLUMN cod_confirmed_at TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_rejected_at') THEN
        ALTER TABLE public.orders ADD COLUMN cod_rejected_at TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_rejection_reason') THEN
        ALTER TABLE public.orders ADD COLUMN cod_rejection_reason TEXT;
    END IF;
END $$;

-- ============================================
-- COD Eligibility Check Function
-- ============================================
CREATE OR REPLACE FUNCTION public.check_cod_eligibility(
    p_buyer_id UUID,
    p_merchant_id UUID,
    p_total_amount INTEGER,
    p_distance_km NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cod_settings JSONB;
    v_max_amount INTEGER;
    v_max_distance NUMERIC;
    v_min_trust_score INTEGER;
    v_buyer_trust_score INTEGER;
    v_buyer_cod_enabled BOOLEAN;
    v_merchant_cod_max_amount INTEGER;
    v_merchant_cod_max_distance NUMERIC;
BEGIN
    SELECT value INTO v_cod_settings FROM app_settings WHERE key = 'cod_settings';

    IF v_cod_settings IS NULL THEN
        v_max_amount := 75000;
        v_max_distance := 3;
        v_min_trust_score := 50;
    ELSE
        v_max_amount := COALESCE((v_cod_settings->>'max_amount')::INTEGER, 75000);
        v_max_distance := COALESCE((v_cod_settings->>'max_distance_km')::NUMERIC, 3);
        v_min_trust_score := COALESCE((v_cod_settings->>'min_trust_score')::INTEGER, 50);
    END IF;

    SELECT trust_score, cod_enabled INTO v_buyer_trust_score, v_buyer_cod_enabled
    FROM profiles WHERE user_id = p_buyer_id;

    IF v_buyer_cod_enabled = false THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'Akun Anda tidak dapat menggunakan COD');
    END IF;

    IF COALESCE(v_buyer_trust_score, 100) < v_min_trust_score THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'Trust score tidak mencukupi untuk COD');
    END IF;

    SELECT cod_max_amount, cod_max_distance_km INTO v_merchant_cod_max_amount, v_merchant_cod_max_distance
    FROM merchants WHERE id = p_merchant_id;

    v_max_amount := LEAST(v_max_amount, COALESCE(v_merchant_cod_max_amount, v_max_amount));
    v_max_distance := LEAST(v_max_distance, COALESCE(v_merchant_cod_max_distance, v_max_distance));

    IF p_total_amount > v_max_amount THEN
        RETURN jsonb_build_object('eligible', false, 'reason',
            format('Nominal terlalu besar untuk COD. Maks: Rp %s', to_char(v_max_amount, 'FM999,999,999')));
    END IF;

    IF p_distance_km IS NOT NULL AND p_distance_km > v_max_distance THEN
        RETURN jsonb_build_object('eligible', false, 'reason',
            format('Jarak terlalu jauh untuk COD. Maks: %s KM', v_max_distance));
    END IF;

    RETURN jsonb_build_object('eligible', true, 'reason', NULL);
END;
$$;

-- ============================================
-- Update buyer trust score function
-- ============================================
CREATE OR REPLACE FUNCTION public.update_cod_trust_score(
    p_buyer_id UUID,
    p_success BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cod_settings JSONB;
    v_penalty_points INTEGER;
    v_bonus_points INTEGER;
    v_min_trust_score INTEGER;
    v_current_score INTEGER;
    v_current_fail_count INTEGER;
    v_new_score INTEGER;
BEGIN
    SELECT value INTO v_cod_settings FROM app_settings WHERE key = 'cod_settings';

    v_penalty_points := COALESCE((v_cod_settings->>'penalty_points')::INTEGER, 50);
    v_bonus_points := COALESCE((v_cod_settings->>'success_bonus_points')::INTEGER, 1);
    v_min_trust_score := COALESCE((v_cod_settings->>'min_trust_score')::INTEGER, 50);

    SELECT trust_score, cod_fail_count INTO v_current_score, v_current_fail_count
    FROM profiles WHERE user_id = p_buyer_id;

    v_current_score := COALESCE(v_current_score, 100);
    v_current_fail_count := COALESCE(v_current_fail_count, 0);

    IF p_success THEN
        v_new_score := LEAST(100, v_current_score + v_bonus_points);
        UPDATE profiles SET trust_score = v_new_score WHERE user_id = p_buyer_id;
    ELSE
        v_new_score := GREATEST(0, v_current_score - v_penalty_points);
        UPDATE profiles
        SET
            trust_score = v_new_score,
            cod_fail_count = v_current_fail_count + 1,
            cod_enabled = CASE WHEN v_new_score < v_min_trust_score THEN false ELSE cod_enabled END
        WHERE user_id = p_buyer_id;
    END IF;
END;
$$;

-- ============================================
-- Product-images storage bucket (ignore if exists)
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies (drop and recreate)
DROP POLICY IF EXISTS "Anyone can view product images storage" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload product images storage" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own product images storage" ON storage.objects;

DROP POLICY IF EXISTS "Anyone can view product images storage" ON storage.objects;
CREATE POLICY "Anyone can view product images storage" ON storage.objects
    FOR SELECT USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Authenticated users can upload product images storage" ON storage.objects;
CREATE POLICY "Authenticated users can upload product images storage" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can delete own product images storage" ON storage.objects;
CREATE POLICY "Users can delete own product images storage" ON storage.objects
    FOR DELETE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL);

-- ===== END SOURCE: 20260128115030_30a887fa-9eed-41a0-9f35-c6cf6ed702fd.sql =====

-- ===== BEGIN SOURCE: 20260128115934_4c1f5601-41a9-4beb-ac95-8575b89fbf1d.sql =====
-- Product Variants table
CREATE TABLE IF NOT EXISTS public.product_variants (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sku TEXT,
  price_adjustment INTEGER DEFAULT 0,
  stock INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Product Images table
CREATE TABLE IF NOT EXISTS public.product_images (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  is_primary BOOLEAN DEFAULT false,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;

-- RLS Policies for product_variants
DROP POLICY IF EXISTS "Anyone can view active product variants" ON public.product_variants;
CREATE POLICY "Anyone can view active product variants"
ON public.product_variants FOR SELECT
USING (is_active = true);

DROP POLICY IF EXISTS "Merchants can manage their product variants" ON public.product_variants;
CREATE POLICY "Merchants can manage their product variants"
ON public.product_variants FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM products p
    JOIN merchants m ON p.merchant_id = m.id
    WHERE p.id = product_variants.product_id
    AND m.user_id = auth.uid()
  )
);

-- RLS Policies for product_images
DROP POLICY IF EXISTS "Anyone can view product images" ON public.product_images;
CREATE POLICY "Anyone can view product images"
ON public.product_images FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Merchants can manage their product images" ON public.product_images;
CREATE POLICY "Merchants can manage their product images"
ON public.product_images FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM products p
    JOIN merchants m ON p.merchant_id = m.id
    WHERE p.id = product_images.product_id
    AND m.user_id = auth.uid()
  )
);

-- Admin policies
DROP POLICY IF EXISTS "Admins can manage all product variants" ON public.product_variants;
CREATE POLICY "Admins can manage all product variants"
ON public.product_variants FOR ALL
USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can manage all product images" ON public.product_images;
CREATE POLICY "Admins can manage all product images"
ON public.product_images FOR ALL
USING (public.is_admin());

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON public.product_images(product_id);
CREATE INDEX IF NOT EXISTS idx_product_images_primary ON public.product_images(product_id, is_primary) WHERE is_primary = true;

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at
BEFORE UPDATE ON public.product_variants
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260128115934_4c1f5601-41a9-4beb-ac95-8575b89fbf1d.sql =====

-- ===== BEGIN SOURCE: 20260128121326_62e7deee-7d24-4c49-85d7-0c27f69e1f9f.sql =====
-- Flash Sales Table
CREATE TABLE IF NOT EXISTS public.flash_sales (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  original_price INTEGER NOT NULL,
  flash_price INTEGER NOT NULL,
  stock_available INTEGER NOT NULL DEFAULT 1,
  stock_sold INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  start_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  end_time TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED', 'CANCELLED')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- RLS for flash_sales
ALTER TABLE public.flash_sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view active flash sales" ON public.flash_sales;
CREATE POLICY "Public can view active flash sales"
ON public.flash_sales FOR SELECT
USING (status = 'ACTIVE' AND end_time > now());

DROP POLICY IF EXISTS "Merchants can manage their flash sales" ON public.flash_sales;
CREATE POLICY "Merchants can manage their flash sales"
ON public.flash_sales FOR ALL
USING (
  merchant_id IN (
    SELECT id FROM public.merchants WHERE user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can manage all flash sales" ON public.flash_sales;
CREATE POLICY "Admins can manage all flash sales"
ON public.flash_sales FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Add verified badge to merchants if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'merchants' AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE public.merchants ADD COLUMN is_verified BOOLEAN DEFAULT false;
    ALTER TABLE public.merchants ADD COLUMN verified_at TIMESTAMP WITH TIME ZONE;
    ALTER TABLE public.merchants ADD COLUMN verified_by UUID;
  END IF;
END $$;

-- Fix RLS policies that are too permissive
-- Drop and recreate permissive policies with proper checks

-- Fix product_variants policies
DROP POLICY IF EXISTS "Public can view product variants" ON public.product_variants;
DROP POLICY IF EXISTS "Public can view active product variants" ON public.product_variants;
CREATE POLICY "Public can view active product variants"
ON public.product_variants FOR SELECT
USING (is_active = true);

-- Fix product_images policies
DROP POLICY IF EXISTS "Public can view product images" ON public.product_images;
CREATE POLICY "Public can view product images"
ON public.product_images FOR SELECT
USING (true);

-- Add index for flash sale queries
CREATE INDEX IF NOT EXISTS idx_flash_sales_status_end ON public.flash_sales(status, end_time);
CREATE INDEX IF NOT EXISTS idx_flash_sales_merchant ON public.flash_sales(merchant_id);

-- Enable realtime for flash_sales
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'flash_sales'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.flash_sales;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260128121326_62e7deee-7d24-4c49-85d7-0c27f69e1f9f.sql =====

-- ===== BEGIN SOURCE: 20260128123950_6b87d4af-a9af-49ef-b561-19a356a6119f.sql =====

-- Fix overly permissive RLS policies

-- 1. Fix notifications table: "System can insert notifications" with WITH CHECK (true)
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;

DROP POLICY IF EXISTS "System can insert notifications for authenticated users" ON public.notifications;
CREATE POLICY "System can insert notifications for authenticated users"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 2. Fix rate_limits table
DROP POLICY IF EXISTS "Rate limits insert via functions" ON public.rate_limits;
DROP POLICY IF EXISTS "Rate limits update via functions" ON public.rate_limits;

DROP POLICY IF EXISTS "Users can insert own rate limits" ON public.rate_limits;
CREATE POLICY "Users can insert own rate limits"
ON public.rate_limits
FOR INSERT
TO authenticated
WITH CHECK (identifier = (auth.uid())::text);

DROP POLICY IF EXISTS "Users can update own rate limits" ON public.rate_limits;
CREATE POLICY "Users can update own rate limits"
ON public.rate_limits
FOR UPDATE
TO authenticated
USING (identifier = (auth.uid())::text);

-- 3. Fix password_reset_tokens table - add policies
DROP POLICY IF EXISTS "Anyone can request password reset" ON public.password_reset_tokens;
CREATE POLICY "Anyone can request password reset"
ON public.password_reset_tokens
FOR INSERT
TO anon, authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens;
CREATE POLICY "Users can verify their tokens"
ON public.password_reset_tokens
FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens;
CREATE POLICY "Tokens can be marked as used"
ON public.password_reset_tokens
FOR UPDATE
TO anon, authenticated
USING (used_at IS NULL AND expires_at > now());

-- ===== END SOURCE: 20260128123950_6b87d4af-a9af-49ef-b561-19a356a6119f.sql =====

-- ===== BEGIN SOURCE: 20260128124009_8261bbc1-740e-4392-a17f-4e02ee129d54.sql =====

-- Fix remaining overly permissive policies

-- 1. Fix notifications INSERT policy - restrict to user's own notifications
DROP POLICY IF EXISTS "System can insert notifications for authenticated users" ON public.notifications;

DROP POLICY IF EXISTS "Authenticated users can receive notifications" ON public.notifications;
CREATE POLICY "Authenticated users can receive notifications"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid() OR is_admin());

-- 2. Fix password_reset_tokens INSERT - this is intentional for password reset flow
-- but we should add rate limiting context. For now, we mark it as acceptable
-- because password reset tokens need to be insertable by anyone
DROP POLICY IF EXISTS "Anyone can request password reset" ON public.password_reset_tokens;

-- More restrictive: only allow insert if email matches pattern and not too many recent tokens
DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens;
CREATE POLICY "Password reset token insert"
ON public.password_reset_tokens
FOR INSERT
TO anon, authenticated
WITH CHECK (
  email IS NOT NULL
  AND token IS NOT NULL
  AND expires_at > now()
);

-- 3. Create missing tables for admin pages
-- Categories table
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  icon TEXT,
  description TEXT,
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active categories" ON public.categories;
CREATE POLICY "Anyone can view active categories"
ON public.categories FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories;
CREATE POLICY "Admins can manage categories"
ON public.categories FOR ALL USING (is_admin());

-- Verifikator withdrawals table
CREATE TABLE IF NOT EXISTS public.verifikator_withdrawals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  verifikator_id UUID NOT NULL,
  amount INTEGER NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  proof_image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE,
  processed_by UUID
);

ALTER TABLE public.verifikator_withdrawals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Verifikators view own withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators view own withdrawals"
ON public.verifikator_withdrawals FOR SELECT
USING (verifikator_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Verifikators create withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Verifikators create withdrawals"
ON public.verifikator_withdrawals FOR INSERT
WITH CHECK (verifikator_id = auth.uid() AND status = 'PENDING');

DROP POLICY IF EXISTS "Admins manage withdrawals" ON public.verifikator_withdrawals;
CREATE POLICY "Admins manage withdrawals"
ON public.verifikator_withdrawals FOR ALL USING (is_admin());

-- User villages junction table
CREATE TABLE IF NOT EXISTS public.user_villages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  village_id UUID NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'admin_desa',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(user_id, village_id)
);

ALTER TABLE public.user_villages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages;
CREATE POLICY "Users view own village assignments"
ON public.user_villages FOR SELECT
USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Admins manage village assignments" ON public.user_villages;
CREATE POLICY "Admins manage village assignments"
ON public.user_villages FOR ALL USING (is_admin());

-- ===== END SOURCE: 20260128124009_8261bbc1-740e-4392-a17f-4e02ee129d54.sql =====

-- ===== BEGIN SOURCE: 20260128124950_2b9c0c11-519e-4639-998c-df5278360697.sql =====
-- Create storage bucket for review images
INSERT INTO storage.buckets (id, name, public)
VALUES ('review-images', 'review-images', true)
ON CONFLICT (id) DO NOTHING;

-- Create policy for users to upload their own review images
DROP POLICY IF EXISTS "Users can upload their own review images" ON storage.objects;
CREATE POLICY "Users can upload their own review images"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'review-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Create policy for public read access to review images
DROP POLICY IF EXISTS "Review images are publicly accessible" ON storage.objects;
CREATE POLICY "Review images are publicly accessible"
ON storage.objects
FOR SELECT
USING (bucket_id = 'review-images');

-- Create policy for users to delete their own review images
DROP POLICY IF EXISTS "Users can delete their own review images" ON storage.objects;
CREATE POLICY "Users can delete their own review images"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'review-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ===== END SOURCE: 20260128124950_2b9c0c11-519e-4639-998c-df5278360697.sql =====

-- ===== BEGIN SOURCE: 20260129093914_7254cddf-cebb-4364-b134-576b07ec530d.sql =====
-- Insert homepage layout settings into app_settings table
INSERT INTO public.app_settings (key, value, category, description)
VALUES
  ('homepage_layout', '{
    "sections": [
      {"id": "hero", "name": "Hero Banner", "enabled": true, "order": 0},
      {"id": "categories", "name": "Kategori", "enabled": true, "order": 1},
      {"id": "popular_tourism", "name": "Wisata Populer", "enabled": true, "order": 2},
      {"id": "promo", "name": "Promo Spesial", "enabled": true, "order": 3},
      {"id": "recommendations", "name": "Rekomendasi Pilihan", "enabled": true, "order": 4},
      {"id": "villages", "name": "Jelajahi Desa", "enabled": true, "order": 5}
    ],
    "visible_categories": ["kuliner", "fashion", "kriya", "wisata"]
  }'::jsonb, 'display', 'Pengaturan tampilan dan urutan section di homepage')
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260129093914_7254cddf-cebb-4364-b134-576b07ec530d.sql =====

-- ===== BEGIN SOURCE: 20260130020331_972d5331-4685-49e7-8632-1153e8e7f91b.sql =====
-- Add location coordinates to villages table
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS location_lat DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS location_lng DECIMAL(11, 8);

-- Add location coordinates to merchants table for precise location
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS location_lat DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS location_lng DECIMAL(11, 8);

-- Update existing villages with approximate coordinates (Tasikmalaya area)
UPDATE public.villages SET
  location_lat = -7.3274,
  location_lng = 108.2207
WHERE district = 'Megamendung' AND location_lat IS NULL;

UPDATE public.villages SET
  location_lat = -7.3350,
  location_lng = 108.2150
WHERE district = 'Cisarua' AND location_lat IS NULL;

-- Create index for location queries
CREATE INDEX IF NOT EXISTS idx_villages_location ON public.villages(location_lat, location_lng);
CREATE INDEX IF NOT EXISTS idx_merchants_location ON public.merchants(location_lat, location_lng);
CREATE INDEX IF NOT EXISTS idx_tourism_location ON public.tourism(location_lat, location_lng);

-- ===== END SOURCE: 20260130020331_972d5331-4685-49e7-8632-1153e8e7f91b.sql =====

-- ===== BEGIN SOURCE: 20260202145620_35f2d9fa-1f9c-4766-9097-20d130f6a734.sql =====
-- Fix Security Issues: Profiles, Saved Addresses, and Merchants RLS

-- ============================================
-- 1. PROFILES TABLE - Stricter RLS
-- ============================================

-- Drop existing policies if not already dropped
DROP POLICY IF EXISTS "Users can view own profile only" ON public.profiles;
DROP POLICY IF EXISTS "Service role has full access to profiles" ON public.profiles;

-- Create stricter policies
CREATE POLICY "Users can view own profile only"
ON public.profiles
FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role has full access to profiles" ON public.profiles;
CREATE POLICY "Service role has full access to profiles"
ON public.profiles
FOR ALL
USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 2. SAVED_ADDRESSES TABLE - Add service role access
-- ============================================

DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses;

CREATE POLICY "Service role has full access to saved_addresses"
ON public.saved_addresses
FOR ALL
USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 3. MERCHANTS TABLE - Protect sensitive data with views
-- ============================================

-- Drop existing view first to recreate with new structure
DROP VIEW IF EXISTS public.public_merchants CASCADE;

-- Create a secure view for public merchant data (masks phone number)
CREATE VIEW public.public_merchants AS
SELECT
  id,
  name,
  image_url,
  business_category,
  business_description,
  village_id,
  -- Mask phone number - only show last 4 digits
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  -- Only show general location (city level), not exact address
  city,
  district,
  province,
  -- Hide exact coordinates for public view
  -- Show approximate location (rounded to ~1km precision)
  CASE
    WHEN location_lat IS NOT NULL THEN
      ROUND(location_lat::numeric, 2)
    ELSE NULL
  END as location_lat_approx,
  CASE
    WHEN location_lng IS NOT NULL THEN
      ROUND(location_lng::numeric, 2)
    ELSE NULL
  END as location_lng_approx,
  is_open,
  open_time,
  close_time,
  rating_avg,
  rating_count,
  is_verified,
  badge,
  order_mode
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

-- Grant access to the public view
GRANT SELECT ON public.public_merchants TO anon;
GRANT SELECT ON public.public_merchants TO authenticated;

-- Update merchant policies
DROP POLICY IF EXISTS "Authenticated users view active merchants basic info" ON public.merchants;

CREATE POLICY "Authenticated users view active merchants basic info"
ON public.merchants
FOR SELECT
USING (
  (user_id = auth.uid())
  OR
  (status = 'ACTIVE' AND registration_status = 'APPROVED' AND auth.uid() IS NOT NULL)
  OR
  is_admin()
  OR
  is_verifikator()
);

-- ============================================
-- 4. COURIERS TABLE - Protect sensitive data with views
-- ============================================

DROP VIEW IF EXISTS public.public_couriers CASCADE;

CREATE VIEW public.public_couriers AS
SELECT
  id,
  name,
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  photo_url,
  vehicle_type,
  CASE
    WHEN current_lat IS NOT NULL THEN
      ROUND(current_lat::numeric, 3)
    ELSE NULL
  END as current_lat_approx,
  CASE
    WHEN current_lng IS NOT NULL THEN
      ROUND(current_lng::numeric, 3)
    ELSE NULL
  END as current_lng_approx,
  is_available,
  status,
  village_id
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

GRANT SELECT ON public.public_couriers TO anon;
GRANT SELECT ON public.public_couriers TO authenticated;

-- ===== END SOURCE: 20260202145620_35f2d9fa-1f9c-4766-9097-20d130f6a734.sql =====

-- ===== BEGIN SOURCE: 20260202145634_a7a84602-1476-48ea-8197-7ca03c504d2a.sql =====
-- Fix SECURITY DEFINER warnings by recreating views with SECURITY INVOKER

-- Drop and recreate public_merchants with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_merchants;

CREATE VIEW public.public_merchants
WITH (security_invoker = true) AS
SELECT
  id,
  name,
  image_url,
  business_category,
  business_description,
  village_id,
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  city,
  district,
  province,
  CASE
    WHEN location_lat IS NOT NULL THEN
      ROUND(location_lat::numeric, 2)
    ELSE NULL
  END as location_lat_approx,
  CASE
    WHEN location_lng IS NOT NULL THEN
      ROUND(location_lng::numeric, 2)
    ELSE NULL
  END as location_lng_approx,
  is_open,
  open_time,
  close_time,
  rating_avg,
  rating_count,
  is_verified,
  badge,
  order_mode
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

GRANT SELECT ON public.public_merchants TO anon;
GRANT SELECT ON public.public_merchants TO authenticated;

-- Drop and recreate public_couriers with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_couriers;

CREATE VIEW public.public_couriers
WITH (security_invoker = true) AS
SELECT
  id,
  name,
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  photo_url,
  vehicle_type,
  CASE
    WHEN current_lat IS NOT NULL THEN
      ROUND(current_lat::numeric, 3)
    ELSE NULL
  END as current_lat_approx,
  CASE
    WHEN current_lng IS NOT NULL THEN
      ROUND(current_lng::numeric, 3)
    ELSE NULL
  END as current_lng_approx,
  is_available,
  status,
  village_id
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED';

GRANT SELECT ON public.public_couriers TO anon;
GRANT SELECT ON public.public_couriers TO authenticated;

-- ===== END SOURCE: 20260202145634_a7a84602-1476-48ea-8197-7ca03c504d2a.sql =====

-- ===== BEGIN SOURCE: 20260203005758_7302871a-0867-412f-908a-350fe9611b18.sql =====
-- Drop the problematic policies and recreate them without circular dependencies
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;

-- Recreate Buyers policy without is_admin() call to avoid recursion
CREATE POLICY "Buyers can view own orders"
  ON public.orders
  FOR SELECT
  USING (auth.uid() = buyer_id);

-- Recreate Admin policy using direct check without function call
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
CREATE POLICY "Admins can manage all orders"
  ON public.orders
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  );

-- ===== END SOURCE: 20260203005758_7302871a-0867-412f-908a-350fe9611b18.sql =====

-- ===== BEGIN SOURCE: 20260203_cleanup_package_table.sql =====
-- Cleanup transaction_packages table
-- Remove unused column price_per_transaction as it's replaced by total_price
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='transaction_packages' AND column_name='price_per_transaction') THEN
        ALTER TABLE public.transaction_packages DROP COLUMN price_per_transaction;
    END IF;
END $$;

-- Ensure package columns are adjusted only after the package table exists.
DO $$
BEGIN
    IF to_regclass('public.transaction_packages') IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'transaction_packages'
             AND column_name = 'kas_fee'
       ) THEN
        ALTER TABLE public.transaction_packages
        ALTER COLUMN kas_fee TYPE NUMERIC(5,2);
        COMMENT ON TABLE public.transaction_packages IS 'Paket kuota transaksi yang dapat dibeli oleh merchant. Jumlah kuota yang dikonsumsi per transaksi diatur di tabel quota_tiers.';
    END IF;
END $$;

-- ===== END SOURCE: 20260203_cleanup_package_table.sql =====

-- ===== BEGIN SOURCE: 20260203_fix_courier_management.sql =====
-- Fix RLS for couriers table to allow admins and verifikators to manage it properly
-- This fixes the issue where data might not load due to permission errors

-- 1. Ensure the is_verifikator function exists (referenced in previous migrations but let's be sure)
CREATE OR REPLACE FUNCTION public.is_verifikator()
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
      AND role = 'verifikator'
  );
$$;

-- 2. Drop existing policies to recreate them cleanly
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;
DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;

-- 3. Recreate policies with proper function calls
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
CREATE POLICY "Admins can manage couriers" ON public.couriers
FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;
CREATE POLICY "Verifikator can manage couriers" ON public.couriers
FOR ALL USING (public.is_verifikator());

DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
CREATE POLICY "Anyone can register as courier" ON public.couriers
FOR INSERT WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');

DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers;
CREATE POLICY "Active couriers visible to authenticated" ON public.couriers
FOR SELECT USING (status = 'ACTIVE' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
CREATE POLICY "Couriers can view own data" ON public.couriers
FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
CREATE POLICY "Couriers can update own location" ON public.couriers
FOR UPDATE USING (user_id = auth.uid() AND status = 'ACTIVE');

-- 4. Add index for performance
CREATE INDEX IF NOT EXISTS idx_couriers_registration_status ON public.couriers(registration_status);
CREATE INDEX IF NOT EXISTS idx_couriers_village_id ON public.couriers(village_id);

-- ===== END SOURCE: 20260203_fix_courier_management.sql =====

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

-- CREATE TABLE IF NOT EXISTS does not add columns to an existing table.
ALTER TABLE public.transaction_packages
  ADD COLUMN IF NOT EXISTS price_per_transaction INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS kas_fee INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS transaction_quota INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS validity_days INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now();

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
CREATE TABLE IF NOT EXISTS public.quota_tiers (
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
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Anyone can view quota tiers'
  ) THEN
    CREATE POLICY "Anyone can view quota tiers"
    ON public.quota_tiers FOR SELECT
    USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Admins can manage quota tiers'
  ) THEN
    CREATE POLICY "Admins can manage quota tiers"
    ON public.quota_tiers FOR ALL
    USING (is_admin());
  END IF;
END $$;

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
-- ===== END BUNDLE: 02_20260127083146_to_20260203_new_q.sql =====

-- ===== BEGIN BUNDLE: 03_20260203_updat_to_20260208001230.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260203_update_package_logic.sql .. 20260208001230_1b037de1-9dcb-4862-bb8f-b4dfd16e8d3e.sql


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

-- Compatibility for an earlier transaction_packages shape. CREATE TABLE IF NOT EXISTS
-- does not add missing columns when the table already exists.
ALTER TABLE public.transaction_packages
  ADD COLUMN IF NOT EXISTS classification_price TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS price_per_transaction INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS kas_fee INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS transaction_quota INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS validity_days INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now();

-- 2. Keep classification_price available for package classification seeds.
-- The compatibility ALTER above adds it when an older table shape is present.

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
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
CREATE POLICY "Admins can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- 3. Verifikator can manage couriers
DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;
CREATE POLICY "Verifikator can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'verifikator'));

-- 4. Anyone can register as courier
DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers;
CREATE POLICY "Anyone can register as courier"
ON public.couriers
FOR INSERT
TO authenticated
WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');

-- 5. Couriers can update own location
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
CREATE POLICY "Couriers can update own location"
ON public.couriers
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND status = 'ACTIVE');

-- 6. Public view for approved couriers (for order assignment)
DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers;
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
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
CREATE POLICY "Buyers can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (auth.uid() = buyer_id);

DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
CREATE POLICY "Buyers can create orders"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id);

DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;
CREATE POLICY "Buyers can update own pending orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (auth.uid() = buyer_id AND status = 'NEW');

-- 2. Admins can manage all orders
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
CREATE POLICY "Admins can manage all orders"
ON public.orders
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- 3. Couriers can view and update assigned orders using security definer
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
CREATE POLICY "Couriers can view assigned orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id));

DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
CREATE POLICY "Couriers can update assigned orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id));

-- 4. Merchants can view and update their orders using security definer
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;
CREATE POLICY "Merchants can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_order_merchant(auth.uid(), merchant_id));

DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
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

-- CREATE TABLE IF NOT EXISTS does not add columns to an existing table.
ALTER TABLE public.quota_tiers
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- Enable RLS
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY;

-- RLS policies for quota_tiers. Earlier migrations may have created
-- policies with the same names, so creation must be idempotent.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Anyone can view quota tiers'
  ) THEN
    CREATE POLICY "Anyone can view quota tiers"
    ON public.quota_tiers
    FOR SELECT
    TO authenticated
    USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Admins can manage quota tiers'
  ) THEN
    CREATE POLICY "Admins can manage quota tiers"
    ON public.quota_tiers
    FOR ALL
    TO authenticated
    USING (public.has_role(auth.uid(), 'admin'));
  END IF;
END $$;

-- Insert default tiers
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order) VALUES
(0, 3000, 1, 'Produk harga rendah (Rp 0 - Rp 3.000)', 1),
(3001, 5000, 2, 'Produk harga menengah bawah (Rp 3.001 - Rp 5.000)', 2),
(5001, 8000, 3, 'Produk harga menengah (Rp 5.001 - Rp 8.000)', 3),
(8001, 15000, 4, 'Produk harga menengah atas (Rp 8.001 - Rp 15.000)', 4),
(15001, NULL, 5, 'Produk harga tinggi (Rp 15.001+)', 5)
ON CONFLICT DO NOTHING;

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_quota_tiers_updated_at ON public.quota_tiers;
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

DROP POLICY IF EXISTS "couriers_own_access" ON public.couriers;
CREATE POLICY "couriers_own_access" ON public.couriers
  FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "couriers_admin_access" ON public.couriers;
CREATE POLICY "couriers_admin_access" ON public.couriers
  FOR ALL USING (public.is_admin());

-- Orders policies
DROP POLICY IF EXISTS "orders_buyer_access" ON public.orders;
DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;
DROP POLICY IF EXISTS "orders_courier_access" ON public.orders;
DROP POLICY IF EXISTS "orders_admin_access" ON public.orders;

DROP POLICY IF EXISTS "orders_buyer_access" ON public.orders;
CREATE POLICY "orders_buyer_access" ON public.orders
  FOR ALL USING (buyer_id = auth.uid());

DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders;
CREATE POLICY "orders_merchant_access" ON public.orders
  FOR ALL USING (public.is_order_merchant(id));

DROP POLICY IF EXISTS "orders_courier_access" ON public.orders;
CREATE POLICY "orders_courier_access" ON public.orders
  FOR ALL USING (public.is_order_courier(id));

DROP POLICY IF EXISTS "orders_admin_access" ON public.orders;
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
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'products');

-- 2. Authenticated (Merchant): Can upload images
DROP POLICY IF EXISTS "Merchant Upload" ON storage.objects;
CREATE POLICY "Merchant Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'products'
  AND auth.role() = 'authenticated'
);

-- 3. Authenticated (Merchant): Can update own images
DROP POLICY IF EXISTS "Merchant Update" ON storage.objects;
CREATE POLICY "Merchant Update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'products'
  AND auth.role() = 'authenticated'
);

-- 4. Authenticated (Merchant): Can delete own images
DROP POLICY IF EXISTS "Merchant Delete" ON storage.objects;
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
DROP POLICY IF EXISTS "Village images are publicly accessible" ON storage.objects;
CREATE POLICY "Village images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'village-images');

-- Allow authenticated users to upload village images
DROP POLICY IF EXISTS "Authenticated users can upload village images" ON storage.objects;
CREATE POLICY "Authenticated users can upload village images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'village-images' AND auth.role() = 'authenticated');

-- Allow authenticated users to update village images
DROP POLICY IF EXISTS "Authenticated users can update village images" ON storage.objects;
CREATE POLICY "Authenticated users can update village images"
ON storage.objects FOR UPDATE
USING (bucket_id = 'village-images' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete village images
DROP POLICY IF EXISTS "Authenticated users can delete village images" ON storage.objects;
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
DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects;
CREATE POLICY "Payment proofs are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'payment-proofs');

-- RLS: Authenticated users can upload payment proofs
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

-- RLS: Users can update their own payment proofs
DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
CREATE POLICY "Users can update their own payment proofs"
ON storage.objects FOR UPDATE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated');

-- RLS: Users can delete their own payment proofs
DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
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
DROP POLICY IF EXISTS "Public can view promotion images" ON storage.objects;
CREATE POLICY "Public can view promotion images"
ON storage.objects FOR SELECT
USING (bucket_id = 'promotions');

-- Allow authenticated users to upload to promotions bucket
DROP POLICY IF EXISTS "Authenticated users can upload promotion images" ON storage.objects;
CREATE POLICY "Authenticated users can upload promotion images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'promotions' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete promotion images
DROP POLICY IF EXISTS "Authenticated users can delete promotion images" ON storage.objects;
CREATE POLICY "Authenticated users can delete promotion images"
ON storage.objects FOR DELETE
USING (bucket_id = 'promotions' AND auth.role() = 'authenticated');

-- Allow public read access to admin-assets bucket
DROP POLICY IF EXISTS "Public can view admin assets" ON storage.objects;
CREATE POLICY "Public can view admin assets"
ON storage.objects FOR SELECT
USING (bucket_id = 'admin-assets');

-- Allow authenticated users to upload to admin-assets bucket
DROP POLICY IF EXISTS "Authenticated users can upload admin assets" ON storage.objects;
CREATE POLICY "Authenticated users can upload admin assets"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'admin-assets' AND auth.role() = 'authenticated');

-- Allow authenticated users to delete admin assets
DROP POLICY IF EXISTS "Authenticated users can delete admin assets" ON storage.objects;
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

-- Policies are recreated safely when a bootstrap is retried.
DROP POLICY IF EXISTS "Admin can view all quota logs" ON public.quota_usage_logs;
CREATE POLICY "Admin can view all quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Merchant can view own quota logs" ON public.quota_usage_logs;
CREATE POLICY "Merchant can view own quota logs" ON public.quota_usage_logs
  FOR SELECT TO authenticated
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs;
CREATE POLICY "System can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_merchant ON public.quota_usage_logs(merchant_id);
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_order ON public.quota_usage_logs(order_id);
CREATE INDEX IF NOT EXISTS idx_quota_usage_logs_created ON public.quota_usage_logs(created_at DESC);

-- Enable realtime only when the table is not already a member.
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
END $$;

-- ===== END SOURCE: 20260207234919_3b703a60-74a4-4b19-914a-bce0c90381c7.sql =====

-- ===== BEGIN SOURCE: 20260207234930_56685a71-d39f-422a-84ff-01a0d4ed0169.sql =====

-- Fix the permissive INSERT policy - restrict to authenticated users whose merchant matches
DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs;

DROP POLICY IF EXISTS "Authenticated users can insert quota logs" ON public.quota_usage_logs;
CREATE POLICY "Authenticated users can insert quota logs" ON public.quota_usage_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
    OR public.has_role(auth.uid(), 'admin')
  );

-- ===== END SOURCE: 20260207234930_56685a71-d39f-422a-84ff-01a0d4ed0169.sql =====

-- ===== BEGIN SOURCE: 20260207_full_quota_system_migration.sql =====
-- Migration: Full Quota System Improvements
-- This migration consolidates all SQL changes for the merchant transaction quota system.

-- =====================================================
-- PHASE 1: CORE BACKEND & DATABASE FIXES
-- =====================================================

-- 1. Create quota_audit_logs table
CREATE TABLE IF NOT EXISTS public.quota_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.merchants(id),
    subscription_id UUID REFERENCES public.merchant_subscriptions(id),
    action_type TEXT NOT NULL, -- 'PURCHASE', 'USAGE', 'RECONCILIATION', 'REFUND'
    previous_quota INTEGER NOT NULL,
    change_amount INTEGER NOT NULL,
    new_quota INTEGER NOT NULL,
    reference_id UUID, -- order_id or package_transaction_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID -- auth.uid()
);

-- Enable RLS for quota_audit_logs
ALTER TABLE public.quota_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can view their own quota logs" ON public.quota_audit_logs;
CREATE POLICY "Merchants can view their own quota logs"
ON public.quota_audit_logs FOR SELECT
TO authenticated
USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view all quota logs" ON public.quota_audit_logs;
CREATE POLICY "Admins can view all quota logs"
ON public.quota_audit_logs FOR SELECT
TO authenticated
USING (EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'));

-- 2. Improved approve_quota_subscription with accumulation logic
CREATE OR REPLACE FUNCTION public.approve_quota_subscription(p_subscription_id UUID, p_admin_notes TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
    v_active_sub RECORD;
    v_remaining_quota INTEGER := 0;
    v_new_total_quota INTEGER;
BEGIN
    -- Get the subscription to approve
    SELECT * INTO v_sub FROM public.merchant_subscriptions WHERE id = p_subscription_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Subscription tidak ditemukan');
    END IF;

    IF v_sub.payment_status = 'PAID' AND v_sub.status = 'ACTIVE' THEN
        RETURN json_build_object('success', false, 'message', 'Subscription sudah aktif');
    END IF;

    -- Find current active subscription to accumulate quota
    SELECT * INTO v_active_sub
    FROM public.merchant_subscriptions
    WHERE merchant_id = v_sub.merchant_id
      AND status = 'ACTIVE'
      AND expired_at > now()
    ORDER BY expired_at DESC
    LIMIT 1;

    IF FOUND THEN
        v_remaining_quota := v_active_sub.transaction_quota - v_active_sub.used_quota;

        -- Mark old subscription as COMPLETED
        UPDATE public.merchant_subscriptions
        SET status = 'COMPLETED', updated_at = now()
        WHERE id = v_active_sub.id;
    END IF;

    -- Calculate new total quota
    v_new_total_quota := v_sub.transaction_quota + v_remaining_quota;

    -- Update the new subscription
    UPDATE public.merchant_subscriptions
    SET
        status = 'ACTIVE',
        payment_status = 'PAID',
        paid_at = now(),
        admin_notes = p_admin_notes,
        transaction_quota = v_new_total_quota,
        used_quota = 0, -- Reset used quota because we've accumulated the remaining into transaction_quota
        updated_at = now()
    WHERE id = p_subscription_id;

    -- Update current_subscription_id in merchants table
    UPDATE public.merchants
    SET
        current_subscription_id = p_subscription_id,
        updated_at = now()
    WHERE id = v_sub.merchant_id;

    -- Log the audit
    INSERT INTO public.quota_audit_logs (
        merchant_id,
        subscription_id,
        action_type,
        previous_quota,
        change_amount,
        new_quota,
        notes,
        created_by
    ) VALUES (
        v_sub.merchant_id,
        p_subscription_id,
        'PURCHASE',
        v_remaining_quota,
        v_sub.transaction_quota,
        v_new_total_quota,
        'Persetujuan paket: ' || p_subscription_id,
        auth.uid()
    );

    RETURN json_build_object('success', true, 'message', 'Subscription berhasil disetujui dengan akumulasi kuota');
END;
$$;

-- 3. Improved use_merchant_quota with validation and logging
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER, p_order_id UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub_id UUID;
    v_current_quota INTEGER;
    v_used_quota INTEGER;
BEGIN
    -- 1. Validate if this order has already deducted quota (prevent double deduction)
    IF p_order_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.quota_audit_logs WHERE reference_id = p_order_id AND action_type = 'USAGE') THEN
            RETURN TRUE; -- Already deducted
        END IF;
    END IF;

    -- 2. Find active subscription with enough quota
    SELECT id, transaction_quota, used_quota INTO v_sub_id, v_current_quota, v_used_quota
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

    -- 3. Deduct quota
    UPDATE public.merchant_subscriptions
    SET used_quota = used_quota + p_credits,
        updated_at = now()
    WHERE id = v_sub_id;

    -- 4. Log the audit
    INSERT INTO public.quota_audit_logs (
        merchant_id,
        subscription_id,
        action_type,
        previous_quota,
        change_amount,
        new_quota,
        reference_id,
        notes
    ) VALUES (
        p_merchant_id,
        v_sub_id,
        'USAGE',
        v_current_quota - v_used_quota,
        -p_credits,
        v_current_quota - (v_used_quota + p_credits),
        p_order_id,
        'Pemakaian kuota untuk order: ' || COALESCE(p_order_id::text, 'N/A')
    );

    RETURN TRUE;
END;
$$;

-- Update the legacy function to call v2
CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN use_merchant_quota_v2(p_merchant_id, 1, NULL);
END;
$$;

-- =====================================================
-- PHASE 2: RECONCILIATION & DATA RECOVERY
-- =====================================================

-- 1. Analysis Query: Compare current quota vs historical purchases
-- This query helps identify merchants whose current quota doesn't match their purchase history.
-- Note: This assumes 'PAID' subscriptions are the source of truth for granted quota.
CREATE OR REPLACE VIEW public.quota_discrepancy_analysis AS
WITH purchase_summary AS (
    SELECT
        merchant_id,
        SUM(transaction_quota) as total_granted_quota
    FROM public.merchant_subscriptions
    WHERE payment_status = 'PAID'
    GROUP BY merchant_id
),
usage_summary AS (
    -- If you have an orders table, you can estimate usage from there
    -- This is a fallback if used_quota in subscriptions was overwritten
    SELECT
        merchant_id,
        COUNT(*) as estimated_usage
    FROM public.orders
    WHERE status NOT IN ('CANCELLED', 'REFUNDED')
    GROUP BY merchant_id
),
current_quota_summary AS (
    SELECT
        merchant_id,
        SUM(transaction_quota - used_quota) as current_remaining_quota
    FROM public.merchant_subscriptions
    WHERE status = 'ACTIVE' AND expired_at > now()
    GROUP BY merchant_id
)
SELECT
    m.id as merchant_id,
    m.name as merchant_name,
    COALESCE(ps.total_granted_quota, 0) as total_purchased,
    COALESCE(us.estimated_usage, 0) as total_used_estimated,
    (COALESCE(ps.total_granted_quota, 0) - COALESCE(us.estimated_usage, 0)) as expected_remaining,
    COALESCE(cqs.current_remaining_quota, 0) as actual_remaining,
    ((COALESCE(ps.total_granted_quota, 0) - COALESCE(us.estimated_usage, 0)) - COALESCE(cqs.current_remaining_quota, 0)) as discrepancy
FROM public.merchants m
LEFT JOIN purchase_summary ps ON m.id = ps.merchant_id
LEFT JOIN usage_summary us ON m.id = us.merchant_id
LEFT JOIN current_quota_summary cqs ON m.id = cqs.merchant_id
WHERE ABS((COALESCE(ps.total_granted_quota, 0) - COALESCE(us.estimated_usage, 0)) - COALESCE(cqs.current_remaining_quota, 0)) > 0;

-- 2. Data Patching Procedure (One-time script)
-- This function can be called to recalculate and fix a merchant's quota.
CREATE OR REPLACE FUNCTION public.reconcile_merchant_quota(p_merchant_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_purchased INTEGER;
    v_total_used INTEGER;
    v_expected_remaining INTEGER;
    v_active_sub_id UUID;
    v_current_remaining INTEGER;
BEGIN
    -- Calculate total purchased credits
    SELECT COALESCE(SUM(transaction_quota), 0) INTO v_total_purchased
    FROM public.merchant_subscriptions
    WHERE merchant_id = p_merchant_id AND payment_status = 'PAID';

    -- Calculate total used credits (from orders)
    -- Adjust this logic if you use a different way to track usage
    SELECT COUNT(*) INTO v_total_used
    FROM public.orders
    WHERE merchant_id = p_merchant_id AND status NOT IN ('CANCELLED', 'REFUNDED');

    v_expected_remaining := v_total_purchased - v_total_used;
    IF v_expected_remaining < 0 THEN v_expected_remaining := 0; END IF;

    -- Find the latest active subscription to apply the fix
    SELECT id, (transaction_quota - used_quota) INTO v_active_sub_id, v_current_remaining
    FROM public.merchant_subscriptions
    WHERE merchant_id = p_merchant_id AND status = 'ACTIVE' AND expired_at > now()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_active_sub_id IS NULL THEN
        RETURN json_build_object('success', false, 'message', 'No active subscription found to patch');
    END IF;

    -- Apply the fix: adjust transaction_quota to make (transaction_quota - used_quota) = v_expected_remaining
    -- We keep used_quota as is and change transaction_quota for audit clarity
    UPDATE public.merchant_subscriptions
    SET transaction_quota = used_quota + v_expected_remaining,
        updated_at = now()
    WHERE id = v_active_sub_id;

    -- Log the reconciliation
    INSERT INTO public.quota_audit_logs (
        merchant_id,
        subscription_id,
        action_type,
        previous_quota,
        change_amount,
        new_quota,
        notes
    ) VALUES (
        p_merchant_id,
        v_active_sub_id,
        'RECONCILIATION',
        v_current_remaining,
        v_expected_remaining - v_current_remaining,
        v_expected_remaining,
        'Manual reconciliation based on purchase history and order count'
    );

    RETURN json_build_object(
        'success', true,
        'expected', v_expected_remaining,
        'previous', v_current_remaining,
        'adjustment', v_expected_remaining - v_current_remaining
    );
END;
$$;

-- =====================================================
-- PHASE 4: MONITORING & PREVENTION (LONG-TERM)
-- =====================================================

-- 1. Low Quota Alert System
-- This trigger automatically sends a notification when quota falls below a threshold.
CREATE OR REPLACE FUNCTION public.check_low_quota_alert()
RETURNS TRIGGER AS $$
DECLARE
    v_remaining INTEGER;
    v_merchant_name TEXT;
    v_user_id UUID;
BEGIN
    v_remaining := NEW.transaction_quota - NEW.used_quota;

    -- Only alert if quota just crossed the threshold (e.g., 5)
    -- and it's a reduction in quota (used_quota increased)
    IF v_remaining <= 5 AND NEW.used_quota > OLD.used_quota AND (OLD.transaction_quota - OLD.used_quota) > 5 THEN
        -- Get merchant info
        SELECT name, user_id INTO v_merchant_name, v_user_id
        FROM public.merchants
        WHERE id = NEW.merchant_id;

        -- Send notification (using existing send_notification RPC)
        PERFORM public.send_notification(
            v_user_id,
            'Kuota Transaksi Hampir Habis',
            'Sisa kuota transaksi Anda tinggal ' || v_remaining || '. Segera isi ulang agar toko tetap aktif.',
            'warning',
            '/merchant/subscription'
        );
    END IF;

    -- Alert if quota is completely empty
    IF v_remaining = 0 AND NEW.used_quota > OLD.used_quota AND (OLD.transaction_quota - OLD.used_quota) > 0 THEN
        SELECT name, user_id INTO v_merchant_name, v_user_id
        FROM public.merchants
        WHERE id = NEW.merchant_id;

        PERFORM public.send_notification(
            v_user_id,
            'Kuota Transaksi Habis!',
            'Kuota transaksi Anda telah habis. Toko Anda sementara tidak dapat menerima pesanan baru.',
            'error',
            '/merchant/subscription'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_quota_usage_alert ON public.merchant_subscriptions;
CREATE TRIGGER on_quota_usage_alert
    AFTER UPDATE OF used_quota ON public.merchant_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION public.check_low_quota_alert();

-- 2. Auto-reconciliation Job (Conceptual for Edge Function)
-- This query can be run by a cron job to detect anomalies.
CREATE OR REPLACE VIEW public.quota_anomalies AS
WITH purchase_summary AS (
    SELECT merchant_id, SUM(transaction_quota) as total_granted
    FROM public.merchant_subscriptions
    WHERE payment_status = 'PAID'
    GROUP BY merchant_id
),
usage_summary AS (
    SELECT merchant_id, COUNT(*) as total_used
    FROM public.orders
    WHERE status NOT IN ('CANCELLED', 'REFUNDED')
    GROUP BY merchant_id
),
current_status AS (
    SELECT merchant_id, SUM(transaction_quota - used_quota) as current_remaining
    FROM public.merchant_subscriptions
    WHERE status = 'ACTIVE' AND expired_at > now()
    GROUP BY merchant_id
)
SELECT
    m.id as merchant_id,
    m.name as merchant_name,
    COALESCE(ps.total_granted, 0) as purchased,
    COALESCE(us.total_used, 0) as used,
    COALESCE(cs.current_remaining, 0) as actual,
    (COALESCE(ps.total_granted, 0) - COALESCE(us.total_used, 0)) as expected,
    ((COALESCE(ps.total_granted, 0) - COALESCE(us.total_used, 0)) - COALESCE(cs.current_remaining, 0)) as discrepancy
FROM public.merchants m
LEFT JOIN purchase_summary ps ON m.id = ps.merchant_id
LEFT JOIN usage_summary us ON m.id = us.merchant_id
LEFT JOIN current_status cs ON m.id = cs.merchant_id
WHERE ABS((COALESCE(ps.total_granted, 0) - COALESCE(us.total_used, 0)) - COALESCE(cs.current_remaining, 0)) > 0;

-- 3. Admin Dashboard Helper
-- Summary of quota circulation for admin monitoring.
CREATE OR REPLACE VIEW public.quota_circulation_summary AS
SELECT
    COUNT(DISTINCT merchant_id) as active_merchants,
    SUM(transaction_quota) as total_quota_issued,
    SUM(used_quota) as total_quota_used,
    SUM(transaction_quota - used_quota) as total_quota_remaining,
    ROUND(AVG((used_quota::numeric / NULLIF(transaction_quota, 0)) * 100), 2) as avg_usage_percentage
FROM public.merchant_subscriptions
WHERE status = 'ACTIVE' AND expired_at > now();

-- ===== END SOURCE: 20260207_full_quota_system_migration.sql =====

-- ===== BEGIN SOURCE: 20260207_quota_enhancement.sql =====
-- MIGRATION: Sistem Kuota V2 (Request & Tiers Enhancement)
-- Deskripsi: Menambahkan kolom bukti pembayaran, catatan admin, memperbarui fungsi persetujuan kuota, dan membuat storage bucket.

-- 1. Modifikasi tabel merchant_subscriptions untuk mendukung bukti pembayaran dan catatan admin
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchant_subscriptions' AND column_name='payment_proof_url') THEN
        ALTER TABLE public.merchant_subscriptions ADD COLUMN payment_proof_url TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchant_subscriptions' AND column_name='admin_notes') THEN
        ALTER TABLE public.merchant_subscriptions ADD COLUMN admin_notes TEXT;
    END IF;
END $$;

-- 2. Memastikan tabel quota_tiers ada dan sesuai
CREATE TABLE IF NOT EXISTS public.quota_tiers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    min_price integer NOT NULL DEFAULT 0,
    max_price integer,
    credit_cost integer NOT NULL DEFAULT 1,
    description text,
    is_active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- 3. Fungsi Helper untuk menghitung biaya kuota berdasarkan harga
CREATE OR REPLACE FUNCTION public.calculate_quota_cost(p_product_price integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cost integer;
BEGIN
    SELECT credit_cost INTO v_cost
    FROM public.quota_tiers
    WHERE p_product_price >= min_price
    AND (max_price IS NULL OR p_product_price <= max_price)
    AND is_active = true
    ORDER BY min_price DESC
    LIMIT 1;

    RETURN COALESCE(v_cost, 1);
END;
$$;

-- 4. Fungsi untuk menyetujui permintaan kuota (RPC)
CREATE OR REPLACE FUNCTION public.approve_quota_subscription(p_subscription_id UUID, p_admin_notes TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
BEGIN
    -- 1. Ambil data subscription
    SELECT * INTO v_sub FROM public.merchant_subscriptions WHERE id = p_subscription_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Subscription tidak ditemukan');
    END IF;

    IF v_sub.payment_status = 'PAID' AND v_sub.status = 'ACTIVE' THEN
        RETURN json_build_object('success', false, 'message', 'Subscription sudah aktif');
    END IF;

    -- 2. Update status subscription
    UPDATE public.merchant_subscriptions
    SET
        status = 'ACTIVE',
        payment_status = 'PAID',
        paid_at = now(),
        admin_notes = p_admin_notes,
        updated_at = now()
    WHERE id = p_subscription_id;

    -- 3. Update current_subscription_id di tabel merchants
    UPDATE public.merchants
    SET
        current_subscription_id = p_subscription_id,
        updated_at = now()
    WHERE id = v_sub.merchant_id;

    RETURN json_build_object('success', true, 'message', 'Subscription berhasil disetujui dan diaktifkan');
END;
$$;

-- 5. Fungsi untuk menolak permintaan kuota (RPC)
CREATE OR REPLACE FUNCTION public.reject_quota_subscription(p_subscription_id UUID, p_admin_notes TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_admin_notes IS NULL OR p_admin_notes = '' THEN
        RETURN json_build_object('success', false, 'message', 'Catatan admin wajib diisi saat menolak');
    END IF;

    UPDATE public.merchant_subscriptions
    SET
        status = 'INACTIVE',
        payment_status = 'REJECTED',
        admin_notes = p_admin_notes,
        updated_at = now()
    WHERE id = p_subscription_id;

    RETURN json_build_object('success', true, 'message', 'Subscription berhasil ditolak');
END;
$$;

-- 6. Seed data awal untuk quota_tiers jika kosong
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order)
SELECT 0, 50000, 1, 'Produk Murah', 1
WHERE NOT EXISTS (SELECT 1 FROM public.quota_tiers);

INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order)
SELECT 50001, 200000, 2, 'Produk Menengah', 2
WHERE NOT EXISTS (SELECT 1 FROM public.quota_tiers WHERE min_price = 50001);

INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order)
SELECT 200001, NULL, 5, 'Produk Mahal', 3
WHERE NOT EXISTS (SELECT 1 FROM public.quota_tiers WHERE min_price = 200001);

-- 7. Membuat Storage Bucket 'merchants' jika belum ada
INSERT INTO storage.buckets (id, name, public)
SELECT 'merchants', 'merchants', true
WHERE NOT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'merchants'
);

-- 8. Menambahkan Storage Policies untuk bucket 'merchants'
-- Menggunakan DROP POLICY IF EXISTS untuk menghindari error jika policy sudah ada
DROP POLICY IF EXISTS "Merchant upload proof" ON storage.objects;
CREATE POLICY "Merchant upload proof"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'merchants' AND
    (storage.foldername(name))[1] = 'payment-proofs'
);

DROP POLICY IF EXISTS "Public view proof" ON storage.objects;
CREATE POLICY "Public view proof"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'merchants');

DROP POLICY IF EXISTS "Admin manage merchants bucket" ON storage.objects;
CREATE POLICY "Admin manage merchants bucket"
ON storage.objects FOR ALL
TO authenticated
USING (
    bucket_id = 'merchants' AND
    EXISTS (
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid() AND role = 'admin'
    )
);

-- ===== END SOURCE: 20260207_quota_enhancement.sql =====

-- ===== BEGIN SOURCE: 20260208000821_832d9773-734e-433d-aa7f-2387335ef8d1.sql =====
-- Drop the restrictive buyer update policy and replace with one that covers all buyer-updatable statuses
DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;

DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders;
CREATE POLICY "Buyers can update own orders"
ON public.orders
FOR UPDATE
USING (
  auth.uid() = buyer_id
  AND status IN ('NEW', 'PENDING_PAYMENT', 'DELIVERED')
)
WITH CHECK (
  auth.uid() = buyer_id
);

-- ===== END SOURCE: 20260208000821_832d9773-734e-433d-aa7f-2387335ef8d1.sql =====

-- ===== BEGIN SOURCE: 20260208001230_1b037de1-9dcb-4862-bb8f-b4dfd16e8d3e.sql =====
-- 1. Add missing columns to villages table
ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS province text;
ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

-- 2. Fix RLS policies for villages table
-- Drop existing INSERT policy that's too restrictive
DROP POLICY IF EXISTS "Anyone can register village" ON public.villages;
DROP POLICY IF EXISTS "villages_register" ON public.villages;

-- Allow authenticated users to register villages (PENDING + inactive)
DROP POLICY IF EXISTS "Authenticated users can register village" ON public.villages;
CREATE POLICY "Authenticated users can register village"
ON public.villages
FOR INSERT
TO authenticated
WITH CHECK (
  registration_status = 'PENDING' AND is_active = false
);

-- Ensure admin ALL policy covers everything (recreate to be safe)
DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages;
CREATE POLICY "Admins can manage villages"
ON public.villages
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Allow admin_desa to update their own village
DROP POLICY IF EXISTS "Admin desa can update own village" ON public.villages;
CREATE POLICY "Admin desa can update own village"
ON public.villages
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_villages uv
    WHERE uv.village_id = id AND uv.user_id = auth.uid()
  )
);

-- 3. Fix RLS policies for user_villages table
-- Drop existing policies
DROP POLICY IF EXISTS "Admins manage village assignments" ON public.user_villages;
DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages;

-- Admin full access
CREATE POLICY "Admins manage village assignments"
ON public.user_villages
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Users can view their own assignments
DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages;
CREATE POLICY "Users view own village assignments"
ON public.user_villages
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- Authenticated users can insert their own assignment (for registration)
DROP POLICY IF EXISTS "Users can register own village assignment" ON public.user_villages;
CREATE POLICY "Users can register own village assignment"
ON public.user_villages
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Add updated_at trigger for villages
DROP TRIGGER IF EXISTS update_villages_updated_at ON public.villages;
CREATE TRIGGER update_villages_updated_at
BEFORE UPDATE ON public.villages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260208001230_1b037de1-9dcb-4862-bb8f-b4dfd16e8d3e.sql =====
-- ===== END BUNDLE: 03_20260203_updat_to_20260208001230.sql =====

-- ===== BEGIN BUNDLE: 04_20260208054918_to_20260220105922.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260208054918_d4a4580e-26df-482d-8fbe-085d2fe7c428.sql .. 20260220105922_a9d87006-18a0-4ab2-aaff-87e7b485b798.sql


-- ===== BEGIN SOURCE: 20260208054918_d4a4580e-26df-482d-8fbe-085d2fe7c428.sql =====

-- =====================================================
-- 1. FIX RLS POLICIES FOR user_roles TABLE
-- =====================================================
-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can manage user roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles;

-- Recreate complete policies
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles;
CREATE POLICY "Admins can view all roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (is_admin());

DROP POLICY IF EXISTS "Admins can insert user roles" ON public.user_roles;
CREATE POLICY "Admins can insert user roles"
  ON public.user_roles FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Admins can update user roles" ON public.user_roles;
CREATE POLICY "Admins can update user roles"
  ON public.user_roles FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Admins can delete user roles" ON public.user_roles;
CREATE POLICY "Admins can delete user roles"
  ON public.user_roles FOR DELETE
  TO authenticated
  USING (is_admin());

-- =====================================================
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
);

ALTER TABLE public.pos_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active POS packages" ON public.pos_packages;
CREATE POLICY "Anyone can view active POS packages"
  ON public.pos_packages FOR SELECT
  USING (is_active = true);

DROP POLICY IF EXISTS "Admins can manage POS packages" ON public.pos_packages;
CREATE POLICY "Admins can manage POS packages"
  ON public.pos_packages FOR ALL
  USING (is_admin());

-- POS Subscriptions (merchant subscriptions for POS feature)
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
);

ALTER TABLE public.pos_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can view own POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can view own POS subscriptions"
  ON public.pos_subscriptions FOR SELECT
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Merchants can create POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can create POS subscriptions"
  ON public.pos_subscriptions FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Merchants can update own POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can update own POS subscriptions"
  ON public.pos_subscriptions FOR UPDATE
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage all POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Admins can manage all POS subscriptions"
  ON public.pos_subscriptions FOR ALL
  USING (is_admin());

-- POS Transactions (cashier transactions)
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
);

ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can manage own POS transactions" ON public.pos_transactions;
CREATE POLICY "Merchants can manage own POS transactions"
  ON public.pos_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_transactions.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can view all POS transactions" ON public.pos_transactions;
CREATE POLICY "Admins can view all POS transactions"
  ON public.pos_transactions FOR SELECT
  USING (is_admin());

-- POS Settings per merchant (invoice design, etc.)
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
);

ALTER TABLE public.pos_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can manage own POS settings" ON public.pos_settings;
CREATE POLICY "Merchants can manage own POS settings"
  ON public.pos_settings FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_settings.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage all POS settings" ON public.pos_settings;
CREATE POLICY "Admins can manage all POS settings"
  ON public.pos_settings FOR ALL
  USING (is_admin());

-- App setting for POS config (trial days, etc.)
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'pos_config',
  '{"trial_days": 30, "is_enabled": true}'::jsonb,
  'features',
  'Konfigurasi fitur kasir POS'
) ON CONFLICT (key) DO NOTHING;

-- Trigger for updated_at
CREATE OR REPLACE TRIGGER update_pos_packages_updated_at
  BEFORE UPDATE ON public.pos_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE TRIGGER update_pos_subscriptions_updated_at
  BEFORE UPDATE ON public.pos_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE TRIGGER update_pos_settings_updated_at
  BEFORE UPDATE ON public.pos_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260208054918_d4a4580e-26df-482d-8fbe-085d2fe7c428.sql =====

-- ===== BEGIN SOURCE: 20260208071146_3c0d0a7a-e137-449c-a26b-c606b97790cb.sql =====
-- Add notification sound setting to merchants
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS notification_sound_enabled BOOLEAN DEFAULT true;

-- ===== END SOURCE: 20260208071146_3c0d0a7a-e137-449c-a26b-c606b97790cb.sql =====

-- ===== BEGIN SOURCE: 20260210114200_f72dfca5-61b2-4ec7-b5b3-7180e8ae36cd.sql =====

-- 1. Setting kuota gratis
INSERT INTO app_settings (key, value, description, category)
VALUES ('free_tier_quota', '{"limit": 100}', 'Jumlah kuota gratis bulanan untuk merchant baru', 'merchant')
ON CONFLICT (key) DO NOTHING;

-- 2. Setting komisi kurir
INSERT INTO app_settings (key, value, description, category)
VALUES ('courier_commission', '{"percent": 80}', 'Persentase komisi kurir dari ongkir', 'courier')
ON CONFLICT (key) DO NOTHING;

-- 3. Tabel withdrawal kurir
CREATE TABLE IF NOT EXISTS public.courier_withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID REFERENCES public.couriers(id) NOT NULL,
  amount NUMERIC NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS for courier_withdrawal_requests
ALTER TABLE public.courier_withdrawal_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Couriers can view own withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Couriers can view own withdrawals"
ON public.courier_withdrawal_requests FOR SELECT
USING (courier_id = public.get_user_courier_id());

DROP POLICY IF EXISTS "Couriers can create own withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Couriers can create own withdrawals"
ON public.courier_withdrawal_requests FOR INSERT
WITH CHECK (courier_id = public.get_user_courier_id());

DROP POLICY IF EXISTS "Admins full access courier withdrawals" ON public.courier_withdrawal_requests;
CREATE POLICY "Admins full access courier withdrawals"
ON public.courier_withdrawal_requests FOR ALL
USING (public.is_admin());

-- Trigger updated_at
DROP TRIGGER IF EXISTS update_courier_withdrawal_requests_updated_at ON public.courier_withdrawal_requests;
CREATE TRIGGER update_courier_withdrawal_requests_updated_at
BEFORE UPDATE ON public.courier_withdrawal_requests
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 4. Kolom saldo di couriers
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS available_balance NUMERIC DEFAULT 0;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS pending_balance NUMERIC DEFAULT 0;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS total_withdrawn NUMERIC DEFAULT 0;

-- 5. Kolom bank di couriers
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_name TEXT;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_account_number TEXT;
ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS bank_account_name TEXT;

-- ===== END SOURCE: 20260210114200_f72dfca5-61b2-4ec7-b5b3-7180e8ae36cd.sql =====

-- ===== BEGIN SOURCE: 20260212000000_add_halal_certification.sql =====
-- Update merchants table with halal certification fields
ALTER TABLE merchants
ADD COLUMN IF NOT EXISTS halal_status text DEFAULT 'NONE',
ADD COLUMN IF NOT EXISTS halal_certificate_url text,
ADD COLUMN IF NOT EXISTS ktp_url text;

-- Create halal_regulations table
CREATE TABLE IF NOT EXISTS halal_regulations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
);

-- Add RLS policies for halal_regulations
ALTER TABLE halal_regulations ENABLE ROW LEVEL SECURITY;

-- Policy: Allow public read access to halal_regulations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'halal_regulations' AND policyname = 'Allow public read access to halal_regulations'
    ) THEN
        CREATE POLICY "Allow public read access to halal_regulations"
        ON halal_regulations FOR SELECT
        USING (true);
    END IF;
END $$;

-- Policy: Allow admin to manage halal_regulations
-- Using public.is_admin() function which is standard in this project
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'halal_regulations' AND policyname = 'Allow admin to manage halal_regulations'
    ) THEN
        CREATE POLICY "Allow admin to manage halal_regulations"
        ON halal_regulations FOR ALL
        USING (public.is_admin());
    END IF;
END $$;

-- ===== END SOURCE: 20260212000000_add_halal_certification.sql =====

-- ===== BEGIN SOURCE: 20260212002837_0c6e6d69-ef2b-47a8-8635-bfbe0c1833ca.sql =====

-- 1. Add user_id column to villages table for linking desa to user accounts
ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- 2. Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_villages_user_id ON public.villages(user_id);

-- 3. Add RLS policy for village owners to view their own village
DROP POLICY IF EXISTS "Village owners can view own village" ON public.villages;
CREATE POLICY "Village owners can view own village"
ON public.villages FOR SELECT
USING (user_id = auth.uid());

-- 4. Add RLS policy for village owners to update their own village
DROP POLICY IF EXISTS "Village owners can update own village" ON public.villages;
CREATE POLICY "Village owners can update own village"
ON public.villages FOR UPDATE
USING (user_id = auth.uid());

-- 5. Fix refund_requests RLS - allow merchants to read refunds for their orders
DROP POLICY IF EXISTS "Merchants can view refunds for their orders" ON public.refund_requests;
CREATE POLICY "Merchants can view refunds for their orders"
ON public.refund_requests FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.id = refund_requests.order_id
    AND m.user_id = auth.uid()
  )
);

-- 6. Ensure buyers can view own refund requests
DROP POLICY IF EXISTS "Buyers can view own refund requests" ON public.refund_requests;
CREATE POLICY "Buyers can view own refund requests"
ON public.refund_requests FOR SELECT
USING (buyer_id = auth.uid());

-- 7. Ensure buyers can create refund requests
DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests;
CREATE POLICY "Buyers can create refund requests"
ON public.refund_requests FOR INSERT
WITH CHECK (buyer_id = auth.uid());

-- 8. Admin full access to refund_requests
DROP POLICY IF EXISTS "Admins can manage refund requests" ON public.refund_requests;
CREATE POLICY "Admins can manage refund requests"
ON public.refund_requests FOR ALL
USING (is_admin());

-- 9. Fix order_items RLS - merchants should also be able to read order items for their orders
DROP POLICY IF EXISTS "Merchants can view order items" ON public.order_items;
CREATE POLICY "Merchants can view order items"
ON public.order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.id = order_items.order_id
    AND m.user_id = auth.uid()
  )
);

-- 10. Couriers should be able to read order items for their deliveries
DROP POLICY IF EXISTS "Couriers can view order items" ON public.order_items;
CREATE POLICY "Couriers can view order items"
ON public.order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN couriers c ON o.courier_id = c.id
    WHERE o.id = order_items.order_id
    AND c.user_id = auth.uid()
  )
);

-- ===== END SOURCE: 20260212002837_0c6e6d69-ef2b-47a8-8635-bfbe0c1833ca.sql =====

-- ===== BEGIN SOURCE: 20260212003000_fix_halal_storage_policies.sql =====
-- Fix storage policies for halal certificates and KTP uploads
-- This ensures that users can upload files to 'certificate/' and 'ktp/' folders in the 'merchants' bucket

-- 1. Allow authenticated users to upload certificates
DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects;
CREATE POLICY "Allow users to upload certificates"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'merchants' AND
    (storage.foldername(name))[1] = 'certificate'
);

-- 2. Allow authenticated users to upload KTP
DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects;
CREATE POLICY "Allow users to upload ktp"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'merchants' AND
    (storage.foldername(name))[1] = 'ktp'
);

-- 3. Ensure public read access for the merchants bucket (already exists but making sure)
DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects;
CREATE POLICY "Public view merchants bucket"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'merchants');

-- ===== END SOURCE: 20260212003000_fix_halal_storage_policies.sql =====

-- ===== BEGIN SOURCE: 20260213134825_a4ccf03f-019f-4a23-8044-e26e56200acc.sql =====

-- Fase 0: Add missing columns and tables

-- 1. Add has_review to orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS has_review BOOLEAN DEFAULT false;

-- 2. Add halal columns to merchants
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS halal_status TEXT DEFAULT 'NONE';
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS halal_certificate_url TEXT;
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS ktp_url TEXT;

-- 3. Create halal_regulations table
CREATE TABLE IF NOT EXISTS public.halal_regulations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.halal_regulations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read halal_regulations" ON public.halal_regulations;
CREATE POLICY "Anyone can read halal_regulations" ON public.halal_regulations FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admin can manage halal_regulations" ON public.halal_regulations;
CREATE POLICY "Admin can manage halal_regulations" ON public.halal_regulations FOR ALL USING (public.is_admin());

-- 4. Create increment_product_view function
CREATE OR REPLACE FUNCTION public.increment_product_view(product_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.products SET view_count = COALESCE(view_count, 0) + 1 WHERE id = product_id;
END;
$$;

-- 5. Fix auto_assign_merchant_to_group trigger to work on UPDATE too
-- Drop and recreate trigger to include UPDATE
DROP TRIGGER IF EXISTS auto_assign_merchant_to_group ON public.merchants;

CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_group_id UUID;
  v_verifikator_id UUID;
BEGIN
  -- Only process if verifikator_code is set and group_id is not
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    -- Find the trade group and verifikator for this code
    SELECT tg.id, tg.verifikator_id INTO v_group_id, v_verifikator_id
    FROM public.trade_groups tg
    JOIN public.verifikator_codes vc ON vc.trade_group = tg.name
    WHERE vc.code = NEW.verifikator_code
    LIMIT 1;

    IF v_group_id IS NOT NULL THEN
      NEW.group_id := v_group_id;
      NEW.verifikator_id := v_verifikator_id;

      -- Insert into group_members if not exists
      INSERT INTO public.group_members (group_id, merchant_id, status)
      VALUES (v_group_id, NEW.id, 'ACTIVE')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_assign_merchant_to_group ON public.merchants;
CREATE TRIGGER auto_assign_merchant_to_group
  BEFORE INSERT OR UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_merchant_to_group();

-- 6. Auto-assign admin_desa role when village is approved
CREATE OR REPLACE FUNCTION public.auto_assign_village_admin_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- When village is approved and has a user_id
  IF NEW.registration_status = 'APPROVED' AND OLD.registration_status = 'PENDING' AND NEW.user_id IS NOT NULL THEN
    -- Add admin_desa role if not exists
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, 'admin_desa')
    ON CONFLICT DO NOTHING;

    -- Add to user_villages if not exists
    INSERT INTO public.user_villages (user_id, village_id, role)
    VALUES (NEW.user_id, NEW.id, 'admin')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_assign_village_admin ON public.villages;
CREATE TRIGGER auto_assign_village_admin
  AFTER UPDATE ON public.villages
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_village_admin_role();

-- ===== END SOURCE: 20260213134825_a4ccf03f-019f-4a23-8044-e26e56200acc.sql =====

-- ===== BEGIN SOURCE: 20260214072940_66279cc5-d697-4593-ba03-497902208fca.sql =====

-- Fase 1: Pasang trigger handle_new_user yang hilang
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ===== END SOURCE: 20260214072940_66279cc5-d697-4593-ba03-497902208fca.sql =====

-- ===== BEGIN SOURCE: 20260214_fix_verifikator_code_sync.sql =====
-- 1. Tambahkan kolom verifikator_code jika belum ada
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS verifikator_code text;

-- 2. Tambahkan index untuk performa pencarian (opsional tapi disarankan)
CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_code ON public.merchants(verifikator_code);

-- 3. Perbarui Policy agar Merchant bisa melihat data mereka sendiri
-- Hapus policy lama untuk menghindari konflik
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants;
DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants;

-- Buat policy baru yang mengizinkan akses ke semua kolom (termasuk verifikator_code)
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants;
CREATE POLICY "Merchants can view own data"
ON public.merchants FOR SELECT
USING (auth.uid() = id);

DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants;
CREATE POLICY "Merchants can update own data"
ON public.merchants FOR UPDATE
USING (auth.uid() = id);

-- ===== END SOURCE: 20260214_fix_verifikator_code_sync.sql =====

-- ===== BEGIN SOURCE: 20260215102940_00f83708-770a-419b-929d-f028bdf39b87.sql =====

-- Tambah kolom slug ke merchants
ALTER TABLE merchants ADD COLUMN IF NOT EXISTS slug text UNIQUE;

-- Index untuk pencarian slug
CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_slug ON merchants(slug) WHERE slug IS NOT NULL;

-- Function untuk generate slug dari nama
CREATE OR REPLACE FUNCTION generate_merchant_slug(merchant_name text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  base_slug text;
  final_slug text;
  counter integer := 0;
BEGIN
  base_slug := lower(regexp_replace(merchant_name, '[^a-zA-Z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  final_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM merchants WHERE slug = final_slug) LOOP
    counter := counter + 1;
    final_slug := base_slug || '-' || counter;
  END LOOP;
  RETURN final_slug;
END;
$$;

-- Set slug untuk merchant yang sudah ada
UPDATE merchants SET slug = generate_merchant_slug(name) WHERE slug IS NULL;

-- ===== END SOURCE: 20260215102940_00f83708-770a-419b-929d-f028bdf39b87.sql =====

-- ===== BEGIN SOURCE: 20260215102956_65ab4313-dc1c-4a61-a563-54e00ae94b73.sql =====

-- Fix search_path for generate_merchant_slug
CREATE OR REPLACE FUNCTION public.generate_merchant_slug(merchant_name text)
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  base_slug text;
  final_slug text;
  counter integer := 0;
BEGIN
  base_slug := lower(regexp_replace(merchant_name, '[^a-zA-Z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  final_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM merchants WHERE slug = final_slug) LOOP
    counter := counter + 1;
    final_slug := base_slug || '-' || counter;
  END LOOP;
  RETURN final_slug;
END;
$$;

-- ===== END SOURCE: 20260215102956_65ab4313-dc1c-4a61-a563-54e00ae94b73.sql =====

-- ===== BEGIN SOURCE: 20260215103428_8818dce9-0f49-4226-921f-73980fa6f07d.sql =====

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
);

-- Index for fast lookups
CREATE INDEX idx_chat_messages_order_id ON public.chat_messages(order_id);
CREATE INDEX idx_chat_messages_auto_delete ON public.chat_messages(auto_delete_at) WHERE auto_delete_at IS NOT NULL;

-- Enable RLS
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Policies: only sender/receiver can access
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id);

DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
CREATE POLICY "Users can update own messages read status"
ON public.chat_messages FOR UPDATE
USING (auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages;
CREATE POLICY "Admins can manage all chat messages"
ON public.chat_messages FOR ALL
USING (is_admin());

-- Enable realtime for chat
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
END $$;

-- Page views tracking table
CREATE TABLE public.page_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  viewer_id uuid,
  page_type text NOT NULL DEFAULT 'product',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_page_views_merchant ON public.page_views(merchant_id, created_at);
CREATE INDEX idx_page_views_product ON public.page_views(product_id, created_at);

ALTER TABLE public.page_views ENABLE ROW LEVEL SECURITY;

-- Anyone can insert page views (anonymous tracking)
DROP POLICY IF EXISTS "Anyone can insert page views" ON public.page_views;
CREATE POLICY "Anyone can insert page views"
ON public.page_views FOR INSERT
WITH CHECK (true);

-- Merchants can view their own page views
DROP POLICY IF EXISTS "Merchants can view own page views" ON public.page_views;
CREATE POLICY "Merchants can view own page views"
ON public.page_views FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = page_views.merchant_id
    AND merchants.user_id = auth.uid()
  )
  OR is_admin()
);

-- Function to set auto_delete_at when order is completed
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
$$;

DROP TRIGGER IF EXISTS trigger_set_chat_auto_delete ON public.orders;
CREATE TRIGGER trigger_set_chat_auto_delete
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.set_chat_auto_delete();

-- Function to clean up expired chat messages (called by cron)
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM chat_messages WHERE auto_delete_at IS NOT NULL AND auto_delete_at <= now();
END;
$$;

-- ===== END SOURCE: 20260215103428_8818dce9-0f49-4226-921f-73980fa6f07d.sql =====

-- ===== BEGIN SOURCE: 20260215103444_7fe72258-2df8-498e-9cd1-ee8089946494.sql =====

-- Fix search_path on generate_merchant_slug
ALTER FUNCTION public.generate_merchant_slug(text) SET search_path = public;

-- ===== END SOURCE: 20260215103444_7fe72258-2df8-498e-9cd1-ee8089946494.sql =====

-- ===== BEGIN SOURCE: 20260215154513_4e9d07f9-fb9b-4df3-8100-23cc92a8378f.sql =====

ALTER TABLE kas_payments ADD COLUMN IF NOT EXISTS invoice_note text;
ALTER TABLE kas_payments ADD COLUMN IF NOT EXISTS sent_at timestamptz;

-- ===== END SOURCE: 20260215154513_4e9d07f9-fb9b-4df3-8100-23cc92a8378f.sql =====

-- ===== BEGIN SOURCE: 20260215155734_b13eac58-177e-4d8b-98ac-e1630e6d34ac.sql =====

-- Tabel pengumuman verifikator ke kelompok
CREATE TABLE IF NOT EXISTS public.group_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  verifikator_id uuid REFERENCES auth.users(id),
  title text NOT NULL,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.group_announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Verifikator can manage own announcements" ON public.group_announcements;
CREATE POLICY "Verifikator can manage own announcements"
  ON public.group_announcements FOR ALL
  USING (verifikator_id = auth.uid());

DROP POLICY IF EXISTS "Group members can read announcements" ON public.group_announcements;
CREATE POLICY "Group members can read announcements"
  ON public.group_announcements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      JOIN public.merchants m ON m.id = gm.merchant_id
      WHERE gm.group_id = group_announcements.group_id
      AND m.user_id = auth.uid()
    )
  );

-- Ambang batas stok per produk
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS low_stock_threshold integer DEFAULT 5;

-- ===== END SOURCE: 20260215155734_b13eac58-177e-4d8b-98ac-e1630e6d34ac.sql =====

-- ===== BEGIN SOURCE: 20260218000000_auto_confirm_email.sql =====
-- Trigger to automatically confirm email for new users
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_email()
RETURNS TRIGGER AS $$
BEGIN
  NEW.email_confirmed_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop if exists and create trigger
DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm ON auth.users;
CREATE TRIGGER on_auth_user_created_auto_confirm
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_auto_confirm_email();

-- ===== END SOURCE: 20260218000000_auto_confirm_email.sql =====

-- ===== BEGIN SOURCE: 20260219000000_add_merchant_auto_approve_setting.sql =====
-- Add merchant auto approve setting to app_settings
INSERT INTO public.app_settings (key, value, description, category)
VALUES (
    'merchant_auto_approve',
    '{"enabled": false}',
    'Enable/disable automatic approval for new merchant registrations',
    'registration'
)
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260219000000_add_merchant_auto_approve_setting.sql =====

-- ===== BEGIN SOURCE: 20260220084303_65515e4b-c3b1-4a16-b325-a3f977d4ce67.sql =====
-- Auto-generate slug on merchant insert
CREATE OR REPLACE FUNCTION auto_set_merchant_slug()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug := generate_merchant_slug(NEW.name);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_merchant_slug ON merchants;
CREATE TRIGGER trg_auto_merchant_slug
  BEFORE INSERT ON merchants
  FOR EACH ROW EXECUTE FUNCTION auto_set_merchant_slug();

-- Also auto-update slug when name changes and slug was auto-generated
CREATE OR REPLACE FUNCTION auto_update_merchant_slug()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  -- Only auto-update if name changed and old slug was derived from old name
  IF NEW.name IS DISTINCT FROM OLD.name AND (OLD.slug IS NULL OR OLD.slug = '' OR OLD.slug = generate_merchant_slug(OLD.name)) THEN
    NEW.slug := generate_merchant_slug(NEW.name);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_update_merchant_slug ON merchants;
CREATE TRIGGER trg_auto_update_merchant_slug
  BEFORE UPDATE ON merchants
  FOR EACH ROW EXECUTE FUNCTION auto_update_merchant_slug();

-- ===== END SOURCE: 20260220084303_65515e4b-c3b1-4a16-b325-a3f977d4ce67.sql =====

-- ===== BEGIN SOURCE: 20260220084533_6b62aa70-289a-4ef5-81c1-bb37dcfb6086.sql =====
-- Create merchant gallery table for "Tentang Kami" photos
CREATE TABLE public.merchant_gallery (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  caption text,
  sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.merchant_gallery ENABLE ROW LEVEL SECURITY;

-- Anyone can view gallery images of active merchants
DROP POLICY IF EXISTS "Public can view merchant gallery" ON public.merchant_gallery;
CREATE POLICY "Public can view merchant gallery"
  ON public.merchant_gallery FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = merchant_gallery.merchant_id
    AND merchants.status = 'ACTIVE'
    AND merchants.registration_status = 'APPROVED'
  ));

-- Merchants can manage own gallery
DROP POLICY IF EXISTS "Merchants can manage own gallery" ON public.merchant_gallery;
CREATE POLICY "Merchants can manage own gallery"
  ON public.merchant_gallery FOR ALL
  USING (EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = merchant_gallery.merchant_id
    AND merchants.user_id = auth.uid()
  ));

-- Admins can manage all galleries
DROP POLICY IF EXISTS "Admins can manage all galleries" ON public.merchant_gallery;
CREATE POLICY "Admins can manage all galleries"
  ON public.merchant_gallery FOR ALL
  USING (is_admin());

-- Create storage bucket for merchant gallery images
INSERT INTO storage.buckets (id, name, public) VALUES ('merchant-gallery', 'merchant-gallery', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for merchant gallery
DROP POLICY IF EXISTS "Public can view merchant gallery images" ON storage.objects;
CREATE POLICY "Public can view merchant gallery images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'merchant-gallery');

DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects;
CREATE POLICY "Authenticated users can upload merchant gallery images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects;
CREATE POLICY "Users can update own merchant gallery images"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects;
CREATE POLICY "Users can delete own merchant gallery images"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL);

-- ===== END SOURCE: 20260220084533_6b62aa70-289a-4ef5-81c1-bb37dcfb6086.sql =====

-- ===== BEGIN SOURCE: 20260220094944_4e9af0cf-2be8-4fa8-ac7b-21d6015ea7ae.sql =====

-- Add is_self_delivery column to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS is_self_delivery boolean DEFAULT false;

-- ===== END SOURCE: 20260220094944_4e9af0cf-2be8-4fa8-ac7b-21d6015ea7ae.sql =====

-- ===== BEGIN SOURCE: 20260220100643_eb05139c-d230-4b52-b83b-20deb8b8b8bb.sql =====
-- Enable realtime for orders table so buyers get live status updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260220100643_eb05139c-d230-4b52-b83b-20deb8b8b8bb.sql =====

-- ===== BEGIN SOURCE: 20260220101331_54473674-8625-4cd5-bcad-a5faa0c4a3e8.sql =====

-- Fix UPDATE policy to include WITH CHECK
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses"
ON public.saved_addresses FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ===== END SOURCE: 20260220101331_54473674-8625-4cd5-bcad-a5faa0c4a3e8.sql =====

-- ===== BEGIN SOURCE: 20260220102410_b1e662ad-3482-496a-aa4d-f8078ad98c25.sql =====

-- Create a function to safely decrement product stock
CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_quantity integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE products
  SET stock = GREATEST(0, stock - p_quantity),
      updated_at = now()
  WHERE id = p_product_id;
END;
$$;

-- ===== END SOURCE: 20260220102410_b1e662ad-3482-496a-aa4d-f8078ad98c25.sql =====

-- ===== BEGIN SOURCE: 20260220105922_a9d87006-18a0-4ab2-aaff-87e7b485b798.sql =====

-- Fase 1: Upgrade tabel chat_messages untuk multi-tipe chat

-- Tambah kolom chat_type dan image_url
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS chat_type TEXT DEFAULT 'buyer_merchant',
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Index untuk query berdasarkan chat_type
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_type ON public.chat_messages(order_id, chat_type);

-- Drop existing RLS policies yang akan di-update
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;

-- Helper function: cek apakah user adalah kurir pada order tertentu
CREATE OR REPLACE FUNCTION public.is_chat_participant(
  _user_id uuid,
  _order_id uuid,
  _chat_type text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN _chat_type = 'buyer_merchant' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN merchants m ON o.merchant_id = m.id
        WHERE o.id = _order_id
          AND (o.buyer_id = _user_id OR m.user_id = _user_id)
      )
    WHEN _chat_type = 'buyer_courier' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN couriers c ON o.courier_id = c.id
        WHERE o.id = _order_id
          AND (o.buyer_id = _user_id OR c.user_id = _user_id)
      )
    WHEN _chat_type = 'merchant_courier' THEN
      EXISTS (
        SELECT 1 FROM orders o
        LEFT JOIN merchants m ON o.merchant_id = m.id
        LEFT JOIN couriers c ON o.courier_id = c.id
        WHERE o.id = _order_id
          AND (m.user_id = _user_id OR c.user_id = _user_id)
      )
    ELSE false
  END
$$;

-- RLS: Users can view chat messages where they are participants
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view own chat messages"
ON public.chat_messages
FOR SELECT
USING (
  (auth.uid() = sender_id OR auth.uid() = receiver_id)
  OR is_chat_participant(auth.uid(), order_id, chat_type)
);

-- RLS: Users can send chat messages if they are a participant
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
CREATE POLICY "Users can send chat messages"
ON public.chat_messages
FOR INSERT
WITH CHECK (
  auth.uid() = sender_id
  AND is_chat_participant(auth.uid(), order_id, chat_type)
);

-- RLS: Users can update read status on messages they received
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
CREATE POLICY "Users can update own messages read status"
ON public.chat_messages
FOR UPDATE
USING (auth.uid() = receiver_id);

-- Create storage bucket for chat images
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-images', 'chat-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for chat images
DROP POLICY IF EXISTS "Authenticated users can upload chat images" ON storage.objects;
CREATE POLICY "Authenticated users can upload chat images"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'chat-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Anyone can view chat images" ON storage.objects;
CREATE POLICY "Anyone can view chat images"
ON storage.objects
FOR SELECT
USING (bucket_id = 'chat-images');

-- ===== END SOURCE: 20260220105922_a9d87006-18a0-4ab2-aaff-87e7b485b798.sql =====
-- ===== END BUNDLE: 04_20260208054918_to_20260220105922.sql =====

-- ===== BEGIN BUNDLE: 05_20260220110705_to_20260508000000.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260220110705_505c5087-9b55-4a78-9d79-ae00fa83a485.sql .. 20260508000000_phase1_pos_saas.sql


-- ===== BEGIN SOURCE: 20260220110705_505c5087-9b55-4a78-9d79-ae00fa83a485.sql =====

-- Drop function with cascade (will also drop dependent policies)
DROP FUNCTION IF EXISTS public.is_chat_participant(uuid, uuid, text) CASCADE;

-- Recreate function
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Recreate the policies that were dropped by CASCADE
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR is_chat_participant(auth.uid(), order_id, chat_type));

DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id AND is_chat_participant(auth.uid(), order_id, chat_type));

-- ===== END SOURCE: 20260220110705_505c5087-9b55-4a78-9d79-ae00fa83a485.sql =====

-- ===== BEGIN SOURCE: 20260220110912_8501cf77-84b6-4db2-863d-e8b5bb274741.sql =====

-- Create chat_messages table if not exists
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL,
  receiver_id UUID NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  chat_type TEXT DEFAULT 'buyer_merchant',
  image_url TEXT,
  auto_delete_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Add columns if they don't exist (for cases where table exists but columns don't)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='chat_type') THEN
    ALTER TABLE public.chat_messages ADD COLUMN chat_type TEXT DEFAULT 'buyer_merchant';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='image_url') THEN
    ALTER TABLE public.chat_messages ADD COLUMN image_url TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='chat_messages' AND column_name='auto_delete_at') THEN
    ALTER TABLE public.chat_messages ADD COLUMN auto_delete_at TIMESTAMP WITH TIME ZONE;
  END IF;
END$$;

-- Drop and recreate function
DROP FUNCTION IF EXISTS public.is_chat_participant(uuid, uuid, text) CASCADE;

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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages;

-- Create policies
DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR is_chat_participant(auth.uid(), order_id, chat_type));

DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id AND is_chat_participant(auth.uid(), order_id, chat_type));

DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
CREATE POLICY "Users can update own messages read status"
ON public.chat_messages FOR UPDATE
USING (auth.uid() = receiver_id);

DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages;
CREATE POLICY "Admins can manage all chat messages"
ON public.chat_messages FOR ALL
USING (is_admin());

-- Enable realtime (ignore error if already added)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END$$;

-- Auto-delete trigger
CREATE OR REPLACE FUNCTION public.set_chat_auto_delete()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status NOT IN ('DONE', 'DELIVERED') THEN
    UPDATE chat_messages
    SET auto_delete_at = now() + interval '3 hours'
    WHERE order_id = NEW.id AND auto_delete_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trigger_set_chat_auto_delete ON public.orders;
CREATE TRIGGER trigger_set_chat_auto_delete
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_chat_auto_delete();

-- Cleanup function
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void AS $$
BEGIN
  DELETE FROM chat_messages WHERE auto_delete_at IS NOT NULL AND auto_delete_at <= now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ===== END SOURCE: 20260220110912_8501cf77-84b6-4db2-863d-e8b5bb274741.sql =====

-- ===== BEGIN SOURCE: 20260220113000_7d04341d-76b7-417a-8020-b8440db4355e.sql =====

-- Create trigger function to auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (user_id) DO UPDATE SET
    full_name = COALESCE(
      EXCLUDED.full_name,
      public.profiles.full_name
    );
  RETURN NEW;
END;
$$;

-- Drop existing trigger if any
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Backfill: create profiles for existing users who don't have one
INSERT INTO public.profiles (user_id, full_name)
SELECT
  u.id,
  COALESCE(
    u.raw_user_meta_data->>'full_name',
    u.raw_user_meta_data->>'name',
    split_part(u.email, '@', 1)
  )
FROM auth.users u
LEFT JOIN public.profiles p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- ===== END SOURCE: 20260220113000_7d04341d-76b7-417a-8020-b8440db4355e.sql =====

-- ===== BEGIN SOURCE: 20260220115912_3db445e5-e360-4861-9a77-e996172d54d9.sql =====

-- 1. Pastikan tabel saved_addresses ada dengan benar
CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  label TEXT NOT NULL DEFAULT 'Rumah',
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  province_id TEXT,
  province_name TEXT,
  city_id TEXT,
  city_name TEXT,
  district_id TEXT,
  district_name TEXT,
  village_id TEXT,
  village_name TEXT,
  address_detail TEXT,
  full_address TEXT,
  lat NUMERIC,
  lng NUMERIC,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

-- 3. Bersihkan dan buat ulang policies
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;

DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5. Tambahkan kolom email ke profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'email'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN email TEXT;
  END IF;
END $$;

-- 6. Backfill email dari auth.users
UPDATE public.profiles p
SET email = u.email
FROM auth.users u
WHERE p.user_id = u.id
AND p.email IS NULL;

-- 7. Enable realtime untuk saved_addresses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ===== END SOURCE: 20260220115912_3db445e5-e360-4861-9a77-e996172d54d9.sql =====

-- ===== BEGIN SOURCE: 20260220115937_b04bafdb-bc2c-4cf8-9e68-fd1df2668cfb.sql =====

-- Fix search_path on set_updated_at function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- ===== END SOURCE: 20260220115937_b04bafdb-bc2c-4cf8-9e68-fd1df2668cfb.sql =====

-- ===== BEGIN SOURCE: 20260220125614_55452632-5bf8-466f-9b47-10c530f6432a.sql =====
ALTER TABLE public.orders DROP CONSTRAINT orders_status_check;

ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (status = ANY (ARRAY[
  'NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT', 'PROCESSED', 'READY',
  'ASSIGNED', 'PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED', 'DONE',
  'CANCELED', 'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED'
]));

-- ===== END SOURCE: 20260220125614_55452632-5bf8-466f-9b47-10c530f6432a.sql =====

-- ===== BEGIN SOURCE: 20260220_fix_saved_addresses_comprehensive.sql =====
-- =============================================
-- MIGRASI: Perbaikan Komprehensif saved_addresses
-- =============================================
-- Deskripsi: Memastikan tabel saved_addresses memiliki struktur yang benar,
--            RLS policies yang tepat, dan terdaftar di realtime publication.

-- 1. Pastikan tabel saved_addresses ada dengan struktur yang benar
CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT 'Rumah',
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  province_id TEXT,
  province_name TEXT,
  city_id TEXT,
  city_name TEXT,
  district_id TEXT,
  district_name TEXT,
  village_id TEXT,
  village_name TEXT,
  address_detail TEXT,
  full_address TEXT,
  lat NUMERIC,
  lng NUMERIC,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

-- 3. Bersihkan dan buat ulang policies
-- Hapus policy lama yang mungkin bermasalah
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Anyone can insert addresses" ON public.saved_addresses;

-- Buat policy baru yang bersih
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5. Enable realtime untuk saved_addresses (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON pr.prpubid = p.oid
    JOIN pg_class c ON pr.prrelid = c.oid
    WHERE p.pubname = 'supabase_realtime'
    AND c.relname = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not add table to publication: %', SQLERRM;
END $$;

-- ===== END SOURCE: 20260220_fix_saved_addresses_comprehensive.sql =====

-- ===== BEGIN SOURCE: 20260220_fix_saved_addresses_rls.sql =====
-- =============================================
-- MIGRASI: Fix RLS Policies untuk saved_addresses
-- =============================================
-- Tanggal: 2026-02-20
-- Deskripsi: Perbaiki RLS policies dan trigger untuk saved_addresses table
--            Tambahkan kolom email ke profiles table jika belum ada
--            Idempotent: Aman untuk dijalankan berkali-kali

-- 1. Pastikan tabel saved_addresses ada dengan benar
CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  label TEXT NOT NULL DEFAULT 'Rumah',
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  province_id TEXT,
  province_name TEXT,
  city_id TEXT,
  city_name TEXT,
  district_id TEXT,
  district_name TEXT,
  village_id TEXT,
  village_name TEXT,
  address_detail TEXT,
  full_address TEXT,
  lat NUMERIC,
  lng NUMERIC,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

-- 3. Bersihkan dan buat ulang policies
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;

DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5. Tambahkan kolom email ke profiles (fix bug column "email" does not exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'email'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN email TEXT;
  END IF;
END $$;

-- 6. Backfill email dari auth.users
UPDATE public.profiles p
SET email = u.email
FROM auth.users u
WHERE p.user_id = u.id
AND p.email IS NULL;

-- 7. Enable realtime untuk saved_addresses (idempotent - hanya jika belum ada)
DO $$
BEGIN
  -- Check if saved_addresses is already in supabase_realtime publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON pr.prpubid = p.oid
    JOIN pg_class c ON pr.prrelid = c.oid
    WHERE p.pubname = 'supabase_realtime'
    AND c.relname = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
END $$;

-- ===== END SOURCE: 20260220_fix_saved_addresses_rls.sql =====

-- ===== BEGIN SOURCE: 20260224043813_b9b0fbfd-f904-4f9b-aea9-a3cd0d1fd021.sql =====
-- Add sold_count column to products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sold_count integer NOT NULL DEFAULT 0;

-- Create index for sorting by sold_count
CREATE INDEX IF NOT EXISTS idx_products_sold_count ON public.products(sold_count DESC);

-- ===== END SOURCE: 20260224043813_b9b0fbfd-f904-4f9b-aea9-a3cd0d1fd021.sql =====

-- ===== BEGIN SOURCE: 20260224_fix_user_roles_rls_for_registration.sql =====
-- Fix RLS policies for user_roles to allow the system/trigger to manage roles
-- and ensure users can always see their own roles.

-- 1. Ensure the trigger function exists and is robust
CREATE OR REPLACE FUNCTION public.handle_merchant_approval_role()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if status is APPROVED (either on insert or update)
  IF (NEW.registration_status = 'APPROVED') THEN
    -- Ensure user_id exists
    IF NEW.user_id IS NOT NULL THEN
      -- Add merchant role to user_roles table
      -- SECURITY DEFINER in the function handles the permission
      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'merchant')
      ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Re-apply the trigger for both INSERT and UPDATE
-- This ensures that if a merchant is created with 'APPROVED' status, the role is added immediately.
DROP TRIGGER IF EXISTS on_merchant_approval_insert ON public.merchants;
CREATE TRIGGER on_merchant_approval_insert
  AFTER INSERT ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role();

DROP TRIGGER IF EXISTS on_merchant_approval_update ON public.merchants;
CREATE TRIGGER on_merchant_approval_update
  AFTER UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role();

-- 3. Fix RLS for user_roles to be more reliable
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- 4. Ensure the enum 'merchant' is correctly handled (it already exists based on previous migrations)

-- ===== END SOURCE: 20260224_fix_user_roles_rls_for_registration.sql =====

-- ===== BEGIN SOURCE: 20260226000000_add_has_review_to_orders.sql =====
-- Add has_review column to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_review BOOLEAN DEFAULT FALSE;

-- ===== END SOURCE: 20260226000000_add_has_review_to_orders.sql =====

-- ===== BEGIN SOURCE: 20260228041319_8cdbdfdc-5e55-4fa1-80f9-a10c4fc0b22f.sql =====

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
);

ALTER TABLE public.courier_deposits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Couriers can create own deposits" ON public.courier_deposits;
CREATE POLICY "Couriers can create own deposits" ON public.courier_deposits
  FOR INSERT WITH CHECK (courier_id = get_user_courier_id());

DROP POLICY IF EXISTS "Couriers can view own deposits" ON public.courier_deposits;
CREATE POLICY "Couriers can view own deposits" ON public.courier_deposits
  FOR SELECT USING (courier_id = get_user_courier_id());

DROP POLICY IF EXISTS "Admins full access courier deposits" ON public.courier_deposits;
CREATE POLICY "Admins full access courier deposits" ON public.courier_deposits
  FOR ALL USING (is_admin());

-- Courier balance logs table
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
);

ALTER TABLE public.courier_balance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Couriers can view own balance logs" ON public.courier_balance_logs;
CREATE POLICY "Couriers can view own balance logs" ON public.courier_balance_logs
  FOR SELECT USING (courier_id = get_user_courier_id());

DROP POLICY IF EXISTS "Admins full access balance logs" ON public.courier_balance_logs;
CREATE POLICY "Admins full access balance logs" ON public.courier_balance_logs
  FOR ALL USING (is_admin());

-- Insert courier minimum balance setting
INSERT INTO public.app_settings (key, category, value, description)
VALUES ('courier_minimum_balance', 'courier', '{"amount": 50000}', 'Saldo minimum yang harus tersisa saat kurir melakukan penarikan')
ON CONFLICT (key) DO NOTHING;

-- Enable realtime for balance logs
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
END $$;
DO $$
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
END $$;

-- ===== END SOURCE: 20260228041319_8cdbdfdc-5e55-4fa1-80f9-a10c4fc0b22f.sql =====

-- ===== BEGIN SOURCE: 20260303061217_56755ee2-bf3f-45ae-be7e-41361e5026c1.sql =====

-- Function to update merchant rating when reviews change
CREATE OR REPLACE FUNCTION public.update_merchant_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_merchant_id uuid;
  new_avg numeric;
  new_count integer;
BEGIN
  -- Determine the merchant_id based on the operation
  IF TG_OP = 'DELETE' THEN
    target_merchant_id := OLD.merchant_id;
  ELSE
    target_merchant_id := NEW.merchant_id;
  END IF;

  -- Calculate new rating stats
  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO new_avg, new_count
  FROM public.reviews
  WHERE merchant_id = target_merchant_id;

  -- Update the merchant
  UPDATE public.merchants
  SET rating_avg = ROUND(new_avg, 1),
      rating_count = new_count,
      updated_at = now()
  WHERE id = target_merchant_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger on reviews table
DROP TRIGGER IF EXISTS trigger_update_merchant_rating ON public.reviews;
CREATE TRIGGER trigger_update_merchant_rating
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW
EXECUTE FUNCTION public.update_merchant_rating();

-- ===== END SOURCE: 20260303061217_56755ee2-bf3f-45ae-be7e-41361e5026c1.sql =====

-- ===== BEGIN SOURCE: 20260303061323_2f45343b-5a0f-45af-af7e-981f4f23ea52.sql =====

-- Create ride_requests table for Ojek Desa feature
CREATE TABLE public.ride_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  passenger_id uuid NOT NULL,
  driver_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  pickup_lat numeric NOT NULL,
  pickup_lng numeric NOT NULL,
  pickup_address text NOT NULL DEFAULT '',
  destination_lat numeric NOT NULL,
  destination_lng numeric NOT NULL,
  destination_address text NOT NULL DEFAULT '',
  distance_km numeric NOT NULL DEFAULT 0,
  estimated_fare integer NOT NULL DEFAULT 0,
  final_fare integer,
  status text NOT NULL DEFAULT 'SEARCHING',
  accepted_at timestamp with time zone,
  picked_up_at timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  rating integer,
  rating_comment text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

-- Passengers can create ride requests
DROP POLICY IF EXISTS "Passengers can create rides" ON public.ride_requests;
CREATE POLICY "Passengers can create rides"
ON public.ride_requests
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = passenger_id);

-- Passengers can view own rides
DROP POLICY IF EXISTS "Passengers can view own rides" ON public.ride_requests;
CREATE POLICY "Passengers can view own rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (auth.uid() = passenger_id);

-- Passengers can update own rides (cancel)
DROP POLICY IF EXISTS "Passengers can update own rides" ON public.ride_requests;
CREATE POLICY "Passengers can update own rides"
ON public.ride_requests
FOR UPDATE
TO authenticated
USING (auth.uid() = passenger_id);

-- Drivers can view SEARCHING rides (to accept)
DROP POLICY IF EXISTS "Drivers can view searching rides" ON public.ride_requests;
CREATE POLICY "Drivers can view searching rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (
  status = 'SEARCHING' AND EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.user_id = auth.uid()
    AND couriers.registration_status = 'APPROVED'
    AND couriers.status = 'ACTIVE'
    AND couriers.is_available = true
  )
);

-- Drivers can view their assigned rides
DROP POLICY IF EXISTS "Drivers can view assigned rides" ON public.ride_requests;
CREATE POLICY "Drivers can view assigned rides"
ON public.ride_requests
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.id = ride_requests.driver_id
    AND couriers.user_id = auth.uid()
  )
);

-- Drivers can update rides they accepted
DROP POLICY IF EXISTS "Drivers can update assigned rides" ON public.ride_requests;
CREATE POLICY "Drivers can update assigned rides"
ON public.ride_requests
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.couriers
    WHERE couriers.id = ride_requests.driver_id
    AND couriers.user_id = auth.uid()
  )
);

-- Admin full access
DROP POLICY IF EXISTS "Admins can manage all rides" ON public.ride_requests;
CREATE POLICY "Admins can manage all rides"
ON public.ride_requests
FOR ALL
TO authenticated
USING (public.is_admin());

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_ride_requests_updated_at ON public.ride_requests;
CREATE TRIGGER update_ride_requests_updated_at
BEFORE UPDATE ON public.ride_requests
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Enable realtime for ride_requests
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'ride_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_requests;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- Insert default ride fare settings
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'ride_fare_settings',
  '{"base_fare": 5000, "per_km_fare": 3000, "min_fare": 5000, "max_fare": 100000}'::jsonb,
  'ride',
  'Pengaturan tarif ojek desa: base_fare (tarif dasar), per_km_fare (tarif per km), min_fare (tarif minimum), max_fare (tarif maksimum)'
)
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260303061323_2f45343b-5a0f-45af-af7e-981f4f23ea52.sql =====

-- ===== BEGIN SOURCE: 20260304083036_d88ed292-f868-451b-a479-2487dedd4e5c.sql =====

-- Atomic RPC to accept a ride, preventing race conditions
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id UUID, p_courier_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_updated INTEGER;
BEGIN
  UPDATE ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN FALSE;
  END IF;

  -- Send notification to passenger
  PERFORM send_notification(
    passenger_id,
    'Driver Ditemukan! 🏍️',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  )
  FROM ride_requests WHERE id = p_ride_id;

  RETURN TRUE;
END;
$$;

-- ===== END SOURCE: 20260304083036_d88ed292-f868-451b-a479-2487dedd4e5c.sql =====

-- ===== BEGIN SOURCE: 20260309040323_1f66e7ec-8223-435e-bbd8-c7335e338238.sql =====

CREATE TABLE IF NOT EXISTS public.merchant_favorites (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id, merchant_id)
);

ALTER TABLE public.merchant_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can view their own favorites"
  ON public.merchant_favorites
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can insert their own favorites"
  ON public.merchant_favorites
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.merchant_favorites;
CREATE POLICY "Users can delete their own favorites"
  ON public.merchant_favorites
  FOR DELETE
  USING (auth.uid() = user_id);

-- ===== END SOURCE: 20260309040323_1f66e7ec-8223-435e-bbd8-c7335e338238.sql =====

-- ===== BEGIN SOURCE: 20260312142500_47527dd5-2b77-460d-bdcc-5d53f0936910.sql =====

-- Cleanup duplicate RLS policies on orders table
-- Keep: orders_admin_access, orders_buyer_access, orders_merchant_access, orders_courier_access (FOR ALL)
-- Remove: granular per-command duplicates
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders;
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;

-- Cleanup duplicate RLS policies on couriers table
-- Keep: couriers_admin_access, couriers_own_access, couriers_public_read
-- Remove: named duplicates
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers;
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers;
DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers;

-- Cleanup duplicate RLS policies on merchants table
-- Keep: Admins can manage merchants, Anyone can register merchant, Merchants can update own data, Verifikator can manage merchants
-- Remove overlapping SELECT policies
DROP POLICY IF EXISTS "Authenticated users can view active merchants" ON public.merchants;
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants;

-- ===== END SOURCE: 20260312142500_47527dd5-2b77-460d-bdcc-5d53f0936910.sql =====

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

DROP POLICY IF EXISTS "Authenticated or anonymous can insert their own page view" ON public.page_views;
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
DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects;
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
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'payment-proofs');

-- UPDATE: only the buyer of the order
DROP POLICY IF EXISTS "Buyer can update own payment proofs" ON storage.objects;
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
DROP POLICY IF EXISTS "Buyer or admin can delete payment proofs" ON storage.objects;
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
DROP POLICY IF EXISTS "tenant_owner_all" ON pos_tenants;
CREATE POLICY "tenant_owner_all" ON pos_tenants FOR ALL USING (user_id = auth.uid());

-- Users within a tenant can access tenant data
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON pos_outlets;
CREATE POLICY "tenant_users_select_outlets" ON pos_outlets FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_outlets" ON pos_outlets;
CREATE POLICY "tenant_owner_manage_outlets" ON pos_outlets FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_categories" ON pos_categories;
CREATE POLICY "tenant_users_select_categories" ON pos_categories FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_categories" ON pos_categories;
CREATE POLICY "tenant_owner_manage_categories" ON pos_categories FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_brands" ON pos_brands;
CREATE POLICY "tenant_users_select_brands" ON pos_brands FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_brands" ON pos_brands;
CREATE POLICY "tenant_owner_manage_brands" ON pos_brands FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_products" ON pos_products;
CREATE POLICY "tenant_users_select_products" ON pos_products FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_products" ON pos_products;
CREATE POLICY "tenant_owner_manage_products" ON pos_products FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_variants" ON pos_product_variants;
CREATE POLICY "tenant_users_select_variants" ON pos_product_variants FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_variants" ON pos_product_variants;
CREATE POLICY "tenant_owner_manage_variants" ON pos_product_variants FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_stock" ON pos_stock;
CREATE POLICY "tenant_users_select_stock" ON pos_stock FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_stock" ON pos_stock;
CREATE POLICY "tenant_owner_manage_stock" ON pos_stock FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_mutations" ON pos_stock_mutations;
CREATE POLICY "tenant_users_select_mutations" ON pos_stock_mutations FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_mutations" ON pos_stock_mutations;
CREATE POLICY "tenant_owner_manage_mutations" ON pos_stock_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_customers" ON pos_customers;
CREATE POLICY "tenant_users_select_customers" ON pos_customers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_customers" ON pos_customers;
CREATE POLICY "tenant_owner_manage_customers" ON pos_customers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_suppliers" ON pos_suppliers;
CREATE POLICY "tenant_users_select_suppliers" ON pos_suppliers FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_suppliers" ON pos_suppliers;
CREATE POLICY "tenant_owner_manage_suppliers" ON pos_suppliers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_sales" ON pos_sales;
CREATE POLICY "tenant_users_select_sales" ON pos_sales FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_sales" ON pos_sales;
CREATE POLICY "tenant_owner_manage_sales" ON pos_sales FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_sale_items" ON pos_sale_items;
CREATE POLICY "tenant_users_select_sale_items" ON pos_sale_items FOR SELECT USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
);
DROP POLICY IF EXISTS "tenant_owner_manage_sale_items" ON pos_sale_items;
CREATE POLICY "tenant_owner_manage_sale_items" ON pos_sale_items FOR ALL USING (
  sale_id IN (SELECT id FROM pos_sales WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()))
);

DROP POLICY IF EXISTS "tenant_owner_manage_held_bills" ON pos_held_bills;
CREATE POLICY "tenant_owner_manage_held_bills" ON pos_held_bills FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON pos_held_bills;
CREATE POLICY "tenant_users_select_held_bills" ON pos_held_bills FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON pos_users;
CREATE POLICY "tenant_users_select_pos_users" ON pos_users FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  OR user_id = auth.uid()
);
DROP POLICY IF EXISTS "tenant_owner_manage_pos_users" ON pos_users;
CREATE POLICY "tenant_owner_manage_pos_users" ON pos_users FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS "tenant_owner_manage_returns" ON pos_sale_returns;
CREATE POLICY "tenant_owner_manage_returns" ON pos_sale_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_owner_manage_return_items" ON pos_sale_return_items;
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
-- ===== END BUNDLE: 05_20260220110705_to_20260508000000.sql =====

-- ===== BEGIN BUNDLE: 06_20260509000000_to_20260823071000.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260509000000_phase2_pos_purchase_kas.sql .. 20260823071000_payment_invoice_idempotency.sql


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
DROP POLICY IF EXISTS "tenant_owner_manage_purchase_orders" ON pos_purchase_orders;
CREATE POLICY "tenant_owner_manage_purchase_orders" ON pos_purchase_orders FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_select_purchase_orders" ON pos_purchase_orders;
CREATE POLICY "tenant_users_select_purchase_orders" ON pos_purchase_orders FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_owner_manage_po_items" ON pos_purchase_order_items;
CREATE POLICY "tenant_owner_manage_po_items" ON pos_purchase_order_items FOR ALL USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "tenant_users_select_po_items" ON pos_purchase_order_items;
CREATE POLICY "tenant_users_select_po_items" ON pos_purchase_order_items FOR SELECT USING (
  purchase_order_id IN (
    SELECT id FROM pos_purchase_orders
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
);

-- Purchase Returns
DROP POLICY IF EXISTS "tenant_owner_manage_purchase_returns" ON pos_purchase_returns;
CREATE POLICY "tenant_owner_manage_purchase_returns" ON pos_purchase_returns FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_owner_manage_purchase_return_items" ON pos_purchase_return_items;
CREATE POLICY "tenant_owner_manage_purchase_return_items" ON pos_purchase_return_items FOR ALL USING (
  purchase_return_id IN (
    SELECT id FROM pos_purchase_returns
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);

-- Cash Sessions
DROP POLICY IF EXISTS "tenant_owner_manage_cash_sessions" ON pos_cash_sessions;
CREATE POLICY "tenant_owner_manage_cash_sessions" ON pos_cash_sessions FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_select_cash_sessions" ON pos_cash_sessions;
CREATE POLICY "tenant_users_select_cash_sessions" ON pos_cash_sessions FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_users_manage_own_sessions" ON pos_cash_sessions;
CREATE POLICY "tenant_users_manage_own_sessions" ON pos_cash_sessions FOR ALL USING (
  cashier_id = auth.uid()
);

-- Cash Mutations
DROP POLICY IF EXISTS "tenant_owner_manage_cash_mutations" ON pos_cash_mutations;
CREATE POLICY "tenant_owner_manage_cash_mutations" ON pos_cash_mutations FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_select_cash_mutations" ON pos_cash_mutations;
CREATE POLICY "tenant_users_select_cash_mutations" ON pos_cash_mutations FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_users_manage_own_mutations" ON pos_cash_mutations;
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

DROP POLICY IF EXISTS "tenant_raw_materials" ON pos_raw_materials;
CREATE POLICY "tenant_raw_materials" ON pos_raw_materials
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "tenant_recipes" ON pos_recipes;
CREATE POLICY "tenant_recipes" ON pos_recipes
  FOR ALL USING (
    tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "tenant_raw_material_mutations" ON pos_raw_material_mutations;
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
DROP POLICY IF EXISTS "tenant_owner_manage_transfers" ON pos_stock_transfers;
CREATE POLICY "tenant_owner_manage_transfers" ON pos_stock_transfers FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_select_transfers" ON pos_stock_transfers;
CREATE POLICY "tenant_users_select_transfers" ON pos_stock_transfers FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_users_create_transfers" ON pos_stock_transfers;
CREATE POLICY "tenant_users_create_transfers" ON pos_stock_transfers FOR INSERT WITH CHECK (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);

DROP POLICY IF EXISTS "tenant_owner_manage_transfer_items" ON pos_stock_transfer_items;
CREATE POLICY "tenant_owner_manage_transfer_items" ON pos_stock_transfer_items FOR ALL USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
  )
);
DROP POLICY IF EXISTS "tenant_users_select_transfer_items" ON pos_stock_transfer_items;
CREATE POLICY "tenant_users_select_transfer_items" ON pos_stock_transfer_items FOR SELECT USING (
  transfer_id IN (
    SELECT id FROM pos_stock_transfers
    WHERE tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
  )
);

-- Audit Logs (read-only untuk semua, insert untuk semua)
DROP POLICY IF EXISTS "tenant_owner_read_audit" ON pos_audit_logs;
CREATE POLICY "tenant_owner_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_read_audit" ON pos_audit_logs;
CREATE POLICY "tenant_users_read_audit" ON pos_audit_logs FOR SELECT USING (
  tenant_id IN (SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true)
);
DROP POLICY IF EXISTS "tenant_users_write_audit" ON pos_audit_logs;
CREATE POLICY "tenant_users_write_audit" ON pos_audit_logs FOR INSERT WITH CHECK (
  tenant_id IN (
    SELECT id FROM pos_tenants WHERE user_id = auth.uid()
    UNION
    SELECT tenant_id FROM pos_users WHERE user_id = auth.uid() AND is_active = true
  )
);

-- Notifications
DROP POLICY IF EXISTS "tenant_owner_manage_notif" ON pos_notifications;
CREATE POLICY "tenant_owner_manage_notif" ON pos_notifications FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "user_own_notif" ON pos_notifications;
CREATE POLICY "user_own_notif" ON pos_notifications FOR ALL USING (
  user_id = auth.uid()
);

-- User Outlet Access
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON pos_user_outlet_access;
CREATE POLICY "tenant_owner_manage_access" ON pos_user_outlet_access FOR ALL USING (
  tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "tenant_users_read_access" ON pos_user_outlet_access;
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
DROP POLICY IF EXISTS "pos_promotions_tenant_access" ON public.pos_promotions;
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
DROP POLICY IF EXISTS "pos_vouchers_tenant_access" ON public.pos_vouchers;
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
DROP POLICY IF EXISTS "pos_voucher_usages_access" ON public.pos_voucher_usages;
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
DROP POLICY IF EXISTS "pos_loyalty_programs_access" ON public.pos_loyalty_programs;
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
DROP POLICY IF EXISTS "pos_loyalty_points_access" ON public.pos_loyalty_points;
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
DROP POLICY IF EXISTS "pos_loyalty_transactions_access" ON public.pos_loyalty_transactions;
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

DROP POLICY IF EXISTS "tenant_tables" ON pos_tables;
CREATE POLICY "tenant_tables" ON pos_tables
  FOR ALL USING (tenant_id IN (SELECT id FROM pos_tenants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "tenant_table_orders" ON pos_table_orders;
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
DROP POLICY IF EXISTS "pos_marketplace_sync_access" ON public.pos_marketplace_sync;
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
DROP POLICY IF EXISTS "pos_sync_logs_access" ON public.pos_sync_logs;
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
DROP POLICY IF EXISTS "pos_marketplace_orders_access" ON public.pos_marketplace_orders;
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
DROP POLICY IF EXISTS "pos_integration_settings_access" ON public.pos_integration_settings;
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

DROP POLICY IF EXISTS "Users can manage own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can manage own push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can manage all push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Admins can manage all push subscriptions"
  ON public.push_subscriptions
  FOR ALL
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
  ON public.push_subscriptions (user_id);

-- ===== END SOURCE: 20260601000000_push_subscriptions.sql =====

-- ===== BEGIN SOURCE: 20260601000001_api_keys_value.sql =====
-- P4-04: Bootstrap API keys and add the hashed key value used for server validation.
-- The AdminApiKeysPage manages this table, so new projects must receive the
-- table before the compatibility ALTER below is executed.

CREATE TABLE IF NOT EXISTS public.api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_prefix TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  key_value TEXT UNIQUE,
  permissions TEXT[] NOT NULL DEFAULT ARRAY['read:products']::TEXT[],
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  request_count BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ
);

ALTER TABLE public.api_keys
  ADD COLUMN IF NOT EXISTS key_value TEXT;

CREATE INDEX IF NOT EXISTS idx_api_keys_key_value
  ON public.api_keys (key_value)
  WHERE key_value IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id
  ON public.api_keys (user_id);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all API keys" ON public.api_keys;
CREATE POLICY "Admins can view all API keys"
  ON public.api_keys FOR SELECT
  TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can create API keys" ON public.api_keys;
CREATE POLICY "Admins can create API keys"
  ON public.api_keys FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update API keys" ON public.api_keys;
CREATE POLICY "Admins can update API keys"
  ON public.api_keys FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete API keys" ON public.api_keys;
CREATE POLICY "Admins can delete API keys"
  ON public.api_keys FOR DELETE
  TO authenticated
  USING (public.is_admin());

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
DROP POLICY IF EXISTS "merchant_own_hours" ON public.merchant_operating_hours;
CREATE POLICY "merchant_own_hours" ON public.merchant_operating_hours
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- Admin bisa baca semua
DROP POLICY IF EXISTS "admin_read_hours" ON public.merchant_operating_hours;
CREATE POLICY "admin_read_hours" ON public.merchant_operating_hours
  FOR SELECT USING (
    public.is_admin()
  );

-- Publik bisa baca (untuk menampilkan jadwal di halaman toko)
DROP POLICY IF EXISTS "public_read_hours" ON public.merchant_operating_hours;
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
  ('site_info','general','{"name":"SaDesa","tagline":"Marketplace Desa Indonesia","support_email":"support@desa-karya-nusantara.id"}'::jsonb,'Informasi umum situs')
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

-- ===== BEGIN SOURCE: 20260822000000_harden_password_reset_tokens.sql =====
-- P0 security hardening: the application uses Supabase Auth's native
-- resetPasswordForEmail flow. The legacy public token table must not be
-- accessible from browser clients.

REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated;

DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens;

-- Keep the table available only to trusted server-side service_role jobs.
DROP POLICY IF EXISTS "Service role manages password reset tokens" ON public.password_reset_tokens;
CREATE POLICY "Service role manages password reset tokens"
  ON public.password_reset_tokens
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE public.password_reset_tokens IS
  'Legacy table retained for migration compatibility; browser access is revoked. Use Supabase Auth native password recovery or a trusted server-side flow.';

-- Prevent accidental exposure if future migrations re-grant table privileges.
ALTER TABLE public.password_reset_tokens FORCE ROW LEVEL SECURITY;

-- ===== END SOURCE: 20260822000000_harden_password_reset_tokens.sql =====

-- ===== BEGIN SOURCE: 20260822010000_harden_pos_rls_tenant_outlet.sql =====
-- P1 security hardening: enforce tenant/outlet consistency and respect
-- granular POS outlet assignments at the database boundary.

-- Prevent rows from one tenant from pointing at another tenant's outlet.
CREATE OR REPLACE FUNCTION public.validate_pos_outlet_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id
      AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_stock',
    'pos_stock_mutations',
    'pos_sales',
    'pos_held_bills',
    'pos_sale_returns'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS validate_%I_outlet_tenant ON public.%I', table_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER validate_%I_outlet_tenant BEFORE INSERT OR UPDATE OF tenant_id, outlet_id ON public.%I FOR EACH ROW EXECUTE FUNCTION public.validate_pos_outlet_tenant()',
        table_name, table_name
      );
    END IF;
  END LOOP;
END;
$$;

-- Ensure outlet-access records cannot cross tenant boundaries.
CREATE OR REPLACE FUNCTION public.validate_pos_user_outlet_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_users u
    WHERE u.id = NEW.pos_user_id AND u.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS user does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.pos_user_outlet_access') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS validate_pos_user_outlet_access_tenant
      ON public.pos_user_outlet_access;
    CREATE TRIGGER validate_pos_user_outlet_access_tenant
      BEFORE INSERT OR UPDATE OF tenant_id, pos_user_id, outlet_id
      ON public.pos_user_outlet_access
      FOR EACH ROW
      EXECUTE FUNCTION public.validate_pos_user_outlet_access();
  END IF;
END;
$$;

-- Replace the broad tenant-wide outlet read policy with owner-or-assigned
-- outlet access. Owners retain visibility over every outlet in their tenant.
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON public.pos_outlets;
DROP POLICY IF EXISTS "POS users can view assigned outlets" ON public.pos_outlets;
CREATE POLICY "POS users can view assigned outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.pos_user_outlet_access a
      JOIN public.pos_users u ON u.id = a.pos_user_id
      WHERE a.outlet_id = pos_outlets.id
        AND a.tenant_id = pos_outlets.tenant_id
        AND a.is_active = true
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  );

-- Only owners may manage outlet assignments; users may inspect their own
-- active assignments. This avoids exposing all staff assignments to any
-- active user in the tenant.
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "tenant_users_read_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS owners manage outlet access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access;

CREATE POLICY "POS owners manage outlet access" ON public.pos_user_outlet_access
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access;
CREATE POLICY "POS users read own outlet access" ON public.pos_user_outlet_access
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.id = pos_user_outlet_access.pos_user_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  );

-- Explicit WITH CHECK clauses make the intended mutation boundary clear for
-- the core POS tables. Existing tenant-user SELECT policies remain read-only.
DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_products', 'pos_stock', 'pos_stock_mutations', 'pos_sales',
    'pos_held_bills', 'pos_customers', 'pos_suppliers', 'pos_users'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    END IF;
  END LOOP;
END;
$$;

-- Reusable access predicate for outlet-scoped POS data.
CREATE OR REPLACE FUNCTION public.pos_user_can_access_outlet(
  p_tenant_id uuid,
  p_outlet_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pos_tenants t
    WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_user_outlet_access a
    JOIN public.pos_users u ON u.id = a.pos_user_id
    WHERE a.tenant_id = p_tenant_id
      AND a.outlet_id = p_outlet_id
      AND a.is_active = true
      AND u.user_id = auth.uid()
      AND u.is_active = true
  );
$$;

-- Remove broad tenant-wide read policies for outlet-scoped data.
DROP POLICY IF EXISTS "tenant_users_select_stock" ON public.pos_stock;
DROP POLICY IF EXISTS "tenant_users_select_mutations" ON public.pos_stock_mutations;
DROP POLICY IF EXISTS "tenant_users_select_sales" ON public.pos_sales;
DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON public.pos_held_bills;
DROP POLICY IF EXISTS "tenant_users_select_returns" ON public.pos_sale_returns;
DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON public.pos_users;

DROP POLICY IF EXISTS "POS users can view assigned stock" ON public.pos_stock;
CREATE POLICY "POS users can view assigned stock" ON public.pos_stock
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned stock mutations" ON public.pos_stock_mutations;
CREATE POLICY "POS users can view assigned stock mutations" ON public.pos_stock_mutations
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned sales" ON public.pos_sales;
CREATE POLICY "POS users can view assigned sales" ON public.pos_sales
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned held bills" ON public.pos_held_bills;
CREATE POLICY "POS users can view assigned held bills" ON public.pos_held_bills
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

DROP POLICY IF EXISTS "POS users can view assigned returns" ON public.pos_sale_returns;
CREATE POLICY "POS users can view assigned returns" ON public.pos_sale_returns
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

-- Staff can see their own POS identity; only tenant owners can see the full
-- tenant user directory.
DROP POLICY IF EXISTS "POS users can view own POS identity" ON public.pos_users;
CREATE POLICY "POS users can view own POS identity" ON public.pos_users
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Explicitly grant the helper only to API roles; the function itself does not
-- expose any data and is used solely inside RLS predicates.
REVOKE ALL ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) TO authenticated;

-- ===== END SOURCE: 20260822010000_harden_pos_rls_tenant_outlet.sql =====

-- ===== BEGIN SOURCE: 20260822020000_add_payment_webhook_idempotency.sql =====
-- Idempotency ledger for payment provider callbacks.
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_key text NOT NULL,
  invoice_id text NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, event_key)
);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events(order_id, received_at DESC);

REVOKE ALL ON public.payment_webhook_events FROM anon, authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages payment webhook events"
  ON public.payment_webhook_events;
CREATE POLICY "Service role manages payment webhook events"
  ON public.payment_webhook_events FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ===== END SOURCE: 20260822020000_add_payment_webhook_idempotency.sql =====

-- ===== BEGIN SOURCE: 20260822030000_harden_storage_ownership.sql =====
-- Storage hardening for sensitive documents and merchant gallery.

-- The legacy merchants bucket contains KTP/certificate paths and must not be
-- publicly readable. Public storefront images use dedicated public buckets.
UPDATE storage.buckets
SET public = false
WHERE id = 'merchants';

DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects;

DROP POLICY IF EXISTS "Owners and reviewers can read merchant documents" ON storage.objects;
CREATE POLICY "Owners and reviewers can read merchant documents"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'merchants'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR public.is_verifikator()
    OR (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

DROP POLICY IF EXISTS "Owners can upload merchant documents" ON storage.objects;
CREATE POLICY "Owners can upload merchant documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchants'
  AND (
    (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
    OR public.is_admin()
    OR public.is_verifikator()
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
);

DROP POLICY IF EXISTS "Owners can update merchant documents" ON storage.objects;
CREATE POLICY "Owners can update merchant documents"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)
WITH CHECK (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

DROP POLICY IF EXISTS "Owners can delete merchant documents" ON storage.objects;
CREATE POLICY "Owners can delete merchant documents"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

-- Merchant gallery remains publicly readable, but writes are restricted to the
-- merchant owner, the related village administrator, or platform admin.
DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects;

DROP POLICY IF EXISTS "Merchant owners can upload gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can upload gallery images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp')
);

DROP POLICY IF EXISTS "Merchant owners can update gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can update gallery images"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
)
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);

DROP POLICY IF EXISTS "Merchant owners can delete gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can delete gallery images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);

-- ===== END SOURCE: 20260822030000_harden_storage_ownership.sql =====

-- ===== BEGIN SOURCE: 20260822040000_harden_stock_decrement.sql =====
-- Prevent overselling: update only when enough stock exists and fail atomically.
CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_quantity integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_product_id IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Invalid stock decrement request';
  END IF;

  UPDATE public.products
  SET stock = stock - p_quantity,
      updated_at = now()
  WHERE id = p_product_id
    AND stock >= p_quantity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient stock or product not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.decrement_stock(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decrement_stock(uuid, integer) TO authenticated;

-- ===== END SOURCE: 20260822040000_harden_stock_decrement.sql =====

-- ===== BEGIN SOURCE: 20260823050000_harden_payment_proof_insert.sql =====
-- Restrict payment-proof uploads to principals who own or fulfill the order.
-- Expected object path: orders/{order_id}/{filename}
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;

DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects;
CREATE POLICY "Buyer merchant admin can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      WHERE o.id::text = (storage.foldername(name))[2]
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid())
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN (
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  )
);

-- ===== END SOURCE: 20260823050000_harden_payment_proof_insert.sql =====

-- ===== BEGIN SOURCE: 20260823070000_atomic_pos_checkout.sql =====
-- Atomic POS checkout with request idempotency.
-- All core sale writes and stock mutations execute in one database transaction.

CREATE TABLE IF NOT EXISTS public.pos_sale_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  cashier_id uuid NOT NULL REFERENCES auth.users(id),
  request_key text NOT NULL,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  response jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, outlet_id, request_key)
);

CREATE INDEX IF NOT EXISTS idx_pos_sale_requests_created_at
  ON public.pos_sale_requests(created_at DESC);

ALTER TABLE public.pos_sale_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pos_sale_requests FROM anon, authenticated;
GRANT ALL ON public.pos_sale_requests TO service_role;

CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_request_key text,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_sale jsonb,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.pos_sale_requests%ROWTYPE;
  v_request_id uuid;
  v_sale_id uuid;
  v_item jsonb;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_before numeric;
  v_after numeric;
  v_sale_number text;
  v_payment_method text;
  v_total numeric;
  v_response jsonb;
  v_recipe record;
  v_raw public.pos_raw_materials%ROWTYPE;
  v_usage numeric;
  v_customer_segment text;
  v_input_price numeric;
  v_effective_price numeric;
  v_computed_subtotal numeric := 0;
  v_price_override_count integer := 0;
  v_sale_earned integer := 0;
  v_sale_redeemed integer := 0;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;

  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  IF p_request_key IS NULL OR length(trim(p_request_key)) < 16 OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid POS request key' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'POS sale requires at least one item' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_sale_requests(tenant_id, outlet_id, cashier_id, request_key)
  VALUES (p_tenant_id, p_outlet_id, p_cashier_id, trim(p_request_key))
  ON CONFLICT (tenant_id, outlet_id, request_key) DO NOTHING
  RETURNING id INTO v_request_id;

  IF v_request_id IS NULL THEN
    SELECT * INTO v_existing
    FROM public.pos_sale_requests
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND request_key = trim(p_request_key);
    IF v_existing.response IS NULL THEN
      RAISE EXCEPTION 'POS request is already being processed' USING ERRCODE = '55P03';
    END IF;
    RETURN v_existing.response || jsonb_build_object('duplicate', true);
  END IF;

  v_sale_number := NULLIF(trim(p_sale->>'sale_number'), '');
  IF v_sale_number IS NULL THEN
    RAISE EXCEPTION 'Sale number is required' USING ERRCODE = '22023';
  END IF;

  v_payment_method := lower(COALESCE(p_sale->>'payment_method', 'cash'));
  -- The UI historically uses qr_pay; persist it as the schema-supported qris value.
  IF v_payment_method = 'qr_pay' THEN v_payment_method := 'qris'; END IF;
  IF v_payment_method NOT IN ('cash', 'qris', 'transfer', 'debit', 'credit', 'split') THEN
    RAISE EXCEPTION 'Unsupported payment method' USING ERRCODE = '22023';
  END IF;

  v_total := COALESCE((p_sale->>'total')::numeric, 0);
  v_customer_segment := lower(COALESCE(NULLIF(p_sale->>'customer_segment', ''), 'retail'));
  IF v_customer_segment NOT IN ('retail', 'wholesale', 'reseller', 'member', 'outlet') THEN
    RAISE EXCEPTION 'Unsupported customer segment' USING ERRCODE = '22023';
  END IF;
  IF v_total < 0 THEN
    RAISE EXCEPTION 'Invalid sale total' USING ERRCODE = '22023';
  END IF;

  -- Resolve price-book prices before inserting the sale. This makes the
  -- server authoritative for both line prices and the final total.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;
    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      IF COALESCE((p_sale->>'offline_sync')::boolean, false) THEN
        RAISE EXCEPTION 'Price conflict for product %: server price is %, queued price is %', v_item->>'product_id', v_effective_price, v_input_price USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('conflict_type', 'PRICE_CHANGED', 'product_id', v_item->>'product_id', 'queued_price', v_input_price, 'server_price', v_effective_price)::text;
      END IF;
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));
  END LOOP;
  v_total := GREATEST(0, v_computed_subtotal - COALESCE((p_sale->>'discount_amount')::numeric, 0) + COALESCE((p_sale->>'tax_amount')::numeric, 0));

  INSERT INTO public.pos_sales(
    tenant_id, outlet_id, sale_number, cashier_id, cashier_name,
    customer_id, customer_name, subtotal, discount_amount, tax_amount, total,
    payment_method, payment_amount, change_amount, status, notes,
    promotion_id, voucher_id, voucher_code, promotion_discount, voucher_discount,
    loyalty_points_earned, loyalty_points_redeemed, loyalty_discount
  ) VALUES (
    p_tenant_id, p_outlet_id, v_sale_number, p_cashier_id,
    NULLIF(p_sale->>'cashier_name', ''), NULLIF(p_sale->>'customer_id', '')::uuid,
    NULLIF(p_sale->>'customer_name', ''), v_computed_subtotal,
    COALESCE((p_sale->>'discount_amount')::numeric, 0), COALESCE((p_sale->>'tax_amount')::numeric, 0), v_total,
    v_payment_method, COALESCE((p_sale->>'payment_amount')::numeric, v_total),
    COALESCE((p_sale->>'change_amount')::numeric, 0), 'completed', NULLIF(p_sale->>'notes', ''),
    NULLIF(p_sale->>'promotion_id', '')::uuid, NULLIF(p_sale->>'voucher_id', '')::uuid,
    NULLIF(p_sale->>'voucher_code', ''), COALESCE((p_sale->>'promotion_discount')::numeric, 0),
    COALESCE((p_sale->>'voucher_discount')::numeric, 0), COALESCE((p_sale->>'loyalty_points_earned')::integer, 0),
    COALESCE((p_sale->>'loyalty_points_redeemed')::integer, 0), COALESCE((p_sale->>'loyalty_discount')::numeric, 0)
  ) RETURNING id INTO v_sale_id;
  SELECT loyalty_points_earned, loyalty_points_redeemed INTO v_sale_earned, v_sale_redeemed
  FROM public.pos_sales WHERE id = v_sale_id;

  v_computed_subtotal := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;

    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));

    INSERT INTO public.pos_sale_items(
      sale_id, product_id, variant_id, product_name, variant_name, sku,
      qty, price, cost_price, discount, tax_amount, subtotal, notes
    ) VALUES (
      v_sale_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      COALESCE(v_item->>'name', 'Produk'), NULLIF(v_item->>'variant_name', ''), NULLIF(v_item->>'sku', ''),
      v_qty, v_effective_price, COALESCE((v_item->>'cost_price')::numeric, 0),
      COALESCE((v_item->>'discount')::numeric, 0), COALESCE((v_item->>'tax_amount')::numeric, 0),
      GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0) + COALESCE((v_item->>'tax_amount')::numeric, 0)), NULLIF(v_item->>'notes', '')
    );

    SELECT * INTO v_stock
    FROM public.pos_stock
    WHERE tenant_id = p_tenant_id
      AND outlet_id = p_outlet_id
      AND product_id = (v_item->>'product_id')::uuid
      AND variant_id IS NOT DISTINCT FROM NULLIF(v_item->>'variant_id', '')::uuid
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stock row not found for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
    END IF;
    v_before := v_stock.quantity;
    v_after := v_before - v_qty;
    IF v_after < 0 THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
    END IF;

    UPDATE public.pos_stock
    SET quantity = v_after, updated_at = now()
    WHERE id = v_stock.id;

    INSERT INTO public.pos_stock_mutations(
      tenant_id, product_id, variant_id, outlet_id, type, quantity,
      quantity_before, quantity_after, reference_id, reference_type, notes, created_by
    ) VALUES (
      p_tenant_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      p_outlet_id, 'sale', -v_qty, v_before, v_after, v_sale_id, 'pos_sale',
      'Atomic POS sale', p_cashier_id
    );
  END LOOP;

  IF v_price_override_count > 0 THEN
    UPDATE public.pos_sales
    SET subtotal = v_computed_subtotal,
        total = GREATEST(0, v_computed_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)),
        notes = concat_ws(' | ', NULLIF(notes, ''), 'Price book: ' || v_customer_segment)
    WHERE id = v_sale_id;
    SELECT total INTO v_total FROM public.pos_sales WHERE id = v_sale_id;
  END IF;

  -- Consume recipe ingredients under row locks in the same transaction.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    FOR v_recipe IN
      SELECT r.raw_material_id, r.qty_needed
      FROM public.pos_recipes r
      WHERE r.tenant_id = p_tenant_id
        AND r.product_id = (v_item->>'product_id')::uuid
    LOOP
      SELECT * INTO v_raw
      FROM public.pos_raw_materials
      WHERE id = v_recipe.raw_material_id
        AND tenant_id = p_tenant_id
        AND (outlet_id = p_outlet_id OR outlet_id IS NULL)
      ORDER BY (outlet_id IS NULL)
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Raw material is unavailable for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
      END IF;
      v_usage := v_recipe.qty_needed * COALESCE((v_item->>'qty')::numeric, 0);
      IF v_raw.current_stock - v_usage < 0 THEN
        RAISE EXCEPTION 'Insufficient raw material stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
      END IF;

      UPDATE public.pos_raw_materials
      SET current_stock = current_stock - v_usage, updated_at = now()
      WHERE id = v_raw.id;
      INSERT INTO public.pos_raw_material_mutations(
        tenant_id, outlet_id, raw_material_id, type, qty,
        qty_before, qty_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, p_outlet_id, v_raw.id, 'usage', -v_usage,
        v_raw.current_stock, v_raw.current_stock - v_usage, v_sale_id, 'pos_sale',
        'Atomic POS sale recipe usage', p_cashier_id
      );
    END LOOP;
  END LOOP;

  -- Keep the customer aggregate in the same transaction when a customer is selected.
  IF NULLIF(p_sale->>'customer_id', '') IS NOT NULL THEN
    UPDATE public.pos_customers
    SET total_purchase = COALESCE(total_purchase, 0) + v_total,
        transaction_count = COALESCE(transaction_count, 0) + 1,
        last_purchase_at = now(),
        loyalty_points = GREATEST(0, COALESCE(loyalty_points, 0)
          - v_sale_redeemed + v_sale_earned),
        updated_at = now()
    WHERE id = (p_sale->>'customer_id')::uuid AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  END IF;

  IF NULLIF(p_sale->>'voucher_id', '') IS NOT NULL THEN
    UPDATE public.pos_vouchers
    SET used_count = used_count + 1, updated_at = now()
    WHERE id = (p_sale->>'voucher_id')::uuid AND tenant_id = p_tenant_id
      AND is_active = true AND (usage_limit IS NULL OR used_count < usage_limit);
    IF NOT FOUND THEN RAISE EXCEPTION 'Voucher is no longer available' USING ERRCODE = '23514'; END IF;
    INSERT INTO public.pos_voucher_usages(voucher_id, sale_id, customer_id, customer_name, discount_given)
    VALUES ((p_sale->>'voucher_id')::uuid, v_sale_id, NULLIF(p_sale->>'customer_id', '')::uuid,
      NULLIF(p_sale->>'customer_name', ''), COALESCE((p_sale->>'voucher_discount')::numeric, 0));
  END IF;

  v_response := jsonb_build_object(
    'sale_id', v_sale_id, 'sale_number', v_sale_number, 'total', v_total,
    'payment_method', v_payment_method, 'duplicate', false
  );
  UPDATE public.pos_sale_requests SET sale_id = v_sale_id, response = v_response WHERE id = v_request_id;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  -- The surrounding transaction rolls back sale, items, stock, and request row together.
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;

-- ===== END SOURCE: 20260823070000_atomic_pos_checkout.sql =====

-- ===== BEGIN SOURCE: 20260823071000_payment_invoice_idempotency.sql =====
-- Reserve one invoice creation attempt per order/provider before calling the
-- external payment provider. This closes the concurrent-create race that a
-- read-before-insert check cannot prevent.
CREATE TABLE IF NOT EXISTS public.payment_invoice_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  request_key text NOT NULL,
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing', 'completed', 'failed')),
  invoice_id text,
  invoice_url text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, order_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_invoice_requests_key
  ON public.payment_invoice_requests(provider, request_key);

ALTER TABLE public.payment_invoice_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_invoice_requests FROM anon, authenticated;
GRANT ALL ON public.payment_invoice_requests TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
  p_provider text,
  p_order_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_invoice_requests%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_order_id IS NULL
     OR p_request_key IS NULL OR length(trim(p_request_key)) < 16
     OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid payment invoice request' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.payment_invoice_requests(provider, order_id, request_key)
  VALUES (lower(trim(p_provider)), p_order_id, trim(p_request_key))
  ON CONFLICT (provider, order_id) DO NOTHING
  RETURNING true INTO v_inserted;

  SELECT * INTO v_row
  FROM public.payment_invoice_requests
  WHERE provider = lower(trim(p_provider)) AND order_id = p_order_id;

  -- A failed attempt can be retried with the same logical request key. An
  -- in-progress or completed attempt remains exclusively owned by its first
  -- caller to prevent concurrent provider calls.
  IF NOT COALESCE(v_inserted, false) AND v_row.status = 'failed' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'processing', request_key = trim(p_request_key), last_error = NULL, updated_at = now()
    WHERE id = v_row.id AND status = 'failed';
    v_inserted := true;
    SELECT * INTO v_row FROM public.payment_invoice_requests WHERE id = v_row.id;
  END IF;

  RETURN jsonb_build_object(
    'can_process', COALESCE(v_inserted, false),
    'status', v_row.status,
    'request_key', v_row.request_key,
    'invoice_id', v_row.invoice_id,
    'invoice_url', v_row.invoice_url,
    'last_error', v_row.last_error,
    'created_at', v_row.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_payment_invoice_request(text, uuid, text) TO service_role;

-- ===== END SOURCE: 20260823071000_payment_invoice_idempotency.sql =====
-- ===== END BUNDLE: 06_20260509000000_to_20260823071000.sql =====

-- ===== BEGIN BUNDLE: 07_20260823080000_to_20260826000000.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260823080000_p1_inventory_shift_atomic.sql .. 20260826000000_atomic_warehouse_transfer.sql


-- ===== BEGIN SOURCE: 20260823080000_p1_inventory_shift_atomic.sql =====
-- P1 inventory ledger and cashier-session hardening.

ALTER TABLE public.pos_sales
  ADD COLUMN IF NOT EXISTS cash_session_id uuid REFERENCES public.pos_cash_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_pos_sales_cash_session
  ON public.pos_sales(cash_session_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_cash_session_per_cashier_outlet
  ON public.pos_cash_sessions(tenant_id, outlet_id, cashier_id)
  WHERE status = 'open' AND cashier_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_pos_sale_cash_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cash_session_id IS NULL THEN
    SELECT id INTO NEW.cash_session_id
    FROM public.pos_cash_sessions
    WHERE tenant_id = NEW.tenant_id
      AND outlet_id = NEW.outlet_id
      AND cashier_id = NEW.cashier_id
      AND status = 'open'
    ORDER BY opened_at DESC
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_pos_sale_cash_session ON public.pos_sales;
CREATE TRIGGER assign_pos_sale_cash_session
  BEFORE INSERT ON public.pos_sales
  FOR EACH ROW EXECUTE FUNCTION public.assign_pos_sale_cash_session();

CREATE OR REPLACE FUNCTION public.open_cash_session(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_cashier_name text,
  p_opening_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_session public.pos_cash_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;
  IF p_opening_balance IS NULL OR p_opening_balance < 0 THEN
    RAISE EXCEPTION 'Invalid opening balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_cash_sessions(
    tenant_id, outlet_id, cashier_id, cashier_name, session_number,
    status, opening_balance, cash_sales_total, non_cash_sales_total,
    cash_in_total, cash_out_total, notes_open
  ) VALUES (
    p_tenant_id, p_outlet_id, p_cashier_id, COALESCE(NULLIF(trim(p_cashier_name), ''), 'Kasir'),
    'KAS-' || to_char(now(), 'YYMMDD-HH24MISS') || '-' || substr(p_cashier_id::text, 1, 6),
    'open', p_opening_balance, 0, 0, 0, 0, NULLIF(trim(p_notes), '')
  ) RETURNING * INTO v_session;

  RETURN jsonb_build_object('session_id', v_session.id, 'session_number', v_session.session_number, 'status', v_session.status);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Cashier already has an open session for this outlet' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.record_cash_mutation(
  p_session_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_category text,
  p_amount numeric,
  p_description text,
  p_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_mutation_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_type NOT IN ('in', 'out') OR NULLIF(trim(p_description), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid cash mutation' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session FROM public.pos_cash_sessions
  WHERE id = p_session_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.pos_cash_mutations(
    tenant_id, outlet_id, cash_session_id, type, category, amount, description, reference, created_by
  ) VALUES (
    p_tenant_id, p_outlet_id, p_session_id, p_type, COALESCE(NULLIF(trim(p_category), ''), 'other'),
    p_amount, trim(p_description), NULLIF(trim(p_reference), ''), auth.uid()
  ) RETURNING id INTO v_mutation_id;

  IF p_type = 'in' THEN
    UPDATE public.pos_cash_sessions SET cash_in_total = COALESCE(cash_in_total, 0) + p_amount WHERE id = p_session_id;
  ELSE
    UPDATE public.pos_cash_sessions SET cash_out_total = COALESCE(cash_out_total, 0) + p_amount WHERE id = p_session_id;
  END IF;
  RETURN jsonb_build_object('mutation_id', v_mutation_id, 'session_id', p_session_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.close_cash_session(
  p_session_id uuid,
  p_closing_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_cash_sales numeric := 0;
  v_non_cash_sales numeric := 0;
  v_cash_in numeric := 0;
  v_cash_out numeric := 0;
  v_expected numeric;
  v_difference numeric;
BEGIN
  IF auth.uid() IS NULL OR p_closing_balance IS NULL OR p_closing_balance < 0 THEN
    RAISE EXCEPTION 'Invalid closing balance' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_session FROM public.pos_cash_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_session.tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN payment_method = 'cash' THEN total ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN payment_method <> 'cash' THEN total ELSE 0 END), 0)
  INTO v_cash_sales, v_non_cash_sales
  FROM public.pos_sales
  WHERE cash_session_id = p_session_id AND status = 'completed';

  SELECT COALESCE(SUM(CASE WHEN type = 'in' THEN amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN type = 'out' THEN amount ELSE 0 END), 0)
  INTO v_cash_in, v_cash_out
  FROM public.pos_cash_mutations
  WHERE cash_session_id = p_session_id;

  v_expected := v_session.opening_balance + v_cash_sales + v_cash_in - v_cash_out;
  v_difference := p_closing_balance - v_expected;

  UPDATE public.pos_cash_sessions
  SET status = 'closed', closing_balance = p_closing_balance, expected_balance = v_expected,
      difference = v_difference, cash_sales_total = v_cash_sales,
      non_cash_sales_total = v_non_cash_sales, cash_in_total = v_cash_in,
      cash_out_total = v_cash_out, notes_close = NULLIF(trim(p_notes), ''), closed_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'session_id', p_session_id, 'expected_balance', v_expected,
    'closing_balance', p_closing_balance, 'difference', v_difference,
    'cash_sales_total', v_cash_sales, 'non_cash_sales_total', v_non_cash_sales,
    'cash_in_total', v_cash_in, 'cash_out_total', v_cash_out
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_pos_stock(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
  v_delta numeric;
BEGIN
  IF p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN
    RAISE EXCEPTION 'Invalid stock adjustment' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_stock FROM public.pos_stock
  WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;

  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE
    CASE WHEN p_type IN ('purchase','return_sale','transfer_in','initial')
      THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < 0 THEN RAISE EXCEPTION 'Insufficient stock' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;

  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(
    tenant_id, product_id, variant_id, outlet_id, type, quantity,
    quantity_before, quantity_after, notes, created_by
  ) VALUES (
    p_tenant_id, v_stock.product_id, v_stock.variant_id, p_outlet_id, p_type,
    v_delta, v_stock.quantity, v_after, NULLIF(trim(p_notes), ''), auth.uid()
  );
  RETURN jsonb_build_object('stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END;
$$;

REVOKE ALL ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.close_cash_session(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_cash_session(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) TO authenticated;

-- ===== END SOURCE: 20260823080000_p1_inventory_shift_atomic.sql =====

-- ===== BEGIN SOURCE: 20260823090000_harden_payment_settings_access.sql =====
-- Payment security hardening:
-- do not expose provider credentials through the generic app_settings read path.

DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings;

DROP POLICY IF EXISTS "Public can view non-sensitive settings" ON public.app_settings;
CREATE POLICY "Public can view non-sensitive settings"
  ON public.app_settings
  FOR SELECT
  USING (
    key !~* '(secret|token|credential|api[_-]?key|private|password)'
    AND key NOT IN (
      'payment_xendit',
      'payment_midtrans',
      'whatsapp_settings',
      'push_notification_settings'
    )
  );

CREATE OR REPLACE FUNCTION public.is_payment_provider_enabled(p_provider text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE lower(trim(p_provider))
    WHEN 'xendit' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_xendit'
    ), false)
    WHEN 'midtrans' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_midtrans'
    ), false)
    ELSE false
  END;
$$;

REVOKE ALL ON FUNCTION public.is_payment_provider_enabled(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_payment_provider_enabled(text) TO anon, authenticated;

-- ===== END SOURCE: 20260823090000_harden_payment_settings_access.sql =====

-- ===== BEGIN SOURCE: 20260823091000_harden_pos_sale_amounts.sql =====
-- Server-side price and line arithmetic guard for all POS sale writes.
-- The checkout RPC remains the atomic boundary; this trigger protects direct
-- inserts and prevents a compromised client from inflating line prices.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_item_amounts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale record;
  v_product_price numeric;
  v_variant_price numeric;
BEGIN
  SELECT tenant_id, outlet_id
  INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale does not exist' USING ERRCODE = '23503';
  END IF;

  IF NEW.qty <= 0 OR NEW.price < 0 OR NEW.discount < 0 OR NEW.tax_amount < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale item amount' USING ERRCODE = '22023';
  END IF;

  IF NEW.discount > NEW.price * NEW.qty THEN
    RAISE EXCEPTION 'Line discount exceeds line amount' USING ERRCODE = '22023';
  END IF;

  IF abs(NEW.subtotal - (NEW.price * NEW.qty - NEW.discount)) > 0.01 THEN
    RAISE EXCEPTION 'Line subtotal mismatch' USING ERRCODE = '22023';
  END IF;

  SELECT price
  INTO v_variant_price
  FROM public.pos_product_variants
  WHERE id = NEW.variant_id
    AND product_id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NEW.variant_id IS NOT NULL AND NOT FOUND THEN
    RAISE EXCEPTION 'Product variant does not belong to tenant or product' USING ERRCODE = '42501';
  END IF;

  SELECT price
  INTO v_product_price
  FROM public.pos_products
  WHERE id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product does not belong to tenant or is inactive' USING ERRCODE = '42501';
  END IF;

  IF NEW.price > COALESCE(v_variant_price, v_product_price) THEN
    RAISE EXCEPTION 'Sale price exceeds catalog price' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pos_sale_item_amounts ON public.pos_sale_items;
CREATE TRIGGER validate_pos_sale_item_amounts
BEFORE INSERT OR UPDATE ON public.pos_sale_items
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_item_amounts();

REVOKE ALL ON FUNCTION public.validate_pos_sale_item_amounts() FROM PUBLIC;

-- ===== END SOURCE: 20260823091000_harden_pos_sale_amounts.sql =====

-- ===== BEGIN SOURCE: 20260823092000_harden_pos_sale_totals.sql =====
-- Validate POS header arithmetic after all sale items have been inserted.
-- A deferred constraint trigger lets the atomic checkout RPC insert the header
-- first and items afterward while still enforcing the invariant at COMMIT.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item_tax numeric;
  v_item_subtotal numeric;
BEGIN
  IF NEW.subtotal < 0 OR NEW.tax_amount < 0 OR NEW.total < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale totals' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(tax_amount), 0), COALESCE(sum(subtotal), 0)
  INTO v_item_tax, v_item_subtotal
  FROM public.pos_sale_items
  WHERE sale_id = NEW.id;

  IF abs(NEW.tax_amount - v_item_tax) > 0.01 THEN
    RAISE EXCEPTION 'Sale tax does not match item tax' USING ERRCODE = '22023';
  END IF;

  -- Header discounts may include promotions, vouchers, or loyalty discounts,
  -- so the valid total may be lower than the item subtotal but never higher
  -- than the subtotal plus tax.
  IF NEW.total > NEW.subtotal + NEW.tax_amount + 0.01 THEN
    RAISE EXCEPTION 'Sale total exceeds subtotal and tax' USING ERRCODE = '22023';
  END IF;

  IF v_item_subtotal > NEW.subtotal + 0.01 THEN
    RAISE EXCEPTION 'Item subtotal exceeds sale subtotal' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_pos_sale_totals ON public.pos_sales;
CREATE CONSTRAINT TRIGGER validate_pos_sale_totals
AFTER INSERT OR UPDATE OF subtotal, tax_amount, total, discount_amount,
  promotion_discount, voucher_discount, loyalty_discount
ON public.pos_sales
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_totals();

REVOKE ALL ON FUNCTION public.validate_pos_sale_totals() FROM PUBLIC;

-- ===== END SOURCE: 20260823092000_harden_pos_sale_totals.sql =====

-- ===== BEGIN SOURCE: 20260823093000_harden_manual_payment_verification.sql =====
-- Manual payment verification must be an authorized, auditable business action.
-- It is intentionally separate from provider webhooks: merchant verification
-- requires ownership and an uploaded proof, while provider callbacks require
-- the provider secret and matching invoice.

CREATE OR REPLACE FUNCTION public.merchant_verify_order_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT id, merchant_id, status, payment_status, payment_proof_url
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_admin()
     AND NOT EXISTS (
       SELECT 1 FROM public.merchants m
       WHERE m.id = v_order.merchant_id AND m.user_id = auth.uid()
     ) THEN
    RAISE EXCEPTION 'Order verification access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'already_paid', true, 'order_id', v_order.id);
  END IF;

  IF v_order.payment_proof_url IS NULL OR length(trim(v_order.payment_proof_url)) = 0 THEN
    RAISE EXCEPTION 'Payment proof is required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET payment_status = 'PAID',
      payment_paid_at = v_now,
      status = CASE WHEN status IN ('PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'NEW') THEN 'PROCESSED' ELSE status END,
      confirmed_at = COALESCE(confirmed_at, v_now),
      updated_at = v_now
  WHERE id = v_order.id;

  RETURN jsonb_build_object('success', true, 'already_paid', false, 'order_id', v_order.id, 'payment_status', 'PAID');
END;
$$;

REVOKE ALL ON FUNCTION public.merchant_verify_order_payment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_verify_order_payment(uuid) TO authenticated;

-- ===== END SOURCE: 20260823093000_harden_manual_payment_verification.sql =====

-- ===== BEGIN SOURCE: 20260823094000_atomic_payment_webhook_processing.sql =====
-- Process a provider callback and its idempotency ledger in one transaction.
-- The order row is locked before the event is recorded, preventing concurrent
-- callbacks from racing through terminal-state checks.
CREATE OR REPLACE FUNCTION public.process_payment_webhook_event(
  p_provider text,
  p_event_key text,
  p_invoice_id text,
  p_order_id uuid,
  p_status text,
  p_paid_at timestamptz DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL,
  p_paid_amount numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_inserted boolean := false;
  v_current_status text;
  v_order_total numeric;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_event_key), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_order_id IS NULL
     OR p_status NOT IN ('PAID', 'EXPIRED', 'PENDING') THEN
    RAISE EXCEPTION 'Invalid payment webhook event' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.payment_invoice_id IS NULL OR v_order.payment_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'Invoice mismatch' USING ERRCODE = '23P01';
  END IF;

  v_order_total := v_order.total;
  IF v_order_total IS NULL OR v_order_total <= 0 OR v_order_total <> trunc(v_order_total) THEN
    RAISE EXCEPTION 'Invalid order total' USING ERRCODE = '22023';
  END IF;

  IF p_status = 'PAID' AND (p_paid_amount IS NULL OR p_paid_amount <> v_order_total) THEN
    RAISE EXCEPTION 'Payment amount mismatch' USING ERRCODE = '22003';
  END IF;

  INSERT INTO public.payment_webhook_events(provider, event_key, invoice_id, order_id, status)
  VALUES (lower(trim(p_provider)), trim(p_event_key), p_invoice_id, p_order_id, p_status)
  ON CONFLICT (provider, event_key) DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT COALESCE(v_inserted, false) THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true);
  END IF;

  v_current_status := COALESCE(v_order.payment_status, 'UNPAID');
  IF v_current_status = 'PAID'
     OR (v_current_status = 'EXPIRED' AND p_status = 'PENDING') THEN
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;

  UPDATE public.orders
  SET payment_status = p_status,
      payment_paid_at = CASE WHEN p_status = 'PAID' THEN COALESCE(p_paid_at, now()) ELSE NULL END,
      payment_method = NULLIF(trim(p_payment_method), ''),
      payment_channel = NULLIF(trim(p_payment_channel), ''),
      status = CASE
        WHEN p_status = 'PAID' THEN 'CONFIRMED'
        WHEN p_status = 'EXPIRED' AND v_current_status <> 'PAID' THEN 'CANCELLED'
        ELSE status
      END
  WHERE id = p_order_id;

  RETURN jsonb_build_object('success', true, 'processed', true, 'status', p_status);
END;
$$;

REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  TO service_role;

COMMENT ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  IS 'Atomically validates, deduplicates, and applies payment provider callbacks.';

-- Prevent direct SQL updates from downgrading a paid order payment status.
CREATE OR REPLACE FUNCTION public.prevent_paid_payment_downgrade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.payment_status = 'PAID' AND NEW.payment_status IS DISTINCT FROM 'PAID' THEN
    RAISE EXCEPTION 'Paid order payment status is terminal' USING ERRCODE = '27000';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_paid_payment_downgrade ON public.orders;
CREATE TRIGGER trg_prevent_paid_payment_downgrade
  BEFORE UPDATE OF payment_status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.prevent_paid_payment_downgrade();

REVOKE ALL ON FUNCTION public.prevent_paid_payment_downgrade() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prevent_paid_payment_downgrade() TO service_role;
-- Rollback note: drop the trigger/function only after restoring the previous
-- webhook implementation; the function is intentionally retained for staged rollout.


-- ===== END SOURCE: 20260823094000_atomic_payment_webhook_processing.sql =====

-- ===== BEGIN SOURCE: 20260825090000_production_refund_return_controls.sql =====
-- Production return/refund controls.
ALTER TABLE public.pos_sale_returns
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'rejected', 'processed')),
  ADD COLUMN IF NOT EXISTS refund_fee numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

CREATE INDEX IF NOT EXISTS idx_pos_sale_returns_status
  ON public.pos_sale_returns(tenant_id, outlet_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION public.request_pos_sale_return(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_sale_id uuid,
  p_reason text,
  p_refund_method text,
  p_restock boolean,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
  v_return_id uuid;
  v_return_number text;
  v_item jsonb;
  v_sale_item public.pos_sale_items%ROWTYPE;
  v_qty numeric;
  v_refunded numeric;
  v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_sale_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR p_refund_method NOT IN ('cash', 'store_credit') THEN
    RAISE EXCEPTION 'Invalid return request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sale FROM public.pos_sales
  WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN
    RAISE EXCEPTION 'Sale is not eligible for return' USING ERRCODE = '55000';
  END IF;

  v_return_number := 'RTN-' || to_char(clock_timestamp(), 'YYMMDDHH24MISSMS');
  INSERT INTO public.pos_sale_returns(
    tenant_id, sale_id, outlet_id, return_number, reason, refund_method,
    total_refund, restock, created_by, status
  ) VALUES (
    p_tenant_id, p_sale_id, p_outlet_id, v_return_number, NULLIF(trim(p_reason), ''),
    p_refund_method, 0, COALESCE(p_restock, true), auth.uid(), 'pending'
  ) RETURNING id INTO v_return_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF NULLIF(v_item->>'sale_item_id', '') IS NULL
       OR (v_item->>'qty')::numeric <= 0 THEN
      RAISE EXCEPTION 'Invalid return item' USING ERRCODE = '22023';
    END IF;
    v_qty := (v_item->>'qty')::numeric;
    SELECT * INTO v_sale_item FROM public.pos_sale_items
    WHERE id = (v_item->>'sale_item_id')::uuid AND sale_id = p_sale_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(SUM(qty), 0) INTO v_refunded
    FROM public.pos_sale_return_items ri
    JOIN public.pos_sale_returns r ON r.id = ri.return_id
    WHERE ri.sale_item_id = v_sale_item.id AND r.status IN ('pending', 'approved', 'processed');
    IF v_refunded + v_qty > v_sale_item.qty THEN
      RAISE EXCEPTION 'Return quantity exceeds sold quantity' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.pos_sale_return_items(return_id, sale_item_id, product_id, product_name, qty, price, subtotal)
    VALUES (v_return_id, v_sale_item.id, v_sale_item.product_id, v_sale_item.product_name, v_qty, v_sale_item.price, v_qty * v_sale_item.price);
    v_total := v_total + v_qty * v_sale_item.price;
  END LOOP;

  UPDATE public.pos_sale_returns SET total_refund = v_total WHERE id = v_return_id;
  RETURN jsonb_build_object('return_id', v_return_id, 'return_number', v_return_number, 'status', 'pending', 'total_refund', v_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_pos_sale_return(
  p_return_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_return public.pos_sale_returns%ROWTYPE;
  v_item record;
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_return_id IS NULL THEN
    RAISE EXCEPTION 'Invalid return approval' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_return FROM public.pos_sale_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_return.tenant_id, v_return.outlet_id) THEN
    RAISE EXCEPTION 'Return access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_return.tenant_id AND t.user_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'Return approval requires supervisor access' USING ERRCODE = '42501';
  END IF;
  IF v_return.status <> 'pending' THEN
    RAISE EXCEPTION 'Return is already processed' USING ERRCODE = '55000';
  END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_sale_returns
    SET status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = NULLIF(trim(p_rejection_reason), '')
    WHERE id = p_return_id;
    RETURN jsonb_build_object('return_id', p_return_id, 'status', 'rejected');
  END IF;

  IF v_return.restock THEN
    FOR v_item IN SELECT * FROM public.pos_sale_return_items WHERE return_id = p_return_id LOOP
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = v_return.tenant_id AND outlet_id = v_return.outlet_id
        AND product_id = v_item.product_id
        AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_item.qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
        INSERT INTO public.pos_stock_mutations(
          tenant_id, product_id, variant_id, outlet_id, type, quantity,
          quantity_before, quantity_after, reference_id, reference_type, notes, created_by
        ) VALUES (
          v_return.tenant_id, v_item.product_id, v_stock.variant_id, v_return.outlet_id, 'return_sale',
          v_item.qty, v_stock.quantity, v_after, p_return_id, 'pos_sale_return', 'Approved sale return', auth.uid()
        );
      END IF;
    END LOOP;
  END IF;

  UPDATE public.pos_sale_returns
  SET status = 'processed', approved_by = auth.uid(), approved_at = now(), processed_at = now()
  WHERE id = p_return_id;
  RETURN jsonb_build_object('return_id', p_return_id, 'status', 'processed', 'total_refund', v_return.total_refund);
END;
$$;

REVOKE ALL ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825090000_production_refund_return_controls.sql =====

-- ===== BEGIN SOURCE: 20260825093000_payment_reconciliation_ledger.sql =====
-- Payment reconciliation ledger. Provider imports/callback processors write here;
-- business users only read the resulting reconciliation state.
CREATE TABLE IF NOT EXISTS public.payment_reconciliation_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  provider_event_id text,
  invoice_id text NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL,
  expected_amount numeric(15,2) NOT NULL DEFAULT 0,
  provider_amount numeric(15,2),
  provider_fee numeric(15,2) NOT NULL DEFAULT 0,
  net_amount numeric(15,2),
  currency text NOT NULL DEFAULT 'IDR',
  provider_status text NOT NULL,
  reconciliation_status text NOT NULL DEFAULT 'unmatched'
    CHECK (reconciliation_status IN ('unmatched', 'matched', 'mismatch', 'refunded', 'settled')),
  settlement_reference text,
  settlement_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(provider, invoice_id),
  UNIQUE(provider, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_order
  ON public.payment_reconciliation_records(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_reconciliation_status
  ON public.payment_reconciliation_records(reconciliation_status, created_at DESC);

ALTER TABLE public.payment_reconciliation_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_reconciliation_records FROM anon, authenticated;
GRANT SELECT ON public.payment_reconciliation_records TO authenticated;
GRANT ALL ON public.payment_reconciliation_records TO service_role;

DROP POLICY IF EXISTS "Admins can view payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Admins can view payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Merchants can view own payment reconciliation" ON public.payment_reconciliation_records;
CREATE POLICY "Merchants can view own payment reconciliation"
  ON public.payment_reconciliation_records FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.record_payment_reconciliation(
  p_provider text,
  p_provider_event_id text,
  p_invoice_id text,
  p_order_id uuid,
  p_expected_amount numeric,
  p_provider_amount numeric,
  p_provider_fee numeric,
  p_provider_status text,
  p_settlement_reference text DEFAULT NULL,
  p_settlement_at timestamptz DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_status text;
  v_id uuid;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_expected_amount IS NULL OR p_expected_amount < 0
     OR p_provider_amount IS NOT NULL AND p_provider_amount < 0
     OR p_provider_fee IS NULL OR p_provider_fee < 0
     OR NULLIF(trim(p_provider_status), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid reconciliation record' USING ERRCODE = '22023';
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  v_status := CASE
    WHEN lower(p_provider_status) IN ('refunded', 'refund') THEN 'refunded'
    WHEN p_provider_amount IS NULL THEN 'unmatched'
    WHEN p_provider_amount <> p_expected_amount THEN 'mismatch'
    WHEN p_settlement_reference IS NOT NULL THEN 'settled'
    ELSE 'matched'
  END;

  INSERT INTO public.payment_reconciliation_records(
    provider, provider_event_id, invoice_id, order_id, merchant_id,
    expected_amount, provider_amount, provider_fee, net_amount, provider_status,
    reconciliation_status, settlement_reference, settlement_at, metadata, updated_at
  ) VALUES (
    lower(trim(p_provider)), NULLIF(trim(p_provider_event_id), ''), p_invoice_id,
    p_order_id, v_order.merchant_id, p_expected_amount, p_provider_amount,
    p_provider_fee, CASE WHEN p_provider_amount IS NULL THEN NULL ELSE p_provider_amount - p_provider_fee END,
    trim(p_provider_status), v_status, NULLIF(trim(p_settlement_reference), ''), p_settlement_at,
    COALESCE(p_metadata, '{}'::jsonb), now()
  )
  ON CONFLICT (provider, invoice_id) DO UPDATE SET
    provider_event_id = COALESCE(EXCLUDED.provider_event_id, payment_reconciliation_records.provider_event_id),
    provider_amount = EXCLUDED.provider_amount,
    provider_fee = EXCLUDED.provider_fee,
    net_amount = EXCLUDED.net_amount,
    provider_status = EXCLUDED.provider_status,
    reconciliation_status = EXCLUDED.reconciliation_status,
    settlement_reference = COALESCE(EXCLUDED.settlement_reference, payment_reconciliation_records.settlement_reference),
    settlement_at = COALESCE(EXCLUDED.settlement_at, payment_reconciliation_records.settlement_at),
    metadata = payment_reconciliation_records.metadata || EXCLUDED.metadata,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'status', v_status, 'provider', lower(trim(p_provider)), 'invoice_id', p_invoice_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment_reconciliation(text, text, text, uuid, numeric, numeric, numeric, text, text, timestamptz, jsonb)
  TO service_role;

-- ===== END SOURCE: 20260825093000_payment_reconciliation_ledger.sql =====

-- ===== BEGIN SOURCE: 20260825100000_cashier_approval_and_stock_opname.sql =====
-- Cashier approval controls ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_void_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid NOT NULL REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_void_pending_sale ON public.pos_void_requests(sale_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.pos_price_override_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  sale_item_id uuid REFERENCES public.pos_sale_items(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  original_price numeric(15,2) NOT NULL,
  requested_price numeric(15,2) NOT NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK (original_price >= 0 AND requested_price >= 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_price_override_pending ON public.pos_price_override_requests(tenant_id, outlet_id, status, created_at DESC);

ALTER TABLE public.pos_void_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_price_override_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view own void requests" ON public.pos_void_requests;
CREATE POLICY "POS users view own void requests" ON public.pos_void_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create void requests" ON public.pos_void_requests;
CREATE POLICY "POS users create void requests" ON public.pos_void_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view price overrides" ON public.pos_price_override_requests;
CREATE POLICY "POS users view price overrides" ON public.pos_price_override_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create price overrides" ON public.pos_price_override_requests;
CREATE POLICY "POS users create price overrides" ON public.pos_price_override_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.request_pos_void(
  p_tenant_id uuid, p_outlet_id uuid, p_sale_id uuid, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sale public.pos_sales%ROWTYPE; v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_reason), '') IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid void request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  INSERT INTO public.pos_void_requests(tenant_id, outlet_id, sale_id, requested_by, reason)
  VALUES (p_tenant_id, p_outlet_id, p_sale_id, auth.uid(), trim(p_reason)) RETURNING id INTO v_id;
  RETURN jsonb_build_object('request_id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_void(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req public.pos_void_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_after numeric;
BEGIN
  SELECT * INTO v_req FROM public.pos_void_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_req.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Void approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Void request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_void_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_req.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  UPDATE public.pos_sales SET status = 'void', voided_by = auth.uid(), voided_at = now(), void_reason = v_req.reason WHERE id = v_sale.id;
  FOR v_item IN SELECT * FROM public.pos_sale_items WHERE sale_id = v_sale.id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE tenant_id = v_sale.tenant_id AND outlet_id = v_sale.outlet_id AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_stock.quantity + v_item.qty;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_sale.tenant_id, v_item.product_id, v_item.variant_id, v_sale.outlet_id, 'return_sale', v_item.qty, v_stock.quantity, v_after, v_sale.id, 'pos_sale_void', 'Approved POS void', auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_void_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id);
END; $$;

-- Stock opname -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_stock_opnames (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  opname_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','counting','approved','cancelled')),
  reason text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_opname_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opname_id uuid NOT NULL REFERENCES public.pos_stock_opnames(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  system_quantity numeric(15,3) NOT NULL,
  counted_quantity numeric(15,3) NOT NULL CHECK (counted_quantity >= 0),
  difference numeric(15,3) NOT NULL,
  notes text
);
ALTER TABLE public.pos_stock_opnames ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_opname_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view stock opnames" ON public.pos_stock_opnames;
CREATE POLICY "POS users view stock opnames" ON public.pos_stock_opnames FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create stock opnames" ON public.pos_stock_opnames;
CREATE POLICY "POS users create stock opnames" ON public.pos_stock_opnames FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view stock opname items" ON public.pos_stock_opname_items;
CREATE POLICY "POS users view stock opname items" ON public.pos_stock_opname_items FOR SELECT TO authenticated USING (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "POS users create stock opname items" ON public.pos_stock_opname_items;
CREATE POLICY "POS users create stock opname items" ON public.pos_stock_opname_items FOR INSERT TO authenticated WITH CHECK (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE created_by = auth.uid() AND status IN ('draft','counting')));

CREATE OR REPLACE FUNCTION public.approve_pos_stock_opname(p_opname_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_opname public.pos_stock_opnames%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_delta numeric;
BEGIN
  SELECT * INTO v_opname FROM public.pos_stock_opnames WHERE id = p_opname_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_opname.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Stock opname approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_opname.status NOT IN ('draft','counting') THEN RAISE EXCEPTION 'Stock opname already decided' USING ERRCODE = '55000'; END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_opname_items WHERE opname_id = p_opname_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id AND tenant_id = v_opname.tenant_id AND outlet_id = v_opname.outlet_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
    v_delta := v_item.counted_quantity - v_stock.quantity;
    IF v_delta <> 0 THEN
      UPDATE public.pos_stock SET quantity = v_item.counted_quantity, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_opname.tenant_id, v_stock.product_id, v_stock.variant_id, v_opname.outlet_id, 'opname', v_delta, v_stock.quantity, v_item.counted_quantity, p_opname_id, 'stock_opname', COALESCE(v_item.notes, v_opname.reason), auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_stock_opnames SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_opname_id;
  RETURN jsonb_build_object('opname_id', p_opname_id, 'status', 'approved');
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_void(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_pos_stock_opname(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_void(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_pos_stock_opname(uuid) TO authenticated;

-- ===== END SOURCE: 20260825100000_cashier_approval_and_stock_opname.sql =====

-- ===== BEGIN SOURCE: 20260825110000_atomic_purchase_receiving.sql =====
CREATE OR REPLACE FUNCTION public.receive_pos_purchase_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_input jsonb;
  v_item public.pos_purchase_order_items%ROWTYPE;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_after numeric;
  v_any boolean := false;
  v_all_received boolean := true;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_purchase_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Invalid purchase receiving request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_po.status IN ('cancelled', 'received') THEN
    RAISE EXCEPTION 'Purchase order is not receivable' USING ERRCODE = '55000';
  END IF;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'item_id', '') IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid received item' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_item FROM public.pos_purchase_order_items
    WHERE id = (v_input->>'item_id')::uuid AND purchase_order_id = p_purchase_order_id
    FOR UPDATE;
    IF NOT FOUND OR v_item.qty_received + v_qty > v_item.qty_ordered THEN
      RAISE EXCEPTION 'Received quantity exceeds ordered quantity' USING ERRCODE = '23514';
    END IF;
    v_any := true;
    UPDATE public.pos_purchase_order_items SET qty_received = qty_received + v_qty WHERE id = v_item.id;
    IF v_item.product_id IS NOT NULL THEN
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id
        AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      ELSE
        v_after := v_qty;
        INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock)
        VALUES (p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, v_after, 0)
        RETURNING * INTO v_stock;
      END IF;
      INSERT INTO public.pos_stock_mutations(
        tenant_id, product_id, variant_id, outlet_id, type, quantity,
        quantity_before, quantity_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, 'purchase', v_qty,
        v_after - v_qty, v_after, p_purchase_order_id, 'purchase_order',
        'Atomic purchase receiving ' || v_po.po_number, auth.uid()
      );
    END IF;
  END LOOP;
  IF NOT v_any THEN RAISE EXCEPTION 'No items received' USING ERRCODE = '22023'; END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM public.pos_purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id AND qty_received < qty_ordered
  ) INTO v_all_received;
  UPDATE public.pos_purchase_orders
  SET status = CASE WHEN v_all_received THEN 'received' ELSE 'partial' END,
      received_date = CURRENT_DATE, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_purchase_order_id;
  RETURN jsonb_build_object('purchase_order_id', p_purchase_order_id, 'status', CASE WHEN v_all_received THEN 'received' ELSE 'partial' END);
END;
$$;

REVOKE ALL ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) TO authenticated;

-- ===== END SOURCE: 20260825110000_atomic_purchase_receiving.sql =====

-- ===== BEGIN SOURCE: 20260825120000_payment_pos_anomaly_detection.sql =====
CREATE TABLE IF NOT EXISTS public.pos_payment_anomalies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  anomaly_type text NOT NULL CHECK (anomaly_type IN (
    'payment_mismatch', 'duplicate_refund', 'repeated_void', 'offline_retry_spike', 'manual_adjustment_spike'
  )),
  severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low','medium','high','critical')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','false_positive')),
  subject_type text NOT NULL,
  subject_id uuid,
  observed_count integer NOT NULL DEFAULT 1,
  threshold integer NOT NULL DEFAULT 1,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  detected_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_by uuid REFERENCES auth.users(id),
  acknowledged_at timestamptz,
  resolved_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_anomaly_open_subject
  ON public.pos_payment_anomalies(anomaly_type, subject_type, subject_id)
  WHERE status IN ('open','acknowledged');
CREATE INDEX IF NOT EXISTS idx_pos_anomaly_tenant_status
  ON public.pos_payment_anomalies(tenant_id, status, detected_at DESC);

ALTER TABLE public.pos_payment_anomalies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pos_payment_anomalies FROM anon, authenticated;
GRANT SELECT, UPDATE ON public.pos_payment_anomalies TO authenticated;
GRANT ALL ON public.pos_payment_anomalies TO service_role;
DROP POLICY IF EXISTS "Admins view and manage anomalies" ON public.pos_payment_anomalies;
CREATE POLICY "Admins view and manage anomalies" ON public.pos_payment_anomalies FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Tenant owners view anomalies" ON public.pos_payment_anomalies;
CREATE POLICY "Tenant owners view anomalies" ON public.pos_payment_anomalies FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.scan_pos_payment_anomalies(
  p_tenant_id uuid DEFAULT NULL,
  p_since timestamptz DEFAULT now() - interval '24 hours'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
  v_row record;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Anomaly scan requires admin access' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN
    SELECT NULL::uuid AS tenant_id, r.order_id AS subject_id, r.id AS record_id, r.expected_amount, r.provider_amount
    FROM public.payment_reconciliation_records r
    WHERE r.created_at >= COALESCE(p_since, now() - interval '24 hours')
      AND r.reconciliation_status = 'mismatch'
  LOOP
    INSERT INTO public.pos_payment_anomalies(
      tenant_id, anomaly_type, severity, subject_type, subject_id, threshold, details
    ) VALUES (
      v_row.tenant_id, 'payment_mismatch', 'high', 'payment_reconciliation', v_row.record_id, 1,
      jsonb_build_object('order_id', v_row.subject_id, 'expected_amount', v_row.expected_amount, 'provider_amount', v_row.provider_amount)
    ) ON CONFLICT (anomaly_type, subject_type, subject_id) WHERE status IN ('open','acknowledged') DO UPDATE
      SET observed_count = pos_payment_anomalies.observed_count + 1, details = EXCLUDED.details;
    v_count := v_count + 1;
  END LOOP;

  FOR v_row IN
    SELECT r.tenant_id, r.sale_id AS subject_id, count(*)::integer AS observed_count
    FROM public.pos_sale_returns r
    WHERE r.created_at >= COALESCE(p_since, now() - interval '24 hours')
      AND r.status IN ('pending','approved','processed')
      AND (p_tenant_id IS NULL OR r.tenant_id = p_tenant_id)
    GROUP BY r.tenant_id, r.sale_id HAVING count(*) > 1
  LOOP
    INSERT INTO public.pos_payment_anomalies(
      tenant_id, anomaly_type, severity, subject_type, subject_id, observed_count, threshold, details
    ) VALUES (
      v_row.tenant_id, 'duplicate_refund', 'high', 'pos_sale', v_row.subject_id, v_row.observed_count, 1,
      jsonb_build_object('return_count', v_row.observed_count)
    ) ON CONFLICT (anomaly_type, subject_type, subject_id) WHERE status IN ('open','acknowledged') DO UPDATE
      SET observed_count = EXCLUDED.observed_count, details = EXCLUDED.details;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scan_pos_payment_anomalies(uuid, timestamptz) TO authenticated;

-- ===== END SOURCE: 20260825120000_payment_pos_anomaly_detection.sql =====

-- ===== BEGIN SOURCE: 20260825130000_supplier_payables_and_terms.sql =====
ALTER TABLE public.pos_purchase_orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid','partial','paid','overdue')),
  ADD COLUMN IF NOT EXISTS payment_terms_days integer NOT NULL DEFAULT 0 CHECK (payment_terms_days >= 0),
  ADD COLUMN IF NOT EXISTS due_date date,
  ADD COLUMN IF NOT EXISTS amount_due numeric(15,2) NOT NULL DEFAULT 0;

UPDATE public.pos_purchase_orders
SET amount_due = GREATEST(0, total - amount_paid),
    due_date = COALESCE(due_date, order_date + payment_terms_days),
    payment_status = CASE WHEN amount_paid >= total AND total > 0 THEN 'paid' WHEN amount_paid > 0 THEN 'partial' ELSE 'unpaid' END
WHERE amount_due = 0 OR due_date IS NULL;

CREATE TABLE IF NOT EXISTS public.pos_supplier_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  purchase_order_id uuid NOT NULL REFERENCES public.pos_purchase_orders(id) ON DELETE RESTRICT,
  supplier_id uuid REFERENCES public.pos_suppliers(id) ON DELETE SET NULL,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash','transfer','debit','credit','other')),
  reference text,
  notes text,
  paid_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_po ON public.pos_supplier_payments(purchase_order_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_supplier ON public.pos_supplier_payments(tenant_id, supplier_id, paid_at DESC);

ALTER TABLE public.pos_supplier_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view supplier payments" ON public.pos_supplier_payments;
CREATE POLICY "POS users view supplier payments" ON public.pos_supplier_payments FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create supplier payments" ON public.pos_supplier_payments;
CREATE POLICY "POS users create supplier payments" ON public.pos_supplier_payments FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.record_supplier_payment(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_payment_id uuid;
  v_new_paid numeric;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_payment_method NOT IN ('cash','transfer','debit','credit','other')
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid supplier payment' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_po.status = 'cancelled' THEN RAISE EXCEPTION 'Purchase order is not payable' USING ERRCODE = '55000'; END IF;
  IF p_amount > GREATEST(0, v_po.total - v_po.amount_paid) THEN RAISE EXCEPTION 'Payment exceeds outstanding balance' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.pos_supplier_payments(tenant_id, outlet_id, purchase_order_id, supplier_id, amount, payment_method, reference, notes, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_purchase_order_id, v_po.supplier_id, p_amount, p_payment_method, NULLIF(trim(p_reference), ''), NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_payment_id;
  v_new_paid := v_po.amount_paid + p_amount;
  v_status := CASE WHEN v_new_paid >= v_po.total THEN 'paid' WHEN v_new_paid > 0 THEN 'partial' ELSE 'unpaid' END;
  UPDATE public.pos_purchase_orders
  SET amount_paid = v_new_paid, amount_due = GREATEST(0, total - v_new_paid), payment_status = v_status, updated_by = auth.uid(), updated_at = now()
  WHERE id = v_po.id;
  RETURN jsonb_build_object('payment_id', v_payment_id, 'purchase_order_id', v_po.id, 'amount_paid', v_new_paid, 'amount_due', GREATEST(0, v_po.total - v_new_paid), 'payment_status', v_status);
END; $$;

REVOKE ALL ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) TO authenticated;

-- ===== END SOURCE: 20260825130000_supplier_payables_and_terms.sql =====

-- ===== BEGIN SOURCE: 20260825140000_stock_batches_fefo_multiwarehouse.sql =====
CREATE TABLE IF NOT EXISTS public.pos_warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  name text NOT NULL,
  code text NOT NULL,
  warehouse_type text NOT NULL DEFAULT 'warehouse' CHECK (warehouse_type IN ('warehouse','outlet','vehicle','transit')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
);
ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.pos_stock_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL,
  stock_id uuid REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE SET NULL,
  batch_number text NOT NULL,
  expiry_date date,
  quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit_cost numeric(15,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, outlet_id, product_id, variant_id, batch_number)
);
CREATE INDEX IF NOT EXISTS idx_pos_stock_batches_fefo
  ON public.pos_stock_batches(tenant_id, outlet_id, product_id, variant_id, expiry_date NULLS LAST, received_at);

ALTER TABLE public.pos_warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view warehouses" ON public.pos_warehouses;
CREATE POLICY "POS users view warehouses" ON public.pos_warehouses FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant owners manage warehouses" ON public.pos_warehouses;
CREATE POLICY "Tenant owners manage warehouses" ON public.pos_warehouses FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view stock batches" ON public.pos_stock_batches;
CREATE POLICY "POS users view stock batches" ON public.pos_stock_batches FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "Tenant owners manage stock batches" ON public.pos_stock_batches;
CREATE POLICY "Tenant owners manage stock batches" ON public.pos_stock_batches FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.consume_pos_stock_fefo(
  p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_quantity numeric, p_reference_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_remaining numeric := p_quantity; v_batch record; v_take numeric; v_consumed numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid FEFO consumption request' USING ERRCODE = '42501';
  END IF;
  FOR v_batch IN SELECT * FROM public.pos_stock_batches
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND product_id = p_product_id
      AND variant_id IS NOT DISTINCT FROM p_variant_id AND quantity > 0
    ORDER BY expiry_date NULLS LAST, received_at, id FOR UPDATE LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_remaining, v_batch.quantity);
    UPDATE public.pos_stock_batches SET quantity = quantity - v_take WHERE id = v_batch.id;
    v_remaining := v_remaining - v_take;
    v_consumed := v_consumed + v_take;
  END LOOP;
  IF v_remaining > 0 THEN RAISE EXCEPTION 'Insufficient FEFO batch stock' USING ERRCODE = '23514'; END IF;
  RETURN jsonb_build_object('product_id', p_product_id, 'consumed', v_consumed, 'remaining', v_remaining, 'reference_id', p_reference_id);
END; $$;
REVOKE ALL ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) TO authenticated;

-- ===== END SOURCE: 20260825140000_stock_batches_fefo_multiwarehouse.sql =====

-- ===== BEGIN SOURCE: 20260825150000_stock_reservation_partial_fulfillment.sql =====
ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0);

CREATE TABLE IF NOT EXISTS public.pos_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.pos_stock_reservations(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id),
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, stock_id)
);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_order ON public.pos_stock_reservations(order_id, status);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_expiry ON public.pos_stock_reservations(status, expires_at);

CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  courier_id uuid REFERENCES auth.users(id),
  tracking_number text,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(tenant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.pos_fulfillment_shipments(id) ON DELETE CASCADE,
  order_item_id uuid REFERENCES public.order_items(id) ON DELETE SET NULL,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);

ALTER TABLE public.pos_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view reservations" ON public.pos_stock_reservations;
CREATE POLICY "POS users view reservations" ON public.pos_stock_reservations FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view reservation items" ON public.pos_stock_reservation_items;
CREATE POLICY "POS users view reservation items" ON public.pos_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.pos_stock_reservations WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "POS users view shipments" ON public.pos_fulfillment_shipments;
CREATE POLICY "POS users view shipments" ON public.pos_fulfillment_shipments FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view shipment items" ON public.pos_fulfillment_shipment_items;
CREATE POLICY "POS users view shipment items" ON public.pos_fulfillment_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.pos_fulfillment_shipments WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));

CREATE OR REPLACE FUNCTION public.reserve_pos_stock(
  p_tenant_id uuid, p_outlet_id uuid, p_order_id uuid, p_items jsonb, p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reservation_id uuid; v_input jsonb; v_stock public.pos_stock%ROWTYPE; v_qty numeric; v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock reservation' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_reservations(tenant_id, outlet_id, order_id, expires_at, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_order_id, p_expires_at, auth.uid()) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'stock_id', '') IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = (v_input->>'stock_id')::uuid AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
    IF NOT FOUND OR v_stock.quantity - v_stock.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available stock for reservation' USING ERRCODE = '23514'; END IF;
    UPDATE public.pos_stock SET reserved_quantity = reserved_quantity + v_qty, updated_at = now() WHERE id = v_stock.id;
    INSERT INTO public.pos_stock_reservation_items(reservation_id, stock_id, product_id, variant_id, quantity)
    VALUES (v_reservation_id, v_stock.id, v_stock.product_id, v_stock.variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'quantity', v_total, 'status', 'active');
END; $$;

CREATE OR REPLACE FUNCTION public.release_pos_stock_reservation(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.pos_stock_reservations%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.pos_stock_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_res.tenant_id, v_res.outlet_id) THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_reservation_items WHERE reservation_id = p_reservation_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id FOR UPDATE;
    IF FOUND THEN UPDATE public.pos_stock SET reserved_quantity = GREATEST(0, reserved_quantity - v_item.quantity), updated_at = now() WHERE id = v_stock.id; END IF;
  END LOOP;
  UPDATE public.pos_stock_reservations SET status = 'released', released_at = now() WHERE id = p_reservation_id;
  RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', 'released');
END; $$;

REVOKE ALL ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_pos_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_pos_stock_reservation(uuid) TO authenticated;

-- ===== END SOURCE: 20260825150000_stock_reservation_partial_fulfillment.sql =====

-- ===== BEGIN SOURCE: 20260825160000_courier_payroll_cod_reconciliation.sql =====
CREATE TABLE IF NOT EXISTS public.courier_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  base_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (base_amount >= 0),
  per_km_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (per_km_amount >= 0),
  bonus_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
  penalty_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (penalty_amount >= 0),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS distance_km numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS base_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS penalty_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rule_id uuid REFERENCES public.courier_commission_rules(id),
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz;

CREATE TABLE IF NOT EXISTS public.courier_cod_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  expected_cash numeric(15,2) NOT NULL CHECK (expected_cash >= 0),
  collected_cash numeric(15,2) NOT NULL CHECK (collected_cash >= 0),
  variance numeric(15,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','matched','shortage','overage','approved','disputed')),
  proof_url text,
  notes text,
  submitted_by uuid REFERENCES auth.users(id),
  reviewed_by uuid REFERENCES auth.users(id),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE(courier_id, order_id)
);
CREATE INDEX IF NOT EXISTS idx_courier_cod_status ON public.courier_cod_reconciliations(courier_id, status, submitted_at DESC);

ALTER TABLE public.courier_commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_cod_reconciliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage courier commission rules" ON public.courier_commission_rules;
CREATE POLICY "Admins manage courier commission rules" ON public.courier_commission_rules FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations FOR SELECT TO authenticated
  USING (courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid() AND courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins manage COD reconciliation" ON public.courier_cod_reconciliations;
CREATE POLICY "Admins manage COD reconciliation" ON public.courier_cod_reconciliations FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.submit_courier_cod_reconciliation(
  p_courier_id uuid, p_order_id uuid, p_collected_cash numeric, p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_id uuid; v_expected numeric; v_variance numeric; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_courier_owner(auth.uid(), p_courier_id) OR p_collected_cash IS NULL OR p_collected_cash < 0 THEN
    RAISE EXCEPTION 'COD reconciliation access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND courier_id = p_courier_id FOR SHARE;
  IF NOT FOUND OR v_order.payment_method <> 'COD' OR v_order.status NOT IN ('DONE','DELIVERED') THEN
    RAISE EXCEPTION 'Order is not eligible for COD reconciliation' USING ERRCODE = '55000';
  END IF;
  v_expected := v_order.total + COALESCE(v_order.shipping_cost, 0);
  v_variance := p_collected_cash - v_expected;
  v_status := CASE WHEN v_variance = 0 THEN 'matched' WHEN v_variance < 0 THEN 'shortage' ELSE 'overage' END;
  INSERT INTO public.courier_cod_reconciliations(courier_id, order_id, expected_cash, collected_cash, variance, status, notes, submitted_by)
  VALUES (p_courier_id, p_order_id, v_expected, p_collected_cash, v_variance, v_status, NULLIF(trim(p_notes), ''), auth.uid())
  ON CONFLICT (courier_id, order_id) DO UPDATE SET
    collected_cash = EXCLUDED.collected_cash, variance = EXCLUDED.variance, status = EXCLUDED.status,
    notes = EXCLUDED.notes, submitted_by = auth.uid(), submitted_at = now(), reviewed_by = NULL, reviewed_at = NULL
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'expected_cash', v_expected, 'collected_cash', p_collected_cash, 'variance', v_variance, 'status', v_status);
END; $$;

CREATE OR REPLACE FUNCTION public.review_courier_cod_reconciliation(p_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() OR p_status NOT IN ('approved','disputed') THEN
    RAISE EXCEPTION 'COD review denied' USING ERRCODE = '42501';
  END IF;
  UPDATE public.courier_cod_reconciliations SET status = p_status, notes = COALESCE(NULLIF(trim(p_notes), ''), notes), reviewed_by = auth.uid(), reviewed_at = now() WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COD reconciliation not found' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END; $$;

REVOKE ALL ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) TO authenticated;

-- ===== END SOURCE: 20260825160000_courier_payroll_cod_reconciliation.sql =====

-- ===== BEGIN SOURCE: 20260825170000_dispute_center_approval_workflow.sql =====
CREATE TABLE IF NOT EXISTS public.business_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  reporter_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject_type text NOT NULL CHECK (subject_type IN ('order','payment','refund','delivery','product','account','payout')),
  subject_id uuid,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','investigating','resolved','rejected','closed')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  amount numeric(15,2) CHECK (amount IS NULL OR amount >= 0),
  evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
  resolution text,
  assigned_to uuid REFERENCES auth.users(id),
  resolved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_business_disputes_status ON public.business_disputes(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_business_disputes_subject ON public.business_disputes(subject_type, subject_id);

CREATE TABLE IF NOT EXISTS public.approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id),
  request_type text NOT NULL CHECK (request_type IN ('refund','discount','void','negative_stock','payout','bank_account','stock_adjustment','price_override')),
  subject_id uuid,
  requested_amount numeric(15,2) CHECK (requested_amount IS NULL OR requested_amount >= 0),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  required_level integer NOT NULL DEFAULT 1 CHECK (required_level > 0),
  approved_level integer NOT NULL DEFAULT 0 CHECK (approved_level >= 0),
  decided_by uuid REFERENCES auth.users(id),
  decided_at timestamptz,
  decision_notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_requests_pending ON public.approval_requests(tenant_id, request_type, status, created_at DESC);

ALTER TABLE public.business_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users create disputes" ON public.business_disputes;
CREATE POLICY "Users create disputes" ON public.business_disputes FOR INSERT TO authenticated WITH CHECK (reporter_id = auth.uid());
DROP POLICY IF EXISTS "Participants view disputes" ON public.business_disputes;
CREATE POLICY "Participants view disputes" ON public.business_disputes FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR assigned_to = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage disputes" ON public.business_disputes;
CREATE POLICY "Admins manage disputes" ON public.business_disputes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Tenant users view approvals" ON public.approval_requests;
CREATE POLICY "Tenant users view approvals" ON public.approval_requests FOR SELECT TO authenticated USING (requester_id = auth.uid() OR public.is_admin() OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Users create approvals" ON public.approval_requests;
CREATE POLICY "Users create approvals" ON public.approval_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS "Admins manage approvals" ON public.approval_requests;
CREATE POLICY "Admins manage approvals" ON public.approval_requests FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.decide_approval_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Approval requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Approval request is not pending' USING ERRCODE = '55000'; END IF;
  v_status := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
  UPDATE public.approval_requests SET status = v_status, approved_level = CASE WHEN p_approve THEN required_level ELSE approved_level END,
    decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', v_status);
END; $$;
REVOKE ALL ON FUNCTION public.decide_approval_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_approval_request(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825170000_dispute_center_approval_workflow.sql =====

-- ===== BEGIN SOURCE: 20260825180000_pricebook_loyalty_import_jobs.sql =====
CREATE TABLE IF NOT EXISTS public.pos_price_books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  customer_segment text NOT NULL DEFAULT 'retail' CHECK (customer_segment IN ('retail','wholesale','reseller','member','outlet')),
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  priority integer NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.pos_price_book_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_book_id uuid NOT NULL REFERENCES public.pos_price_books(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE CASCADE,
  price numeric(15,2) NOT NULL CHECK (price >= 0),
  UNIQUE(price_book_id, product_id, variant_id)
);
ALTER TABLE public.pos_price_books ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_pos_price_books_active ON public.pos_price_books(tenant_id, is_active, starts_at, ends_at, priority DESC);

CREATE TABLE IF NOT EXISTS public.pos_loyalty_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  rule_type text NOT NULL CHECK (rule_type IN ('earn','redeem','tier','expiry','category_bonus')),
  category_id uuid REFERENCES public.pos_categories(id) ON DELETE SET NULL,
  min_spend numeric(15,2) NOT NULL DEFAULT 0 CHECK (min_spend >= 0),
  points_per_currency numeric(12,4) NOT NULL DEFAULT 0 CHECK (points_per_currency >= 0),
  points_value numeric(15,2) NOT NULL DEFAULT 0 CHECK (points_value >= 0),
  tier_name text,
  expires_after_days integer CHECK (expires_after_days IS NULL OR expires_after_days > 0),
  is_active boolean NOT NULL DEFAULT true,
  priority integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_rules_active ON public.pos_loyalty_rules(tenant_id, rule_type, is_active, priority DESC);

CREATE TABLE IF NOT EXISTS public.pos_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('products','stock','customers','suppliers')),
  status text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','validated','committed','rolled_back','failed')),
  source_filename text,
  row_count integer NOT NULL DEFAULT 0,
  valid_count integer NOT NULL DEFAULT 0,
  invalid_count integer NOT NULL DEFAULT 0,
  preview_rows jsonb NOT NULL DEFAULT '[]'::jsonb,
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  rollback_token text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  rolled_back_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_pos_import_jobs_tenant ON public.pos_import_jobs(tenant_id, entity_type, status, created_at DESC);

ALTER TABLE public.pos_price_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_price_book_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_loyalty_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view price books" ON public.pos_price_books;
CREATE POLICY "POS users view price books" ON public.pos_price_books FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "Tenant owners manage price books" ON public.pos_price_books;
CREATE POLICY "Tenant owners manage price books" ON public.pos_price_books FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view price book items" ON public.pos_price_book_items;
CREATE POLICY "POS users view price book items" ON public.pos_price_book_items FOR SELECT TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
DROP POLICY IF EXISTS "Tenant owners manage price book items" ON public.pos_price_book_items;
CREATE POLICY "Tenant owners manage price book items" ON public.pos_price_book_items FOR ALL TO authenticated USING (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))) WITH CHECK (price_book_id IN (SELECT id FROM public.pos_price_books WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));
DROP POLICY IF EXISTS "POS users view loyalty rules" ON public.pos_loyalty_rules;
CREATE POLICY "POS users view loyalty rules" ON public.pos_loyalty_rules FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules;
CREATE POLICY "Tenant owners manage loyalty rules" ON public.pos_loyalty_rules FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Users view own imports" ON public.pos_import_jobs;
CREATE POLICY "Users view own imports" ON public.pos_import_jobs FOR SELECT TO authenticated USING (created_by = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Users create scoped imports" ON public.pos_import_jobs;
CREATE POLICY "Users create scoped imports" ON public.pos_import_jobs FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.get_effective_pos_price(p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_segment text DEFAULT 'retail')
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT i.price FROM public.pos_price_book_items i JOIN public.pos_price_books b ON b.id = i.price_book_id WHERE b.tenant_id = p_tenant_id AND (b.outlet_id IS NULL OR b.outlet_id = p_outlet_id) AND b.customer_segment = p_segment AND b.is_active AND (b.starts_at IS NULL OR b.starts_at <= now()) AND (b.ends_at IS NULL OR b.ends_at >= now()) AND i.product_id = p_product_id AND i.variant_id IS NOT DISTINCT FROM p_variant_id ORDER BY (b.outlet_id IS NOT NULL) DESC, b.priority DESC NULLS LAST LIMIT 1), (SELECT price FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id));
$$;
REVOKE ALL ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_effective_pos_price(uuid, uuid, uuid, uuid, text) TO authenticated;

-- ===== END SOURCE: 20260825180000_pricebook_loyalty_import_jobs.sql =====

-- ===== BEGIN SOURCE: 20260825190000_crm_segments_campaigns.sql =====
CREATE TABLE IF NOT EXISTS public.crm_customer_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_dynamic boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.crm_segment_members (
  segment_id uuid NOT NULL REFERENCES public.crm_customer_segments(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(segment_id, customer_id)
);
CREATE TABLE IF NOT EXISTS public.crm_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  segment_id uuid REFERENCES public.crm_customer_segments(id) ON DELETE SET NULL,
  name text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('in_app','email','whatsapp','push')),
  template text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','scheduled','sending','sent','cancelled','failed')),
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.crm_campaign_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.crm_campaigns(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','delivered','failed','opted_out')),
  provider_message_id text,
  error_message text,
  sent_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(campaign_id, customer_id)
);
CREATE TABLE IF NOT EXISTS public.crm_abandoned_carts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cart_snapshot jsonb NOT NULL,
  total_amount numeric(15,2) NOT NULL DEFAULT 0,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  reminder_sent_at timestamptz,
  recovered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_crm_campaigns_status ON public.crm_campaigns(tenant_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_crm_abandoned_carts_reminder ON public.crm_abandoned_carts(tenant_id, last_activity_at, reminder_sent_at) WHERE recovered_at IS NULL;

ALTER TABLE public.crm_customer_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_segment_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_campaign_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_abandoned_carts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant owners manage CRM segments" ON public.crm_customer_segments;
CREATE POLICY "Tenant owners manage CRM segments" ON public.crm_customer_segments FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view CRM segments" ON public.crm_customer_segments;
CREATE POLICY "Tenant users view CRM segments" ON public.crm_customer_segments FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant owners manage CRM campaigns" ON public.crm_campaigns;
CREATE POLICY "Tenant owners manage CRM campaigns" ON public.crm_campaigns FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view CRM campaigns" ON public.crm_campaigns;
CREATE POLICY "Tenant users view CRM campaigns" ON public.crm_campaigns FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Customer views own campaign delivery" ON public.crm_campaign_deliveries;
CREATE POLICY "Customer views own campaign delivery" ON public.crm_campaign_deliveries FOR SELECT TO authenticated USING (customer_id = auth.uid() OR campaign_id IN (SELECT id FROM public.crm_campaigns WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));
DROP POLICY IF EXISTS "Tenant users manage abandoned carts" ON public.crm_abandoned_carts;
CREATE POLICY "Tenant users manage abandoned carts" ON public.crm_abandoned_carts FOR ALL TO authenticated USING (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (customer_id = auth.uid() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Customers view own segment membership" ON public.crm_segment_members;
CREATE POLICY "Customers view own segment membership" ON public.crm_segment_members FOR SELECT TO authenticated USING (customer_id = auth.uid() OR segment_id IN (SELECT id FROM public.crm_customer_segments WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));

-- ===== END SOURCE: 20260825190000_crm_segments_campaigns.sql =====

-- ===== BEGIN SOURCE: 20260825200000_notification_delivery_queue.sql =====
CREATE TABLE IF NOT EXISTS public.notification_delivery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('whatsapp','push','email','in_app')),
  template_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','sent','failed','dead_letter','cancelled','opted_out')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts > 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  provider_message_id text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  dead_letter_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_due ON public.notification_delivery_jobs(status, next_attempt_at) WHERE status IN ('queued','failed');
CREATE INDEX IF NOT EXISTS idx_notification_jobs_recipient ON public.notification_delivery_jobs(recipient_id, created_at DESC);

ALTER TABLE public.notification_delivery_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated USING (recipient_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Admins manage notification jobs" ON public.notification_delivery_jobs FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated;

-- ===== END SOURCE: 20260825200000_notification_delivery_queue.sql =====

-- ===== BEGIN SOURCE: 20260825210000_subscription_billing_controls.sql =====
ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS billing_period text NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly','quarterly','yearly')),
  ADD COLUMN IF NOT EXISTS current_period_start timestamptz,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz,
  ADD COLUMN IF NOT EXISTS grace_period_until timestamptz,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS provider_subscription_id text;

CREATE TABLE IF NOT EXISTS public.subscription_billing_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL,
  amount numeric(15,2),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'received' CHECK (status IN ('received','processed','ignored','failed')),
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE(provider, provider_event_id)
);
CREATE INDEX IF NOT EXISTS idx_subscription_events_subscription ON public.subscription_billing_events(subscription_id, created_at DESC);

ALTER TABLE public.subscription_billing_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant views own subscription events" ON public.subscription_billing_events;
CREATE POLICY "Merchant views own subscription events" ON public.subscription_billing_events FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription events" ON public.subscription_billing_events;
CREATE POLICY "Admins manage subscription events" ON public.subscription_billing_events FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.record_subscription_billing_event(
  p_subscription_id uuid, p_provider text, p_provider_event_id text, p_event_type text, p_amount numeric, p_payload jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_merchant_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Billing event ingestion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT merchant_id INTO v_merchant_id FROM public.merchant_subscriptions WHERE id = p_subscription_id;
  IF v_merchant_id IS NULL THEN RAISE EXCEPTION 'Subscription not found' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO public.subscription_billing_events(subscription_id, provider, provider_event_id, event_type, amount, payload)
  VALUES (p_subscription_id, p_provider, p_provider_event_id, p_event_type, p_amount, COALESCE(p_payload, '{}'::jsonb))
  ON CONFLICT (provider, provider_event_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN jsonb_build_object('duplicate', true, 'provider_event_id', p_provider_event_id); END IF;
  RETURN jsonb_build_object('duplicate', false, 'event_id', v_id);
END; $$;
REVOKE ALL ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) TO service_role;

-- ===== END SOURCE: 20260825210000_subscription_billing_controls.sql =====

-- ===== BEGIN SOURCE: 20260825220000_tax_accounting_journal.sql =====
CREATE TABLE IF NOT EXISTS public.pos_tax_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  tax_code text NOT NULL,
  rate numeric(7,4) NOT NULL DEFAULT 0 CHECK (rate >= 0 AND rate <= 100),
  inclusive boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, tax_code)
);

CREATE TABLE IF NOT EXISTS public.pos_journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  entry_number text NOT NULL,
  entry_date date NOT NULL DEFAULT CURRENT_DATE,
  source_type text NOT NULL CHECK (source_type IN ('sale','payment','refund','purchase','payout','adjustment','tax','settlement')),
  source_id uuid,
  memo text NOT NULL,
  status text NOT NULL DEFAULT 'posted' CHECK (status IN ('draft','posted','reversed')),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, entry_number)
);
CREATE TABLE IF NOT EXISTS public.pos_journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id uuid NOT NULL REFERENCES public.pos_journal_entries(id) ON DELETE CASCADE,
  account_code text NOT NULL,
  account_name text NOT NULL,
  debit numeric(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  tax_profile_id uuid REFERENCES public.pos_tax_profiles(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK ((debit = 0 AND credit > 0) OR (credit = 0 AND debit > 0))
);
CREATE INDEX IF NOT EXISTS idx_pos_journal_entries_export ON public.pos_journal_entries(tenant_id, entry_date, status);
CREATE INDEX IF NOT EXISTS idx_pos_journal_lines_account ON public.pos_journal_lines(journal_entry_id, account_code);

ALTER TABLE public.pos_tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_journal_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant owners manage tax profiles" ON public.pos_tax_profiles;
CREATE POLICY "Tenant owners manage tax profiles" ON public.pos_tax_profiles FOR ALL TO authenticated USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())) WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view tax profiles" ON public.pos_tax_profiles;
CREATE POLICY "Tenant users view tax profiles" ON public.pos_tax_profiles FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant users view journals" ON public.pos_journal_entries;
CREATE POLICY "Tenant users view journals" ON public.pos_journal_entries FOR SELECT TO authenticated USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Tenant users view journal lines" ON public.pos_journal_lines;
CREATE POLICY "Tenant users view journal lines" ON public.pos_journal_lines FOR SELECT TO authenticated USING (journal_entry_id IN (SELECT id FROM public.pos_journal_entries WHERE tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.post_pos_journal_entry(
  p_tenant_id uuid, p_outlet_id uuid, p_entry_number text, p_entry_date date, p_source_type text, p_source_id uuid, p_memo text, p_lines jsonb
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_line jsonb; v_debit numeric; v_credit numeric; v_total_debit numeric := 0; v_total_credit numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'Invalid journal entry' USING ERRCODE = '42501';
  END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_debit := COALESCE((v_line->>'debit')::numeric, 0); v_credit := COALESCE((v_line->>'credit')::numeric, 0);
    IF (v_debit > 0 AND v_credit > 0) OR (v_debit = 0 AND v_credit = 0) THEN RAISE EXCEPTION 'Journal line must contain debit or credit only' USING ERRCODE = '23514'; END IF;
    v_total_debit := v_total_debit + v_debit; v_total_credit := v_total_credit + v_credit;
  END LOOP;
  IF v_total_debit <> v_total_credit THEN RAISE EXCEPTION 'Journal entry is not balanced' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.pos_journal_entries(tenant_id, outlet_id, entry_number, entry_date, source_type, source_id, memo, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_entry_number, COALESCE(p_entry_date, CURRENT_DATE), p_source_type, p_source_id, p_memo, auth.uid()) RETURNING id INTO v_entry_id;
  INSERT INTO public.pos_journal_lines(journal_entry_id, account_code, account_name, debit, credit, tax_profile_id, metadata)
  SELECT v_entry_id, value->>'account_code', value->>'account_name', COALESCE((value->>'debit')::numeric,0), COALESCE((value->>'credit')::numeric,0), NULLIF(value->>'tax_profile_id','')::uuid, COALESCE(value->'metadata','{}'::jsonb)
  FROM jsonb_array_elements(p_lines);
  RETURN v_entry_id;
END; $$;
REVOKE ALL ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_pos_journal_entry(uuid, uuid, text, date, text, uuid, text, jsonb) TO authenticated;

-- ===== END SOURCE: 20260825220000_tax_accounting_journal.sql =====

-- ===== BEGIN SOURCE: 20260825230000_worker_claim_and_subscription_processor.sql =====
CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;
REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_one_subscription_billing_event()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event public.subscription_billing_events%ROWTYPE; v_payload jsonb; v_status text; v_period_start timestamptz; v_period_end timestamptz; v_grace timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Subscription event processing requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_event FROM public.subscription_billing_events WHERE status IN ('received','failed') ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('processed', false, 'reason', 'empty'); END IF;
  v_payload := COALESCE(v_event.payload, '{}'::jsonb);
  v_period_start := NULLIF(COALESCE(v_payload->>'period_start', v_payload->>'current_period_start'), '')::timestamptz;
  v_period_end := NULLIF(COALESCE(v_payload->>'period_end', v_payload->>'current_period_end'), '')::timestamptz;
  v_grace := NULLIF(v_payload->>'grace_period_until', '')::timestamptz;
  IF v_event.event_type IN ('payment_succeeded','invoice_paid','subscription_renewed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'PAID', status = 'ACTIVE', paid_at = COALESCE(paid_at, now()), current_period_start = COALESCE(v_period_start, current_period_start), current_period_end = COALESCE(v_period_end, current_period_end), grace_period_until = NULL, updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('payment_failed','invoice_failed') THEN
    UPDATE public.merchant_subscriptions SET payment_status = 'UNPAID', status = CASE WHEN v_grace IS NULL OR v_grace > now() THEN 'PAST_DUE' ELSE 'EXPIRED' END, grace_period_until = COALESCE(v_grace, now() + interval '7 days'), updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSIF v_event.event_type IN ('subscription_cancelled','cancelled') THEN
    UPDATE public.merchant_subscriptions SET status = 'CANCELLED', updated_at = now() WHERE id = v_event.subscription_id;
    v_status := 'processed';
  ELSE
    v_status := 'ignored';
  END IF;
  UPDATE public.subscription_billing_events SET status = v_status, processed_at = now(), error_message = NULL WHERE id = v_event.id;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', v_status);
EXCEPTION WHEN OTHERS THEN
  IF v_event.id IS NOT NULL THEN UPDATE public.subscription_billing_events SET status = 'failed', error_message = SQLERRM WHERE id = v_event.id; END IF;
  RETURN jsonb_build_object('processed', true, 'event_id', v_event.id, 'status', 'failed', 'error', SQLERRM);
END; $$;
REVOKE ALL ON FUNCTION public.process_one_subscription_billing_event() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_one_subscription_billing_event() TO authenticated, service_role;

-- ===== END SOURCE: 20260825230000_worker_claim_and_subscription_processor.sql =====

-- ===== BEGIN SOURCE: 20260825235000_price_override_approval_rpc.sql =====
CREATE OR REPLACE FUNCTION public.decide_pos_price_override(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.pos_price_override_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item public.pos_sale_items%ROWTYPE; v_subtotal numeric;
BEGIN
  SELECT * INTO v_request FROM public.pos_price_override_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_request.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Price override approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_request.status <> 'pending' THEN RAISE EXCEPTION 'Price override request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_price_override_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  IF v_request.sale_item_id IS NULL THEN RAISE EXCEPTION 'Price override item is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_item FROM public.pos_sale_items WHERE id = v_request.sale_item_id FOR UPDATE;
  IF NOT FOUND OR (v_request.sale_id IS NOT NULL AND v_item.sale_id <> v_request.sale_id) THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_item.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Only completed POS sales can be price-adjusted' USING ERRCODE = '55000'; END IF;
  IF v_sale.tenant_id <> v_request.tenant_id OR v_sale.outlet_id <> v_request.outlet_id THEN RAISE EXCEPTION 'Price override scope mismatch' USING ERRCODE = '42501'; END IF;
  UPDATE public.pos_sale_items SET price = v_request.requested_price, subtotal = GREATEST(0, (v_request.requested_price * qty) - COALESCE(discount, 0)) WHERE id = v_item.id;
  SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM public.pos_sale_items WHERE sale_id = v_sale.id;
  UPDATE public.pos_sales SET subtotal = v_subtotal, total = GREATEST(0, v_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)), notes = concat_ws(E'\n', notes, 'Approved price override: ', v_request.id::text) WHERE id = v_sale.id;
  UPDATE public.pos_price_override_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id, 'new_price', v_request.requested_price, 'new_subtotal', v_subtotal);
END; $$;
REVOKE ALL ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260825235000_price_override_approval_rpc.sql =====

-- ===== BEGIN SOURCE: 20260826000000_atomic_warehouse_transfer.sql =====
CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  from_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  to_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','cancelled')),
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (from_warehouse_id <> to_warehouse_id)
);
CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES public.pos_warehouse_transfers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE RESTRICT,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfers_tenant ON public.pos_warehouse_transfers(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfer_items_transfer ON public.pos_warehouse_transfer_items(transfer_id);
ALTER TABLE public.pos_warehouse_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_warehouse_transfer_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view warehouse transfers" ON public.pos_warehouse_transfers;
CREATE POLICY "POS users view warehouse transfers" ON public.pos_warehouse_transfers FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
DROP POLICY IF EXISTS "Tenant owners insert warehouse transfers" ON public.pos_warehouse_transfers;
CREATE POLICY "Tenant owners insert warehouse transfers" ON public.pos_warehouse_transfers FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "POS users view warehouse transfer items" ON public.pos_warehouse_transfer_items;
CREATE POLICY "POS users view warehouse transfer items" ON public.pos_warehouse_transfer_items FOR SELECT TO authenticated
  USING (transfer_id IN (SELECT id FROM public.pos_warehouse_transfers WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)));

CREATE OR REPLACE FUNCTION public.transfer_stock_between_warehouses(
  p_tenant_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_items jsonb,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_from public.pos_warehouses%ROWTYPE; v_to public.pos_warehouses%ROWTYPE; v_transfer_id uuid; v_item jsonb; v_source public.pos_stock%ROWTYPE; v_dest public.pos_stock%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty numeric; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 OR p_from_warehouse_id = p_to_warehouse_id THEN
    RAISE EXCEPTION 'Invalid warehouse transfer' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_from FROM public.pos_warehouses WHERE id = p_from_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  SELECT * INTO v_to FROM public.pos_warehouses WHERE id = p_to_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  IF NOT FOUND OR v_from.outlet_id IS NULL OR v_to.outlet_id IS NULL THEN RAISE EXCEPTION 'Warehouse must be active and linked to an outlet' USING ERRCODE = '55000'; END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, v_from.outlet_id) OR NOT public.pos_user_can_access_outlet(p_tenant_id, v_to.outlet_id) THEN RAISE EXCEPTION 'Warehouse transfer access denied' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.pos_warehouse_transfers(tenant_id, from_warehouse_id, to_warehouse_id, notes, created_by)
  VALUES (p_tenant_id, p_from_warehouse_id, p_to_warehouse_id, NULLIF(trim(p_notes), ''), auth.uid()) RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_item->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_item->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid warehouse transfer item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_from.outlet_id AND warehouse_id = p_from_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available warehouse stock' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_qty;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (p_tenant_id, v_product_id, v_variant_id, v_from.outlet_id, 'transfer_out', -v_qty, v_source.quantity, v_after, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer out', auth.uid());
    SELECT * INTO v_dest FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_to.outlet_id AND warehouse_id = p_to_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF FOUND THEN
      UPDATE public.pos_stock SET quantity = quantity + v_qty, updated_at = now() WHERE id = v_dest.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, v_dest.quantity, v_dest.quantity + v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, outlet_id, warehouse_id, product_id, variant_id, quantity, reserved_quantity, min_stock)
      VALUES (p_tenant_id, v_to.outlet_id, p_to_warehouse_id, v_product_id, v_variant_id, v_qty, 0, 0);
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, 0, v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    END IF;
    INSERT INTO public.pos_warehouse_transfer_items(transfer_id, product_id, variant_id, quantity) VALUES (v_transfer_id, v_product_id, v_variant_id, v_qty);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'completed');
END; $$;
REVOKE ALL ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) TO authenticated;

-- ===== END SOURCE: 20260826000000_atomic_warehouse_transfer.sql =====
-- ===== END BUNDLE: 07_20260823080000_to_20260826000000.sql =====

-- ===== BEGIN BUNDLE: 08_20260826010000_to_20260829160000.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260826010000_atomic_loyalty_checkout_crm.sql .. 20260829160000_pos_workflow_transition_hardening.sql


-- ===== BEGIN SOURCE: 20260826010000_atomic_loyalty_checkout_crm.sql =====
-- Atomic loyalty ledger and checkout/CRM integration.
-- The legacy pos_customers.loyalty_points remains a compatibility aggregate;
-- pos_loyalty_ledger is the immutable source of point movements.

CREATE TABLE IF NOT EXISTS public.pos_loyalty_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES public.pos_customers(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  entry_type text NOT NULL CHECK (entry_type IN ('earn','redeem','adjust','expire','reverse')),
  points integer NOT NULL CHECK (points <> 0),
  balance_before integer NOT NULL CHECK (balance_before >= 0),
  balance_after integer NOT NULL CHECK (balance_after >= 0),
  rule_id uuid REFERENCES public.pos_loyalty_rules(id) ON DELETE SET NULL,
  idempotency_key text,
  description text,
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_customer
  ON public.pos_loyalty_ledger(tenant_id, customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_loyalty_ledger_sale
  ON public.pos_loyalty_ledger(sale_id) WHERE sale_id IS NOT NULL;

ALTER TABLE public.pos_loyalty_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger;
CREATE POLICY "Tenant users view loyalty ledger" ON public.pos_loyalty_ledger
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
    OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger;
CREATE POLICY "Tenant owners manage loyalty ledger" ON public.pos_loyalty_ledger
  FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- Backfill the aggregate account once. This is safe to re-run.
INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, used_points, expired_points, tier)
SELECT c.tenant_id, c.id, GREATEST(0, COALESCE(c.loyalty_points, 0)), 0, 0,
       COALESCE(NULLIF(c.loyalty_tier, ''), 'Bronze')
FROM public.pos_customers c
ON CONFLICT (tenant_id, customer_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pos_loyalty_actor_can_access(p_tenant_id uuid, p_actor_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p_actor_id = auth.uid()
    AND (
      EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.pos_users u WHERE u.tenant_id = p_tenant_id AND u.user_id = auth.uid() AND u.is_active = true)
    );
$$;

CREATE OR REPLACE FUNCTION public.earn_pos_loyalty_points(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_sale_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actor uuid := COALESCE(p_actor_id, auth.uid());
  v_customer public.pos_customers%ROWTYPE;
  v_account public.pos_loyalty_points%ROWTYPE;
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_points integer;
  v_before integer;
  v_after integer;
  v_entry_id uuid;
BEGIN
  IF NOT public.pos_loyalty_actor_can_access(p_tenant_id, v_actor) THEN
    RAISE EXCEPTION 'Loyalty access denied' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'Invalid loyalty amount' USING ERRCODE = '22023';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, balance_after INTO v_entry_id, v_after
    FROM public.pos_loyalty_ledger
    WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('entry_id', v_entry_id, 'points', v_after, 'balance', v_after, 'duplicate', true);
    END IF;
  END IF;

  SELECT * INTO v_customer FROM public.pos_customers
  WHERE id = p_customer_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_account FROM public.pos_loyalty_points
  WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, tier)
    VALUES (p_tenant_id, p_customer_id, GREATEST(0, COALESCE(v_customer.loyalty_points, 0)), COALESCE(v_customer.loyalty_tier, 'Bronze'))
    RETURNING * INTO v_account;
  END IF;

  SELECT * INTO v_rule FROM public.pos_loyalty_rules
  WHERE tenant_id = p_tenant_id AND rule_type = 'earn' AND is_active = true AND min_spend <= p_amount
  ORDER BY priority DESC, points_per_currency DESC, created_at DESC LIMIT 1;
  v_points := CASE WHEN FOUND THEN floor(p_amount * v_rule.points_per_currency)::integer ELSE 0 END;
  v_before := GREATEST(0, COALESCE(v_account.total_points, 0) - COALESCE(v_account.used_points, 0) - COALESCE(v_account.expired_points, 0));
  v_after := v_before + v_points;
  IF v_points = 0 THEN
    RETURN jsonb_build_object('points', 0, 'balance', v_before, 'duplicate', false);
  END IF;

  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, rule_id, idempotency_key, description, created_by)
  VALUES (p_tenant_id, p_customer_id, p_sale_id, 'earn', v_points, v_before, v_after, v_rule.id, p_idempotency_key, 'Atomic loyalty earn', v_actor)
  RETURNING id INTO v_entry_id;
  UPDATE public.pos_loyalty_points SET total_points = total_points + v_points, updated_at = now() WHERE id = v_account.id;
  UPDATE public.pos_customers SET loyalty_points = v_after, updated_at = now() WHERE id = p_customer_id;
  RETURN jsonb_build_object('entry_id', v_entry_id, 'points', v_points, 'balance', v_after, 'duplicate', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.redeem_pos_loyalty_points(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_points integer,
  p_sale_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_actor uuid := COALESCE(p_actor_id, auth.uid());
  v_customer public.pos_customers%ROWTYPE;
  v_account public.pos_loyalty_points%ROWTYPE;
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_before integer;
  v_after integer;
  v_entry_id uuid;
BEGIN
  IF NOT public.pos_loyalty_actor_can_access(p_tenant_id, v_actor) THEN RAISE EXCEPTION 'Loyalty access denied' USING ERRCODE = '42501'; END IF;
  IF p_points IS NULL OR p_points <= 0 THEN RAISE EXCEPTION 'Invalid redeem points' USING ERRCODE = '22023'; END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, balance_after INTO v_entry_id, v_after FROM public.pos_loyalty_ledger
    WHERE tenant_id = p_tenant_id AND idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('entry_id', v_entry_id, 'points', p_points, 'balance', v_after, 'duplicate', true); END IF;
  END IF;
  SELECT * INTO v_customer FROM public.pos_customers WHERE id = p_customer_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_account FROM public.pos_loyalty_points WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Loyalty account does not exist' USING ERRCODE = 'P0002'; END IF;
  v_before := GREATEST(0, COALESCE(v_account.total_points, 0) - COALESCE(v_account.used_points, 0) - COALESCE(v_account.expired_points, 0));
  IF p_points > v_before THEN RAISE EXCEPTION 'Insufficient loyalty points' USING ERRCODE = '23514'; END IF;
  SELECT * INTO v_rule FROM public.pos_loyalty_rules WHERE tenant_id = p_tenant_id AND rule_type = 'redeem' AND is_active = true ORDER BY priority DESC, created_at DESC LIMIT 1;
  v_after := v_before - p_points;
  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, rule_id, idempotency_key, description, created_by)
  VALUES (p_tenant_id, p_customer_id, p_sale_id, 'redeem', -p_points, v_before, v_after, v_rule.id, p_idempotency_key, 'Atomic loyalty redeem', v_actor)
  RETURNING id INTO v_entry_id;
  UPDATE public.pos_loyalty_points SET used_points = used_points + p_points, updated_at = now() WHERE id = v_account.id;
  UPDATE public.pos_customers SET loyalty_points = v_after, updated_at = now() WHERE id = p_customer_id;
  RETURN jsonb_build_object('entry_id', v_entry_id, 'points', p_points, 'balance', v_after, 'duplicate', false);
END;
$$;

REVOKE ALL ON FUNCTION public.pos_loyalty_actor_can_access(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) TO authenticated;

-- Mirror legacy checkout point mutations into the immutable ledger exactly once.
CREATE OR REPLACE FUNCTION public.record_pos_sale_loyalty_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_before integer;
  v_after integer;
  v_points integer;
BEGIN
  IF NEW.customer_id IS NULL OR (COALESCE(NEW.loyalty_points_earned, 0) = 0 AND COALESCE(NEW.loyalty_points_redeemed, 0) = 0) THEN RETURN NEW; END IF;
  INSERT INTO public.pos_loyalty_points(tenant_id, customer_id, total_points, tier)
  VALUES (NEW.tenant_id, NEW.customer_id, 0, 'Bronze') ON CONFLICT (tenant_id, customer_id) DO NOTHING;
  SELECT GREATEST(0, total_points - used_points - expired_points) INTO v_before FROM public.pos_loyalty_points
  WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id FOR UPDATE;
  v_points := COALESCE(NEW.loyalty_points_earned, 0) - COALESCE(NEW.loyalty_points_redeemed, 0);
  IF v_points = 0 THEN RETURN NEW; END IF;
  v_after := GREATEST(0, v_before + v_points);
  INSERT INTO public.pos_loyalty_ledger(tenant_id, customer_id, sale_id, entry_type, points, balance_before, balance_after, idempotency_key, description, created_by)
  VALUES (NEW.tenant_id, NEW.customer_id, NEW.id, CASE WHEN v_points >= 0 THEN 'earn' ELSE 'redeem' END, v_points, v_before, v_after, 'sale:' || NEW.id::text, 'POS sale loyalty sync', NEW.cashier_id)
  ON CONFLICT (tenant_id, idempotency_key) DO NOTHING;
  IF v_points > 0 THEN
    UPDATE public.pos_loyalty_points SET total_points = total_points + v_points, updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id;
  ELSE
    UPDATE public.pos_loyalty_points SET used_points = used_points + abs(v_points), updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.apply_pos_sale_loyalty_rules()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rule public.pos_loyalty_rules%ROWTYPE;
  v_available integer;
  v_requested_redeem integer := GREATEST(0, COALESCE(NEW.loyalty_points_redeemed, 0));
BEGIN
  IF NEW.customer_id IS NULL THEN
    NEW.loyalty_points_earned := 0;
    NEW.loyalty_points_redeemed := 0;
    NEW.loyalty_discount := 0;
    RETURN NEW;
  END IF;
  SELECT * INTO v_rule FROM public.pos_loyalty_rules
  WHERE tenant_id = NEW.tenant_id AND rule_type = 'earn' AND is_active = true AND min_spend <= NEW.total
  ORDER BY priority DESC, points_per_currency DESC, created_at DESC LIMIT 1;
  NEW.loyalty_points_earned := CASE WHEN FOUND THEN floor(NEW.total * v_rule.points_per_currency)::integer ELSE 0 END;
  SELECT GREATEST(0, total_points - used_points - expired_points) INTO v_available
  FROM public.pos_loyalty_points WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id FOR UPDATE;
  IF v_available IS NULL THEN
    SELECT GREATEST(0, COALESCE(loyalty_points, 0)) INTO v_available FROM public.pos_customers
    WHERE tenant_id = NEW.tenant_id AND id = NEW.customer_id FOR UPDATE;
  END IF;
  IF v_requested_redeem > COALESCE(v_available, 0) THEN
    RAISE EXCEPTION 'Insufficient loyalty points' USING ERRCODE = '23514';
  END IF;
  NEW.loyalty_points_redeemed := v_requested_redeem;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_apply_pos_sale_loyalty_rules ON public.pos_sales;
CREATE TRIGGER trg_apply_pos_sale_loyalty_rules
BEFORE INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.apply_pos_sale_loyalty_rules();
DROP TRIGGER IF EXISTS trg_record_pos_sale_loyalty_ledger ON public.pos_sales;
CREATE TRIGGER trg_record_pos_sale_loyalty_ledger
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.record_pos_sale_loyalty_ledger();

-- Reusing a cart after a completed sale marks matching active carts as recovered.
CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id AND customer_id = NEW.customer_id AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales;
CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale();

-- ===== END SOURCE: 20260826010000_atomic_loyalty_checkout_crm.sql =====

-- ===== BEGIN SOURCE: 20260826010000_marketplace_stock_reservation_lifecycle.sql =====
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS reserved_stock integer NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0);

CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  consumed_at timestamptz,
  UNIQUE(order_id)
);
CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.marketplace_stock_reservations(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.product_variants(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, product_id, variant_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservations_expiry ON public.marketplace_stock_reservations(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservation_items_product ON public.marketplace_stock_reservation_items(product_id);
ALTER TABLE public.marketplace_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_stock_reservation_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyers view own stock reservations" ON public.marketplace_stock_reservations;
CREATE POLICY "Buyers view own stock reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants view order reservations" ON public.marketplace_stock_reservations;
CREATE POLICY "Merchants view order reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = order_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Users view own reservation items" ON public.marketplace_stock_reservation_items;
CREATE POLICY "Users view own reservation items" ON public.marketplace_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.marketplace_stock_reservations WHERE buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = marketplace_stock_reservations.order_id AND m.user_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_reservation_id uuid; v_input jsonb; v_product public.products%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty integer; v_total integer := 0; v_existing public.marketplace_stock_reservations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR v_order.status IN ('CANCELLED','CANCELED','REJECTED','REFUNDED') THEN RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_existing FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true); END IF;
  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at) VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute')) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND OR v_product.stock - v_product.reserved_stock < v_qty THEN RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET reserved_stock = reserved_stock + v_qty, updated_at = now() WHERE id = v_product_id;
    INSERT INTO public.marketplace_stock_reservation_items(reservation_id, product_id, variant_id, quantity) VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'status', 'active', 'quantity', v_total, 'expires_at', p_expires_at);
END; $$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(p_order_id uuid, p_status text DEFAULT 'released')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  SELECT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer AND NOT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = p_order_id AND m.user_id = auth.uid()) AND NOT public.is_admin() THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    UPDATE public.products SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = CASE WHEN p_status IN ('expired','released') THEN p_status ELSE 'released' END, released_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END; $$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_product public.products%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true); END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
    IF NOT FOUND OR v_product.reserved_stock < v_item.quantity OR v_product.stock < v_item.quantity THEN RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET stock = stock - v_item.quantity, reserved_stock = reserved_stock - v_item.quantity, sold_count = COALESCE(sold_count, 0) + v_item.quantity, updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = 'consumed', consumed_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END; $$;

CREATE OR REPLACE FUNCTION public.expire_marketplace_stock_reservations(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order_id uuid; v_count integer := 0;
BEGIN
  FOR v_order_id IN SELECT order_id FROM public.marketplace_stock_reservations WHERE status = 'active' AND expires_at <= now() ORDER BY expires_at FOR UPDATE SKIP LOCKED LIMIT GREATEST(1, LEAST(p_limit, 1000)) LOOP
    PERFORM public.release_marketplace_stock_reservation(v_order_id, 'expired'); v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.marketplace_reservation_order_status_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF lower(COALESCE(NEW.status, '')) IN ('cancelled','canceled','rejected','refunded') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.release_marketplace_stock_reservation(NEW.id, 'released');
  ELSIF lower(COALESCE(NEW.status, '')) IN ('shipped','delivered','completed','done') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.consume_marketplace_stock_reservation(NEW.id);
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_marketplace_reservation_order_status ON public.orders;
CREATE TRIGGER trg_marketplace_reservation_order_status AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.marketplace_reservation_order_status_trigger();

REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role;

-- ===== END SOURCE: 20260826010000_marketplace_stock_reservation_lifecycle.sql =====

-- ===== BEGIN SOURCE: 20260826020000_crm_notification_dispatch.sql =====
-- CRM campaign dispatch into the durable notification queue.
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS dedupe_key text;
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_jobs_tenant_dedupe
  ON public.notification_delivery_jobs(tenant_id, dedupe_key)
  WHERE dedupe_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_campaign record;
  v_member record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  v_phone text;
  v_message text;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_member IN
      SELECT sm.customer_id
      FROM public.crm_segment_members sm
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, status)
      VALUES (v_campaign.id, v_member.customer_id, 'queued')
      ON CONFLICT (campaign_id, customer_id) DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;

      SELECT COALESCE(u.raw_user_meta_data->>'phone', u.phone) INTO v_phone
      FROM auth.users u WHERE u.id = v_member.customer_id;
      v_message := replace(replace(v_campaign.template, '{{customer_id}}', v_member.customer_id::text), '{{campaign_name}}', v_campaign.name);
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_member.customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_phone, 'message', v_message),
        'crm:' || v_campaign.id::text || ':' || v_member.customer_id::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) TO service_role;

-- ===== END SOURCE: 20260826020000_crm_notification_dispatch.sql =====

-- ===== BEGIN SOURCE: 20260826020000_marketplace_partial_fulfillment.sql =====
CREATE TABLE IF NOT EXISTS public.marketplace_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  tracking_number text,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(merchant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.marketplace_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.marketplace_shipments(id) ON DELETE CASCADE,
  order_item_id uuid NOT NULL REFERENCES public.order_items(id) ON DELETE RESTRICT,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(shipment_id, order_item_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipments_order ON public.marketplace_shipments(order_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipment_items_order_item ON public.marketplace_shipment_items(order_item_id);
ALTER TABLE public.marketplace_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyer views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Buyer views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Merchant views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Merchant views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Buyer views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Buyer views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid())));
DROP POLICY IF EXISTS "Merchant views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Merchant views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.create_marketplace_shipment(p_order_id uuid, p_items jsonb, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_merchant_id uuid; v_shipment_id uuid; v_input jsonb; v_item public.order_items%ROWTYPE; v_product_id uuid; v_order_item_id uuid; v_qty integer; v_shipped integer; v_total integer := 0; v_number text;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid shipment request' USING ERRCODE = '22023'; END IF;
  SELECT o.* INTO v_order
  FROM public.orders o
  JOIN public.merchants m ON m.id = o.merchant_id
  WHERE o.id = p_order_id AND m.user_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  v_merchant_id := v_order.merchant_id;
  v_number := 'SHP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  INSERT INTO public.marketplace_shipments(order_id, merchant_id, shipment_number, tracking_number) VALUES (p_order_id, v_merchant_id, v_number, NULLIF(trim(p_tracking_number), '')) RETURNING id INTO v_shipment_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_order_item_id := NULLIF(v_input->>'order_item_id', '')::uuid; v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_order_item_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid shipment item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_item FROM public.order_items WHERE id = v_order_item_id AND order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(sum(quantity), 0) INTO v_shipped FROM public.marketplace_shipment_items si JOIN public.marketplace_shipments s ON s.id = si.shipment_id WHERE si.order_item_id = v_order_item_id AND s.status <> 'cancelled';
    IF v_shipped + v_qty > v_item.quantity THEN RAISE EXCEPTION 'Shipment quantity exceeds order quantity' USING ERRCODE = '23514'; END IF;
    v_product_id := NULLIF(v_item.product_id::text, '')::uuid;
    INSERT INTO public.marketplace_shipment_items(shipment_id, order_item_id, product_id, quantity) VALUES (v_shipment_id, v_order_item_id, v_product_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('id', v_shipment_id, 'shipment_number', v_number, 'quantity', v_total, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.update_marketplace_shipment_status(p_shipment_id uuid, p_status text, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_shipment public.marketplace_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_status NOT IN ('pending','processing','packed','shipped','delivered','cancelled') THEN RAISE EXCEPTION 'Invalid shipment status' USING ERRCODE = '22023'; END IF;
  SELECT s.* INTO v_shipment FROM public.marketplace_shipments s WHERE s.id = p_shipment_id AND (s.merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  UPDATE public.marketplace_shipments SET status = p_status, tracking_number = COALESCE(NULLIF(trim(p_tracking_number), ''), tracking_number), shipped_at = CASE WHEN p_status = 'shipped' AND shipped_at IS NULL THEN now() ELSE shipped_at END, delivered_at = CASE WHEN p_status = 'delivered' AND delivered_at IS NULL THEN now() ELSE delivered_at END WHERE id = p_shipment_id;
  RETURN jsonb_build_object('id', p_shipment_id, 'status', p_status);
END; $$;
REVOKE ALL ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) TO authenticated;

-- ===== END SOURCE: 20260826020000_marketplace_partial_fulfillment.sql =====

-- ===== BEGIN SOURCE: 20260826030000_merchant_import_commit_rollback.sql =====
CREATE TABLE IF NOT EXISTS public.merchant_product_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','validated','committed','rolled_back','failed')),
  row_count integer NOT NULL DEFAULT 0 CHECK (row_count >= 0),
  valid_count integer NOT NULL DEFAULT 0 CHECK (valid_count >= 0),
  error_count integer NOT NULL DEFAULT 0 CHECK (error_count >= 0),
  inserted_product_ids uuid[] NOT NULL DEFAULT '{}',
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  rolled_back_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_merchant_product_import_jobs_merchant ON public.merchant_product_import_jobs(merchant_id, created_at DESC);
ALTER TABLE public.merchant_product_import_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Merchant manages own product import jobs" ON public.merchant_product_import_jobs;
CREATE POLICY "Merchant manages own product import jobs" ON public.merchant_product_import_jobs FOR ALL TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());

CREATE OR REPLACE FUNCTION public.commit_merchant_product_import(p_merchant_id uuid, p_rows jsonb, p_validation_errors jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job_id uuid; v_ids uuid[] := '{}'; v_row jsonb; v_product_id uuid; v_count integer := 0; v_errors integer := jsonb_array_length(COALESCE(p_validation_errors, '[]'::jsonb));
BEGIN
  IF auth.uid() IS NULL OR NOT (p_merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN RAISE EXCEPTION 'Import access denied or invalid rows' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.merchant_product_import_jobs(merchant_id, created_by, status, row_count, valid_count, error_count, validation_errors) VALUES (p_merchant_id, auth.uid(), 'validated', jsonb_array_length(p_rows) + v_errors, jsonb_array_length(p_rows), v_errors, COALESCE(p_validation_errors, '[]'::jsonb)) RETURNING id INTO v_job_id;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    IF NULLIF(trim(v_row->>'name'), '') IS NULL OR COALESCE((v_row->>'price')::numeric, 0) <= 0 OR COALESCE((v_row->>'stock')::integer, -1) < 0 THEN RAISE EXCEPTION 'Invalid product import row' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.products(merchant_id, name, description, price, stock, category, is_active, is_promo) VALUES (p_merchant_id, trim(v_row->>'name'), NULLIF(v_row->>'description', ''), (v_row->>'price')::numeric, (v_row->>'stock')::integer, trim(v_row->>'category'), COALESCE((v_row->>'is_active')::boolean, true), COALESCE((v_row->>'is_promo')::boolean, false)) RETURNING id INTO v_product_id;
    v_ids := array_append(v_ids, v_product_id); v_count := v_count + 1;
  END LOOP;
  UPDATE public.merchant_product_import_jobs SET status = 'committed', inserted_product_ids = v_ids, committed_at = now() WHERE id = v_job_id;
  RETURN jsonb_build_object('job_id', v_job_id, 'status', 'committed', 'inserted_count', v_count);
EXCEPTION WHEN OTHERS THEN
  IF v_job_id IS NOT NULL THEN UPDATE public.merchant_product_import_jobs SET status = 'failed' WHERE id = v_job_id; END IF;
  RAISE;
END; $$;

CREATE OR REPLACE FUNCTION public.rollback_merchant_product_import(p_job_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.merchant_product_import_jobs%ROWTYPE; v_deleted integer := 0;
BEGIN
  SELECT * INTO v_job FROM public.merchant_product_import_jobs WHERE id = p_job_id AND (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'committed' THEN RAISE EXCEPTION 'Import rollback not available' USING ERRCODE = '55000'; END IF;
  DELETE FROM public.products WHERE id = ANY(v_job.inserted_product_ids) AND merchant_id = v_job.merchant_id AND created_at >= v_job.committed_at;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  UPDATE public.merchant_product_import_jobs SET status = 'rolled_back', rolled_back_at = now() WHERE id = v_job.id;
  RETURN jsonb_build_object('job_id', p_job_id, 'status', 'rolled_back', 'deleted_count', v_deleted);
END; $$;
REVOKE ALL ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rollback_merchant_product_import(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.commit_merchant_product_import(uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_merchant_product_import(uuid) TO authenticated;

-- ===== END SOURCE: 20260826030000_merchant_import_commit_rollback.sql =====

-- ===== BEGIN SOURCE: 20260826030000_pos_customer_crm_identity.sql =====
-- Unify POS customers with CRM while keeping legacy auth-user references compatible.
ALTER TABLE public.pos_customers
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_customers_tenant_auth_user
  ON public.pos_customers(tenant_id, auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pos_customers_tenant_phone
  ON public.pos_customers(tenant_id, phone) WHERE phone IS NOT NULL;

ALTER TABLE public.crm_segment_members DROP CONSTRAINT IF EXISTS crm_segment_members_pkey;
ALTER TABLE public.crm_segment_members
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_segment_members
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_auth
  ON public.crm_segment_members(segment_id, customer_id) WHERE customer_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_segment_members_pos
  ON public.crm_segment_members(segment_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL;
ALTER TABLE public.crm_segment_members
  DROP CONSTRAINT IF EXISTS crm_segment_members_target_check;
ALTER TABLE public.crm_segment_members
  ADD CONSTRAINT crm_segment_members_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.crm_campaign_deliveries
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_campaign_deliveries
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_campaign_deliveries_pos
  ON public.crm_campaign_deliveries(campaign_id, pos_customer_id) WHERE pos_customer_id IS NOT NULL;
ALTER TABLE public.crm_campaign_deliveries
  DROP CONSTRAINT IF EXISTS crm_campaign_deliveries_target_check;
ALTER TABLE public.crm_campaign_deliveries
  ADD CONSTRAINT crm_campaign_deliveries_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.crm_abandoned_carts
  ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE public.crm_abandoned_carts
  ADD COLUMN IF NOT EXISTS pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
ALTER TABLE public.crm_abandoned_carts
  DROP CONSTRAINT IF EXISTS crm_abandoned_carts_target_check;
ALTER TABLE public.crm_abandoned_carts
  ADD CONSTRAINT crm_abandoned_carts_target_check CHECK (customer_id IS NOT NULL OR pos_customer_id IS NOT NULL);

ALTER TABLE public.notification_delivery_jobs
  ALTER COLUMN recipient_id DROP NOT NULL;
ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS recipient_pos_customer_id uuid REFERENCES public.pos_customers(id) ON DELETE CASCADE;
ALTER TABLE public.notification_delivery_jobs
  DROP CONSTRAINT IF EXISTS notification_delivery_jobs_recipient_check;
ALTER TABLE public.notification_delivery_jobs
  ADD CONSTRAINT notification_delivery_jobs_recipient_check CHECK (recipient_id IS NOT NULL OR recipient_pos_customer_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_pos_recipient
  ON public.notification_delivery_jobs(recipient_pos_customer_id, created_at DESC);

DROP POLICY IF EXISTS "Users view own notification jobs" ON public.notification_delivery_jobs;
CREATE POLICY "Users view own notification jobs" ON public.notification_delivery_jobs FOR SELECT TO authenticated
  USING (
    recipient_id = auth.uid()
    OR recipient_pos_customer_id IN (SELECT id FROM public.pos_customers WHERE auth_user_id = auth.uid())
    OR public.is_admin()
  );

CREATE OR REPLACE FUNCTION public.enqueue_due_crm_campaign_jobs(p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_campaign record;
  v_target record;
  v_delivery_id uuid;
  v_job_id uuid;
  v_queued integer := 0;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'CRM dispatcher requires admin or service role' USING ERRCODE = '42501';
  END IF;
  FOR v_campaign IN
    SELECT c.* FROM public.crm_campaigns c
    WHERE c.status = 'scheduled' AND COALESCE(c.scheduled_at, now()) <= now()
    ORDER BY COALESCE(c.scheduled_at, c.created_at)
    LIMIT v_limit FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_target IN
      SELECT sm.customer_id, NULL::uuid AS pos_customer_id, COALESCE(u.raw_user_meta_data->>'phone', u.phone) AS phone
      FROM public.crm_segment_members sm JOIN auth.users u ON u.id = sm.customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id
      UNION ALL
      SELECT NULL::uuid, sm.pos_customer_id, pc.phone
      FROM public.crm_segment_members sm JOIN public.pos_customers pc ON pc.id = sm.pos_customer_id
      WHERE v_campaign.segment_id IS NOT NULL AND sm.segment_id = v_campaign.segment_id AND pc.is_active = true
    LOOP
      INSERT INTO public.crm_campaign_deliveries(campaign_id, customer_id, pos_customer_id, status)
      VALUES (v_campaign.id, v_target.customer_id, v_target.pos_customer_id, 'queued')
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_delivery_id;
      IF v_delivery_id IS NULL THEN CONTINUE; END IF;
      INSERT INTO public.notification_delivery_jobs(
        tenant_id, recipient_id, recipient_pos_customer_id, channel, template_key, payload, dedupe_key
      ) VALUES (
        v_campaign.tenant_id, v_target.customer_id, v_target.pos_customer_id, v_campaign.channel, 'crm_campaign',
        jsonb_build_object('campaign_id', v_campaign.id, 'delivery_id', v_delivery_id, 'to', v_target.phone, 'message', v_campaign.template),
        'crm:' || v_campaign.id::text || ':' || COALESCE(v_target.customer_id, v_target.pos_customer_id)::text
      )
      ON CONFLICT (tenant_id, dedupe_key) DO NOTHING
      RETURNING id INTO v_job_id;
      IF v_job_id IS NOT NULL THEN v_queued := v_queued + 1; END IF;
    END LOOP;
    UPDATE public.crm_campaigns SET status = 'sending' WHERE id = v_campaign.id;
  END LOOP;
  RETURN jsonb_build_object('queued', v_queued);
END; $$;

CREATE OR REPLACE FUNCTION public.mark_crm_cart_recovered_after_pos_sale()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE public.crm_abandoned_carts
    SET recovered_at = now()
    WHERE tenant_id = NEW.tenant_id
      AND (customer_id = NEW.customer_id OR pos_customer_id = NEW.customer_id)
      AND recovered_at IS NULL;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_mark_crm_cart_recovered ON public.pos_sales;
CREATE TRIGGER trg_mark_crm_cart_recovered
AFTER INSERT ON public.pos_sales FOR EACH ROW EXECUTE FUNCTION public.mark_crm_cart_recovered_after_pos_sale();

-- Best-effort deterministic backfill for existing customers. Ambiguous emails remain unmapped.
UPDATE public.pos_customers pc
SET auth_user_id = u.id
FROM auth.users u
WHERE pc.auth_user_id IS NULL
  AND pc.email IS NOT NULL
  AND lower(trim(pc.email)) = lower(trim(u.email))
  AND NOT EXISTS (
    SELECT 1 FROM public.pos_customers occupied
    WHERE occupied.tenant_id = pc.tenant_id AND occupied.auth_user_id = u.id
  );

-- ===== END SOURCE: 20260826030000_pos_customer_crm_identity.sql =====

-- ===== BEGIN SOURCE: 20260827090000_atomic_pricebook_admin_rpc.sql =====
-- Atomic admin operation for price-book header plus its first item.
CREATE OR REPLACE FUNCTION public.create_pos_price_book(
  p_tenant_id uuid,
  p_name text,
  p_customer_segment text,
  p_outlet_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_priority integer,
  p_product_id uuid,
  p_variant_id uuid,
  p_price numeric
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_book_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.pos_tenants WHERE id = p_tenant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Price book administration denied' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Invalid price book input' USING ERRCODE = '22023';
  END IF;
  IF p_customer_segment NOT IN ('retail','wholesale','reseller','member','outlet') THEN
    RAISE EXCEPTION 'Invalid customer segment' USING ERRCODE = '22023';
  END IF;
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at < p_starts_at THEN
    RAISE EXCEPTION 'Price book end date precedes start date' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id AND is_active = true) THEN
    RAISE EXCEPTION 'Product does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  IF p_outlet_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_price_books(tenant_id, name, customer_segment, outlet_id, starts_at, ends_at, priority, created_by)
  VALUES (p_tenant_id, trim(p_name), p_customer_segment, p_outlet_id, p_starts_at, p_ends_at, COALESCE(p_priority, 0), auth.uid())
  RETURNING id INTO v_book_id;
  INSERT INTO public.pos_price_book_items(price_book_id, product_id, variant_id, price)
  VALUES (v_book_id, p_product_id, p_variant_id, p_price);
  RETURN v_book_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) TO authenticated;

-- ===== END SOURCE: 20260827090000_atomic_pricebook_admin_rpc.sql =====

-- ===== BEGIN SOURCE: 20260827100000_refund_approval_workflow_rpc.sql =====
CREATE OR REPLACE FUNCTION public.decide_refund_request(
  p_request_id uuid,
  p_approve boolean,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_request public.refund_requests%ROWTYPE;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Refund approval denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_request FROM public.refund_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund request not found' USING ERRCODE = 'P0002'; END IF;
  IF upper(COALESCE(v_request.status, '')) <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund request is no longer pending' USING ERRCODE = '55000';
  END IF;
  v_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  UPDATE public.refund_requests
  SET status = v_status,
      admin_notes = NULLIF(trim(p_notes), ''),
      processed_at = now()
  WHERE id = p_request_id;
  RETURN jsonb_build_object('id', p_request_id, 'status', v_status, 'processed_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.decide_refund_request(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_refund_request(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260827100000_refund_approval_workflow_rpc.sql =====

-- ===== BEGIN SOURCE: 20260827110000_atomic_stock_transfer_approval.sql =====
CREATE OR REPLACE FUNCTION public.create_pos_stock_transfer(
  p_tenant_id uuid,
  p_transfer_number text,
  p_from_outlet_id uuid,
  p_to_outlet_id uuid,
  p_notes text,
  p_items jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer_id uuid;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true
    UNION ALL SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Transfer creation denied' USING ERRCODE = '42501'; END IF;
  IF p_from_outlet_id = p_to_outlet_id OR NULLIF(trim(p_transfer_number), '') IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock transfer' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_from_outlet_id AND tenant_id = p_tenant_id)
     OR NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_to_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Transfer outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_transfers(tenant_id, transfer_number, from_outlet_id, to_outlet_id, status, notes, requested_by)
  VALUES (p_tenant_id, trim(p_transfer_number), p_from_outlet_id, p_to_outlet_id, 'pending', NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'qty_requested')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid transfer quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.pos_products WHERE id = (v_item->>'product_id')::uuid AND tenant_id = p_tenant_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer product does not belong to tenant' USING ERRCODE = '42501'; END IF;
    INSERT INTO public.pos_stock_transfer_items(transfer_id, product_id, variant_id, product_name, sku, unit, qty_requested, qty_sent, qty_received)
    VALUES (v_transfer_id, v_product.id, NULLIF(v_item->>'variant_id', '')::uuid, v_product.name, v_product.sku, COALESCE(v_product.unit, 'pcs'), v_qty, 0, 0);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_transfer(p_transfer_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_transfer public.pos_stock_transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Transfer approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'pending' THEN RAISE EXCEPTION 'Transfer is no longer pending' USING ERRCODE = '55000'; END IF;
  IF p_approve THEN
    UPDATE public.pos_stock_transfers SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_transfer_id;
  ELSE
    UPDATE public.pos_stock_transfers SET status = 'rejected', rejection_reason = COALESCE(NULLIF(trim(p_reason), ''), 'Ditolak supervisor') WHERE id = p_transfer_id;
  END IF;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END);
END; $$;

CREATE OR REPLACE FUNCTION public.complete_pos_stock_transfer(p_transfer_id uuid, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer public.pos_stock_transfers%ROWTYPE;
  v_transfer_item public.pos_stock_transfer_items%ROWTYPE;
  v_input jsonb;
  v_source public.pos_stock%ROWTYPE;
  v_destination public.pos_stock%ROWTYPE;
  v_sent numeric;
  v_received numeric;
  v_after numeric;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid()) OR (public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.from_outlet_id) AND public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.to_outlet_id))) THEN
    RAISE EXCEPTION 'Transfer completion denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'approved' OR jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'Transfer is not ready for completion' USING ERRCODE = '55000'; END IF;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_transfer_item FROM public.pos_stock_transfer_items WHERE id = (v_input->>'item_id')::uuid AND transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer item not found' USING ERRCODE = 'P0002'; END IF;
    v_sent := COALESCE((v_input->>'qty_sent')::numeric, v_transfer_item.qty_requested);
    v_received := COALESCE((v_input->>'qty_received')::numeric, v_sent);
    IF v_sent <= 0 OR v_received < 0 OR v_received > v_sent OR v_sent > v_transfer_item.qty_requested THEN RAISE EXCEPTION 'Invalid transfer receive quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.from_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_sent THEN RAISE EXCEPTION 'Insufficient source stock for transfer' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_sent;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.from_outlet_id, 'transfer_out', -v_sent, v_source.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer keluar', auth.uid());
    SELECT * INTO v_destination FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.to_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_destination.quantity + v_received;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_destination.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, 'transfer_in', v_received, v_destination.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer masuk', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock) VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, v_received, 0);
    END IF;
    UPDATE public.pos_stock_transfer_items SET qty_sent = v_sent, qty_received = v_received WHERE id = v_transfer_item.id;
  END LOOP;
  UPDATE public.pos_stock_transfers SET status = 'completed', completed_by = auth.uid(), completed_at = now() WHERE id = p_transfer_id;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', 'completed');
END; $$;

REVOKE ALL ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) TO authenticated;

-- ===== END SOURCE: 20260827110000_atomic_stock_transfer_approval.sql =====

-- ===== BEGIN SOURCE: 20260827120000_stock_adjustment_approval_rpc.sql =====
ALTER TABLE public.approval_requests ADD COLUMN IF NOT EXISTS request_context jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.request_pos_stock_adjustment(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_stock public.pos_stock%ROWTYPE; v_request_id uuid; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid stock adjustment request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE CASE WHEN p_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment cannot reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.approval_requests(tenant_id, requester_id, request_type, subject_id, requested_amount, reason, request_context)
  VALUES (p_tenant_id, auth.uid(), 'stock_adjustment', p_stock_id, p_quantity, COALESCE(NULLIF(trim(p_notes), ''), 'Stock adjustment requires approval'), jsonb_build_object('type', p_type, 'notes', NULLIF(trim(p_notes), ''), 'outlet_id', p_outlet_id, 'quantity_before', v_stock.quantity, 'quantity_after_requested', v_after))
  RETURNING id INTO v_request_id;
  RETURN jsonb_build_object('request_id', v_request_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_adjustment(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_stock public.pos_stock%ROWTYPE; v_type text; v_after numeric; v_delta numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Stock adjustment approval denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id AND request_type = 'stock_adjustment' FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Stock adjustment approval is not pending' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.approval_requests SET status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  v_type := v_request.request_context->>'type';
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_request.subject_id AND tenant_id = v_request.tenant_id FOR UPDATE;
  IF NOT FOUND OR v_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN RAISE EXCEPTION 'Stock adjustment target is invalid' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN v_type = 'adjustment' THEN v_request.requested_amount ELSE CASE WHEN v_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + v_request.requested_amount ELSE v_stock.quantity - v_request.requested_amount END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment would reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;
  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, notes, created_by, reference_id, reference_type)
  VALUES (v_request.tenant_id, v_stock.product_id, v_stock.variant_id, (v_request.request_context->>'outlet_id')::uuid, v_type, v_delta, v_stock.quantity, v_after, COALESCE(NULLIF(trim(p_notes), ''), v_request.reason), auth.uid(), p_request_id, 'stock_adjustment_approval');
  UPDATE public.approval_requests SET status = 'approved', approved_level = required_level, decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) TO authenticated;

-- ===== END SOURCE: 20260827120000_stock_adjustment_approval_rpc.sql =====

-- ===== BEGIN SOURCE: 20260827180000_add_cashback_tables.sql =====
-- SaDesa cashback rules and ledger
-- Safe to replay: all objects and policies are guarded or recreated by name.

CREATE TABLE IF NOT EXISTS public.cashback_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  cashback_percent numeric(5,2) NOT NULL,
  min_order_amount numeric(14,2) NOT NULL DEFAULT 0,
  max_cashback numeric(14,2),
  category text,
  is_active boolean NOT NULL DEFAULT true,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cashback_rules_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT cashback_rules_percent_range CHECK (cashback_percent > 0 AND cashback_percent <= 50),
  CONSTRAINT cashback_rules_min_order_non_negative CHECK (min_order_amount >= 0),
  CONSTRAINT cashback_rules_max_positive CHECK (max_cashback IS NULL OR max_cashback > 0),
  CONSTRAINT cashback_rules_valid_period CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE INDEX IF NOT EXISTS cashback_rules_active_period_idx
  ON public.cashback_rules (is_active, valid_from, valid_until);

CREATE TABLE IF NOT EXISTS public.cashback_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  rule_id uuid REFERENCES public.cashback_rules(id) ON DELETE SET NULL,
  amount numeric(14,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  CONSTRAINT cashback_transactions_amount_positive CHECK (amount > 0),
  CONSTRAINT cashback_transactions_status_valid CHECK (status IN ('pending', 'confirmed', 'cancelled', 'reversed'))
);

CREATE INDEX IF NOT EXISTS cashback_transactions_user_created_idx
  ON public.cashback_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cashback_transactions_status_idx
  ON public.cashback_transactions (status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS cashback_transactions_order_rule_unique_idx
  ON public.cashback_transactions (order_id, rule_id)
  WHERE order_id IS NOT NULL AND rule_id IS NOT NULL AND status <> 'reversed';

GRANT SELECT ON public.cashback_rules TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cashback_rules TO authenticated;
GRANT SELECT ON public.cashback_transactions TO authenticated;
GRANT ALL ON public.cashback_rules, public.cashback_transactions TO service_role;

ALTER TABLE public.cashback_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cashback_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view active cashback rules" ON public.cashback_rules;
CREATE POLICY "Public can view active cashback rules"
  ON public.cashback_rules FOR SELECT
  TO anon, authenticated
  USING (is_active = true AND valid_from <= now() AND (valid_until IS NULL OR valid_until >= now()));

DROP POLICY IF EXISTS "Admins can manage cashback rules" ON public.cashback_rules;
CREATE POLICY "Admins can manage cashback rules"
  ON public.cashback_rules FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Users can view own cashback transactions" ON public.cashback_transactions;
CREATE POLICY "Users can view own cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view cashback transactions" ON public.cashback_transactions;
CREATE POLICY "Admins can view cashback transactions"
  ON public.cashback_transactions FOR SELECT
  TO authenticated
  USING (public.is_admin());

COMMENT ON TABLE public.cashback_rules IS 'Database-backed cashback programs managed by SaDesa administrators.';
COMMENT ON TABLE public.cashback_transactions IS 'Cashback ledger for buyer awards and reversals.';

-- ===== END SOURCE: 20260827180000_add_cashback_tables.sql =====

-- ===== BEGIN SOURCE: 20260828100000_pwa_device_management.sql =====
CREATE TABLE IF NOT EXISTS public.pwa_device_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT 'Perangkat PWA',
  device_type text NOT NULL DEFAULT 'browser' CHECK (device_type IN ('browser','pwa','kiosk')),
  platform text,
  user_agent text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','idle','revoked')),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  last_sync_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_user ON public.pwa_device_sessions(user_id, status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_tenant ON public.pwa_device_sessions(tenant_id, status, last_seen_at DESC);
ALTER TABLE public.pwa_device_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Users view own PWA devices" ON public.pwa_device_sessions FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Admins manage PWA devices" ON public.pwa_device_sessions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true) OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pwa_device_sessions(user_id, tenant_id, device_id, device_name, device_type, platform, user_agent, status, last_seen_at, revoked_at, revoked_by)
  VALUES (auth.uid(), p_tenant_id, trim(p_device_id), COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'), p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''), 'active', now(), NULL, NULL)
  ON CONFLICT (user_id, device_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent, status = 'active', last_seen_at = now(), revoked_at = NULL, revoked_by = NULL, updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.heartbeat_pwa_device(p_device_id text, p_sync_at timestamptz DEFAULT NULL)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_device FROM public.pwa_device_sessions WHERE user_id = auth.uid() AND device_id = trim(p_device_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'PWA device is not registered' USING ERRCODE = 'P0002'; END IF;
  IF v_device.status <> 'revoked' THEN
    UPDATE public.pwa_device_sessions SET status = 'active', last_seen_at = now(), last_sync_at = COALESCE(p_sync_at, last_sync_at), updated_at = now() WHERE id = v_device.id RETURNING * INTO v_device;
  END IF;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.revoke_pwa_device(p_device_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Device revoke requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.pwa_device_sessions SET status = 'revoked', revoked_at = now(), revoked_by = auth.uid(), updated_at = now() WHERE id = p_device_session_id AND status <> 'revoked';
  IF NOT FOUND THEN RAISE EXCEPTION 'Device not found or already revoked' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('device_id', p_device_session_id, 'status', 'revoked');
END; $$;

REVOKE ALL ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_pwa_device(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_pwa_device(uuid) TO authenticated;

-- ===== END SOURCE: 20260828100000_pwa_device_management.sql =====

-- ===== BEGIN SOURCE: 20260828160000_pos_payment_invariants.sql =====
-- Enforce payment invariants for every POS sale, including writes outside the checkout RPC.
CREATE OR REPLACE FUNCTION public.validate_pos_sale_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.total IS NULL OR NEW.total < 0 THEN
    RAISE EXCEPTION 'POS sale total must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.payment_amount IS NULL OR NEW.payment_amount < 0 THEN
    RAISE EXCEPTION 'POS payment amount must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.change_amount IS NULL OR NEW.change_amount < 0 THEN
    RAISE EXCEPTION 'POS change amount must be non-negative' USING ERRCODE = '22023';
  END IF;

  IF NEW.payment_method = 'cash' THEN
    IF NEW.payment_amount < NEW.total OR NEW.change_amount <> NEW.payment_amount - NEW.total THEN
      RAISE EXCEPTION 'Cash payment and change do not match sale total' USING ERRCODE = '22023';
    END IF;
  ELSIF NEW.payment_method IN ('qris', 'transfer', 'debit', 'credit', 'split') THEN
    IF NEW.payment_amount <> NEW.total OR NEW.change_amount <> 0 THEN
      RAISE EXCEPTION 'Non-cash payment must equal sale total with zero change' USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported POS payment method' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_payment ON public.pos_sales;
CREATE TRIGGER trg_validate_pos_sale_payment
BEFORE INSERT OR UPDATE OF total, payment_method, payment_amount, change_amount
ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_payment();

REVOKE ALL ON FUNCTION public.validate_pos_sale_payment() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_payment() TO service_role;

-- ===== END SOURCE: 20260828160000_pos_payment_invariants.sql =====

-- ===== BEGIN SOURCE: 20260828170000_pos_authorization_checkout_hardening.sql =====
-- POS authorization and checkout invariants.
-- This migration is safe to re-run and keeps enforcement in the database.

CREATE OR REPLACE FUNCTION public.pos_user_has_role(
  p_tenant_id uuid,
  p_roles text[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = p_tenant_id
      AND t.user_id = auth.uid()
      AND 'owner' = ANY(p_roles)
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_users u
    WHERE u.tenant_id = p_tenant_id
      AND u.user_id = auth.uid()
      AND u.is_active = true
      AND u.role = ANY(p_roles)
  );
$$;

REVOKE ALL ON FUNCTION public.pos_user_has_role(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pos_user_has_role(uuid, text[]) TO authenticated;

-- Sale item visibility must follow the parent sale's assigned outlet.
DROP POLICY IF EXISTS "tenant_users_select_sale_items" ON public.pos_sale_items;
DROP POLICY IF EXISTS "POS users can view assigned sale items" ON public.pos_sale_items;
CREATE POLICY "POS users can view assigned sale items"
  ON public.pos_sale_items
  FOR SELECT TO authenticated
  USING (
    sale_id IN (
      SELECT s.id
      FROM public.pos_sales s
      WHERE public.pos_user_can_access_outlet(s.tenant_id, s.outlet_id)
    )
  );

-- Reject malformed financial line values regardless of whether they came from
-- the checkout RPC or an administrative write path.
CREATE OR REPLACE FUNCTION public.validate_pos_sale_item_values()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.qty IS NULL OR NEW.qty <= 0 THEN
    RAISE EXCEPTION 'POS sale item quantity must be positive' USING ERRCODE = '22023';
  END IF;
  IF NEW.price IS NULL OR NEW.price < 0 THEN
    RAISE EXCEPTION 'POS sale item price must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(NEW.discount, 0) < 0 OR COALESCE(NEW.tax_amount, 0) < 0 THEN
    RAISE EXCEPTION 'POS sale item discount and tax must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.subtotal IS NULL OR NEW.subtotal < 0 THEN
    RAISE EXCEPTION 'POS sale item subtotal must be non-negative' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_item_values ON public.pos_sale_items;
CREATE TRIGGER trg_validate_pos_sale_item_values
BEFORE INSERT OR UPDATE OF qty, price, discount, tax_amount, subtotal
ON public.pos_sale_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_item_values();

REVOKE ALL ON FUNCTION public.validate_pos_sale_item_values() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_item_values() TO service_role;

-- ===== END SOURCE: 20260828170000_pos_authorization_checkout_hardening.sql =====

-- ===== BEGIN SOURCE: 20260828180000_pos_concurrency_hardening.sql =====
-- Concurrency hardening for POS voucher redemption, cash sessions, and returns.

CREATE OR REPLACE FUNCTION public.validate_pos_cash_session_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep service-role/batch imports compatible while enforcing browser actors.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.cashier_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cash session cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_has_role(NEW.tenant_id, ARRAY['owner', 'manager', 'kasir']::text[]) THEN
    RAISE EXCEPTION 'POS role cannot open cash session' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_cash_session_actor ON public.pos_cash_sessions;
CREATE TRIGGER trg_validate_pos_cash_session_actor
BEFORE INSERT ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_cash_session_actor();

REVOKE ALL ON FUNCTION public.validate_pos_cash_session_actor() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_cash_session_actor() TO service_role;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_voucher_usage_sale_once
  ON public.pos_voucher_usages(voucher_id, sale_id)
  WHERE sale_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_returns_total_refund_nonnegative') THEN
    ALTER TABLE public.pos_sale_returns ADD CONSTRAINT pos_sale_returns_total_refund_nonnegative CHECK (total_refund >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_qty_positive') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_qty_positive CHECK (qty > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_values_nonnegative') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_values_nonnegative CHECK (price >= 0 AND subtotal >= 0);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
BEGIN
  SELECT * INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id
    AND tenant_id = NEW.tenant_id
    AND outlet_id = NEW.outlet_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Return sale does not belong to tenant and outlet' USING ERRCODE = '42501';
  END IF;
  IF v_sale.status NOT IN ('completed', 'refunded', 'partially_refunded') THEN
    RAISE EXCEPTION 'Only completed POS sales can be returned' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_context ON public.pos_sale_returns;
CREATE TRIGGER trg_validate_pos_sale_return_context
BEFORE INSERT OR UPDATE OF sale_id, tenant_id, outlet_id
ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_context();

CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_item_quantity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed numeric;
  v_returned numeric;
BEGIN
  SELECT si.qty INTO v_allowed
  FROM public.pos_sale_items si
  WHERE si.id = NEW.sale_item_id
    AND si.sale_id = (SELECT sale_id FROM public.pos_sale_returns WHERE id = NEW.return_id)
  FOR UPDATE;
  IF v_allowed IS NULL THEN
    RAISE EXCEPTION 'Return item does not belong to original sale' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(ri.qty), 0) INTO v_returned
  FROM public.pos_sale_return_items ri
  WHERE ri.sale_item_id = NEW.sale_item_id
    AND ri.return_id <> NEW.return_id;
  IF NEW.qty > v_allowed - v_returned THEN
    RAISE EXCEPTION 'Return quantity exceeds purchased quantity' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_item_quantity ON public.pos_sale_return_items;
CREATE TRIGGER trg_validate_pos_sale_return_item_quantity
BEFORE INSERT OR UPDATE OF return_id, sale_item_id, qty
ON public.pos_sale_return_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_item_quantity();

REVOKE ALL ON FUNCTION public.validate_pos_sale_return_context() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_sale_return_item_quantity() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_context() TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_item_quantity() TO service_role;

-- ===== END SOURCE: 20260828180000_pos_concurrency_hardening.sql =====

-- ===== BEGIN SOURCE: 20260828190000_pos_audit_trail_hardening.sql =====
-- Server-side audit trail for critical POS mutations.

CREATE INDEX IF NOT EXISTS idx_pos_audit_logs_entity_lookup
  ON public.pos_audit_logs(tenant_id, module, entity_type, entity_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.write_pos_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row jsonb;
  v_old jsonb;
  v_tenant_id uuid;
  v_outlet_id uuid;
  v_entity_id text;
  v_action text;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_old := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END;
  v_tenant_id := NULLIF(v_row->>'tenant_id', '')::uuid;
  v_outlet_id := NULLIF(v_row->>'outlet_id', '')::uuid;
  v_entity_id := COALESCE(v_row->>'id', v_row->>'sale_id', v_row->>'session_id');
  v_action := lower(TG_OP);

  IF v_tenant_id IS NOT NULL THEN
    INSERT INTO public.pos_audit_logs(
      tenant_id, outlet_id, user_id, action, module, entity_type,
      entity_id, description, old_values, new_values
    ) VALUES (
      v_tenant_id, v_outlet_id, auth.uid(), v_action, 'pos', TG_TABLE_NAME,
      v_entity_id, format('%s %s', v_action, TG_TABLE_NAME), v_old,
      CASE WHEN TG_OP <> 'DELETE' THEN v_row ELSE NULL END
    );
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_pos_sales ON public.pos_sales;
CREATE TRIGGER trg_audit_pos_sales
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_sale_returns ON public.pos_sale_returns;
CREATE TRIGGER trg_audit_pos_sale_returns
AFTER INSERT OR UPDATE OR DELETE ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_cash_sessions ON public.pos_cash_sessions;
CREATE TRIGGER trg_audit_pos_cash_sessions
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_stock_mutations ON public.pos_stock_mutations;
CREATE TRIGGER trg_audit_pos_stock_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_stock_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

DROP TRIGGER IF EXISTS trg_audit_pos_cash_mutations ON public.pos_cash_mutations;
CREATE TRIGGER trg_audit_pos_cash_mutations
AFTER INSERT OR UPDATE OR DELETE ON public.pos_cash_mutations
FOR EACH ROW EXECUTE FUNCTION public.write_pos_audit_log();

REVOKE ALL ON FUNCTION public.write_pos_audit_log() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_pos_audit_log() TO service_role;

-- ===== END SOURCE: 20260828190000_pos_audit_trail_hardening.sql =====

-- ===== BEGIN SOURCE: 20260829100000_security_privilege_hardening.sql =====
-- SECURITY DEFINER trigger/helper functions must not be callable by browser roles.
-- Their execution is reserved for database triggers or server-side worker paths.
REVOKE ALL ON FUNCTION public.mark_crm_cart_recovered_after_pos_sale() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_due_crm_campaign_jobs(integer) FROM PUBLIC, anon, authenticated;

-- Keep the critical transaction functions callable only by authenticated users
-- after their own tenant/outlet checks; service_role retains ownership access.
REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.earn_pos_loyalty_points(uuid, uuid, numeric, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.redeem_pos_loyalty_points(uuid, uuid, integer, uuid, uuid, text) FROM PUBLIC, anon;

-- ===== END SOURCE: 20260829100000_security_privilege_hardening.sql =====

-- ===== BEGIN SOURCE: 20260829110000_legacy_security_definer_hardening.sql =====
-- Harden legacy SECURITY DEFINER functions created before explicit search_path
-- conventions were applied. Trigger functions are not browser APIs.
ALTER FUNCTION public.check_low_quota_alert() SET search_path = public;
ALTER FUNCTION public.increment_product_view(uuid) SET search_path = public;
ALTER FUNCTION public.auto_assign_merchant_to_group() SET search_path = public;
ALTER FUNCTION public.auto_assign_village_admin_role() SET search_path = public;
ALTER FUNCTION public.handle_merchant_approval_role() SET search_path = public;

REVOKE ALL ON FUNCTION public.check_low_quota_alert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_merchant_to_group() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_village_admin_role() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_merchant_approval_role() FROM PUBLIC, anon, authenticated;

-- ===== END SOURCE: 20260829110000_legacy_security_definer_hardening.sql =====

-- ===== BEGIN SOURCE: 20260829120000_subscription_entitlements_usage.sql =====
-- Subscription plans, entitlements, invoices, and usage ledger.
-- Safe to replay: all schema objects and policies are guarded.

CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  price numeric(15,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  billing_interval text NOT NULL DEFAULT 'monthly' CHECK (billing_interval IN ('monthly', 'quarterly', 'yearly')),
  trial_days integer NOT NULL DEFAULT 0 CHECK (trial_days >= 0 AND trial_days <= 365),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.subscription_plans(id),
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_plan ON public.merchant_subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_active_merchant
  ON public.merchant_subscriptions(merchant_id, status, expired_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_plan_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES public.subscription_plans(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  entitlement_type text NOT NULL DEFAULT 'limit' CHECK (entitlement_type IN ('boolean', 'limit', 'metered')),
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plan_id, feature_key)
);

CREATE TABLE IF NOT EXISTS public.merchant_subscription_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  source text NOT NULL DEFAULT 'override' CHECK (source IN ('override', 'support', 'migration')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key),
  CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_merchant_entitlements_active
  ON public.merchant_subscription_entitlements(subscription_id, feature_key, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS public.subscription_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text,
  provider_invoice_id text,
  invoice_number text,
  amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'paid', 'void', 'uncollectible', 'failed')),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  due_at timestamptz,
  paid_at timestamptz,
  hosted_invoice_url text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_invoice_id),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_subscription_invoices_subscription
  ON public.subscription_invoices(subscription_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_usage_counters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  used_quantity numeric(20,4) NOT NULL DEFAULT 0 CHECK (used_quantity >= 0),
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, period_start, period_end),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_counters_merchant_period
  ON public.subscription_usage_counters(merchant_id, feature_key, period_start, period_end);

CREATE TABLE IF NOT EXISTS public.subscription_usage_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  quantity numeric(20,4) NOT NULL CHECK (quantity > 0),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  idempotency_key text NOT NULL,
  source_type text NOT NULL DEFAULT 'application',
  source_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, idempotency_key),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_ledger_merchant_created
  ON public.subscription_usage_ledger(merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_feature_period
  ON public.subscription_usage_ledger(subscription_id, feature_key, period_start, period_end, created_at DESC);

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plan_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_subscription_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users view active subscription plans" ON public.subscription_plans;
CREATE POLICY "Authenticated users view active subscription plans"
  ON public.subscription_plans FOR SELECT TO authenticated
  USING (is_active OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription plans" ON public.subscription_plans;
CREATE POLICY "Admins manage subscription plans"
  ON public.subscription_plans FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users view plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Authenticated users view plan entitlements"
  ON public.subscription_plan_entitlements FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.subscription_plans p WHERE p.id = plan_id AND (p.is_active OR public.is_admin())));
DROP POLICY IF EXISTS "Admins manage plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Admins manage plan entitlements"
  ON public.subscription_plan_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Merchants view own subscription entitlements"
  ON public.merchant_subscription_entitlements FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage merchant subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Admins manage merchant subscription entitlements"
  ON public.merchant_subscription_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Merchants view own subscription invoices"
  ON public.subscription_invoices FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Admins manage subscription invoices"
  ON public.subscription_invoices FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Merchants view own usage counters"
  ON public.subscription_usage_counters FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Admins manage usage counters"
  ON public.subscription_usage_counters FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Merchants view own usage ledger"
  ON public.subscription_usage_ledger FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Admins manage usage ledger"
  ON public.subscription_usage_ledger FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.consume_subscription_usage(
  p_merchant_id uuid,
  p_feature_key text,
  p_quantity numeric,
  p_idempotency_key text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_source_type text DEFAULT 'application',
  p_source_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_plan_limit bigint;
  v_override_limit bigint;
  v_enabled boolean;
  v_used numeric(20,4);
  v_counter public.subscription_usage_counters%ROWTYPE;
  v_ledger_id uuid;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NULLIF(trim(p_idempotency_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid subscription usage request' USING ERRCODE = '22023';
  END IF;
  IF p_period_end <= p_period_start THEN
    RAISE EXCEPTION 'Usage period is invalid' USING ERRCODE = '22023';
  END IF;
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Subscription usage access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active subscription found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_subscription.id::text || ':' || p_feature_key || ':' || p_idempotency_key, 0));
  SELECT id, quantity INTO v_ledger_id, v_used
  FROM public.subscription_usage_ledger
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND idempotency_key = p_idempotency_key;
  IF v_ledger_id IS NOT NULL THEN
    RETURN jsonb_build_object('accepted', true, 'idempotent', true, 'ledger_id', v_ledger_id, 'quantity', v_used);
  END IF;

  SELECT spe.enabled, spe.limit_value INTO v_enabled, v_override_limit
  FROM public.merchant_subscription_entitlements spe
  WHERE spe.subscription_id = v_subscription.id
    AND spe.feature_key = p_feature_key
    AND spe.starts_at <= now()
    AND (spe.ends_at IS NULL OR spe.ends_at > now());
  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value INTO v_enabled, v_plan_limit
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id AND spe.feature_key = p_feature_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Feature is not included in subscription' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF COALESCE(v_enabled, false) = false THEN
    RAISE EXCEPTION 'Feature is disabled for subscription' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.subscription_usage_counters(subscription_id, merchant_id, feature_key, period_start, period_end, limit_value)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_period_start, p_period_end, COALESCE(v_override_limit, v_plan_limit))
  ON CONFLICT (subscription_id, feature_key, period_start, period_end) DO NOTHING;
  SELECT * INTO v_counter
  FROM public.subscription_usage_counters
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND period_start = p_period_start AND period_end = p_period_end
  FOR UPDATE;

  IF v_counter.limit_value IS NOT NULL AND v_counter.used_quantity + p_quantity > v_counter.limit_value THEN
    RAISE EXCEPTION 'Subscription usage limit exceeded' USING ERRCODE = '54000';
  END IF;

  UPDATE public.subscription_usage_counters
  SET used_quantity = used_quantity + p_quantity, updated_at = now()
  WHERE id = v_counter.id;
  INSERT INTO public.subscription_usage_ledger(subscription_id, merchant_id, feature_key, quantity, period_start, period_end, idempotency_key, source_type, source_id, metadata)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_quantity, p_period_start, p_period_end, p_idempotency_key, COALESCE(NULLIF(trim(p_source_type), ''), 'application'), p_source_id, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object('accepted', true, 'idempotent', false, 'ledger_id', v_ledger_id, 'used_quantity', v_counter.used_quantity + p_quantity, 'limit_value', v_counter.limit_value);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) TO authenticated, service_role;

-- Seed only the plan catalog; entitlements are intentionally explicit and can be managed by admin UI.
INSERT INTO public.subscription_plans (code, name, description, price, billing_interval, trial_days, sort_order)
VALUES
  ('free', 'Free', 'Operasi marketplace dasar', 0, 'monthly', 0, 10),
  ('starter', 'Starter', 'POS dan laporan operasional', 49000, 'monthly', 14, 20),
  ('growth', 'Growth', 'Inventaris, CRM, dan automation', 149000, 'monthly', 14, 30),
  ('pro', 'Pro', 'Multi-outlet, API, dan analytics lanjutan', 399000, 'monthly', 14, 40)
ON CONFLICT (code) DO NOTHING;

DROP TRIGGER IF EXISTS set_subscription_plans_updated_at ON public.subscription_plans;
CREATE TRIGGER set_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_plan_entitlements_updated_at ON public.subscription_plan_entitlements;
CREATE TRIGGER set_subscription_plan_entitlements_updated_at BEFORE UPDATE ON public.subscription_plan_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_merchant_subscription_entitlements_updated_at ON public.merchant_subscription_entitlements;
CREATE TRIGGER set_merchant_subscription_entitlements_updated_at BEFORE UPDATE ON public.merchant_subscription_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_invoices_updated_at ON public.subscription_invoices;
CREATE TRIGGER set_subscription_invoices_updated_at BEFORE UPDATE ON public.subscription_invoices
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_usage_counters_updated_at ON public.subscription_usage_counters;
CREATE TRIGGER set_subscription_usage_counters_updated_at BEFORE UPDATE ON public.subscription_usage_counters
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ===== END SOURCE: 20260829120000_subscription_entitlements_usage.sql =====

-- ===== BEGIN SOURCE: 20260829130000_subscription_entitlement_enforcement.sql =====
-- Subscription entitlement catalog and server-side resolution.
-- Idempotent and safe to replay. Existing merchant overrides always win.

INSERT INTO public.subscription_plan_entitlements (plan_id, feature_key, entitlement_type, enabled, limit_value, unit)
SELECT p.id, v.feature_key, v.entitlement_type, v.enabled, v.limit_value, v.unit
FROM public.subscription_plans p
JOIN (VALUES
  ('free', 'active_products', 'limit', true, 50::bigint, 'items'),
  ('free', 'pos_devices', 'limit', true, 1::bigint, 'devices'),
  ('free', 'whatsapp_messages', 'metered', true, 0::bigint, 'messages/month'),
  ('free', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('free', 'customer_segments', 'limit', true, 0::bigint, 'segments'),
  ('free', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('free', 'offline_queue', 'limit', true, 20::bigint, 'transactions'),
  ('free', 'reports_history_days', 'limit', true, 30::bigint, 'days'),
  ('free', 'loyalty_rules', 'limit', true, 1::bigint, 'rules'),
  ('starter', 'active_products', 'limit', true, 300::bigint, 'items'),
  ('starter', 'pos_devices', 'limit', true, 2::bigint, 'devices'),
  ('starter', 'whatsapp_messages', 'metered', true, 500::bigint, 'messages/month'),
  ('starter', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('starter', 'customer_segments', 'limit', true, 1::bigint, 'segments'),
  ('starter', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('starter', 'offline_queue', 'limit', true, 100::bigint, 'transactions'),
  ('starter', 'reports_history_days', 'limit', true, 365::bigint, 'days'),
  ('starter', 'loyalty_rules', 'limit', true, 3::bigint, 'rules'),
  ('growth', 'active_products', 'limit', true, 2000::bigint, 'items'),
  ('growth', 'pos_devices', 'limit', true, 5::bigint, 'devices'),
  ('growth', 'whatsapp_messages', 'metered', true, 3000::bigint, 'messages/month'),
  ('growth', 'warehouses', 'limit', true, 2::bigint, 'warehouses'),
  ('growth', 'customer_segments', 'limit', true, 10::bigint, 'segments'),
  ('growth', 'api_requests', 'metered', true, 10000::bigint, 'requests/month'),
  ('growth', 'offline_queue', 'limit', true, 500::bigint, 'transactions'),
  ('growth', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('growth', 'loyalty_rules', 'limit', true, 10::bigint, 'rules'),
  ('pro', 'active_products', 'limit', true, NULL::bigint, 'items'),
  ('pro', 'pos_devices', 'limit', true, NULL::bigint, 'devices'),
  ('pro', 'whatsapp_messages', 'metered', true, 15000::bigint, 'messages/month'),
  ('pro', 'warehouses', 'limit', true, NULL::bigint, 'warehouses'),
  ('pro', 'customer_segments', 'limit', true, NULL::bigint, 'segments'),
  ('pro', 'api_requests', 'metered', true, 100000::bigint, 'requests/month'),
  ('pro', 'offline_queue', 'limit', true, 2000::bigint, 'transactions'),
  ('pro', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('pro', 'loyalty_rules', 'limit', true, NULL::bigint, 'rules')
) AS v(plan_code, feature_key, entitlement_type, enabled, limit_value, unit) ON v.plan_code = p.code
ON CONFLICT (plan_id, feature_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_subscription_entitlement(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_enabled boolean;
  v_limit bigint;
  v_unit text;
  v_source text;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid entitlement request' USING ERRCODE = '22023';
  END IF;
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Entitlement access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('enabled', false, 'limit_value', 0, 'source', 'none');
  END IF;

  SELECT mse.enabled, mse.limit_value, mse.unit, 'override'
  INTO v_enabled, v_limit, v_unit, v_source
  FROM public.merchant_subscription_entitlements mse
  WHERE mse.subscription_id = v_subscription.id
    AND mse.feature_key = p_feature_key
    AND mse.starts_at <= now()
    AND (mse.ends_at IS NULL OR mse.ends_at > now());

  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value, spe.unit, 'plan'
    INTO v_enabled, v_limit, v_unit, v_source
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id
      AND spe.feature_key = p_feature_key;
  END IF;

  RETURN jsonb_build_object(
    'enabled', COALESCE(v_enabled, false),
    'limit_value', v_limit,
    'unit', v_unit,
    'source', COALESCE(v_source, 'none'),
    'subscription_id', v_subscription.id,
    'plan_id', v_subscription.plan_id,
    'status', v_subscription.status,
    'grace_period_until', v_subscription.grace_period_until
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_subscription_entitlement(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_entitlement(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.require_subscription_feature(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entitlement jsonb;
BEGIN
  v_entitlement := public.get_subscription_entitlement(p_merchant_id, p_feature_key);
  IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
    RAISE EXCEPTION 'Feature is not included in active subscription' USING ERRCODE = '42501';
  END IF;
  RETURN v_entitlement;
END;
$$;

REVOKE ALL ON FUNCTION public.require_subscription_feature(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_subscription_feature(uuid, text) TO authenticated, service_role;

-- ===== END SOURCE: 20260829130000_subscription_entitlement_enforcement.sql =====

-- ===== BEGIN SOURCE: 20260829140000_subscription_runtime_enforcement.sql =====
-- Runtime subscription enforcement for PWA devices and WhatsApp delivery.
-- Safe to replay: functions are replaced and grants are deterministic.

CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_device public.pwa_device_sessions%ROWTYPE;
  v_merchant_id uuid;
  v_entitlement jsonb;
  v_limit bigint;
  v_active_devices bigint;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true)
    OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;

  -- Serialize registrations per account so two tabs cannot bypass the device limit.
  PERFORM pg_advisory_xact_lock(hashtextextended('pwa-device:' || auth.uid()::text, 0));
  SELECT * INTO v_device
  FROM public.pwa_device_sessions
  WHERE user_id = auth.uid() AND device_id = trim(p_device_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
    SELECT count(*) INTO v_active_devices
    FROM public.pwa_device_sessions
    WHERE user_id = auth.uid() AND status <> 'revoked';

    -- Accounts without an active subscription retain one basic device.
    v_limit := 1;
    IF v_merchant_id IS NOT NULL THEN
      v_entitlement := public.get_subscription_entitlement(v_merchant_id, 'pos_devices');
      IF COALESCE((v_entitlement->>'subscription_id') IS NOT NULL, false) THEN
        IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
          RAISE EXCEPTION 'POS device feature is not included in active subscription' USING ERRCODE = '42501';
        END IF;
        v_limit := NULLIF((v_entitlement->>'limit_value')::bigint, 0);
      END IF;
    END IF;
    IF v_limit IS NOT NULL AND v_active_devices >= v_limit THEN
      RAISE EXCEPTION 'POS device limit exceeded' USING ERRCODE = '54000';
    END IF;
  END IF;

  INSERT INTO public.pwa_device_sessions(user_id, tenant_id, device_id, device_name, device_type, platform, user_agent, status, last_seen_at, revoked_at, revoked_by)
  VALUES (auth.uid(), p_tenant_id, trim(p_device_id), COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'), p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''), 'active', now(), NULL, NULL)
  ON CONFLICT (user_id, device_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent, status = 'active', last_seen_at = now(), revoked_at = NULL, revoked_by = NULL, updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END; $$;

-- Worker-only bridge: resolve the POS tenant owner to merchant billing identity,
-- then consume exactly once per delivery job.
CREATE OR REPLACE FUNCTION public.consume_whatsapp_delivery_usage(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_job public.notification_delivery_jobs%ROWTYPE;
  v_merchant_id uuid;
  v_period_start timestamptz := date_trunc('month', now());
  v_period_end timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'WhatsApp usage enforcement requires worker access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.channel <> 'whatsapp' THEN
    RAISE EXCEPTION 'WhatsApp delivery job not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT m.id INTO v_merchant_id
  FROM public.pos_tenants t
  JOIN public.merchants m ON m.user_id = t.user_id
  WHERE t.id = v_job.tenant_id
  LIMIT 1;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'WhatsApp delivery merchant mapping is missing' USING ERRCODE = '23503';
  END IF;
  RETURN public.consume_subscription_usage(
    v_merchant_id,
    'whatsapp_messages',
    1,
    'notification_delivery_job',
    v_period_start,
    v_period_end,
    'notification_delivery_job:' || p_job_id::text,
    'whatsapp_delivery',
    jsonb_build_object('job_id', p_job_id, 'tenant_id', v_job.tenant_id, 'recipient_id', v_job.recipient_id)
  );
END; $$;
REVOKE ALL ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) TO service_role;

-- Service-role worker access is explicit; browser clients remain admin-only.
CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1
  WHERE id = p_job_id AND status IN ('queued','failed') AND next_attempt_at <= now() AND attempts < max_attempts
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF auth.role() <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs SET status = v_status, provider_message_id = COALESCE(p_provider_message_id, provider_message_id), last_error = NULLIF(trim(p_error), ''), next_attempt_at = COALESCE(v_next, next_attempt_at), sent_at = CASE WHEN p_success THEN now() ELSE sent_at END, dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$;

REVOKE ALL ON FUNCTION public.claim_notification_delivery_job(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_delivery_job(uuid) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery_job(uuid, boolean, text, text) TO service_role, authenticated;

-- ===== END SOURCE: 20260829140000_subscription_runtime_enforcement.sql =====

-- ===== BEGIN SOURCE: 20260829150000_pos_tenant_merchant_mapping.sql =====
-- Explicit POS tenant to merchant billing identity mapping.
-- Ambiguous existing users are intentionally left unmapped for manual resolution.
ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_pos_tenants_merchant_id ON public.pos_tenants(merchant_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_tenants_one_per_merchant
  ON public.pos_tenants(merchant_id) WHERE merchant_id IS NOT NULL;

DO $$
BEGIN
  UPDATE public.pos_tenants t
  SET merchant_id = m.id
  FROM public.merchants m
  WHERE t.merchant_id IS NULL
    AND m.user_id = t.user_id
    AND (SELECT count(*) FROM public.merchants m2 WHERE m2.user_id = t.user_id) = 1;
END $$;

CREATE OR REPLACE FUNCTION public.set_pos_tenant_merchant(
  p_tenant_id uuid,
  p_merchant_id uuid
)
RETURNS public.pos_tenants
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_tenant FROM public.pos_tenants WHERE id = p_tenant_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR v_tenant.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'POS tenant mapping access denied' USING ERRCODE = '42501';
  END IF;
  IF p_merchant_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = p_merchant_id AND (public.is_admin() OR m.user_id = v_tenant.user_id)
  ) THEN
    RAISE EXCEPTION 'Merchant must belong to the POS tenant owner' USING ERRCODE = '42501';
  END IF;
  UPDATE public.pos_tenants
  SET merchant_id = p_merchant_id, updated_at = now()
  WHERE id = p_tenant_id
  RETURNING * INTO v_tenant;
  RETURN v_tenant;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Merchant is already mapped to another POS tenant' USING ERRCODE = '23505';
END; $$;
REVOKE ALL ON FUNCTION public.set_pos_tenant_merchant(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pos_tenant_merchant(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.consume_whatsapp_delivery_usage(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_job public.notification_delivery_jobs%ROWTYPE;
  v_merchant_id uuid;
  v_period_start timestamptz := date_trunc('month', now());
  v_period_end timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'WhatsApp usage enforcement requires worker access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.channel <> 'whatsapp' THEN
    RAISE EXCEPTION 'WhatsApp delivery job not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT t.merchant_id INTO v_merchant_id
  FROM public.pos_tenants t
  WHERE t.id = v_job.tenant_id;
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'WhatsApp delivery tenant has no explicit merchant mapping' USING ERRCODE = '23503';
  END IF;
  RETURN public.consume_subscription_usage(
    v_merchant_id,
    'whatsapp_messages',
    1,
    'notification_delivery_job',
    v_period_start,
    v_period_end,
    'notification_delivery_job:' || p_job_id::text,
    'whatsapp_delivery',
    jsonb_build_object('job_id', p_job_id, 'tenant_id', v_job.tenant_id, 'merchant_id', v_merchant_id, 'recipient_id', v_job.recipient_id)
  );
END; $$;
REVOKE ALL ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_whatsapp_delivery_usage(uuid) TO service_role;

-- ===== END SOURCE: 20260829150000_pos_tenant_merchant_mapping.sql =====

-- ===== BEGIN SOURCE: 20260829160000_pos_workflow_transition_hardening.sql =====
-- Server-side workflow transitions for POS tables and KDS orders.
-- The expected status prevents stale clients from overwriting a newer state.

CREATE OR REPLACE FUNCTION public.transition_pos_table_order(
  p_order_id uuid,
  p_to_status text,
  p_expected_status text DEFAULT NULL
)
RETURNS public.pos_table_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.pos_table_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Order meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.pos_user_has_role(v_order.tenant_id, ARRAY['owner','manager','kasir','cashier']) THEN
    RAISE EXCEPTION 'Tidak memiliki akses mengubah order meja' USING ERRCODE = '42501';
  END IF;
  IF p_expected_status IS NOT NULL AND v_order.status <> p_expected_status THEN
    RAISE EXCEPTION 'Order sudah berubah dari % menjadi %', p_expected_status, v_order.status USING ERRCODE = '40001';
  END IF;
  IF p_to_status NOT IN ('pending','cooking','ready','served','paid','cancelled') THEN
    RAISE EXCEPTION 'Status order tidak valid' USING ERRCODE = '22023';
  END IF;
  IF NOT (
    (v_order.status = 'pending' AND p_to_status IN ('cooking','cancelled')) OR
    (v_order.status = 'cooking' AND p_to_status IN ('ready','cancelled')) OR
    (v_order.status = 'ready' AND p_to_status IN ('served','cancelled')) OR
    (v_order.status = 'served' AND p_to_status = 'paid')
  ) THEN
    RAISE EXCEPTION 'Transisi order % ke % tidak diizinkan', v_order.status, p_to_status USING ERRCODE = '55000';
  END IF;

  UPDATE public.pos_table_orders
  SET status = p_to_status,
      cooking_started_at = CASE WHEN p_to_status = 'cooking' THEN COALESCE(cooking_started_at, now()) ELSE cooking_started_at END,
      ready_at = CASE WHEN p_to_status = 'ready' THEN COALESCE(ready_at, now()) ELSE ready_at END,
      served_at = CASE WHEN p_to_status = 'served' THEN COALESCE(served_at, now()) ELSE served_at END,
      updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_pos_table(
  p_table_id uuid,
  p_to_status text,
  p_expected_status text DEFAULT NULL
)
RETURNS public.pos_tables
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
BEGIN
  SELECT * INTO v_table FROM public.pos_tables WHERE id = p_table_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.pos_user_has_role(v_table.tenant_id, ARRAY['owner','manager','kasir','cashier']) THEN
    RAISE EXCEPTION 'Tidak memiliki akses mengubah meja' USING ERRCODE = '42501';
  END IF;
  IF p_expected_status IS NOT NULL AND v_table.status <> p_expected_status THEN
    RAISE EXCEPTION 'Meja sudah berubah dari % menjadi %', p_expected_status, v_table.status USING ERRCODE = '40001';
  END IF;
  IF p_to_status NOT IN ('available','occupied','reserved','cleaning') THEN
    RAISE EXCEPTION 'Status meja tidak valid' USING ERRCODE = '22023';
  END IF;
  IF NOT (
    (v_table.status = 'available' AND p_to_status IN ('reserved','occupied','cleaning')) OR
    (v_table.status = 'reserved' AND p_to_status IN ('occupied','available')) OR
    (v_table.status = 'occupied' AND p_to_status IN ('cleaning','available')) OR
    (v_table.status = 'cleaning' AND p_to_status = 'available')
  ) THEN
    RAISE EXCEPTION 'Transisi meja % ke % tidak diizinkan', v_table.status, p_to_status USING ERRCODE = '55000';
  END IF;

  UPDATE public.pos_tables SET status = p_to_status, updated_at = now()
  WHERE id = p_table_id RETURNING * INTO v_table;
  RETURN v_table;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_pos_table_order(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transition_pos_table(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_pos_table_order(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_pos_table(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pos_table_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_table_id uuid,
  p_order_number text,
  p_customer_name text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS public.pos_table_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  IF NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','kasir','cashier']) THEN
    RAISE EXCEPTION 'Tidak memiliki akses membuat order meja' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_table FROM public.pos_tables WHERE id = p_table_id AND tenant_id = p_tenant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meja tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF p_outlet_id IS DISTINCT FROM v_table.outlet_id THEN
    RAISE EXCEPTION 'Outlet order tidak sesuai dengan outlet meja' USING ERRCODE = '22023';
  END IF;
  IF v_table.status NOT IN ('available','reserved') THEN
    RAISE EXCEPTION 'Meja sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.pos_table_orders(tenant_id, outlet_id, table_id, table_name, order_number, status, items, customer_name, notes)
  VALUES (p_tenant_id, p_outlet_id, p_table_id, v_table.name, p_order_number, 'pending', COALESCE(p_items, '[]'::jsonb), p_customer_name, p_notes)
  RETURNING * INTO v_order;

  UPDATE public.pos_tables SET status = 'occupied', updated_at = now() WHERE id = p_table_id;
  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pos_table_order(uuid, uuid, uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_table_order(uuid, uuid, uuid, text, text, text, jsonb) TO authenticated;

-- ===== END SOURCE: 20260829160000_pos_workflow_transition_hardening.sql =====
-- ===== END BUNDLE: 08_20260826010000_to_20260829160000.sql =====

-- ===== BEGIN BUNDLE: 09_20260904090000_to_20260904090000.sql =====
-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260904090000_pos_unified_transaction_history.sql .. 20260904090000_pos_unified_transaction_history.sql


-- ===== BEGIN SOURCE: 20260904090000_pos_unified_transaction_history.sql =====
-- POS unified transaction history and legacy reconciliation map.
-- New cashier writes remain exclusively in pos_sales; this migration only exposes
-- legacy records for reporting and gives operators an idempotent reconciliation key.

CREATE TABLE IF NOT EXISTS public.pos_transaction_migration_map (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legacy_transaction_id uuid NOT NULL REFERENCES public.pos_transactions(id) ON DELETE CASCADE,
  pos_sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'mapped', 'migrated', 'exception')),
  exception_code text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (legacy_transaction_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_transaction_migration_map_sale
  ON public.pos_transaction_migration_map(pos_sale_id)
  WHERE pos_sale_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pos_transaction_migration_map_scope
  ON public.pos_transaction_migration_map(tenant_id, outlet_id, status);

ALTER TABLE public.pos_transaction_migration_map ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users can view transaction migration map" ON public.pos_transaction_migration_map;
CREATE POLICY "POS users can view transaction migration map"
  ON public.pos_transaction_migration_map FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
    OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
  );

DROP POLICY IF EXISTS "POS owners manage transaction migration map" ON public.pos_transaction_migration_map;
CREATE POLICY "POS owners manage transaction migration map"
  ON public.pos_transaction_migration_map FOR ALL TO authenticated
  USING (public.is_admin() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (public.is_admin() OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));

-- Allow the unified history view to expose mapped legacy transactions to POS users.
DROP POLICY IF EXISTS "POS users can view mapped legacy transactions" ON public.pos_transactions;
CREATE POLICY "POS users can view mapped legacy transactions"
  ON public.pos_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.pos_transaction_migration_map map
      WHERE map.legacy_transaction_id = pos_transactions.id
        AND (
          public.is_admin()
          OR map.tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
          OR map.tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)
        )
    )
  );

-- Seed the map deterministically. A legacy merchant is auto-mapped only when it
-- resolves to exactly one POS tenant. An outlet is auto-selected only when the
-- tenant has exactly one active outlet; otherwise the row remains an exception
-- for manual outlet assignment.
INSERT INTO public.pos_transaction_migration_map (
  legacy_transaction_id,
  tenant_id,
  outlet_id,
  status,
  exception_code,
  notes
)
SELECT
  tx.id,
  tenant.id,
  CASE WHEN outlet_counts.active_outlet_count = 1 THEN outlet_counts.only_outlet_id ELSE NULL END,
  CASE
    WHEN tenant.id IS NULL THEN 'exception'
    WHEN outlet_counts.active_outlet_count = 1 THEN 'mapped'
    ELSE 'exception'
  END,
  CASE
    WHEN tenant.id IS NULL THEN 'MERCHANT_TENANT_UNMAPPED'
    WHEN outlet_counts.active_outlet_count <> 1 THEN 'OUTLET_MAPPING_AMBIGUOUS'
    ELSE NULL
  END,
  CASE
    WHEN tenant.id IS NULL THEN 'No unique POS tenant is mapped to the legacy merchant.'
    WHEN outlet_counts.active_outlet_count <> 1 THEN 'Manual outlet assignment is required before outlet-scoped reconciliation.'
    ELSE 'Initial idempotent legacy mapping.'
  END
FROM public.pos_transactions tx
LEFT JOIN public.pos_tenants tenant ON tenant.merchant_id = tx.merchant_id
LEFT JOIN LATERAL (
  SELECT
    count(*)::integer AS active_outlet_count,
    min(outlet.id) AS only_outlet_id
  FROM public.pos_outlets outlet
  WHERE outlet.tenant_id = tenant.id AND outlet.is_active = true
) outlet_counts ON true
ON CONFLICT (legacy_transaction_id) DO NOTHING;

CREATE OR REPLACE VIEW public.pos_unified_transaction_history
WITH (security_invoker = true) AS
SELECT
  sale.id,
  'modern'::text AS source,
  sale.id AS source_id,
  sale.tenant_id,
  sale.outlet_id,
  sale.sale_number,
  sale.cashier_name,
  sale.customer_name,
  sale.subtotal,
  sale.discount_amount,
  sale.tax_amount,
  sale.total,
  sale.payment_method,
  sale.payment_amount,
  sale.change_amount,
  sale.status,
  sale.notes,
  sale.created_at,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', item.id,
        'product_name', item.product_name,
        'variant_name', item.variant_name,
        'qty', item.qty,
        'price', item.price,
        'discount', item.discount,
        'subtotal', item.subtotal
      ) ORDER BY item.created_at, item.id
    ) FILTER (WHERE item.id IS NOT NULL),
    '[]'::jsonb
  ) AS items
FROM public.pos_sales sale
LEFT JOIN public.pos_sale_items item ON item.sale_id = sale.id
GROUP BY sale.id

UNION ALL

SELECT
  legacy.id,
  'legacy'::text AS source,
  legacy.id AS source_id,
  mapping.tenant_id,
  mapping.outlet_id,
  legacy.transaction_number AS sale_number,
  legacy.cashier_name,
  legacy.customer_name,
  legacy.subtotal::numeric,
  legacy.discount::numeric AS discount_amount,
  legacy.tax::numeric AS tax_amount,
  legacy.total::numeric,
  lower(legacy.payment_method) AS payment_method,
  legacy.payment_amount::numeric,
  legacy.change_amount::numeric,
  lower(legacy.status) AS status,
  legacy.notes,
  legacy.created_at,
  COALESCE(legacy.items, '[]'::jsonb) AS items
FROM public.pos_transactions legacy
JOIN public.pos_transaction_migration_map mapping
  ON mapping.legacy_transaction_id = legacy.id
WHERE mapping.pos_sale_id IS NULL
  AND mapping.tenant_id IS NOT NULL;

COMMENT ON VIEW public.pos_unified_transaction_history IS
  'Read-only reporting view combining canonical pos_sales with unmigrated legacy pos_transactions. New checkout must never write legacy rows.';

GRANT SELECT ON public.pos_unified_transaction_history TO authenticated;

-- ===== END SOURCE: 20260904090000_pos_unified_transaction_history.sql =====
-- ===== END BUNDLE: 09_20260904090000_to_20260904090000.sql =====

-- ===== BEGIN BUNDLE: 10_20260905000000_merchant_pos_product_catalog.sql =====
-- Merchant catalog integration for POS with per-outlet operational stock.
-- Merchant products are the source of truth; pos_products is a compatibility projection
-- because existing POS sales and stock tables reference pos_products IDs.

ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_tenants_merchant_id
  ON public.pos_tenants(merchant_id)
  WHERE merchant_id IS NOT NULL;

UPDATE public.pos_tenants t
SET merchant_id = m.id
FROM public.merchants m
WHERE t.merchant_id IS NULL
  AND m.user_id = t.user_id;

ALTER TABLE public.pos_products
  ADD COLUMN IF NOT EXISTS merchant_product_id uuid REFERENCES public.products(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_merchant_product
  ON public.pos_products(tenant_id, merchant_product_id)
  WHERE merchant_product_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_to_pos(p_product_id uuid, p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product public.products%ROWTYPE;
  v_pos_product_id uuid;
BEGIN
  SELECT * INTO v_product
  FROM public.products
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_pos_product_id
  FROM public.pos_products
  WHERE tenant_id = p_tenant_id
    AND merchant_product_id = p_product_id
  LIMIT 1;

  IF v_pos_product_id IS NULL THEN
    INSERT INTO public.pos_products (
      tenant_id, merchant_product_id, name, price, image_url, description, is_active,
      is_stock_tracked, has_variants, unit, cost_price, tax_rate
    ) VALUES (
      p_tenant_id, v_product.id, v_product.name, v_product.price, v_product.image_url,
      v_product.description, v_product.is_active, true, false, 'pcs', 0, 0
    ) RETURNING id INTO v_pos_product_id;
  ELSE
    UPDATE public.pos_products
    SET name = v_product.name,
        price = v_product.price,
        image_url = v_product.image_url,
        description = v_product.description,
        is_active = v_product.is_active,
        updated_at = now()
    WHERE id = v_pos_product_id;
  END IF;

  RETURN v_pos_product_id;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_product_to_pos(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.ensure_pos_stock_rows_for_product(p_product_id uuid, p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_outlet public.pos_outlets%ROWTYPE;
BEGIN
  -- A failed or deleted projection must never result in an invalid
  -- pos_stock row with a NULL product_id.
  IF p_product_id IS NULL THEN
    RETURN;
  END IF;

  FOR v_outlet IN
    SELECT *
    FROM public.pos_outlets
    WHERE tenant_id = p_tenant_id
      AND is_active = true
  LOOP
    -- Existing quantity and min_stock are operational data and must never be overwritten.
    INSERT INTO public.pos_stock (tenant_id, product_id, outlet_id, quantity, min_stock)
    VALUES (p_tenant_id, p_product_id, v_outlet.id, 0, 0)
    ON CONFLICT (product_id, variant_id, outlet_id) DO NOTHING;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_pos_stock_rows_for_product(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_to_pos_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT * FROM public.pos_tenants WHERE merchant_id = NEW.merchant_id AND is_active = true
  LOOP
    PERFORM public.sync_merchant_product_to_pos(NEW.id, v_tenant.id);
    PERFORM public.ensure_pos_stock_rows_for_product(
      (SELECT id FROM public.pos_products WHERE tenant_id = v_tenant.id AND merchant_product_id = NEW.id LIMIT 1),
      v_tenant.id
    );
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_to_pos ON public.products;
CREATE TRIGGER trg_sync_merchant_product_to_pos
AFTER INSERT OR UPDATE OF name, price, image_url, description, is_active, merchant_id
ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.sync_merchant_product_to_pos_trigger();

-- Backfill existing Merchant products into every linked POS tenant.
DO $$
DECLARE
  v_product public.products%ROWTYPE;
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_product IN SELECT * FROM public.products LOOP
    FOR v_tenant IN
      SELECT * FROM public.pos_tenants
      WHERE merchant_id = v_product.merchant_id AND is_active = true
    LOOP
      PERFORM public.sync_merchant_product_to_pos(v_product.id, v_tenant.id);
      PERFORM public.ensure_pos_stock_rows_for_product(
        (SELECT id FROM public.pos_products WHERE tenant_id = v_tenant.id AND merchant_product_id = v_product.id LIMIT 1),
        v_tenant.id
      );
    END LOOP;
  END LOOP;
END;
$$;

COMMENT ON COLUMN public.pos_tenants.merchant_id IS 'Canonical Merchant owner for the POS tenant.';
COMMENT ON COLUMN public.pos_products.merchant_product_id IS 'Source product in Merchant catalog; POS stock remains per outlet in pos_stock.';
-- ===== END BUNDLE: 10_20260905000000_merchant_pos_product_catalog.sql =====

-- ===== BEGIN BUNDLE: 11_20260906000000_merchant_pos_control_plane.sql =====
-- Merchant-POS control plane.
-- Merchant is the canonical business identity and product catalog.
-- POS keeps only its operational projection and outlet-level stock.

CREATE OR REPLACE FUNCTION public.sync_pos_tenant_catalog(p_tenant_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_count integer := 0;
  v_pos_product_id uuid;
BEGIN
  SELECT * INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN 0;
  END IF;

  FOR v_product IN
    SELECT *
    FROM public.products
    WHERE merchant_id = v_tenant.merchant_id
  LOOP
    v_pos_product_id := public.sync_merchant_product_to_pos(v_product.id, p_tenant_id);
    PERFORM public.ensure_pos_stock_rows_for_product(v_pos_product_id, p_tenant_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_pos_tenant_catalog(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_pos_tenant_catalog_after_mapping()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.merchant_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.merchant_id IS DISTINCT FROM NEW.merchant_id) THEN
    PERFORM public.sync_pos_tenant_catalog(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_tenant_catalog_after_mapping ON public.pos_tenants;
CREATE TRIGGER trg_sync_pos_tenant_catalog_after_mapping
AFTER INSERT OR UPDATE OF merchant_id ON public.pos_tenants
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_tenant_catalog_after_mapping();

CREATE OR REPLACE FUNCTION public.ensure_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_merchant_id uuid;
  v_tenant public.pos_tenants%ROWTYPE;
  v_outlet public.pos_outlets%ROWTYPE;
  v_source_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id
  INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = v_user_id
  ORDER BY (m.registration_status = 'APPROVED') DESC, m.updated_at DESC NULLS LAST, m.created_at DESC
  LIMIT 1;

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant profile is required before enabling POS' USING ERRCODE = '23503';
  END IF;

  INSERT INTO public.pos_tenants (
    user_id, name, phone, address, timezone, currency, merchant_id, is_active
  )
  VALUES (
    v_user_id,
    NULLIF(trim(p_name), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_address), ''),
    COALESCE(NULLIF(trim(p_timezone), ''), 'Asia/Jakarta'),
    COALESCE(NULLIF(trim(p_currency), ''), 'IDR'),
    v_merchant_id,
    true
  )
  ON CONFLICT (user_id) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.pos_tenants.name),
    phone = COALESCE(EXCLUDED.phone, public.pos_tenants.phone),
    address = COALESCE(EXCLUDED.address, public.pos_tenants.address),
    timezone = COALESCE(EXCLUDED.timezone, public.pos_tenants.timezone),
    currency = COALESCE(EXCLUDED.currency, public.pos_tenants.currency),
    merchant_id = COALESCE(public.pos_tenants.merchant_id, EXCLUDED.merchant_id),
    is_active = true,
    updated_at = now()
  RETURNING * INTO v_tenant;

  IF v_tenant.merchant_id IS NULL THEN
    RAISE EXCEPTION 'POS tenant is not mapped to a merchant' USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO v_outlet
  FROM public.pos_outlets
  WHERE tenant_id = v_tenant.id AND is_active = true
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
    VALUES (
      v_tenant.id,
      COALESCE(NULLIF(trim(p_outlet_name), ''), v_tenant.name || ' - Outlet Utama'),
      NULLIF(trim(COALESCE(p_outlet_address, p_address)), ''),
      NULLIF(trim(COALESCE(p_outlet_phone, p_phone)), ''),
      true
    )
    RETURNING * INTO v_outlet;
  END IF;

  v_source_count := public.sync_pos_tenant_catalog(v_tenant.id);

  RETURN jsonb_build_object(
    'tenant', to_jsonb(v_tenant),
    'outlet', to_jsonb(v_outlet),
    'merchant_id', v_tenant.merchant_id,
    'source_products_synced', v_source_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pos_integration_health()
RETURNS TABLE (
  tenant_id uuid,
  tenant_name text,
  merchant_id uuid,
  merchant_name text,
  owner_user_id uuid,
  outlet_count bigint,
  source_product_count bigint,
  linked_product_count bigint,
  unlinked_pos_product_count bigint,
  sync_gap_count bigint,
  status text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.name,
    t.merchant_id,
    m.name,
    t.user_id,
    (SELECT count(*) FROM public.pos_outlets o WHERE o.tenant_id = t.id AND o.is_active),
    (SELECT count(*) FROM public.products p WHERE p.merchant_id = t.merchant_id),
    (SELECT count(*) FROM public.pos_products pp WHERE pp.tenant_id = t.id AND pp.merchant_product_id IS NOT NULL),
    (SELECT count(*) FROM public.pos_products pp WHERE pp.tenant_id = t.id AND pp.merchant_product_id IS NULL),
    CASE
      WHEN t.merchant_id IS NULL THEN NULL::bigint
      ELSE (
        SELECT count(*)
        FROM public.products p
        WHERE p.merchant_id = t.merchant_id
          AND NOT EXISTS (
            SELECT 1
            FROM public.pos_products pp
            WHERE pp.tenant_id = t.id
              AND pp.merchant_product_id = p.id
          )
      )
    END,
    CASE
      WHEN t.merchant_id IS NULL THEN 'NEEDS_MAPPING'
      WHEN EXISTS (
        SELECT 1
        FROM public.products p
        WHERE p.merchant_id = t.merchant_id
          AND NOT EXISTS (
            SELECT 1 FROM public.pos_products pp
            WHERE pp.tenant_id = t.id AND pp.merchant_product_id = p.id
          )
      ) THEN 'NEEDS_SYNC'
      WHEN NOT EXISTS (
        SELECT 1 FROM public.pos_outlets o
        WHERE o.tenant_id = t.id AND o.is_active
      ) THEN 'NEEDS_OUTLET'
      ELSE 'READY'
    END
  FROM public.pos_tenants t
  LEFT JOIN public.merchants m ON m.id = t.merchant_id
  WHERE public.is_admin()
  ORDER BY t.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.get_pos_integration_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_integration_health() TO authenticated;
-- ===== END BUNDLE: 11_20260906000000_merchant_pos_control_plane.sql =====

-- ===== BEGIN BUNDLE: 12_20260906010000_pos_feature_gate.sql =====
-- POS feature gate.
-- POS status belongs to the merchant-owned tenant and is enforced for
-- operational mutations. The legacy is_active column remains for compatibility.

ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS business_type text,
  ADD COLUMN IF NOT EXISTS enabled_modules jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS trial_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS activated_at timestamptz,
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz;

UPDATE public.pos_tenants
SET status = CASE WHEN is_active THEN 'active' ELSE 'inactive' END
WHERE status IS NULL OR status NOT IN ('inactive', 'setup_required', 'trial', 'active', 'suspended', 'cancelled');

ALTER TABLE public.pos_tenants
  DROP CONSTRAINT IF EXISTS pos_tenants_status_check;

ALTER TABLE public.pos_tenants
  ADD CONSTRAINT pos_tenants_status_check
  CHECK (status IN ('inactive', 'setup_required', 'trial', 'active', 'suspended', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_pos_tenants_status
  ON public.pos_tenants(status);

CREATE OR REPLACE FUNCTION public.is_pos_tenant_active(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants
    WHERE id = p_tenant_id
      AND is_active = true
      AND status IN ('trial', 'active')
  );
$$;

REVOKE ALL ON FUNCTION public.is_pos_tenant_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pos_tenant_active(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_active_pos_tenant_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;

  IF NOT public.is_pos_tenant_active(v_tenant_id) THEN
    RAISE EXCEPTION 'POS is not active for this merchant'
      USING ERRCODE = '42501';
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_active_pos_tenant_mutation() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_table record;
BEGIN
  FOR v_table IN
    SELECT DISTINCT c.table_schema, c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND c.table_name LIKE 'pos_%'
      AND c.table_name <> 'pos_tenants'
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS enforce_active_pos_tenant_mutation ON %I.%I',
      v_table.table_schema, v_table.table_name
    );
    EXECUTE format(
      'CREATE TRIGGER enforce_active_pos_tenant_mutation
       BEFORE INSERT OR UPDATE OR DELETE ON %I.%I
       FOR EACH ROW EXECUTE FUNCTION public.enforce_active_pos_tenant_mutation()',
      v_table.table_schema, v_table.table_name
    );
  END LOOP;
END;
$$;

-- POS transactions/settings use merchant_id instead of tenant_id. Keep
-- subscription requests available before activation, but protect operational
-- transaction and settings mutations once a tenant is suspended/cancelled.
DROP POLICY IF EXISTS "Merchants can manage own POS transactions" ON public.pos_transactions;
CREATE POLICY "Merchants can manage own active POS transactions"
  ON public.pos_transactions FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_transactions.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_transactions.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  );

DROP POLICY IF EXISTS "Merchants can manage own POS settings" ON public.pos_settings;
CREATE POLICY "Merchants can manage own active POS settings"
  ON public.pos_settings FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_settings.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_settings.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  );

CREATE OR REPLACE FUNCTION public.activate_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL,
  p_business_type text DEFAULT 'simple',
  p_enabled_modules jsonb DEFAULT '["cashier"]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_tenant_id uuid;
BEGIN
  v_result := public.ensure_merchant_pos_workspace(
    p_name, p_phone, p_address, p_timezone, p_currency,
    p_outlet_name, p_outlet_address, p_outlet_phone
  );
  v_tenant_id := (v_result->'tenant'->>'id')::uuid;

  UPDATE public.pos_tenants
  SET status = 'active',
      business_type = NULLIF(trim(p_business_type), ''),
      enabled_modules = CASE
        WHEN jsonb_typeof(p_enabled_modules) = 'array' THEN p_enabled_modules
        ELSE '["cashier"]'::jsonb
      END,
      activated_at = COALESCE(activated_at, now()),
      updated_at = now()
  WHERE id = v_tenant_id;

  RETURN v_result || jsonb_build_object(
    'status', 'active',
    'business_type', NULLIF(trim(p_business_type), ''),
    'enabled_modules', p_enabled_modules
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_merchant_pos_workspace(text, text, text, text, text, text, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_merchant_pos_workspace(text, text, text, text, text, text, text, text, text, jsonb) TO authenticated;
-- ===== END BUNDLE: 12_20260906010000_pos_feature_gate.sql =====

-- ===== BEGIN BUNDLE: 13_20260906020000_pos_subscription_admin_actions.sql =====
-- Atomic admin actions for POS subscriptions and the merchant POS feature gate.

CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_duration_months integer;
  v_started_at timestamptz;
  v_expired_at timestamptz;
  v_action text := upper(trim(p_action));
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;

  v_duration_months := COALESCE(v_duration_months, 1);

  IF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at IS NOT NULL
       AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
    ELSE
      v_started_at := now();
      v_expired_at := v_started_at + make_interval(months => CASE
        WHEN v_action = 'EXTEND' THEN GREATEST(1, COALESCE(p_extension_months, 1))
        ELSE v_duration_months
      END);
    END IF;

    UPDATE public.pos_subscriptions
    SET status = 'ACTIVE',
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'active',
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED',
        payment_status = 'UNPAID',
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'suspended',
        is_active = false,
        suspended_at = now(),
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED',
        payment_status = 'CANCELLED',
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'cancelled',
        is_active = false,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(NULLIF(trim(p_rejection_reason), ''), 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action
      USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object(
    'subscription', to_jsonb(s),
    'tenant', to_jsonb(t)
  )
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;
-- ===== END BUNDLE: 13_20260906020000_pos_subscription_admin_actions.sql =====

-- ===== BEGIN BUNDLE: 14_20260907000000_pos_activation_entitlement_gate.sql =====
-- POS activation must be backed by an approved merchant entitlement.
-- Existing operational tenants remain usable through the normal POS routes,
-- but the setup/activation RPC cannot be used to re-activate without one.

CREATE OR REPLACE FUNCTION public.ensure_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_merchant_id uuid;
  v_tenant public.pos_tenants%ROWTYPE;
  v_outlet public.pos_outlets%ROWTYPE;
  v_source_count integer;
  v_has_active_entitlement boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id
  INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = v_user_id
    AND m.registration_status = 'APPROVED'
    AND m.status = 'ACTIVE'
  ORDER BY m.updated_at DESC NULLS LAST, m.created_at DESC
  LIMIT 1;

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'An approved and active merchant profile is required before enabling POS'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.pos_subscriptions s
    WHERE s.merchant_id = v_merchant_id
      AND s.status = 'ACTIVE'
      AND s.started_at IS NOT NULL
      AND s.expired_at > now()
      AND (
        s.is_trial = true
        OR s.payment_status = 'PAID'
      )
  )
  INTO v_has_active_entitlement;

  IF NOT v_has_active_entitlement THEN
    RAISE EXCEPTION 'An active POS trial or subscription is required before enabling POS'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.pos_tenants (
    user_id, name, phone, address, timezone, currency, merchant_id, is_active
  )
  VALUES (
    v_user_id,
    NULLIF(trim(p_name), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_address), ''),
    COALESCE(NULLIF(trim(p_timezone), ''), 'Asia/Jakarta'),
    COALESCE(NULLIF(trim(p_currency), ''), 'IDR'),
    v_merchant_id,
    true
  )
  ON CONFLICT (user_id) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.pos_tenants.name),
    phone = COALESCE(EXCLUDED.phone, public.pos_tenants.phone),
    address = COALESCE(EXCLUDED.address, public.pos_tenants.address),
    timezone = COALESCE(EXCLUDED.timezone, public.pos_tenants.timezone),
    currency = COALESCE(EXCLUDED.currency, public.pos_tenants.currency),
    merchant_id = COALESCE(public.pos_tenants.merchant_id, EXCLUDED.merchant_id),
    is_active = true,
    status = CASE
      WHEN public.pos_tenants.status IN ('suspended', 'cancelled') THEN 'active'
      ELSE public.pos_tenants.status
    END,
    updated_at = now()
  RETURNING * INTO v_tenant;

  IF v_tenant.merchant_id IS NULL THEN
    RAISE EXCEPTION 'POS tenant is not mapped to a merchant' USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO v_outlet
  FROM public.pos_outlets
  WHERE tenant_id = v_tenant.id AND is_active = true
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
    VALUES (
      v_tenant.id,
      COALESCE(NULLIF(trim(p_outlet_name), ''), v_tenant.name || ' - Outlet Utama'),
      NULLIF(trim(COALESCE(p_outlet_address, p_address)), ''),
      NULLIF(trim(COALESCE(p_outlet_phone, p_phone)), ''),
      true
    )
    RETURNING * INTO v_outlet;
  END IF;

  v_source_count := public.sync_pos_tenant_catalog(v_tenant.id);

  RETURN jsonb_build_object(
    'tenant', to_jsonb(v_tenant),
    'outlet', to_jsonb(v_outlet),
    'merchant_id', v_tenant.merchant_id,
    'source_products_synced', v_source_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) TO authenticated;
-- ===== END BUNDLE: 14_20260907000000_pos_activation_entitlement_gate.sql =====

-- ===== BEGIN BUNDLE: 15_20260907010000_pos_marketplace_stock_projection.sql =====
-- POS outlet stock is the operational source of truth for linked products.
-- products.stock is the marketplace projection of available POS stock across
-- active outlets: quantity minus POS reservations.

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_internal(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_mapping record;
  v_available numeric;
  v_projected_stock integer;
  v_processed integer := 0;
  v_updated integer := 0;
BEGIN
  -- Allow only this server-side projection path to write marketplace stock
  -- for products whose operational source is POS stock.
  PERFORM set_config('app.pos_stock_projection', 'on', true);

  SELECT *
  INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id;

  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'tenant_id', p_tenant_id,
      'processed', 0,
      'updated', 0,
      'status', 'unmapped'
    );
  END IF;

  FOR v_mapping IN
    SELECT
      pp.id AS pos_product_id,
      COALESCE(ms.marketplace_product_id, pp.merchant_product_id) AS marketplace_product_id,
      ms.id AS sync_id
    FROM public.pos_products pp
    LEFT JOIN public.pos_marketplace_sync ms
      ON ms.tenant_id = pp.tenant_id
      AND ms.pos_product_id = pp.id
    JOIN public.products marketplace_product
      ON marketplace_product.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
      AND marketplace_product.merchant_id = v_tenant.merchant_id
    WHERE pp.tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pp.id = p_pos_product_id)
      AND (ms.id IS NULL OR (ms.sync_stock = true AND ms.sync_status = 'synced'))
  LOOP
    v_processed := v_processed + 1;

    SELECT COALESCE(SUM(
      GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)
    ), 0)
    INTO v_available
    FROM public.pos_stock ps
    JOIN public.pos_outlets po
      ON po.id = ps.outlet_id
      AND po.tenant_id = ps.tenant_id
      AND po.is_active = true
    WHERE ps.tenant_id = p_tenant_id
      AND ps.product_id = v_mapping.pos_product_id
      AND ps.variant_id IS NULL;

    -- products.stock is integer-based while POS supports fractional units.
    -- Round only at the marketplace boundary; POS retains exact quantities.
    v_projected_stock := GREATEST(0, ROUND(v_available))::integer;

    UPDATE public.products
    SET stock = v_projected_stock,
        updated_at = now()
    WHERE id = v_mapping.marketplace_product_id
      AND merchant_id = v_tenant.merchant_id
      AND stock IS DISTINCT FROM v_projected_stock;

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    IF v_mapping.sync_id IS NOT NULL THEN
      UPDATE public.pos_marketplace_sync
      SET last_synced_at = now(),
          sync_status = 'synced',
          error_message = NULL,
          updated_at = now()
      WHERE id = v_mapping.sync_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'processed', v_processed,
    'updated', v_updated,
    'status', 'success'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.pos_tenants t
      WHERE t.id = p_tenant_id
        AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.pos_users u
      WHERE u.tenant_id = p_tenant_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock synchronization access denied'
      USING ERRCODE = '42501';
  END IF;

  RETURN public.sync_pos_stock_to_marketplace_internal(p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
  v_product_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;
BEGIN
  PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant_id, v_product_id);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_stock_to_marketplace ON public.pos_stock;
CREATE TRIGGER trg_sync_pos_stock_to_marketplace
AFTER INSERT OR UPDATE OF quantity, reserved_quantity, product_id, tenant_id, outlet_id OR DELETE
ON public.pos_stock
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_stock_to_marketplace_after_change();

REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_after_change() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) TO authenticated;

DO $$
DECLARE
  v_tenant_id uuid;
BEGIN
  FOR v_tenant_id IN
    SELECT id FROM public.pos_tenants WHERE is_active = true
  LOOP
    PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant_id);
  END LOOP;
END;
$$;
-- ===== END BUNDLE: 15_20260907010000_pos_marketplace_stock_projection.sql =====

-- ===== BEGIN BUNDLE: 16_20260907020000_pos_marketplace_stock_guard.sql =====
-- Linked products must receive stock from POS outlet stock, not from a
-- merchant's manual marketplace edit. The projection function in migration 15
-- opts into the internal transaction setting before it updates products.stock.

CREATE OR REPLACE FUNCTION public.prevent_manual_stock_edit_for_pos_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.stock IS DISTINCT FROM OLD.stock
     AND COALESCE(current_setting('app.pos_stock_projection', true), '') <> 'on'
     AND EXISTS (
       SELECT 1
       FROM public.pos_products pp
       JOIN public.pos_tenants pt ON pt.id = pp.tenant_id
       WHERE pp.merchant_product_id = NEW.id
         AND pt.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Stock produk tertaut POS hanya dapat diubah dari stok outlet POS'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_stock_edit_for_pos_product ON public.products;
CREATE TRIGGER trg_prevent_manual_stock_edit_for_pos_product
BEFORE UPDATE OF stock ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.prevent_manual_stock_edit_for_pos_product();

REVOKE ALL ON FUNCTION public.prevent_manual_stock_edit_for_pos_product() FROM PUBLIC, anon, authenticated;
-- ===== END BUNDLE: 16_20260907020000_pos_marketplace_stock_guard.sql =====

