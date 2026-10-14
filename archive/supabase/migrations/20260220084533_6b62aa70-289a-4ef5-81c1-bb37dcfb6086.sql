-- Create merchant gallery table for "Tentang Kami" photos
CREATE TABLE public.merchant_gallery (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  caption text,
  sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_0fa1b63ea59c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0fa1b63ea59c$;

DO $bootstrap_do_49ca0854500f$
BEGIN
  EXECUTE $bootstrap_sql_49ca0854500f$-- Enable RLS
ALTER TABLE public.merchant_gallery ENABLE ROW LEVEL SECURITY$bootstrap_sql_49ca0854500f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49ca0854500f$;

DO $bootstrap_do_e141ceb4955f$
BEGIN
  EXECUTE $bootstrap_sql_e141ceb4955f$-- Anyone can view gallery images of active merchants
DROP POLICY IF EXISTS "Public can view merchant gallery" ON public.merchant_gallery$bootstrap_sql_e141ceb4955f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e141ceb4955f$;

DO $bootstrap_do_fca6623a7f67$
BEGIN
  EXECUTE $bootstrap_sql_fca6623a7f67$CREATE POLICY "Public can view merchant gallery"
  ON public.merchant_gallery FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = merchant_gallery.merchant_id
    AND merchants.status = 'ACTIVE'
    AND merchants.registration_status = 'APPROVED'
  ))$bootstrap_sql_fca6623a7f67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fca6623a7f67$;

DO $bootstrap_do_788eb8d588a1$
BEGIN
  EXECUTE $bootstrap_sql_788eb8d588a1$-- Merchants can manage own gallery
DROP POLICY IF EXISTS "Merchants can manage own gallery" ON public.merchant_gallery$bootstrap_sql_788eb8d588a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_788eb8d588a1$;

DO $bootstrap_do_fd6152178cb7$
BEGIN
  EXECUTE $bootstrap_sql_fd6152178cb7$CREATE POLICY "Merchants can manage own gallery"
  ON public.merchant_gallery FOR ALL
  USING (EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = merchant_gallery.merchant_id
    AND merchants.user_id = auth.uid()
  ))$bootstrap_sql_fd6152178cb7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd6152178cb7$;

DO $bootstrap_do_aea04dc56ad4$
BEGIN
  EXECUTE $bootstrap_sql_aea04dc56ad4$-- Admins can manage all galleries
DROP POLICY IF EXISTS "Admins can manage all galleries" ON public.merchant_gallery$bootstrap_sql_aea04dc56ad4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aea04dc56ad4$;

DO $bootstrap_do_360cdd52886a$
BEGIN
  EXECUTE $bootstrap_sql_360cdd52886a$CREATE POLICY "Admins can manage all galleries"
  ON public.merchant_gallery FOR ALL
  USING (is_admin())$bootstrap_sql_360cdd52886a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_360cdd52886a$;

DO $bootstrap_do_1ba72384c7a8$
BEGIN
  EXECUTE $bootstrap_sql_1ba72384c7a8$-- Create storage bucket for merchant gallery images
INSERT INTO storage.buckets (id, name, public) VALUES ('merchant-gallery', 'merchant-gallery', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_1ba72384c7a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ba72384c7a8$;

DO $bootstrap_do_f72e50599c7d$
BEGIN
  EXECUTE $bootstrap_sql_f72e50599c7d$-- Storage policies for merchant gallery
DROP POLICY IF EXISTS "Public can view merchant gallery images" ON storage.objects$bootstrap_sql_f72e50599c7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f72e50599c7d$;

DO $bootstrap_do_85050b33ad66$
BEGIN
  EXECUTE $bootstrap_sql_85050b33ad66$CREATE POLICY "Public can view merchant gallery images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'merchant-gallery')$bootstrap_sql_85050b33ad66$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_85050b33ad66$;

DO $bootstrap_do_a9668d959ee3$
BEGIN
  EXECUTE $bootstrap_sql_a9668d959ee3$DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects$bootstrap_sql_a9668d959ee3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9668d959ee3$;

DO $bootstrap_do_e3f008ef0496$
BEGIN
  EXECUTE $bootstrap_sql_e3f008ef0496$CREATE POLICY "Authenticated users can upload merchant gallery images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL)$bootstrap_sql_e3f008ef0496$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e3f008ef0496$;

DO $bootstrap_do_45f2c514967b$
BEGIN
  EXECUTE $bootstrap_sql_45f2c514967b$DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects$bootstrap_sql_45f2c514967b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45f2c514967b$;

DO $bootstrap_do_ffed30449dce$
BEGIN
  EXECUTE $bootstrap_sql_ffed30449dce$CREATE POLICY "Users can update own merchant gallery images"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL)$bootstrap_sql_ffed30449dce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ffed30449dce$;

DO $bootstrap_do_cac58afc1945$
BEGIN
  EXECUTE $bootstrap_sql_cac58afc1945$DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects$bootstrap_sql_cac58afc1945$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cac58afc1945$;

DO $bootstrap_do_ca58c38dea87$
BEGIN
  EXECUTE $bootstrap_sql_ca58c38dea87$CREATE POLICY "Users can delete own merchant gallery images"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'merchant-gallery' AND auth.uid() IS NOT NULL)$bootstrap_sql_ca58c38dea87$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca58c38dea87$;

DO $bootstrap_do_db906ce76c17$
BEGIN
  EXECUTE $bootstrap_sql_db906ce76c17$
