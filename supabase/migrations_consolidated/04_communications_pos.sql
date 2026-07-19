-- ============================================================
-- FILE 04: COMMUNICATIONS, POS, ADDRESSES, WISHLIST, STORAGE
-- ============================================================
-- notifications, broadcast_notifications, push_subscriptions,
-- chat_messages (+ auto-delete), saved_addresses, wishlists,
-- pos_packages, pos_settings, pos_subscriptions, pos_transactions,
-- halal_regulations, page_views, storage buckets & policies.
-- Idempotent.
-- ============================================================

-- 1. NOTIFICATIONS ---------------------------------------------

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'info',
  link text,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own notifications" ON public.notifications;
CREATE POLICY "Users view own notifications" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users update own notifications" ON public.notifications;
CREATE POLICY "Users update own notifications" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users delete own notifications" ON public.notifications;
CREATE POLICY "Users delete own notifications" ON public.notifications
  FOR DELETE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
CREATE POLICY "System can insert notifications" ON public.notifications
  FOR INSERT WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

-- 2. BROADCAST NOTIFICATIONS -----------------------------------

CREATE TABLE IF NOT EXISTS public.broadcast_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'info',
  link text,
  target_role text,
  target_village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'DRAFT',
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.broadcast_notifications TO authenticated;
GRANT ALL ON public.broadcast_notifications TO service_role;
ALTER TABLE public.broadcast_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage broadcasts" ON public.broadcast_notifications;
CREATE POLICY "Admins manage broadcasts" ON public.broadcast_notifications
  FOR ALL USING (public.is_admin());

-- 3. PUSH SUBSCRIPTIONS ----------------------------------------

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_subscriptions TO authenticated;
GRANT ALL ON public.push_subscriptions TO service_role;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own push subs" ON public.push_subscriptions;
CREATE POLICY "Users view own push subs" ON public.push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users insert own push subs" ON public.push_subscriptions;
CREATE POLICY "Users insert own push subs" ON public.push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users update own push subs" ON public.push_subscriptions;
CREATE POLICY "Users update own push subs" ON public.push_subscriptions
  FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users delete own push subs" ON public.push_subscriptions;
CREATE POLICY "Users delete own push subs" ON public.push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON public.push_subscriptions(user_id);

-- 4. CHAT MESSAGES ---------------------------------------------

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  message text,
  image_url text,
  chat_type text NOT NULL DEFAULT 'buyer_merchant',
  is_read boolean NOT NULL DEFAULT false,
  auto_delete_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO authenticated;
GRANT ALL ON public.chat_messages TO service_role;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Helper function (idempotent via CREATE OR REPLACE)
CREATE OR REPLACE FUNCTION public.is_chat_participant(
  user_uuid uuid, p_order_id uuid, p_chat_type text
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
$$;

DROP POLICY IF EXISTS "Users view own chat messages" ON public.chat_messages;
CREATE POLICY "Users view own chat messages" ON public.chat_messages
  FOR SELECT USING (
    auth.uid() = sender_id OR auth.uid() = receiver_id
    OR public.is_chat_participant(auth.uid(), order_id, chat_type)
  );
DROP POLICY IF EXISTS "Users send chat messages" ON public.chat_messages;
CREATE POLICY "Users send chat messages" ON public.chat_messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND public.is_chat_participant(auth.uid(), order_id, chat_type)
  );
DROP POLICY IF EXISTS "Users update own chat read" ON public.chat_messages;
CREATE POLICY "Users update own chat read" ON public.chat_messages
  FOR UPDATE USING (auth.uid() = receiver_id);
DROP POLICY IF EXISTS "Users delete own chat" ON public.chat_messages;
CREATE POLICY "Users delete own chat" ON public.chat_messages
  FOR DELETE USING (auth.uid() = sender_id);

CREATE INDEX IF NOT EXISTS idx_chat_messages_order ON public.chat_messages(order_id, chat_type);
CREATE INDEX IF NOT EXISTS idx_chat_messages_receiver ON public.chat_messages(receiver_id);

-- Cleanup expired chats
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM chat_messages WHERE auto_delete_at IS NOT NULL AND auto_delete_at <= now();
END;
$$;

-- Trigger: set auto_delete_at when order finished
CREATE OR REPLACE FUNCTION public.set_chat_auto_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status NOT IN ('DONE', 'DELIVERED') THEN
    UPDATE chat_messages
    SET auto_delete_at = now() + interval '3 hours'
    WHERE order_id = NEW.id AND auto_delete_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_chat_auto_delete ON public.orders;
CREATE TRIGGER trg_set_chat_auto_delete
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_chat_auto_delete();

-- 5. SAVED ADDRESSES -------------------------------------------

CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'Rumah',
  recipient_name text NOT NULL,
  phone text NOT NULL,
  province_id text,
  province_name text,
  city_id text,
  city_name text,
  district_id text,
  district_name text,
  village_id text,
  village_name text,
  address_detail text,
  full_address text,
  lat numeric,
  lng numeric,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;
GRANT ALL ON public.saved_addresses TO service_role;
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own addresses" ON public.saved_addresses;
CREATE POLICY "Users view own addresses" ON public.saved_addresses
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users insert own addresses" ON public.saved_addresses
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users update own addresses" ON public.saved_addresses;
CREATE POLICY "Users update own addresses" ON public.saved_addresses
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users delete own addresses" ON public.saved_addresses
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 6. WISHLISTS -------------------------------------------------

CREATE TABLE IF NOT EXISTS public.wishlists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, product_id)
);

GRANT SELECT, INSERT, DELETE ON public.wishlists TO authenticated;
GRANT ALL ON public.wishlists TO service_role;
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own wishlist" ON public.wishlists;
CREATE POLICY "Users view own wishlist" ON public.wishlists
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users add own wishlist" ON public.wishlists;
CREATE POLICY "Users add own wishlist" ON public.wishlists
  FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users remove own wishlist" ON public.wishlists;
CREATE POLICY "Users remove own wishlist" ON public.wishlists
  FOR DELETE USING (auth.uid() = user_id);

-- 7. POS PACKAGES ----------------------------------------------

CREATE TABLE IF NOT EXISTS public.pos_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  price integer NOT NULL DEFAULT 0,
  duration_days integer NOT NULL DEFAULT 30,
  features jsonb DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.pos_packages TO anon, authenticated;
GRANT ALL ON public.pos_packages TO service_role;
ALTER TABLE public.pos_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone view active pos packages" ON public.pos_packages;
CREATE POLICY "Anyone view active pos packages" ON public.pos_packages
  FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins manage pos packages" ON public.pos_packages;
CREATE POLICY "Admins manage pos packages" ON public.pos_packages
  FOR ALL USING (public.is_admin());

-- 8. POS SETTINGS ----------------------------------------------

CREATE TABLE IF NOT EXISTS public.pos_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL UNIQUE REFERENCES public.merchants(id) ON DELETE CASCADE,
  business_name text,
  address text,
  phone text,
  tax_percent numeric DEFAULT 0,
  service_charge_percent numeric DEFAULT 0,
  currency text DEFAULT 'IDR',
  receipt_footer text,
  logo_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_settings TO authenticated;
GRANT ALL ON public.pos_settings TO service_role;
ALTER TABLE public.pos_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchant view own pos settings" ON public.pos_settings;
CREATE POLICY "Merchant view own pos settings" ON public.pos_settings
  FOR SELECT USING (merchant_id = public.get_user_merchant_id() OR public.is_admin());
DROP POLICY IF EXISTS "Merchant manage own pos settings" ON public.pos_settings;
CREATE POLICY "Merchant manage own pos settings" ON public.pos_settings
  FOR ALL USING (merchant_id = public.get_user_merchant_id() OR public.is_admin());

-- 9. POS SUBSCRIPTIONS -----------------------------------------

CREATE TABLE IF NOT EXISTS public.pos_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id uuid REFERENCES public.pos_packages(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'PENDING',
  payment_status text NOT NULL DEFAULT 'PENDING',
  payment_amount integer NOT NULL DEFAULT 0,
  payment_method text,
  payment_proof_url text,
  activated_at timestamptz,
  expired_at timestamptz,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.pos_subscriptions TO authenticated;
GRANT ALL ON public.pos_subscriptions TO service_role;
ALTER TABLE public.pos_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchant view own pos sub" ON public.pos_subscriptions;
CREATE POLICY "Merchant view own pos sub" ON public.pos_subscriptions
  FOR SELECT USING (merchant_id = public.get_user_merchant_id() OR public.is_admin());
DROP POLICY IF EXISTS "Merchant create own pos sub" ON public.pos_subscriptions;
CREATE POLICY "Merchant create own pos sub" ON public.pos_subscriptions
  FOR INSERT WITH CHECK (merchant_id = public.get_user_merchant_id());
DROP POLICY IF EXISTS "Merchant update own pos sub" ON public.pos_subscriptions;
CREATE POLICY "Merchant update own pos sub" ON public.pos_subscriptions
  FOR UPDATE USING (merchant_id = public.get_user_merchant_id() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage pos subs" ON public.pos_subscriptions;
CREATE POLICY "Admins manage pos subs" ON public.pos_subscriptions
  FOR ALL USING (public.is_admin());

-- 10. POS TRANSACTIONS -----------------------------------------

CREATE TABLE IF NOT EXISTS public.pos_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  transaction_number text,
  cashier_name text,
  customer_name text,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  subtotal integer NOT NULL DEFAULT 0,
  discount integer DEFAULT 0,
  tax integer DEFAULT 0,
  service_charge integer DEFAULT 0,
  total integer NOT NULL DEFAULT 0,
  payment_method text,
  paid_amount integer DEFAULT 0,
  change_amount integer DEFAULT 0,
  status text NOT NULL DEFAULT 'COMPLETED',
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.pos_transactions TO authenticated;
GRANT ALL ON public.pos_transactions TO service_role;
ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchant view own pos tx" ON public.pos_transactions;
CREATE POLICY "Merchant view own pos tx" ON public.pos_transactions
  FOR SELECT USING (merchant_id = public.get_user_merchant_id() OR public.is_admin());
DROP POLICY IF EXISTS "Merchant create own pos tx" ON public.pos_transactions;
CREATE POLICY "Merchant create own pos tx" ON public.pos_transactions
  FOR INSERT WITH CHECK (merchant_id = public.get_user_merchant_id());

CREATE INDEX IF NOT EXISTS idx_pos_tx_merchant ON public.pos_transactions(merchant_id, created_at DESC);

-- 11. HALAL REGULATIONS ----------------------------------------

CREATE TABLE IF NOT EXISTS public.halal_regulations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content text NOT NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.halal_regulations TO anon, authenticated;
GRANT ALL ON public.halal_regulations TO service_role;
ALTER TABLE public.halal_regulations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone view halal regulations" ON public.halal_regulations;
CREATE POLICY "Anyone view halal regulations" ON public.halal_regulations
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins manage halal regulations" ON public.halal_regulations;
CREATE POLICY "Admins manage halal regulations" ON public.halal_regulations
  FOR ALL USING (public.is_admin());

-- 12. PAGE VIEWS -----------------------------------------------

CREATE TABLE IF NOT EXISTS public.page_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_type text NOT NULL,
  page_id uuid,
  viewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ip_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON public.page_views TO anon, authenticated;
GRANT ALL ON public.page_views TO service_role;
ALTER TABLE public.page_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone insert own page view" ON public.page_views;
CREATE POLICY "Anyone insert own page view" ON public.page_views
  FOR INSERT WITH CHECK (viewer_id IS NULL OR viewer_id = auth.uid());
DROP POLICY IF EXISTS "Admins view page views" ON public.page_views;
CREATE POLICY "Admins view page views" ON public.page_views
  FOR SELECT USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_page_views_page ON public.page_views(page_type, page_id);

-- 13. STORAGE BUCKETS ------------------------------------------

INSERT INTO storage.buckets (id, name, public) VALUES
  ('product-images', 'product-images', true),
  ('tourism-images', 'tourism-images', true),
  ('profile-images', 'profile-images', true),
  ('merchant-images', 'merchant-images', true),
  ('review-images', 'review-images', true),
  ('village-images', 'village-images', true),
  ('promotions', 'promotions', true),
  ('admin-assets', 'admin-assets', true),
  ('merchant-gallery', 'merchant-gallery', true),
  ('payment-proofs', 'payment-proofs', false),
  ('pod-images', 'pod-images', false),
  ('chat-images', 'chat-images', false),
  ('courier-documents', 'courier-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Public read policy for public buckets
DROP POLICY IF EXISTS "Public buckets read" ON storage.objects;
CREATE POLICY "Public buckets read" ON storage.objects
  FOR SELECT USING (bucket_id IN (
    'product-images','tourism-images','profile-images','merchant-images',
    'review-images','village-images','promotions','admin-assets','merchant-gallery'
  ));

-- Authenticated upload to any bucket
DROP POLICY IF EXISTS "Authenticated upload" ON storage.objects;
CREATE POLICY "Authenticated upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Owner can update/delete their own files (files stored with user_id as first folder)
DROP POLICY IF EXISTS "Owner update files" ON storage.objects;
CREATE POLICY "Owner update files" ON storage.objects
  FOR UPDATE TO authenticated
  USING (owner = auth.uid());

DROP POLICY IF EXISTS "Owner delete files" ON storage.objects;
CREATE POLICY "Owner delete files" ON storage.objects
  FOR DELETE TO authenticated
  USING (owner = auth.uid());

-- Private buckets: signed URL access only (owner + admin fallback)
DROP POLICY IF EXISTS "Private bucket owner read" ON storage.objects;
CREATE POLICY "Private bucket owner read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id IN ('payment-proofs','pod-images','chat-images','courier-documents')
    AND (owner = auth.uid() OR public.is_admin())
  );

-- END OF FILE 04
