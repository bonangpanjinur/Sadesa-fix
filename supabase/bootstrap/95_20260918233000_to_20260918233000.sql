-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260918233000_merchant_paid_ads.sql .. 20260918233000_merchant_paid_ads.sql

-- ===== BEGIN SOURCE: 20260918233000_merchant_paid_ads.sql =====
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
);

CREATE TABLE IF NOT EXISTS public.merchant_ads (
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
);

CREATE INDEX IF NOT EXISTS idx_ad_packages_active ON public.ad_packages(is_active, placement_type);
CREATE INDEX IF NOT EXISTS idx_merchant_ads_delivery ON public.merchant_ads(placement_type, status, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_merchant_ads_merchant ON public.merchant_ads(merchant_id, created_at DESC);

ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages;
CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admin manages ad packages" ON public.ad_packages;
CREATE POLICY "Admin manages ad packages" ON public.ad_packages
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Public can view active merchant ads" ON public.merchant_ads;
CREATE POLICY "Public can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    status = 'active'
    AND (start_date IS NULL OR start_date <= now())
    AND (end_date IS NULL OR end_date > now())
  );

DROP POLICY IF EXISTS "Merchant can view own ads" ON public.merchant_ads;
CREATE POLICY "Merchant can view own ads" ON public.merchant_ads
  FOR SELECT TO authenticated USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Merchant can submit own ads" ON public.merchant_ads;
CREATE POLICY "Merchant can submit own ads" ON public.merchant_ads
  FOR INSERT TO authenticated WITH CHECK (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
    AND status = 'pending'
  );

DROP POLICY IF EXISTS "Admin moderates merchant ads" ON public.merchant_ads;
CREATE POLICY "Admin moderates merchant ads" ON public.merchant_ads
  FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admin deletes merchant ads" ON public.merchant_ads;
CREATE POLICY "Admin deletes merchant ads" ON public.merchant_ads
  FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- A public bucket is needed for creative images; database policies still control
-- which campaigns can be delivered to buyers.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects;
CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads');

INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days)
SELECT * FROM (VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000::numeric, 30),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000::numeric, 30),
  ('Banner Homepage', 'home_banner', 'Tampil sebagai rekomendasi sponsor di halaman utama', 50000::numeric, 14),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi produk pilihan', 10000::numeric, 30)
) AS seed(name, placement_type, description, price_per_day, max_days)
WHERE NOT EXISTS (SELECT 1 FROM public.ad_packages WHERE ad_packages.placement_type = seed.placement_type);

-- ===== END SOURCE: 20260918233000_merchant_paid_ads.sql =====
