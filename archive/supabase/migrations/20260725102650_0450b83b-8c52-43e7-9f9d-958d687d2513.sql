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
)$bootstrap_sql_659492747129$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_659492747129$;

DO $bootstrap_do_a0dafdf6a717$
BEGIN
  EXECUTE $bootstrap_sql_a0dafdf6a717$GRANT SELECT ON public.app_settings TO anon, authenticated$bootstrap_sql_a0dafdf6a717$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0dafdf6a717$;

DO $bootstrap_do_46f21ba6e9fb$
BEGIN
  EXECUTE $bootstrap_sql_46f21ba6e9fb$GRANT INSERT, UPDATE, DELETE ON public.app_settings TO authenticated$bootstrap_sql_46f21ba6e9fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46f21ba6e9fb$;

DO $bootstrap_do_3bcd435d2be4$
BEGIN
  EXECUTE $bootstrap_sql_3bcd435d2be4$GRANT ALL ON public.app_settings TO service_role$bootstrap_sql_3bcd435d2be4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3bcd435d2be4$;

DO $bootstrap_do_09f7303fb5e6$
BEGIN
  EXECUTE $bootstrap_sql_09f7303fb5e6$ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_09f7303fb5e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09f7303fb5e6$;

DO $bootstrap_do_ef393289bea5$
BEGIN
  EXECUTE $bootstrap_sql_ef393289bea5$DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings$bootstrap_sql_ef393289bea5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef393289bea5$;

DO $bootstrap_do_f953b8e5cf2d$
BEGIN
  EXECUTE $bootstrap_sql_f953b8e5cf2d$CREATE POLICY "Anyone can view settings" ON public.app_settings FOR SELECT USING (true)$bootstrap_sql_f953b8e5cf2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f953b8e5cf2d$;

DO $bootstrap_do_6b43d1f9f208$
BEGIN
  EXECUTE $bootstrap_sql_6b43d1f9f208$DROP POLICY IF EXISTS "Admins can manage settings" ON public.app_settings$bootstrap_sql_6b43d1f9f208$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b43d1f9f208$;

DO $bootstrap_do_ced50efb19b3$
BEGIN
  EXECUTE $bootstrap_sql_ced50efb19b3$CREATE POLICY "Admins can manage settings" ON public.app_settings FOR ALL USING (public.is_admin())$bootstrap_sql_ced50efb19b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ced50efb19b3$;

DO $bootstrap_do_3afc39200007$
BEGIN
  EXECUTE $bootstrap_sql_3afc39200007$CREATE TABLE IF NOT EXISTS public.admin_audit_logs (
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
)$bootstrap_sql_3afc39200007$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3afc39200007$;

DO $bootstrap_do_1558da6f693d$
BEGIN
  EXECUTE $bootstrap_sql_1558da6f693d$GRANT SELECT, INSERT ON public.admin_audit_logs TO authenticated$bootstrap_sql_1558da6f693d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1558da6f693d$;

DO $bootstrap_do_60b94fb11ff4$
BEGIN
  EXECUTE $bootstrap_sql_60b94fb11ff4$GRANT ALL ON public.admin_audit_logs TO service_role$bootstrap_sql_60b94fb11ff4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60b94fb11ff4$;

DO $bootstrap_do_9c213d7d1e59$
BEGIN
  EXECUTE $bootstrap_sql_9c213d7d1e59$ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_9c213d7d1e59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c213d7d1e59$;

DO $bootstrap_do_0dd8b843a63f$
BEGIN
  EXECUTE $bootstrap_sql_0dd8b843a63f$DROP POLICY IF EXISTS "Admins can view logs" ON public.admin_audit_logs$bootstrap_sql_0dd8b843a63f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0dd8b843a63f$;

DO $bootstrap_do_96bf336bab2e$
BEGIN
  EXECUTE $bootstrap_sql_96bf336bab2e$CREATE POLICY "Admins can view logs" ON public.admin_audit_logs FOR SELECT USING (public.is_admin())$bootstrap_sql_96bf336bab2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_96bf336bab2e$;

DO $bootstrap_do_63b1255d8415$
BEGIN
  EXECUTE $bootstrap_sql_63b1255d8415$DROP POLICY IF EXISTS "Admins can insert logs" ON public.admin_audit_logs$bootstrap_sql_63b1255d8415$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63b1255d8415$;

DO $bootstrap_do_16292f394083$
BEGIN
  EXECUTE $bootstrap_sql_16292f394083$CREATE POLICY "Admins can insert logs" ON public.admin_audit_logs FOR INSERT WITH CHECK (public.is_admin())$bootstrap_sql_16292f394083$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16292f394083$;

DO $bootstrap_do_ba058387cb39$
BEGIN
  EXECUTE $bootstrap_sql_ba058387cb39$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created ON public.admin_audit_logs(created_at DESC)$bootstrap_sql_ba058387cb39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba058387cb39$;

DO $bootstrap_do_5dd69df6d3d6$
BEGIN
  EXECUTE $bootstrap_sql_5dd69df6d3d6$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin ON public.admin_audit_logs(admin_id)$bootstrap_sql_5dd69df6d3d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5dd69df6d3d6$;

DO $bootstrap_do_398d103e83fc$
BEGIN
  EXECUTE $bootstrap_sql_398d103e83fc$CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity ON public.admin_audit_logs(entity_type, entity_id)$bootstrap_sql_398d103e83fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_398d103e83fc$;

DO $bootstrap_do_59aef008c218$
BEGIN
  EXECUTE $bootstrap_sql_59aef008c218$CREATE TABLE IF NOT EXISTS public.backup_logs (
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
)$bootstrap_sql_59aef008c218$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59aef008c218$;

DO $bootstrap_do_ba09c15a91a4$
BEGIN
  EXECUTE $bootstrap_sql_ba09c15a91a4$GRANT SELECT, INSERT, UPDATE ON public.backup_logs TO authenticated$bootstrap_sql_ba09c15a91a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba09c15a91a4$;

DO $bootstrap_do_2ccee5a6f611$
BEGIN
  EXECUTE $bootstrap_sql_2ccee5a6f611$GRANT ALL ON public.backup_logs TO service_role$bootstrap_sql_2ccee5a6f611$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ccee5a6f611$;

DO $bootstrap_do_894ceac39257$
BEGIN
  EXECUTE $bootstrap_sql_894ceac39257$ALTER TABLE public.backup_logs ENABLE ROW LEVEL SECURITY$bootstrap_sql_894ceac39257$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_894ceac39257$;

DO $bootstrap_do_01e27b3dcb02$
BEGIN
  EXECUTE $bootstrap_sql_01e27b3dcb02$DROP POLICY IF EXISTS "Admins view backups" ON public.backup_logs$bootstrap_sql_01e27b3dcb02$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01e27b3dcb02$;

DO $bootstrap_do_0b7cea87cfc4$
BEGIN
  EXECUTE $bootstrap_sql_0b7cea87cfc4$CREATE POLICY "Admins view backups" ON public.backup_logs FOR SELECT USING (public.is_admin())$bootstrap_sql_0b7cea87cfc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b7cea87cfc4$;

DO $bootstrap_do_33e2d069fa2a$
BEGIN
  EXECUTE $bootstrap_sql_33e2d069fa2a$DROP POLICY IF EXISTS "Admins create backups" ON public.backup_logs$bootstrap_sql_33e2d069fa2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33e2d069fa2a$;

DO $bootstrap_do_246a39aa41bd$
BEGIN
  EXECUTE $bootstrap_sql_246a39aa41bd$CREATE POLICY "Admins create backups" ON public.backup_logs FOR INSERT WITH CHECK (public.is_admin())$bootstrap_sql_246a39aa41bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_246a39aa41bd$;

DO $bootstrap_do_d5cd81945ce7$
BEGIN
  EXECUTE $bootstrap_sql_d5cd81945ce7$CREATE TABLE IF NOT EXISTS public.backup_schedules (
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
)$bootstrap_sql_d5cd81945ce7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5cd81945ce7$;

DO $bootstrap_do_ad2facbf8222$
BEGIN
  EXECUTE $bootstrap_sql_ad2facbf8222$GRANT SELECT, INSERT, UPDATE, DELETE ON public.backup_schedules TO authenticated$bootstrap_sql_ad2facbf8222$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad2facbf8222$;

DO $bootstrap_do_eb4c4e0cfb75$
BEGIN
  EXECUTE $bootstrap_sql_eb4c4e0cfb75$GRANT ALL ON public.backup_schedules TO service_role$bootstrap_sql_eb4c4e0cfb75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb4c4e0cfb75$;

DO $bootstrap_do_8bf90e2feba3$
BEGIN
  EXECUTE $bootstrap_sql_8bf90e2feba3$ALTER TABLE public.backup_schedules ENABLE ROW LEVEL SECURITY$bootstrap_sql_8bf90e2feba3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8bf90e2feba3$;

DO $bootstrap_do_bf665f521972$
BEGIN
  EXECUTE $bootstrap_sql_bf665f521972$DROP POLICY IF EXISTS "Admins can manage backup schedules" ON public.backup_schedules$bootstrap_sql_bf665f521972$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf665f521972$;

DO $bootstrap_do_2050c4bad47a$
BEGIN
  EXECUTE $bootstrap_sql_2050c4bad47a$CREATE POLICY "Admins can manage backup schedules" ON public.backup_schedules FOR ALL USING (public.is_admin())$bootstrap_sql_2050c4bad47a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2050c4bad47a$;

DO $bootstrap_do_069dc36bbabe$
BEGIN
  EXECUTE $bootstrap_sql_069dc36bbabe$CREATE TABLE IF NOT EXISTS public.seo_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_path text NOT NULL UNIQUE,
  title text, description text, keywords text,
  og_image text, og_title text, og_description text,
  canonical_url text, robots text DEFAULT 'index, follow',
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
)$bootstrap_sql_069dc36bbabe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_069dc36bbabe$;

DO $bootstrap_do_6d361de8717e$
BEGIN
  EXECUTE $bootstrap_sql_6d361de8717e$GRANT SELECT ON public.seo_settings TO anon, authenticated$bootstrap_sql_6d361de8717e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d361de8717e$;

DO $bootstrap_do_111937aae2b5$
BEGIN
  EXECUTE $bootstrap_sql_111937aae2b5$GRANT INSERT, UPDATE, DELETE ON public.seo_settings TO authenticated$bootstrap_sql_111937aae2b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_111937aae2b5$;

DO $bootstrap_do_17f0095722ef$
BEGIN
  EXECUTE $bootstrap_sql_17f0095722ef$GRANT ALL ON public.seo_settings TO service_role$bootstrap_sql_17f0095722ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17f0095722ef$;

DO $bootstrap_do_6d3594818ee1$
BEGIN
  EXECUTE $bootstrap_sql_6d3594818ee1$ALTER TABLE public.seo_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_6d3594818ee1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d3594818ee1$;

DO $bootstrap_do_d10f58cc81e0$
BEGIN
  EXECUTE $bootstrap_sql_d10f58cc81e0$DROP POLICY IF EXISTS "Anyone can view SEO settings" ON public.seo_settings$bootstrap_sql_d10f58cc81e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d10f58cc81e0$;

DO $bootstrap_do_889dbc07c7fc$
BEGIN
  EXECUTE $bootstrap_sql_889dbc07c7fc$CREATE POLICY "Anyone can view SEO settings" ON public.seo_settings FOR SELECT USING (true)$bootstrap_sql_889dbc07c7fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_889dbc07c7fc$;

DO $bootstrap_do_ecb96973f2ff$
BEGIN
  EXECUTE $bootstrap_sql_ecb96973f2ff$DROP POLICY IF EXISTS "Admins manage SEO" ON public.seo_settings$bootstrap_sql_ecb96973f2ff$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ecb96973f2ff$;

DO $bootstrap_do_1907f25079d1$
BEGIN
  EXECUTE $bootstrap_sql_1907f25079d1$CREATE POLICY "Admins manage SEO" ON public.seo_settings FOR ALL USING (public.is_admin())$bootstrap_sql_1907f25079d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1907f25079d1$;

DO $bootstrap_do_87eab9c6998e$
BEGIN
  EXECUTE $bootstrap_sql_87eab9c6998e$-- Realtime publications
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
END $$$bootstrap_sql_87eab9c6998e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_87eab9c6998e$;

DO $bootstrap_do_e5af1ff7b745$
BEGIN
  EXECUTE $bootstrap_sql_e5af1ff7b745$-- Seed: kategori
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
ON CONFLICT (slug) DO NOTHING$bootstrap_sql_e5af1ff7b745$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5af1ff7b745$;

DO $bootstrap_do_b426afa0c304$
BEGIN
  EXECUTE $bootstrap_sql_b426afa0c304$-- Seed: app_settings
INSERT INTO public.app_settings (key, category, value, description) VALUES
  ('cod_settings','payment','{"max_amount":75000,"max_distance_km":3,"min_trust_score":50,"penalty_points":50,"success_bonus_points":1}'::jsonb,'Aturan Cash On Delivery'),
  ('platform_fee','finance','{"percent":5,"min_amount":500,"max_amount":10000}'::jsonb,'Biaya platform per transaksi'),
  ('courier_minimum_balance','courier','{"amount":50000}'::jsonb,'Saldo minimum tersisa saat kurir menarik dana'),
  ('shipping_defaults','shipping','{"base_fee":5000,"per_km":2000,"free_shipping_threshold":100000}'::jsonb,'Default ongkir'),
  ('site_info','general','{"name":"SaDesa","tagline":"Marketplace Desa Indonesia","support_email":"support@desa-karya-nusantara.id"}'::jsonb,'Informasi umum situs')
ON CONFLICT (key) DO NOTHING$bootstrap_sql_b426afa0c304$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b426afa0c304$;

DO $bootstrap_do_c08c518e2202$
BEGIN
  EXECUTE $bootstrap_sql_c08c518e2202$-- Seed: POS packages
INSERT INTO public.pos_packages (name, description, price, duration_months, is_active, sort_order) VALUES
  ('POS Basic','Fitur kasir dasar untuk UMKM',50000,1,true,1),
  ('POS Pro','Fitur lengkap untuk toko berkembang',150000,1,true,2),
  ('POS Enterprise','Fitur enterprise untuk multi-outlet',350000,1,true,3)
ON CONFLICT DO NOTHING$bootstrap_sql_c08c518e2202$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c08c518e2202$;

DO $bootstrap_do_d4d7198b499e$
BEGIN
  EXECUTE $bootstrap_sql_d4d7198b499e$-- Seed: transaction packages
INSERT INTO public.transaction_packages (name, description, classification_price, price_per_transaction, transaction_quota, validity_days, total_credits, group_commission_percent, is_active) VALUES
  ('Paket Starter','100 transaksi selama 30 hari','UNDER_5K',250,100,30,100,5,true),
  ('Paket Bisnis','500 transaksi selama 30 hari','FROM_5K_TO_10K',200,500,30,500,5,true),
  ('Paket Premium','2000 transaksi selama 30 hari','ABOVE_20K',175,2000,30,2000,5,true)
ON CONFLICT DO NOTHING$bootstrap_sql_d4d7198b499e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4d7198b499e$;

DO $bootstrap_do_c584411b1e2c$
BEGIN
  EXECUTE $bootstrap_sql_c584411b1e2c$-- Seed: halal regulations
INSERT INTO public.halal_regulations (content)
SELECT 'Semua produk makanan & minuman yang dijual wajib mencantumkan status sertifikasi halal jika berlaku. Merchant bertanggung jawab atas kebenaran informasi.'
WHERE NOT EXISTS (SELECT 1 FROM public.halal_regulations)
ON CONFLICT DO NOTHING$bootstrap_sql_c584411b1e2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c584411b1e2c$;

DO $bootstrap_do_7daed97e3978$
BEGIN
  EXECUTE $bootstrap_sql_7daed97e3978$
