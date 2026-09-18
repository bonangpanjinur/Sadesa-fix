-- Merchant paid advertising workflow
-- Merchants submit paid placements; admins approve them before public display.

CREATE TABLE IF NOT EXISTS public.ad_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  description TEXT,
  price_per_day NUMERIC(12, 0) NOT NULL CHECK (price_per_day > 0),
  max_days INTEGER NOT NULL DEFAULT 30 CHECK (max_days BETWEEN 1 AND 365),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID REFERENCES public.ad_packages(id) ON DELETE SET NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  description TEXT,
  image_url TEXT,
  link_url TEXT,
  duration_days INTEGER NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'expired', 'rejected')),
  payment_amount NUMERIC(12, 0) NOT NULL CHECK (payment_amount >= 0),
  payment_proof_url TEXT,
  rejection_reason TEXT,
  view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  click_count INTEGER NOT NULL DEFAULT 0 CHECK (click_count >= 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT merchant_ads_dates_valid CHECK (end_date IS NULL OR start_date IS NULL OR end_date > start_date)
);

CREATE INDEX IF NOT EXISTS merchant_ads_public_banner_idx
  ON public.merchant_ads (placement_type, status, start_date, end_date, sort_order);
CREATE INDEX IF NOT EXISTS merchant_ads_merchant_idx
  ON public.merchant_ads (merchant_id, created_at DESC);

ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.ad_packages TO anon, authenticated;
GRANT SELECT ON public.merchant_ads TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.ad_packages TO authenticated;
GRANT INSERT, UPDATE ON public.merchant_ads TO authenticated;

DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages;
CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS "Admins manage ad packages" ON public.ad_packages;
CREATE POLICY "Admins manage ad packages" ON public.ad_packages
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active merchant ads" ON public.merchant_ads;
CREATE POLICY "Anyone can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    (status = 'active' AND start_date <= now() AND (end_date IS NULL OR end_date >= now()))
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Merchants submit own ads" ON public.merchant_ads;
CREATE POLICY "Merchants submit own ads" ON public.merchant_ads
  FOR INSERT WITH CHECK (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id
        AND m.user_id = auth.uid()
        AND m.registration_status = 'APPROVED'
    )
  );

DROP POLICY IF EXISTS "Merchants update own pending ads" ON public.merchant_ads;
CREATE POLICY "Merchants update own pending ads" ON public.merchant_ads
  FOR UPDATE USING (
    public.is_admin() OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
    )
  ) WITH CHECK (
    public.is_admin() OR (
      status = 'pending' AND EXISTS (
        SELECT 1 FROM public.merchants m
        WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
      )
    )
  );

DROP TRIGGER IF EXISTS update_ad_packages_updated_at ON public.ad_packages;
CREATE TRIGGER update_ad_packages_updated_at
  BEFORE UPDATE ON public.ad_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_merchant_ads_updated_at ON public.merchant_ads;
CREATE TRIGGER update_merchant_ads_updated_at
  BEFORE UPDATE ON public.merchant_ads
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days, is_active)
VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000, 30, true),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000, 30, true),
  ('Banner di Atas Menu', 'home_banner', 'Banner besar di atas menu layanan halaman utama', 50000, 14, true),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi rekomendasi produk', 10000, 30, true)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.merchant_ads IS 'Paid merchant advertising submissions, approved by admin before publication.';
COMMENT ON COLUMN public.merchant_ads.placement_type IS 'home_banner renders above the main service menu on the homepage.';

NOTIFY pgrst, 'reload schema';
