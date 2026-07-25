-- ============================================================
-- FILE 05: ADMIN SETTINGS, AUDIT, BACKUP, REALTIME & SEED DATA
-- Aligned with live schema. Idempotent.
-- ============================================================

-- 1. APP SETTINGS ----------------------------------------------
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
CREATE POLICY "Anyone can view settings" ON public.app_settings
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins can manage settings" ON public.app_settings;
CREATE POLICY "Admins can manage settings" ON public.app_settings
  FOR ALL USING (public.is_admin());

-- 2. ADMIN AUDIT LOGS ------------------------------------------
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
CREATE POLICY "Admins can view logs" ON public.admin_audit_logs
  FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins can insert logs" ON public.admin_audit_logs;
CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs
  FOR INSERT WITH CHECK (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id);

-- 3. BACKUP LOGS -----------------------------------------------
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
CREATE POLICY "Admins view backups" ON public.backup_logs
  FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS "Admins create backups" ON public.backup_logs;
CREATE POLICY "Admins create backups" ON public.backup_logs
  FOR INSERT WITH CHECK (public.is_admin());

-- 4. BACKUP SCHEDULES ------------------------------------------
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
CREATE POLICY "Admins can manage backup schedules" ON public.backup_schedules
  FOR ALL USING (public.is_admin());

-- 5. SEO SETTINGS ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path text NOT NULL UNIQUE,
  title text,
  description text,
  keywords text,
  og_image text,
  og_title text,
  og_description text,
  canonical_url text,
  robots text DEFAULT 'index, follow',
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

GRANT SELECT ON public.seo_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.seo_settings TO authenticated;
GRANT ALL ON public.seo_settings TO service_role;
ALTER TABLE public.seo_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view SEO settings" ON public.seo_settings;
CREATE POLICY "Anyone can view SEO settings" ON public.seo_settings
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins manage SEO" ON public.seo_settings;
CREATE POLICY "Admins manage SEO" ON public.seo_settings
  FOR ALL USING (public.is_admin());

-- 6. REALTIME PUBLICATIONS -------------------------------------
DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'orders','order_items','notifications','chat_messages',
    'ride_requests','couriers','merchants','products',
    'saved_addresses','courier_deposits','courier_balance_logs',
    'push_subscriptions','flash_sales','reviews'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t)
       AND NOT EXISTS (
      SELECT 1 FROM pg_publication_rel pr
      JOIN pg_publication p ON pr.prpubid = p.oid
      JOIN pg_class c ON pr.prrelid = c.oid
      JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE p.pubname = 'supabase_realtime'
        AND n.nspname = 'public' AND c.relname = t
    ) THEN
      BEGIN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped % : %', t, SQLERRM;
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
INSERT INTO public.app_settings (key, category, value, description) VALUES
  ('cod_settings', 'payment',
    '{"max_amount": 75000, "max_distance_km": 3, "min_trust_score": 50, "penalty_points": 50, "success_bonus_points": 1}'::jsonb,
    'Aturan Cash On Delivery'),
  ('platform_fee', 'finance',
    '{"percent": 5, "min_amount": 500, "max_amount": 10000}'::jsonb,
    'Biaya platform per transaksi'),
  ('courier_minimum_balance', 'courier',
    '{"amount": 50000}'::jsonb,
    'Saldo minimum tersisa saat kurir menarik dana'),
  ('shipping_defaults', 'shipping',
    '{"base_fee": 5000, "per_km": 2000, "free_shipping_threshold": 100000}'::jsonb,
    'Default ongkir'),
  ('site_info', 'general',
    '{"name": "DesaMart", "tagline": "Marketplace Desa Indonesia", "support_email": "support@desa-karya-nusantara.id"}'::jsonb,
    'Informasi umum situs')
ON CONFLICT (key) DO NOTHING;

-- Default POS packages
INSERT INTO public.pos_packages (name, description, price, duration_months, is_active, sort_order) VALUES
  ('POS Basic', 'Fitur kasir dasar untuk UMKM', 50000, 1, true, 1),
  ('POS Pro', 'Fitur lengkap untuk toko berkembang', 150000, 1, true, 2),
  ('POS Enterprise', 'Fitur enterprise untuk multi-outlet', 350000, 1, true, 3)
ON CONFLICT DO NOTHING;

-- Default transaction packages (kuota merchant)
INSERT INTO public.transaction_packages (name, description, classification_price, price_per_transaction, transaction_quota, validity_days, total_credits, group_commission_percent, is_active) VALUES
  ('Paket Starter', '100 transaksi selama 30 hari', 'UNDER_5K', 250, 100, 30, 100, 5, true),
  ('Paket Bisnis', '500 transaksi selama 30 hari', 'FROM_5K_TO_10K', 200, 500, 30, 500, 5, true),
  ('Paket Premium', '2000 transaksi selama 30 hari', 'ABOVE_20K', 175, 2000, 30, 2000, 5, true)
ON CONFLICT DO NOTHING;

-- Default halal regulations (only if empty)
INSERT INTO public.halal_regulations (content)
SELECT 'Semua produk makanan & minuman yang dijual wajib mencantumkan status sertifikasi halal jika berlaku. Merchant bertanggung jawab atas kebenaran informasi.'
WHERE NOT EXISTS (SELECT 1 FROM public.halal_regulations);

-- END OF FILE 05
