-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260127080732_36fd1d8b-6207-4fed-8758-87368ec25e10.sql .. 20260203_fix_is_admin_and_packages.sql


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
