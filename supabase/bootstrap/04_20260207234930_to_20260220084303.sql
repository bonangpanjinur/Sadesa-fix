-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260207234930_56685a71-d39f-422a-84ff-01a0d4ed0169.sql .. 20260220084303_65515e4b-c3b1-4a16-b325-a3f977d4ce67.sql


-- ===== BEGIN SOURCE: 20260207234930_56685a71-d39f-422a-84ff-01a0d4ed0169.sql =====

-- Fix the permissive INSERT policy - restrict to authenticated users whose merchant matches
DROP POLICY IF EXISTS "System can insert quota logs" ON public.quota_usage_logs;

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

CREATE POLICY "Merchants can view their own quota logs"
ON public.quota_audit_logs FOR SELECT
TO authenticated
USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

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
CREATE POLICY "Users view own village assignments"
ON public.user_villages
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- Authenticated users can insert their own assignment (for registration)
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
CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (is_admin());

CREATE POLICY "Admins can insert user roles"
  ON public.user_roles FOR INSERT
  TO authenticated
  WITH CHECK (is_admin());

CREATE POLICY "Admins can update user roles"
  ON public.user_roles FOR UPDATE
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

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

CREATE POLICY "Anyone can view active POS packages"
  ON public.pos_packages FOR SELECT
  USING (is_active = true);

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

CREATE POLICY "Merchants can view own POS subscriptions"
  ON public.pos_subscriptions FOR SELECT
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

CREATE POLICY "Merchants can create POS subscriptions"
  ON public.pos_subscriptions FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

CREATE POLICY "Merchants can update own POS subscriptions"
  ON public.pos_subscriptions FOR UPDATE
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()));

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

CREATE POLICY "Merchants can manage own POS transactions"
  ON public.pos_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_transactions.merchant_id AND merchants.user_id = auth.uid()));

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

CREATE POLICY "Merchants can manage own POS settings"
  ON public.pos_settings FOR ALL
  USING (EXISTS (SELECT 1 FROM merchants WHERE merchants.id = pos_settings.merchant_id AND merchants.user_id = auth.uid()));

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

CREATE POLICY "Couriers can view own withdrawals"
ON public.courier_withdrawal_requests FOR SELECT
USING (courier_id = public.get_user_courier_id());

CREATE POLICY "Couriers can create own withdrawals"
ON public.courier_withdrawal_requests FOR INSERT
WITH CHECK (courier_id = public.get_user_courier_id());

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
CREATE POLICY "Anyone can read halal_regulations" ON public.halal_regulations FOR SELECT USING (true);
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
CREATE POLICY "Merchants can view own data"
ON public.merchants FOR SELECT
USING (auth.uid() = id);

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
CREATE POLICY "Users can view own chat messages"
ON public.chat_messages FOR SELECT
USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send chat messages"
ON public.chat_messages FOR INSERT
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update own messages read status"
ON public.chat_messages FOR UPDATE
USING (auth.uid() = receiver_id);

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
CREATE POLICY "Anyone can insert page views"
ON public.page_views FOR INSERT
WITH CHECK (true);

-- Merchants can view their own page views
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

CREATE POLICY "Verifikator can manage own announcements"
  ON public.group_announcements FOR ALL
  USING (verifikator_id = auth.uid());

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
