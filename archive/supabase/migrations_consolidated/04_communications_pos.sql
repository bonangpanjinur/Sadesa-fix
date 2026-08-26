-- ============================================================
-- FILE 04: COMMUNICATIONS, POS, ADDRESSES, WISHLIST, STORAGE
-- ============================================================
-- Aligned to live schema (2026-04). Idempotent — safe to re-run.
-- Tables:
--   notifications, broadcast_notifications, push_subscriptions,
--   chat_messages (+ auto-delete), saved_addresses, wishlists,
--   pos_packages, pos_settings, pos_subscriptions, pos_transactions,
--   halal_regulations, page_views + storage buckets & policies.
-- ============================================================

-- 1. NOTIFICATIONS ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
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

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Authenticated users can receive notifications" ON public.notifications;
CREATE POLICY "Authenticated users can receive notifications" ON public.notifications
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins can manage all notifications" ON public.notifications;
CREATE POLICY "Admins can manage all notifications" ON public.notifications
  FOR ALL USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

-- 2. BROADCAST NOTIFICATIONS -----------------------------------
CREATE TABLE IF NOT EXISTS public.broadcast_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  target_audience text NOT NULL DEFAULT 'ALL',
  target_roles text[] DEFAULT '{}'::text[],
  scheduled_at timestamptz,
  sent_at timestamptz,
  sent_count integer DEFAULT 0,
  status text NOT NULL DEFAULT 'DRAFT',
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.broadcast_notifications TO authenticated;
GRANT ALL ON public.broadcast_notifications TO service_role;
ALTER TABLE public.broadcast_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage broadcasts" ON public.broadcast_notifications;
CREATE POLICY "Admins can manage broadcasts" ON public.broadcast_notifications
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

DROP POLICY IF EXISTS "Users can view their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can view their own push subscriptions" ON public.push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can insert their own push subscriptions" ON public.push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can update their own push subscriptions" ON public.push_subscriptions
  FOR UPDATE USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete their own push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can delete their own push subscriptions" ON public.push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON public.push_subscriptions(user_id);

-- 4. CHAT MESSAGES ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  receiver_id uuid NOT NULL,
  message text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  chat_type text DEFAULT 'buyer_merchant',
  image_url text,
  auto_delete_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Ensure columns exist if table pre-existed with older shape
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS chat_type text DEFAULT 'buyer_merchant',
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS auto_delete_at timestamptz;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO authenticated;
GRANT ALL ON public.chat_messages TO service_role;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Helper function (SECURITY DEFINER)
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

DROP POLICY IF EXISTS "Users can view own chat messages" ON public.chat_messages;
CREATE POLICY "Users can view own chat messages" ON public.chat_messages
  FOR SELECT USING (
    auth.uid() = sender_id OR auth.uid() = receiver_id
    OR public.is_chat_participant(auth.uid(), order_id, chat_type)
  );
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;
CREATE POLICY "Users can send chat messages" ON public.chat_messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND public.is_chat_participant(auth.uid(), order_id, chat_type)
  );
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
CREATE POLICY "Users can update own messages read status" ON public.chat_messages
  FOR UPDATE USING (auth.uid() = receiver_id);
DROP POLICY IF EXISTS "Admins can manage all chat messages" ON public.chat_messages;
CREATE POLICY "Admins can manage all chat messages" ON public.chat_messages
  FOR ALL USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_chat_messages_order_id ON public.chat_messages(order_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_type ON public.chat_messages(order_id, chat_type);
CREATE INDEX IF NOT EXISTS idx_chat_messages_auto_delete
  ON public.chat_messages(auto_delete_at) WHERE auto_delete_at IS NOT NULL;

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
  user_id uuid NOT NULL,
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

DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses;
CREATE POLICY "Users can view own addresses" ON public.saved_addresses
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses;
CREATE POLICY "Users can insert own addresses" ON public.saved_addresses
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses;
CREATE POLICY "Users can update own addresses" ON public.saved_addresses
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses;
CREATE POLICY "Users can delete own addresses" ON public.saved_addresses
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses;
CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 6. WISHLISTS -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wishlists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, product_id)
);

GRANT SELECT, INSERT, DELETE ON public.wishlists TO authenticated;
GRANT ALL ON public.wishlists TO service_role;
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own wishlists" ON public.wishlists;
CREATE POLICY "Users can view own wishlists" ON public.wishlists
  FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can add to own wishlist" ON public.wishlists;
CREATE POLICY "Users can add to own wishlist" ON public.wishlists
  FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can remove from own wishlist" ON public.wishlists;
CREATE POLICY "Users can remove from own wishlist" ON public.wishlists
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_wishlists_user_id ON public.wishlists(user_id);
CREATE INDEX IF NOT EXISTS idx_wishlists_product_id ON public.wishlists(product_id);

-- 6b. POS TENANTS & OUTLETS (SaaS kasir) -----------------------
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

DROP TRIGGER IF EXISTS update_pos_tenants_updated_at ON public.pos_tenants;
CREATE TRIGGER update_pos_tenants_updated_at
  BEFORE UPDATE ON public.pos_tenants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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

DROP TRIGGER IF EXISTS update_pos_outlets_updated_at ON public.pos_outlets;
CREATE TRIGGER update_pos_outlets_updated_at
  BEFORE UPDATE ON public.pos_outlets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 7. POS PACKAGES ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  duration_months integer NOT NULL DEFAULT 1,
  price integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.pos_packages TO anon, authenticated;
GRANT ALL ON public.pos_packages TO service_role;
ALTER TABLE public.pos_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active POS packages" ON public.pos_packages;
CREATE POLICY "Anyone can view active POS packages" ON public.pos_packages
  FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage POS packages" ON public.pos_packages;
CREATE POLICY "Admins can manage POS packages" ON public.pos_packages
  FOR ALL USING (public.is_admin());

DROP TRIGGER IF EXISTS update_pos_packages_updated_at ON public.pos_packages;
CREATE TRIGGER update_pos_packages_updated_at
  BEFORE UPDATE ON public.pos_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 8. POS SETTINGS ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL UNIQUE REFERENCES public.merchants(id),
  invoice_header text,
  invoice_footer text,
  show_logo boolean NOT NULL DEFAULT true,
  show_address boolean NOT NULL DEFAULT true,
  show_phone boolean NOT NULL DEFAULT true,
  paper_size text NOT NULL DEFAULT '58mm',
  font_size text NOT NULL DEFAULT 'normal',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_settings TO authenticated;
GRANT ALL ON public.pos_settings TO service_role;
ALTER TABLE public.pos_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can manage own POS settings" ON public.pos_settings;
CREATE POLICY "Merchants can manage own POS settings" ON public.pos_settings
  FOR ALL USING (EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = pos_settings.merchant_id AND merchants.user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Admins can manage all POS settings" ON public.pos_settings;
CREATE POLICY "Admins can manage all POS settings" ON public.pos_settings
  FOR ALL USING (public.is_admin());

DROP TRIGGER IF EXISTS update_pos_settings_updated_at ON public.pos_settings;
CREATE TRIGGER update_pos_settings_updated_at
  BEFORE UPDATE ON public.pos_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 9. POS SUBSCRIPTIONS -----------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id),
  package_id uuid REFERENCES public.pos_packages(id),
  status text NOT NULL DEFAULT 'PENDING',
  payment_amount integer NOT NULL DEFAULT 0,
  payment_proof_url text,
  payment_status text NOT NULL DEFAULT 'UNPAID',
  started_at timestamptz,
  expired_at timestamptz,
  approved_by uuid,
  approved_at timestamptz,
  rejection_reason text,
  is_trial boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.pos_subscriptions TO authenticated;
GRANT ALL ON public.pos_subscriptions TO service_role;
ALTER TABLE public.pos_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can view own POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can view own POS subscriptions" ON public.pos_subscriptions
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Merchants can create POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can create POS subscriptions" ON public.pos_subscriptions
  FOR INSERT WITH CHECK (EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Merchants can update own POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Merchants can update own POS subscriptions" ON public.pos_subscriptions
  FOR UPDATE USING (EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = pos_subscriptions.merchant_id AND merchants.user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Admins can manage all POS subscriptions" ON public.pos_subscriptions;
CREATE POLICY "Admins can manage all POS subscriptions" ON public.pos_subscriptions
  FOR ALL USING (public.is_admin());

DROP TRIGGER IF EXISTS update_pos_subscriptions_updated_at ON public.pos_subscriptions;
CREATE TRIGGER update_pos_subscriptions_updated_at
  BEFORE UPDATE ON public.pos_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 10. POS TRANSACTIONS -----------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id),
  transaction_number text NOT NULL,
  customer_name text,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  subtotal integer NOT NULL DEFAULT 0,
  discount integer NOT NULL DEFAULT 0,
  tax integer NOT NULL DEFAULT 0,
  total integer NOT NULL DEFAULT 0,
  payment_method text NOT NULL DEFAULT 'CASH',
  payment_amount integer NOT NULL DEFAULT 0,
  change_amount integer NOT NULL DEFAULT 0,
  notes text,
  cashier_name text,
  status text NOT NULL DEFAULT 'COMPLETED',
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.pos_transactions TO authenticated;
GRANT ALL ON public.pos_transactions TO service_role;
ALTER TABLE public.pos_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can manage own POS transactions" ON public.pos_transactions;
CREATE POLICY "Merchants can manage own POS transactions" ON public.pos_transactions
  FOR ALL USING (EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = pos_transactions.merchant_id AND merchants.user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Admins can view all POS transactions" ON public.pos_transactions;
CREATE POLICY "Admins can view all POS transactions" ON public.pos_transactions
  FOR SELECT USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_pos_tx_merchant ON public.pos_transactions(merchant_id, created_at DESC);

-- 11. HALAL REGULATIONS ----------------------------------------
CREATE TABLE IF NOT EXISTS public.halal_regulations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

GRANT SELECT ON public.halal_regulations TO anon, authenticated;
GRANT ALL ON public.halal_regulations TO service_role;
ALTER TABLE public.halal_regulations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read halal_regulations" ON public.halal_regulations;
CREATE POLICY "Anyone can read halal_regulations" ON public.halal_regulations
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admin can manage halal_regulations" ON public.halal_regulations;
CREATE POLICY "Admin can manage halal_regulations" ON public.halal_regulations
  FOR ALL USING (public.is_admin());

-- 12. PAGE VIEWS -----------------------------------------------
CREATE TABLE IF NOT EXISTS public.page_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE CASCADE,
  viewer_id uuid,
  page_type text NOT NULL DEFAULT 'product',
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON public.page_views TO anon, authenticated;
GRANT ALL ON public.page_views TO service_role;
ALTER TABLE public.page_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated or anonymous can insert their own page view" ON public.page_views;
CREATE POLICY "Authenticated or anonymous can insert their own page view" ON public.page_views
  FOR INSERT WITH CHECK (viewer_id IS NULL OR viewer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants can view own page views" ON public.page_views;
CREATE POLICY "Merchants can view own page views" ON public.page_views
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = page_views.merchant_id AND merchants.user_id = auth.uid()
    ) OR public.is_admin()
  );

CREATE INDEX IF NOT EXISTS idx_page_views_merchant ON public.page_views(merchant_id, created_at);
CREATE INDEX IF NOT EXISTS idx_page_views_product ON public.page_views(product_id, created_at);

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

-- Authenticated upload
DROP POLICY IF EXISTS "Authenticated upload" ON storage.objects;
CREATE POLICY "Authenticated upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Owner update / delete their own files
DROP POLICY IF EXISTS "Owner update files" ON storage.objects;
CREATE POLICY "Owner update files" ON storage.objects
  FOR UPDATE TO authenticated USING (owner = auth.uid());

DROP POLICY IF EXISTS "Owner delete files" ON storage.objects;
CREATE POLICY "Owner delete files" ON storage.objects
  FOR DELETE TO authenticated USING (owner = auth.uid());

-- Private buckets: owner + admin
DROP POLICY IF EXISTS "Private bucket owner read" ON storage.objects;
CREATE POLICY "Private bucket owner read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id IN ('payment-proofs','pod-images','chat-images','courier-documents')
    AND (owner = auth.uid() OR public.is_admin())
  );

-- END OF FILE 04
