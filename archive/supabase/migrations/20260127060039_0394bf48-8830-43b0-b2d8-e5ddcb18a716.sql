-- Create storage buckets for images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('product-images', 'product-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('tourism-images', 'tourism-images', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('profile-images', 'profile-images', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('merchant-images', 'merchant-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING$bootstrap_sql_87b42084289d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_87b42084289d$;

DO $bootstrap_do_215655b5f5ec$
BEGIN
  EXECUTE $bootstrap_sql_215655b5f5ec$-- RLS for product-images: Merchants can upload to their own folder
DROP POLICY IF EXISTS "Anyone can view product images" ON storage.objects$bootstrap_sql_215655b5f5ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_215655b5f5ec$;

DO $bootstrap_do_a5d0232f48c9$
BEGIN
  EXECUTE $bootstrap_sql_a5d0232f48c9$CREATE POLICY "Anyone can view product images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images')$bootstrap_sql_a5d0232f48c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5d0232f48c9$;

DO $bootstrap_do_330a1e77b34b$
BEGIN
  EXECUTE $bootstrap_sql_330a1e77b34b$DROP POLICY IF EXISTS "Merchants can upload product images" ON storage.objects$bootstrap_sql_330a1e77b34b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_330a1e77b34b$;

DO $bootstrap_do_487bc127b803$
BEGIN
  EXECUTE $bootstrap_sql_487bc127b803$CREATE POLICY "Merchants can upload product images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
      AND merchants.status = 'ACTIVE'
    )
  )
)$bootstrap_sql_487bc127b803$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_487bc127b803$;

DO $bootstrap_do_ef912f4af287$
BEGIN
  EXECUTE $bootstrap_sql_ef912f4af287$DROP POLICY IF EXISTS "Merchants can update own product images" ON storage.objects$bootstrap_sql_ef912f4af287$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef912f4af287$;

DO $bootstrap_do_2308d85a13c5$
BEGIN
  EXECUTE $bootstrap_sql_2308d85a13c5$CREATE POLICY "Merchants can update own product images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
)$bootstrap_sql_2308d85a13c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2308d85a13c5$;

DO $bootstrap_do_59adad2337d9$
BEGIN
  EXECUTE $bootstrap_sql_59adad2337d9$DROP POLICY IF EXISTS "Merchants can delete own product images" ON storage.objects$bootstrap_sql_59adad2337d9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59adad2337d9$;

DO $bootstrap_do_56b3daa80cbf$
BEGIN
  EXECUTE $bootstrap_sql_56b3daa80cbf$CREATE POLICY "Merchants can delete own product images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'product-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
)$bootstrap_sql_56b3daa80cbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56b3daa80cbf$;

DO $bootstrap_do_d5a8e77ee1c4$
BEGIN
  EXECUTE $bootstrap_sql_d5a8e77ee1c4$-- RLS for tourism-images: Admin desa can upload
DROP POLICY IF EXISTS "Anyone can view tourism images" ON storage.objects$bootstrap_sql_d5a8e77ee1c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5a8e77ee1c4$;

DO $bootstrap_do_0baf9c211791$
BEGIN
  EXECUTE $bootstrap_sql_0baf9c211791$CREATE POLICY "Anyone can view tourism images"
ON storage.objects FOR SELECT
USING (bucket_id = 'tourism-images')$bootstrap_sql_0baf9c211791$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0baf9c211791$;

DO $bootstrap_do_a697c22c5cf3$
BEGIN
  EXECUTE $bootstrap_sql_a697c22c5cf3$DROP POLICY IF EXISTS "Admin desa can upload tourism images" ON storage.objects$bootstrap_sql_a697c22c5cf3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a697c22c5cf3$;

DO $bootstrap_do_89bd077cb27f$
BEGIN
  EXECUTE $bootstrap_sql_89bd077cb27f$CREATE POLICY "Admin desa can upload tourism images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
)$bootstrap_sql_89bd077cb27f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89bd077cb27f$;

DO $bootstrap_do_176d16fb85cf$
BEGIN
  EXECUTE $bootstrap_sql_176d16fb85cf$DROP POLICY IF EXISTS "Admin desa can update tourism images" ON storage.objects$bootstrap_sql_176d16fb85cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_176d16fb85cf$;

DO $bootstrap_do_b67c8d39adce$
BEGIN
  EXECUTE $bootstrap_sql_b67c8d39adce$CREATE POLICY "Admin desa can update tourism images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
)$bootstrap_sql_b67c8d39adce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b67c8d39adce$;

DO $bootstrap_do_7dd42c981cc5$
BEGIN
  EXECUTE $bootstrap_sql_7dd42c981cc5$DROP POLICY IF EXISTS "Admin desa can delete tourism images" ON storage.objects$bootstrap_sql_7dd42c981cc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7dd42c981cc5$;

DO $bootstrap_do_3e55768bab1b$
BEGIN
  EXECUTE $bootstrap_sql_3e55768bab1b$CREATE POLICY "Admin desa can delete tourism images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'tourism-images'
  AND (is_admin() OR is_admin_desa())
)$bootstrap_sql_3e55768bab1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e55768bab1b$;

DO $bootstrap_do_a40cae244bd7$
BEGIN
  EXECUTE $bootstrap_sql_a40cae244bd7$-- RLS for profile-images: Users can upload their own
DROP POLICY IF EXISTS "Anyone can view profile images" ON storage.objects$bootstrap_sql_a40cae244bd7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a40cae244bd7$;

DO $bootstrap_do_8b9ad2676c05$
BEGIN
  EXECUTE $bootstrap_sql_8b9ad2676c05$CREATE POLICY "Anyone can view profile images"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-images')$bootstrap_sql_8b9ad2676c05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b9ad2676c05$;

DO $bootstrap_do_e2544ce1310d$
BEGIN
  EXECUTE $bootstrap_sql_e2544ce1310d$DROP POLICY IF EXISTS "Users can upload own profile image" ON storage.objects$bootstrap_sql_e2544ce1310d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e2544ce1310d$;

DO $bootstrap_do_50bc45696f3f$
BEGIN
  EXECUTE $bootstrap_sql_50bc45696f3f$CREATE POLICY "Users can upload own profile image"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'profile-images'
  AND auth.uid() IS NOT NULL
)$bootstrap_sql_50bc45696f3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50bc45696f3f$;

DO $bootstrap_do_d33ccf4d7827$
BEGIN
  EXECUTE $bootstrap_sql_d33ccf4d7827$DROP POLICY IF EXISTS "Users can update own profile image" ON storage.objects$bootstrap_sql_d33ccf4d7827$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d33ccf4d7827$;

DO $bootstrap_do_5b05f0f19329$
BEGIN
  EXECUTE $bootstrap_sql_5b05f0f19329$CREATE POLICY "Users can update own profile image"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'profile-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
)$bootstrap_sql_5b05f0f19329$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b05f0f19329$;

DO $bootstrap_do_dd188bd2d14d$
BEGIN
  EXECUTE $bootstrap_sql_dd188bd2d14d$DROP POLICY IF EXISTS "Users can delete own profile image" ON storage.objects$bootstrap_sql_dd188bd2d14d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd188bd2d14d$;

DO $bootstrap_do_a4152703d606$
BEGIN
  EXECUTE $bootstrap_sql_a4152703d606$CREATE POLICY "Users can delete own profile image"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'profile-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
)$bootstrap_sql_a4152703d606$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4152703d606$;

DO $bootstrap_do_fa064438e341$
BEGIN
  EXECUTE $bootstrap_sql_fa064438e341$-- RLS for merchant-images: Merchants can upload their store image
DROP POLICY IF EXISTS "Anyone can view merchant images" ON storage.objects$bootstrap_sql_fa064438e341$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa064438e341$;

DO $bootstrap_do_464a04a77d16$
BEGIN
  EXECUTE $bootstrap_sql_464a04a77d16$CREATE POLICY "Anyone can view merchant images"
ON storage.objects FOR SELECT
USING (bucket_id = 'merchant-images')$bootstrap_sql_464a04a77d16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_464a04a77d16$;

DO $bootstrap_do_401425707810$
BEGIN
  EXECUTE $bootstrap_sql_401425707810$DROP POLICY IF EXISTS "Merchants can upload merchant images" ON storage.objects$bootstrap_sql_401425707810$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_401425707810$;

DO $bootstrap_do_55330769a44d$
BEGIN
  EXECUTE $bootstrap_sql_55330769a44d$CREATE POLICY "Merchants can upload merchant images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    auth.uid() IS NOT NULL
  )
)$bootstrap_sql_55330769a44d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55330769a44d$;

DO $bootstrap_do_b147f70f4248$
BEGIN
  EXECUTE $bootstrap_sql_b147f70f4248$DROP POLICY IF EXISTS "Merchants can update own merchant images" ON storage.objects$bootstrap_sql_b147f70f4248$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b147f70f4248$;

DO $bootstrap_do_9658ea6f8819$
BEGIN
  EXECUTE $bootstrap_sql_9658ea6f8819$CREATE POLICY "Merchants can update own merchant images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
)$bootstrap_sql_9658ea6f8819$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9658ea6f8819$;

DO $bootstrap_do_e1be8390917f$
BEGIN
  EXECUTE $bootstrap_sql_e1be8390917f$DROP POLICY IF EXISTS "Merchants can delete own merchant images" ON storage.objects$bootstrap_sql_e1be8390917f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1be8390917f$;

DO $bootstrap_do_141ac473ae30$
BEGIN
  EXECUTE $bootstrap_sql_141ac473ae30$CREATE POLICY "Merchants can delete own merchant images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'merchant-images'
  AND (
    is_admin() OR
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.user_id = auth.uid()
    )
  )
)$bootstrap_sql_141ac473ae30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_141ac473ae30$;

DO $bootstrap_do_f41f3aba2d34$
BEGIN
  EXECUTE $bootstrap_sql_f41f3aba2d34$-- Add avatar_url to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS avatar_url TEXT$bootstrap_sql_f41f3aba2d34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f41f3aba2d34$;

DO $bootstrap_do_b0e5135556b0$
BEGIN
  EXECUTE $bootstrap_sql_b0e5135556b0$
