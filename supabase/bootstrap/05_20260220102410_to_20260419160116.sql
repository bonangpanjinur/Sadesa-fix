-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260220102410_b1e662ad-3482-496a-aa4d-f8078ad98c25.sql .. 20260419160116_b45d64ac-3359-4860-94e7-e8213dfbb3a6.sql


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
