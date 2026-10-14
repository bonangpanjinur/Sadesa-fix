-- Create promotions/ads table for various ad types
CREATE TABLE public.promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('banner', 'wisata_populer', 'produk_populer', 'promo_spesial')),
  title TEXT NOT NULL,
  subtitle TEXT,
  image_url TEXT,
  link_url TEXT,
  link_type TEXT CHECK (link_type IN ('product', 'tourism', 'village', 'merchant', 'external', 'category')),
  link_id UUID,

  -- Who is advertising
  advertiser_type TEXT CHECK (advertiser_type IN ('admin', 'village', 'merchant')),
  advertiser_id UUID,

  -- Scheduling
  start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  end_date TIMESTAMP WITH TIME ZONE,

  -- Pricing & Status
  price INTEGER DEFAULT 0,
  is_paid BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  is_approved BOOLEAN DEFAULT false,

  -- Ordering
  sort_order INTEGER DEFAULT 0,

  -- Stats
  view_count INTEGER DEFAULT 0,
  click_count INTEGER DEFAULT 0,

  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_e5b81e1d1d59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5b81e1d1d59$;

DO $bootstrap_do_6aff1153c65d$
BEGIN
  EXECUTE $bootstrap_sql_6aff1153c65d$-- Enable RLS
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY$bootstrap_sql_6aff1153c65d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6aff1153c65d$;

DO $bootstrap_do_096ff8245365$
BEGIN
  EXECUTE $bootstrap_sql_096ff8245365$-- Anyone can view active & approved promotions within date range
DROP POLICY IF EXISTS "Anyone can view active promotions" ON public.promotions$bootstrap_sql_096ff8245365$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_096ff8245365$;

DO $bootstrap_do_371b1c9a079b$
BEGIN
  EXECUTE $bootstrap_sql_371b1c9a079b$CREATE POLICY "Anyone can view active promotions"
ON public.promotions
FOR SELECT
USING (
  is_active = true
  AND is_approved = true
  AND start_date <= now()
  AND (end_date IS NULL OR end_date >= now())
)$bootstrap_sql_371b1c9a079b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_371b1c9a079b$;

DO $bootstrap_do_c25ffa60425d$
BEGIN
  EXECUTE $bootstrap_sql_c25ffa60425d$-- Admin can manage all promotions
DROP POLICY IF EXISTS "Admins can manage promotions" ON public.promotions$bootstrap_sql_c25ffa60425d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c25ffa60425d$;

DO $bootstrap_do_082964e2708d$
BEGIN
  EXECUTE $bootstrap_sql_082964e2708d$CREATE POLICY "Admins can manage promotions"
ON public.promotions
FOR ALL
USING (is_admin())$bootstrap_sql_082964e2708d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_082964e2708d$;

DO $bootstrap_do_1e1b56d3e482$
BEGIN
  EXECUTE $bootstrap_sql_1e1b56d3e482$-- Villages can create promotions for themselves
DROP POLICY IF EXISTS "Villages can create own promotions" ON public.promotions$bootstrap_sql_1e1b56d3e482$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e1b56d3e482$;

DO $bootstrap_do_b1d3bd885d9b$
BEGIN
  EXECUTE $bootstrap_sql_b1d3bd885d9b$CREATE POLICY "Villages can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'village'
  AND is_approved = false
)$bootstrap_sql_b1d3bd885d9b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1d3bd885d9b$;

DO $bootstrap_do_26c8b5c7d495$
BEGIN
  EXECUTE $bootstrap_sql_26c8b5c7d495$-- Merchants can create promotions for themselves
DROP POLICY IF EXISTS "Merchants can create own promotions" ON public.promotions$bootstrap_sql_26c8b5c7d495$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26c8b5c7d495$;

DO $bootstrap_do_4d6ac6b73385$
BEGIN
  EXECUTE $bootstrap_sql_4d6ac6b73385$CREATE POLICY "Merchants can create own promotions"
ON public.promotions
FOR INSERT
WITH CHECK (
  advertiser_type = 'merchant'
  AND is_approved = false
)$bootstrap_sql_4d6ac6b73385$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d6ac6b73385$;

DO $bootstrap_do_4d3039df4dd9$
BEGIN
  EXECUTE $bootstrap_sql_4d3039df4dd9$-- Add trigger for updated_at
DROP TRIGGER IF EXISTS update_promotions_updated_at ON public.promotions$bootstrap_sql_4d3039df4dd9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d3039df4dd9$;

DO $bootstrap_do_26f6952a4e39$
BEGIN
  EXECUTE $bootstrap_sql_26f6952a4e39$CREATE TRIGGER update_promotions_updated_at
BEFORE UPDATE ON public.promotions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_26f6952a4e39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26f6952a4e39$;

DO $bootstrap_do_f0aa7b9d4cbe$
BEGIN
  EXECUTE $bootstrap_sql_f0aa7b9d4cbe$-- Insert sample banner promotions
INSERT INTO public.promotions (type, title, subtitle, image_url, link_url, link_type, advertiser_type, is_approved, sort_order) VALUES
('banner', 'Jelajahi Produk Asli Desa', 'Dukung UMKM lokal & ekonomi desa Indonesia', NULL, '/products', 'category', 'admin', true, 1),
('banner', 'Wisata Desa Bojong', 'Nikmati keindahan alam dan budaya desa', NULL, '/tourism', 'category', 'admin', true, 2),
('banner', 'Promo Spesial Akhir Bulan', 'Diskon hingga 30% untuk produk pilihan', NULL, '/products', 'category', 'admin', true, 3)
ON CONFLICT DO NOTHING$bootstrap_sql_f0aa7b9d4cbe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f0aa7b9d4cbe$;

DO $bootstrap_do_edf764f7ce14$
BEGIN
  EXECUTE $bootstrap_sql_edf764f7ce14$
