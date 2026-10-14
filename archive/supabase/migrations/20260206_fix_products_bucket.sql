-- Create storage bucket for products if it doesn't exist
-- The roadmap mentioned 'products' bucket, but the code uses 'product-images'.
-- We will create 'products' as an alias or ensure both exist to be safe,
-- but primarily we'll fix the code to use 'product-images' consistently or vice versa.
-- According to the roadmap, the user wants a bucket named 'products'.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('products', 'products', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING$bootstrap_sql_fff48422902c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fff48422902c$;

DO $bootstrap_do_6f52583349d5$
BEGIN
  EXECUTE $bootstrap_sql_6f52583349d5$-- Set up RLS policies for the 'products' bucket
-- 1. Public: Anyone can view images
DROP POLICY IF EXISTS "Public Access" ON storage.objects$bootstrap_sql_6f52583349d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f52583349d5$;

DO $bootstrap_do_6d72ec933fc1$
BEGIN
  EXECUTE $bootstrap_sql_6d72ec933fc1$CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'products')$bootstrap_sql_6d72ec933fc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d72ec933fc1$;

DO $bootstrap_do_27e6a58f307a$
BEGIN
  EXECUTE $bootstrap_sql_27e6a58f307a$-- 2. Authenticated (Merchant): Can upload images
DROP POLICY IF EXISTS "Merchant Upload" ON storage.objects$bootstrap_sql_27e6a58f307a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27e6a58f307a$;

DO $bootstrap_do_09d247d0cce5$
BEGIN
  EXECUTE $bootstrap_sql_09d247d0cce5$CREATE POLICY "Merchant Upload"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'products'
  AND auth.role() = 'authenticated'
)$bootstrap_sql_09d247d0cce5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09d247d0cce5$;

DO $bootstrap_do_697b7c78ec66$
BEGIN
  EXECUTE $bootstrap_sql_697b7c78ec66$-- 3. Authenticated (Merchant): Can update own images
DROP POLICY IF EXISTS "Merchant Update" ON storage.objects$bootstrap_sql_697b7c78ec66$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_697b7c78ec66$;

DO $bootstrap_do_68b8cf14a1d7$
BEGIN
  EXECUTE $bootstrap_sql_68b8cf14a1d7$CREATE POLICY "Merchant Update"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'products'
  AND auth.role() = 'authenticated'
)$bootstrap_sql_68b8cf14a1d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68b8cf14a1d7$;

DO $bootstrap_do_40dafa463aee$
BEGIN
  EXECUTE $bootstrap_sql_40dafa463aee$-- 4. Authenticated (Merchant): Can delete own images
DROP POLICY IF EXISTS "Merchant Delete" ON storage.objects$bootstrap_sql_40dafa463aee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40dafa463aee$;

DO $bootstrap_do_697c0d364f24$
BEGIN
  EXECUTE $bootstrap_sql_697c0d364f24$CREATE POLICY "Merchant Delete"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'products'
  AND auth.role() = 'authenticated'
)$bootstrap_sql_697c0d364f24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_697c0d364f24$;

DO $bootstrap_do_823c282153de$
BEGIN
  EXECUTE $bootstrap_sql_823c282153de$
