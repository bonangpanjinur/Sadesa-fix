-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260127034916_79ea4061-eab6-4151-9591-63293a92b7fe.sql .. 20260127073300_6cb5784e-39e2-4626-8d8d-8bdc12a2a2e4.sql


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
CREATE TABLE public.user_roles (
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
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_merchants_updated_at
    BEFORE UPDATE ON public.merchants
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

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
CREATE POLICY "Users can view own roles"
    ON public.user_roles FOR SELECT
    USING (auth.uid() = user_id);

-- PROFILES policies
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- VILLAGES policies (public read)
CREATE POLICY "Anyone can view active villages"
    ON public.villages FOR SELECT
    USING (is_active = true);

CREATE POLICY "Admins can manage villages"
    ON public.villages FOR ALL
    USING (public.is_admin());

-- MERCHANTS policies (public read)
CREATE POLICY "Anyone can view active merchants"
    ON public.merchants FOR SELECT
    USING (status = 'ACTIVE');

CREATE POLICY "Admins can manage merchants"
    ON public.merchants FOR ALL
    USING (public.is_admin());

-- PRODUCTS policies (public read)
CREATE POLICY "Anyone can view active products"
    ON public.products FOR SELECT
    USING (is_active = true);

CREATE POLICY "Admins can manage products"
    ON public.products FOR ALL
    USING (public.is_admin());

-- TOURISM policies (public read)
CREATE POLICY "Anyone can view active tourism"
    ON public.tourism FOR SELECT
    USING (is_active = true);

CREATE POLICY "Admins can manage tourism"
    ON public.tourism FOR ALL
    USING (public.is_admin());

-- ORDERS policies
CREATE POLICY "Buyers can view own orders"
    ON public.orders FOR SELECT
    USING (auth.uid() = buyer_id OR public.is_admin());

CREATE POLICY "Buyers can create orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Buyers can update own pending orders"
    ON public.orders FOR UPDATE
    USING (auth.uid() = buyer_id AND status = 'NEW');

CREATE POLICY "Admins can manage all orders"
    ON public.orders FOR ALL
    USING (public.is_admin());

-- ORDER_ITEMS policies
CREATE POLICY "Users can view own order items"
    ON public.order_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.orders 
            WHERE orders.id = order_items.order_id 
            AND (orders.buyer_id = auth.uid() OR public.is_admin())
        )
    );

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
CREATE POLICY "Anyone can register village" 
ON public.villages 
FOR INSERT 
WITH CHECK (
  registration_status = 'PENDING' AND 
  is_active = false
);

-- Allow anyone to register a merchant (pending approval by verifikator)
CREATE POLICY "Anyone can register merchant"
ON public.merchants
FOR INSERT
WITH CHECK (
  registration_status = 'PENDING' AND
  status = 'PENDING'
);

-- Verifikator can manage merchants (approve/reject)
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
CREATE POLICY "Anyone can view active codes"
ON public.verifikator_codes
FOR SELECT
USING (is_active = true);

-- Verifikator can manage their own codes
CREATE POLICY "Verifikator can manage own codes"
ON public.verifikator_codes
FOR ALL
USING (
  verifikator_id = auth.uid() OR 
  is_admin()
);

-- Admin can manage all codes
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
CREATE POLICY "Admins can manage promotions"
ON public.promotions
FOR ALL
USING (is_admin());

-- Villages can create promotions for themselves
CREATE POLICY "Villages can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'village' 
  AND is_approved = false
);

-- Merchants can create promotions for themselves  
CREATE POLICY "Merchants can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'merchant'
  AND is_approved = false
);

-- Add trigger for updated_at
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
CREATE POLICY "Admins can manage couriers" ON public.couriers
FOR ALL USING (is_admin());

CREATE POLICY "Verifikator can manage couriers" ON public.couriers
FOR ALL USING (is_verifikator());

CREATE POLICY "Anyone can register as courier" ON public.couriers
FOR INSERT WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE');

CREATE POLICY "Active couriers visible to authenticated" ON public.couriers
FOR SELECT USING (status = 'ACTIVE' AND auth.uid() IS NOT NULL);

CREATE POLICY "Couriers can view own data" ON public.couriers
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Couriers can update own location" ON public.couriers
FOR UPDATE USING (user_id = auth.uid() AND status = 'ACTIVE');

-- RLS policies for app_settings
CREATE POLICY "Admins can manage settings" ON public.app_settings
FOR ALL USING (is_admin());

CREATE POLICY "Anyone can view settings" ON public.app_settings
FOR SELECT USING (true);

-- Update trigger for couriers
CREATE TRIGGER update_couriers_updated_at
BEFORE UPDATE ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Update trigger for app_settings
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

-- Storage policies for courier-documents bucket
CREATE POLICY "Anyone can upload courier documents" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'courier-documents');

CREATE POLICY "Admins can view all courier documents" ON storage.objects
FOR SELECT USING (bucket_id = 'courier-documents' AND (is_admin() OR is_verifikator()));

CREATE POLICY "Couriers can view own documents" ON storage.objects
FOR SELECT USING (
    bucket_id = 'courier-documents' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);

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
CREATE POLICY "Couriers can view assigned orders" 
ON public.orders 
FOR SELECT 
USING (courier_id IN (SELECT id FROM couriers WHERE user_id = auth.uid()));

-- Couriers can update assigned orders (status changes)
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
CREATE POLICY "Merchants can view own data"
ON public.merchants
FOR SELECT
USING (user_id = auth.uid());

-- Allow merchants to update own data
CREATE POLICY "Merchants can update own data"
ON public.merchants
FOR UPDATE
USING (user_id = auth.uid());

-- Allow admin desa to manage tourism in their village
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
CREATE POLICY "Anyone can view product images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

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
CREATE POLICY "Anyone can view tourism images"
ON storage.objects FOR SELECT
USING (bucket_id = 'tourism-images');

CREATE POLICY "Admin desa can upload tourism images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

CREATE POLICY "Admin desa can update tourism images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

CREATE POLICY "Admin desa can delete tourism images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

-- RLS for profile-images: Users can upload their own
CREATE POLICY "Anyone can view profile images"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-images');

CREATE POLICY "Users can upload own profile image"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'profile-images' 
  AND auth.uid() IS NOT NULL
);

CREATE POLICY "Users can update own profile image"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'profile-images' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can delete own profile image"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'profile-images' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS for merchant-images: Merchants can upload their store image
CREATE POLICY "Anyone can view merchant images"
ON storage.objects FOR SELECT
USING (bucket_id = 'merchant-images');

CREATE POLICY "Merchants can upload merchant images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'merchant-images' 
  AND (
    is_admin() OR 
    auth.uid() IS NOT NULL
  )
);

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
CREATE POLICY "Admins can manage refunds" ON public.refund_requests
FOR ALL USING (is_admin());

CREATE POLICY "Buyers can view own refunds" ON public.refund_requests
FOR SELECT USING (buyer_id = auth.uid());

CREATE POLICY "Buyers can create refund requests" ON public.refund_requests
FOR INSERT WITH CHECK (buyer_id = auth.uid() AND status = 'PENDING');

-- RLS for admin_audit_logs (admin only)
CREATE POLICY "Admins can view logs" ON public.admin_audit_logs
FOR SELECT USING (is_admin());

CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs
FOR INSERT WITH CHECK (is_admin());

-- Update profiles RLS to allow admin to update block status
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
FOR UPDATE USING (auth.uid() = user_id AND is_blocked = false);

CREATE POLICY "Admins can update any profile" ON public.profiles
FOR ALL USING (is_admin());

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_refund_requests_status ON public.refund_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_buyer ON public.refund_requests(buyer_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC);

-- Trigger for updated_at
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
CREATE POLICY "Anyone can view visible reviews" ON public.reviews
FOR SELECT USING (is_visible = true);

CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews
FOR INSERT WITH CHECK (buyer_id = auth.uid());

CREATE POLICY "Merchants can reply to their reviews" ON public.reviews
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = reviews.merchant_id 
    AND merchants.user_id = auth.uid()
  )
);

CREATE POLICY "Admins can manage reviews" ON public.reviews
FOR ALL USING (is_admin());

-- Withdrawal requests policies
CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = withdrawal_requests.merchant_id 
    AND merchants.user_id = auth.uid()
  )
);

CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = withdrawal_requests.merchant_id 
    AND merchants.user_id = auth.uid()
  ) AND status = 'PENDING'
);

CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests
FOR ALL USING (is_admin());

-- Insurance fund policies
CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = insurance_fund.merchant_id 
    AND merchants.user_id = auth.uid()
  )
);

CREATE POLICY "Merchants can create claims" ON public.insurance_fund
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = insurance_fund.merchant_id 
    AND merchants.user_id = auth.uid()
  ) AND type = 'claim' AND status = 'PENDING'
);

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
CREATE TRIGGER update_reviews_updated_at
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

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
  '{"enabled": true, "max_amount": 75000, "max_distance_km": 3, "service_fee": 1000, "min_trust_score": 50, "confirmation_timeout_minutes": 15, "penalty_points": 50, "success_bonus_points": 1}',
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
CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "System can insert notifications" ON public.notifications
FOR INSERT WITH CHECK (true);

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
CREATE POLICY "Anyone can view active packages" 
ON public.transaction_packages FOR SELECT 
USING (is_active = true);

CREATE POLICY "Admins can manage packages" 
ON public.transaction_packages FOR ALL 
USING (is_admin());

-- RLS for merchant_subscriptions
CREATE POLICY "Merchants can view own subscriptions" 
ON public.merchant_subscriptions FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM merchants 
  WHERE merchants.id = merchant_subscriptions.merchant_id 
  AND merchants.user_id = auth.uid()
));

CREATE POLICY "Merchants can create subscriptions" 
ON public.merchant_subscriptions FOR INSERT 
WITH CHECK (EXISTS (
  SELECT 1 FROM merchants 
  WHERE merchants.id = merchant_subscriptions.merchant_id 
  AND merchants.user_id = auth.uid()
) AND status = 'PENDING');

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
CREATE TRIGGER update_transaction_packages_updated_at
BEFORE UPDATE ON public.transaction_packages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

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
CREATE POLICY "Verifikators can manage own groups"
ON public.trade_groups FOR ALL
USING (verifikator_id = auth.uid() OR is_admin());

CREATE POLICY "Admins can manage all groups"
ON public.trade_groups FOR ALL
USING (is_admin());

CREATE POLICY "Anyone can view active groups"
ON public.trade_groups FOR SELECT
USING (is_active = true);

-- Group Members Policies
CREATE POLICY "Verifikators can manage group members"
ON public.group_members FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups 
    WHERE trade_groups.id = group_members.group_id 
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
);

CREATE POLICY "Merchants can view own membership"
ON public.group_members FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = group_members.merchant_id 
    AND merchants.user_id = auth.uid()
  )
);

CREATE POLICY "Admins can manage all members"
ON public.group_members FOR ALL
USING (is_admin());

-- Kas Payments Policies
CREATE POLICY "Verifikators can manage payments in their groups"
ON public.kas_payments FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups 
    WHERE trade_groups.id = kas_payments.group_id 
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
);

CREATE POLICY "Merchants can view own payments"
ON public.kas_payments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants 
    WHERE merchants.id = kas_payments.merchant_id 
    AND merchants.user_id = auth.uid()
  )
);

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
CREATE TRIGGER update_trade_groups_updated_at
  BEFORE UPDATE ON public.trade_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

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
CREATE POLICY "Admins can manage all earnings"
  ON public.verifikator_earnings FOR ALL
  USING (is_admin());

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
CREATE TRIGGER trigger_record_verifikator_commission
  AFTER INSERT OR UPDATE ON public.merchant_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.record_verifikator_commission();
-- ===== END SOURCE: 20260127073300_6cb5784e-39e2-4626-8d8d-8bdc12a2a2e4.sql =====
