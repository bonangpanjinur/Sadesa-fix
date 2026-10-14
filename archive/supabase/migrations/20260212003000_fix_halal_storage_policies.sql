-- Fix storage policies for halal certificates and KTP uploads
-- This ensures that users can upload files to 'certificate/' and 'ktp/' folders in the 'merchants' bucket

-- 1. Allow authenticated users to upload certificates
DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects$bootstrap_sql_1e6d408b0473$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e6d408b0473$;

DO $bootstrap_do_f598a7a6222c$
BEGIN
  EXECUTE $bootstrap_sql_f598a7a6222c$CREATE POLICY "Allow users to upload certificates"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'merchants' AND
    (storage.foldername(name))[1] = 'certificate'
)$bootstrap_sql_f598a7a6222c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f598a7a6222c$;

DO $bootstrap_do_56a199a3fe9f$
BEGIN
  EXECUTE $bootstrap_sql_56a199a3fe9f$-- 2. Allow authenticated users to upload KTP
DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects$bootstrap_sql_56a199a3fe9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56a199a3fe9f$;

DO $bootstrap_do_6e6a92030e8b$
BEGIN
  EXECUTE $bootstrap_sql_6e6a92030e8b$CREATE POLICY "Allow users to upload ktp"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'merchants' AND
    (storage.foldername(name))[1] = 'ktp'
)$bootstrap_sql_6e6a92030e8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e6a92030e8b$;

DO $bootstrap_do_db7b7b0210aa$
BEGIN
  EXECUTE $bootstrap_sql_db7b7b0210aa$-- 3. Ensure public read access for the merchants bucket (already exists but making sure)
DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects$bootstrap_sql_db7b7b0210aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db7b7b0210aa$;

DO $bootstrap_do_18f62e7f6855$
BEGIN
  EXECUTE $bootstrap_sql_18f62e7f6855$CREATE POLICY "Public view merchants bucket"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'merchants')$bootstrap_sql_18f62e7f6855$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18f62e7f6855$;

DO $bootstrap_do_26690aa3acc4$
BEGIN
  EXECUTE $bootstrap_sql_26690aa3acc4$
