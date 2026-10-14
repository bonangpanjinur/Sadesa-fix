-- Merchant paid advertising: packages, submissions, moderation and delivery.
CREATE TABLE IF NOT EXISTS public.ad_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  description TEXT,
  price_per_day NUMERIC(12, 2) NOT NULL CHECK (price_per_day > 0),
  max_days INTEGER NOT NULL DEFAULT 30 CHECK (max_days BETWEEN 1 AND 365),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_1c14b98fd2b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c14b98fd2b8$;

DO $bootstrap_do_2a8679f5759a$
BEGIN
  EXECUTE $bootstrap_sql_2a8679f5759a$CREATE TABLE IF NOT EXISTS public.merchant_ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID REFERENCES public.ad_packages(id) ON DELETE SET NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  description TEXT CHECK (description IS NULL OR char_length(description) <= 200),
  image_url TEXT,
  link_url TEXT,
  duration_days INTEGER NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'expired', 'rejected')),
  payment_amount NUMERIC(12, 2) NOT NULL CHECK (payment_amount >= 0),
  payment_proof_url TEXT,
  rejection_reason TEXT,
  view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  click_count INTEGER NOT NULL DEFAULT 0 CHECK (click_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT merchant_ads_date_order CHECK (end_date IS NULL OR start_date IS NULL OR end_date > start_date)
)$bootstrap_sql_2a8679f5759a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a8679f5759a$;

DO $bootstrap_do_fb3e992dc2d8$
BEGIN
  EXECUTE $bootstrap_sql_fb3e992dc2d8$CREATE INDEX IF NOT EXISTS idx_ad_packages_active ON public.ad_packages(is_active, placement_type)$bootstrap_sql_fb3e992dc2d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb3e992dc2d8$;

DO $bootstrap_do_90ddf159311b$
BEGIN
  EXECUTE $bootstrap_sql_90ddf159311b$CREATE INDEX IF NOT EXISTS idx_merchant_ads_delivery ON public.merchant_ads(placement_type, status, start_date, end_date)$bootstrap_sql_90ddf159311b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90ddf159311b$;

DO $bootstrap_do_814b802fe83d$
BEGIN
  EXECUTE $bootstrap_sql_814b802fe83d$CREATE INDEX IF NOT EXISTS idx_merchant_ads_merchant ON public.merchant_ads(merchant_id, created_at DESC)$bootstrap_sql_814b802fe83d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_814b802fe83d$;

DO $bootstrap_do_2d6700019f46$
BEGIN
  EXECUTE $bootstrap_sql_2d6700019f46$ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_2d6700019f46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d6700019f46$;

DO $bootstrap_do_bba9b6103b88$
BEGIN
  EXECUTE $bootstrap_sql_bba9b6103b88$ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY$bootstrap_sql_bba9b6103b88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bba9b6103b88$;

DO $bootstrap_do_eb22ad4b6b16$
BEGIN
  EXECUTE $bootstrap_sql_eb22ad4b6b16$DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages$bootstrap_sql_eb22ad4b6b16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb22ad4b6b16$;

DO $bootstrap_do_f54135440733$
BEGIN
  EXECUTE $bootstrap_sql_f54135440733$CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.has_role(auth.uid(), 'admin'))$bootstrap_sql_f54135440733$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f54135440733$;

DO $bootstrap_do_f3f567749b41$
BEGIN
  EXECUTE $bootstrap_sql_f3f567749b41$DROP POLICY IF EXISTS "Admin manages ad packages" ON public.ad_packages$bootstrap_sql_f3f567749b41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3f567749b41$;

DO $bootstrap_do_ad263997cb5d$
BEGIN
  EXECUTE $bootstrap_sql_ad263997cb5d$CREATE POLICY "Admin manages ad packages" ON public.ad_packages
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_ad263997cb5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad263997cb5d$;

DO $bootstrap_do_2a5444c9bfb9$
BEGIN
  EXECUTE $bootstrap_sql_2a5444c9bfb9$DROP POLICY IF EXISTS "Public can view active merchant ads" ON public.merchant_ads$bootstrap_sql_2a5444c9bfb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a5444c9bfb9$;

DO $bootstrap_do_7cf60ca1eb1e$
BEGIN
  EXECUTE $bootstrap_sql_7cf60ca1eb1e$CREATE POLICY "Public can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    status = 'active'
    AND (start_date IS NULL OR start_date <= now())
    AND (end_date IS NULL OR end_date > now())
  )$bootstrap_sql_7cf60ca1eb1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cf60ca1eb1e$;

DO $bootstrap_do_8679a5482f35$
BEGIN
  EXECUTE $bootstrap_sql_8679a5482f35$DROP POLICY IF EXISTS "Merchant can view own ads" ON public.merchant_ads$bootstrap_sql_8679a5482f35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8679a5482f35$;

DO $bootstrap_do_dc0fcc3fb861$
BEGIN
  EXECUTE $bootstrap_sql_dc0fcc3fb861$CREATE POLICY "Merchant can view own ads" ON public.merchant_ads
  FOR SELECT TO authenticated USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  )$bootstrap_sql_dc0fcc3fb861$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc0fcc3fb861$;

DO $bootstrap_do_6f7eb3cb3695$
BEGIN
  EXECUTE $bootstrap_sql_6f7eb3cb3695$DROP POLICY IF EXISTS "Merchant can submit own ads" ON public.merchant_ads$bootstrap_sql_6f7eb3cb3695$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f7eb3cb3695$;

DO $bootstrap_do_ab33caa9e871$
BEGIN
  EXECUTE $bootstrap_sql_ab33caa9e871$CREATE POLICY "Merchant can submit own ads" ON public.merchant_ads
  FOR INSERT TO authenticated WITH CHECK (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
    AND status = 'pending'
  )$bootstrap_sql_ab33caa9e871$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab33caa9e871$;

DO $bootstrap_do_abbb52577a59$
BEGIN
  EXECUTE $bootstrap_sql_abbb52577a59$DROP POLICY IF EXISTS "Admin moderates merchant ads" ON public.merchant_ads$bootstrap_sql_abbb52577a59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_abbb52577a59$;

DO $bootstrap_do_665d31ff5342$
BEGIN
  EXECUTE $bootstrap_sql_665d31ff5342$CREATE POLICY "Admin moderates merchant ads" ON public.merchant_ads
  FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_665d31ff5342$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_665d31ff5342$;

DO $bootstrap_do_4e0cda995ced$
BEGIN
  EXECUTE $bootstrap_sql_4e0cda995ced$DROP POLICY IF EXISTS "Admin deletes merchant ads" ON public.merchant_ads$bootstrap_sql_4e0cda995ced$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e0cda995ced$;

DO $bootstrap_do_968a929b52dd$
BEGIN
  EXECUTE $bootstrap_sql_968a929b52dd$CREATE POLICY "Admin deletes merchant ads" ON public.merchant_ads
  FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_968a929b52dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_968a929b52dd$;

DO $bootstrap_do_4fbd6d33372c$
BEGIN
  EXECUTE $bootstrap_sql_4fbd6d33372c$-- A public bucket is needed for creative images; database policies still control
-- which campaigns can be delivered to buyers.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_4fbd6d33372c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fbd6d33372c$;

DO $bootstrap_do_defc06c37ce7$
BEGIN
  EXECUTE $bootstrap_sql_defc06c37ce7$DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects$bootstrap_sql_defc06c37ce7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_defc06c37ce7$;

DO $bootstrap_do_bfe51739d13c$
BEGIN
  EXECUTE $bootstrap_sql_bfe51739d13c$CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads')$bootstrap_sql_bfe51739d13c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfe51739d13c$;

DO $bootstrap_do_9532f2f57c9c$
BEGIN
  EXECUTE $bootstrap_sql_9532f2f57c9c$DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects$bootstrap_sql_9532f2f57c9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9532f2f57c9c$;

DO $bootstrap_do_440f2f23f5dc$
BEGIN
  EXECUTE $bootstrap_sql_440f2f23f5dc$CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads')$bootstrap_sql_440f2f23f5dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_440f2f23f5dc$;

DO $bootstrap_do_c83ac311cc88$
BEGIN
  EXECUTE $bootstrap_sql_c83ac311cc88$DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects$bootstrap_sql_c83ac311cc88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c83ac311cc88$;

DO $bootstrap_do_fd190a5bee73$
BEGIN
  EXECUTE $bootstrap_sql_fd190a5bee73$CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_fd190a5bee73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd190a5bee73$;

DO $bootstrap_do_4458ecba248b$
BEGIN
  EXECUTE $bootstrap_sql_4458ecba248b$DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects$bootstrap_sql_4458ecba248b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4458ecba248b$;

DO $bootstrap_do_5681e10a4906$
BEGIN
  EXECUTE $bootstrap_sql_5681e10a4906$CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_5681e10a4906$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5681e10a4906$;

DO $bootstrap_do_fc0f1a8fdf46$
BEGIN
  EXECUTE $bootstrap_sql_fc0f1a8fdf46$INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days)
SELECT * FROM (VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000::numeric, 30),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000::numeric, 30),
  ('Banner Homepage', 'home_banner', 'Tampil sebagai rekomendasi sponsor di halaman utama', 50000::numeric, 14),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi produk pilihan', 10000::numeric, 30)
) AS seed(name, placement_type, description, price_per_day, max_days)
WHERE NOT EXISTS (SELECT 1 FROM public.ad_packages WHERE ad_packages.placement_type = seed.placement_type)
ON CONFLICT DO NOTHING$bootstrap_sql_fc0f1a8fdf46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc0f1a8fdf46$;

DO $bootstrap_do_f4f6480528db$
BEGIN
  EXECUTE $bootstrap_sql_f4f6480528db$
