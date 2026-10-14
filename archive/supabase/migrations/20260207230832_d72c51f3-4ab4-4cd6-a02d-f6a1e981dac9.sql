-- Create promotions storage bucket for banner images
INSERT INTO storage.buckets (id, name, public) VALUES ('promotions', 'promotions', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_f765a337ffb6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f765a337ffb6$;

DO $bootstrap_do_5731078fd472$
BEGIN
  EXECUTE $bootstrap_sql_5731078fd472$-- Create admin-assets bucket for QRIS images etc
INSERT INTO storage.buckets (id, name, public) VALUES ('admin-assets', 'admin-assets', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_5731078fd472$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5731078fd472$;

DO $bootstrap_do_c0756a438506$
BEGIN
  EXECUTE $bootstrap_sql_c0756a438506$-- Allow public read access to promotions bucket
DROP POLICY IF EXISTS "Public can view promotion images" ON storage.objects$bootstrap_sql_c0756a438506$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0756a438506$;

DO $bootstrap_do_430c3a07ed04$
BEGIN
  EXECUTE $bootstrap_sql_430c3a07ed04$CREATE POLICY "Public can view promotion images"
ON storage.objects FOR SELECT
USING (bucket_id = 'promotions')$bootstrap_sql_430c3a07ed04$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_430c3a07ed04$;

DO $bootstrap_do_14e9baac86d0$
BEGIN
  EXECUTE $bootstrap_sql_14e9baac86d0$-- Allow authenticated users to upload to promotions bucket
DROP POLICY IF EXISTS "Authenticated users can upload promotion images" ON storage.objects$bootstrap_sql_14e9baac86d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14e9baac86d0$;

DO $bootstrap_do_04514c894fac$
BEGIN
  EXECUTE $bootstrap_sql_04514c894fac$CREATE POLICY "Authenticated users can upload promotion images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'promotions' AND auth.role() = 'authenticated')$bootstrap_sql_04514c894fac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04514c894fac$;

DO $bootstrap_do_70521be6b9ea$
BEGIN
  EXECUTE $bootstrap_sql_70521be6b9ea$-- Allow authenticated users to delete promotion images
DROP POLICY IF EXISTS "Authenticated users can delete promotion images" ON storage.objects$bootstrap_sql_70521be6b9ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70521be6b9ea$;

DO $bootstrap_do_79b0f94d873c$
BEGIN
  EXECUTE $bootstrap_sql_79b0f94d873c$CREATE POLICY "Authenticated users can delete promotion images"
ON storage.objects FOR DELETE
USING (bucket_id = 'promotions' AND auth.role() = 'authenticated')$bootstrap_sql_79b0f94d873c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79b0f94d873c$;

DO $bootstrap_do_417e8ba60d37$
BEGIN
  EXECUTE $bootstrap_sql_417e8ba60d37$-- Allow public read access to admin-assets bucket
DROP POLICY IF EXISTS "Public can view admin assets" ON storage.objects$bootstrap_sql_417e8ba60d37$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_417e8ba60d37$;

DO $bootstrap_do_11ff379b2ece$
BEGIN
  EXECUTE $bootstrap_sql_11ff379b2ece$CREATE POLICY "Public can view admin assets"
ON storage.objects FOR SELECT
USING (bucket_id = 'admin-assets')$bootstrap_sql_11ff379b2ece$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11ff379b2ece$;

DO $bootstrap_do_33c144ea470f$
BEGIN
  EXECUTE $bootstrap_sql_33c144ea470f$-- Allow authenticated users to upload to admin-assets bucket
DROP POLICY IF EXISTS "Authenticated users can upload admin assets" ON storage.objects$bootstrap_sql_33c144ea470f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33c144ea470f$;

DO $bootstrap_do_f1e26d5e4233$
BEGIN
  EXECUTE $bootstrap_sql_f1e26d5e4233$CREATE POLICY "Authenticated users can upload admin assets"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'admin-assets' AND auth.role() = 'authenticated')$bootstrap_sql_f1e26d5e4233$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1e26d5e4233$;

DO $bootstrap_do_b255f5f6f1fc$
BEGIN
  EXECUTE $bootstrap_sql_b255f5f6f1fc$-- Allow authenticated users to delete admin assets
DROP POLICY IF EXISTS "Authenticated users can delete admin assets" ON storage.objects$bootstrap_sql_b255f5f6f1fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b255f5f6f1fc$;

DO $bootstrap_do_e52c18d12bb4$
BEGIN
  EXECUTE $bootstrap_sql_e52c18d12bb4$CREATE POLICY "Authenticated users can delete admin assets"
ON storage.objects FOR DELETE
USING (bucket_id = 'admin-assets' AND auth.role() = 'authenticated')$bootstrap_sql_e52c18d12bb4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e52c18d12bb4$;

DO $bootstrap_do_05868736d28a$
BEGIN
  EXECUTE $bootstrap_sql_05868736d28a$
