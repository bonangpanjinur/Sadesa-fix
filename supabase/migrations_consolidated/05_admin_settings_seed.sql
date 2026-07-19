-- ============================================================
-- FILE 05: ADMIN SETTINGS, AUDIT, BACKUP, REALTIME & SEED DATA
-- ============================================================
-- app_settings, admin_audit_logs, backup_logs, backup_schedules,
-- seo_settings, realtime publications, and default seed data
-- (categories, app_settings, transaction_packages, pos_packages,
-- halal_regulations). Idempotent.
-- ============================================================

-- 1. APP SETTINGS ----------------------------------------------

CREATE TABLE IF NOT EXISTS public.app_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  category text NOT NULL DEFAULT 'general',
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  description text,
  is_public boolean NOT NULL DEFAULT false,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.app_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.app_settings TO authenticated;
GRANT ALL ON public.app_settings TO service_role;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone view public settings" ON public.app_settings;
CREATE POLICY "Anyone view public settings" ON public.app_settings
  FOR SELECT USING (is_public = true OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage settings" ON public.app_settings;
CREATE POLICY "Admins manage settings" ON public.app_settings
  FOR ALL USING (public.is_admin());

DROP TRIGGER IF EXISTS set_app_settings_updated_at ON public.app_settings;
CREATE TRIGGER set_app_settings_updated_at
  BEFORE UPDATE ON public.app_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2. ADMIN AUDIT LOGS ------------------------------------------

CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text,
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

DROP POLICY IF EXISTS "Admins view audit logs" ON public.admin_audit_logs;
CREATE POLICY "Admins view audit logs" ON public.admin_audit_logs
  FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins insert audit logs" ON public.admin_audit_logs;
CREATE POLICY "Admins insert audit logs" ON public.admin_audit_logs
  FOR INSERT WITH CHECK (public.is_admin() AND admin_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_audit_created_at ON public.admin_audit_logs(created_at DESC);

-- 3. BACKUP LOGS -----------------------------------------------

CREATE TABLE IF NOT EXISTS public.backup_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING',
  file_url text,
  file_size_bytes bigint,
  tables_included text[],
  error_message text,
  triggered_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

GRANT SELECT, INSERT, UPDATE ON public.backup_logs TO authenticated;
GRANT ALL ON public.backup_logs TO service_role;
ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins view backup logs" ON public.backup_logs;
CREATE POLICY "Admins view backup logs" ON public.backup_logs
  FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins manage backup logs" ON public.backup_logs;
CREATE POLICY "Admins manage backup logs" ON public.backup_logs
  FOR ALL USING (public.is_admin());

-- 4. BACKUP SCHEDULES ------------------------------------------

CREATE TABLE IF NOT EXISTS public.backup_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  frequency text NOT NULL DEFAULT 'daily',
  time_of_day text,
  tables_included text[],
  retention_days integer NOT NULL DEFAULT 30,
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

DROP POLICY IF EXISTS "Admins manage backup schedules" ON public.backup_schedules;
CREATE POLICY "Admins manage backup schedules" ON public.backup_schedules
  FOR ALL USING (public.is_admin());

-- 5. SEO SETTINGS ----------------------------------------------

CREATE TABLE IF NOT EXISTS public.seo_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_key text NOT NULL UNIQUE,
  title text,
  description text,
  keywords text,
  og_title text,
  og_description text,
  og_image_url text,
  twitter_card text DEFAULT 'summary_large_image',
  canonical_url text,
  robots text DEFAULT 'index,follow',
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.seo_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.seo_settings TO authenticated;
GRANT ALL ON public.seo_settings TO service_role;
ALTER TABLE public.seo_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone view seo settings" ON public.seo_settings;
CREATE POLICY "Anyone view seo settings" ON public.seo_settings
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins manage seo settings" ON public.seo_settings;
CREATE POLICY "Admins manage seo settings" ON public.seo_settings
  FOR ALL USING (public.is_admin());

-- 6. REALTIME PUBLICATIONS -------------------------------------
-- Idempotent: cek dulu apakah tabel sudah masuk publication.

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'orders', 'order_items', 'notifications', 'chat_messages',
    'ride_requests', 'couriers', 'merchants', 'products',
    'saved_addresses', 'courier_deposits', 'courier_balance_logs',
    'push_subscriptions', 'flash_sales', 'reviews'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_rel pr
      JOIN pg_publication p ON pr.prpubid = p.oid
      JOIN pg_class c ON pr.prrelid = c.oid
      JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE p.pubname = 'supabase_realtime'
        AND n.nspname = 'public'
        AND c.relname = t
    ) THEN
      BEGIN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not add % to publication: %', t, SQLERRM;
      END;
    END IF;
  END LOOP;
END $$;

-- 7. SEED DATA -------------------------------------------------

-- Default kategori produk
INSERT INTO public.categories (slug, name, icon, sort_order, is_active) VALUES
  ('makanan', 'Makanan', '🍔', 1, true),
  ('minuman', 'Minuman', '🥤', 2, true),
  ('sembako', 'Sembako', '🛒', 3, true),
  ('sayuran', 'Sayuran & Buah', '🥬', 4, true),
  ('fashion', 'Fashion', '👕', 5, true),
  ('elektronik', 'Elektronik', '📱', 6, true),
  ('rumah-tangga', 'Rumah Tangga', '🏠', 7, true),
  ('kerajinan', 'Kerajinan', '🎨', 8, true),
  ('kesehatan', 'Kesehatan', '💊', 9, true),
  ('lainnya', 'Lainnya', '📦', 99, true)
ON CONFLICT (slug) DO NOTHING;

-- Default app_settings
INSERT INTO public.app_settings (key, category, value, description, is_public) VALUES
  ('cod_settings', 'payment',
    '{"max_amount": 75000, "max_distance_km": 3, "min_trust_score": 50, "penalty_points": 50, "success_bonus_points": 1}'::jsonb,
    'Aturan Cash On Delivery', true),
  ('platform_fee', 'finance',
    '{"percent": 5, "min_amount": 500, "max_amount": 10000}'::jsonb,
    'Biaya platform per transaksi', true),
  ('courier_minimum_balance', 'courier',
    '{"amount": 50000}'::jsonb,
    'Saldo minimum tersisa saat kurir menarik dana', true),
  ('shipping_defaults', 'shipping',
    '{"base_fee": 5000, "per_km": 2000, "free_shipping_threshold": 100000}'::jsonb,
    'Default ongkir', true),
  ('site_info', 'general',
    '{"name": "DesaMart", "tagline": "Marketplace Desa Indonesia", "support_email": "support@desa-karya-nusantara.id"}'::jsonb,
    'Informasi umum situs', true)
ON CONFLICT (key) DO NOTHING;

-- Default POS packages
INSERT INTO public.pos_packages (name, description, price, duration_days, features, is_active) VALUES
  ('POS Basic', 'Fitur kasir dasar untuk UMKM', 50000, 30,
    '["Kasir","Katalog Produk","Struk Digital","Laporan Harian"]'::jsonb, true),
  ('POS Pro', 'Fitur lengkap untuk toko berkembang', 150000, 30,
    '["Semua fitur Basic","Multi-user","Manajemen Stok","Analitik","Kartu Loyalitas"]'::jsonb, true),
  ('POS Enterprise', 'Fitur enterprise untuk multi-outlet', 350000, 30,
    '["Semua fitur Pro","Multi-outlet","API Integration","Prioritas Support"]'::jsonb, true)
ON CONFLICT DO NOTHING;

-- Default transaction packages (kuota merchant)
INSERT INTO public.transaction_packages (name, description, price, transaction_quota, duration_days, group_commission_percent, is_active) VALUES
  ('Paket Starter', '100 transaksi selama 30 hari', 25000, 100, 30, 5, true),
  ('Paket Bisnis', '500 transaksi selama 30 hari', 100000, 500, 30, 5, true),
  ('Paket Premium', '2000 transaksi selama 30 hari', 350000, 2000, 30, 5, true)
ON CONFLICT DO NOTHING;

-- Default halal regulations
INSERT INTO public.halal_regulations (content) VALUES
  ('Semua produk makanan & minuman yang dijual wajib mencantumkan status sertifikasi halal jika berlaku. Merchant bertanggung jawab atas kebenaran informasi.')
ON CONFLICT DO NOTHING;

-- END OF FILE 05
