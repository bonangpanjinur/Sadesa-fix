-- Create village-images storage bucket for village main images
INSERT INTO storage.buckets (id, name, public)
VALUES ('village-images', 'village-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_9644d890d31d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9644d890d31d$;

DO $bootstrap_do_6ee629c7551c$
BEGIN
  EXECUTE $bootstrap_sql_6ee629c7551c$-- Allow public read access to village images
DROP POLICY IF EXISTS "Village images are publicly accessible" ON storage.objects$bootstrap_sql_6ee629c7551c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ee629c7551c$;

DO $bootstrap_do_e1eecdcb77c4$
BEGIN
  EXECUTE $bootstrap_sql_e1eecdcb77c4$CREATE POLICY "Village images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'village-images')$bootstrap_sql_e1eecdcb77c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1eecdcb77c4$;

DO $bootstrap_do_b62b6c42d8de$
BEGIN
  EXECUTE $bootstrap_sql_b62b6c42d8de$-- Allow authenticated users to upload village images
DROP POLICY IF EXISTS "Authenticated users can upload village images" ON storage.objects$bootstrap_sql_b62b6c42d8de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b62b6c42d8de$;

DO $bootstrap_do_f3cc1eac476a$
BEGIN
  EXECUTE $bootstrap_sql_f3cc1eac476a$CREATE POLICY "Authenticated users can upload village images"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'village-images' AND auth.role() = 'authenticated')$bootstrap_sql_f3cc1eac476a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3cc1eac476a$;

DO $bootstrap_do_192470560931$
BEGIN
  EXECUTE $bootstrap_sql_192470560931$-- Allow authenticated users to update village images
DROP POLICY IF EXISTS "Authenticated users can update village images" ON storage.objects$bootstrap_sql_192470560931$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_192470560931$;

DO $bootstrap_do_c6d5fc66268b$
BEGIN
  EXECUTE $bootstrap_sql_c6d5fc66268b$CREATE POLICY "Authenticated users can update village images"
ON storage.objects FOR UPDATE
USING (bucket_id = 'village-images' AND auth.role() = 'authenticated')$bootstrap_sql_c6d5fc66268b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6d5fc66268b$;

DO $bootstrap_do_3ac5dfe37b2b$
BEGIN
  EXECUTE $bootstrap_sql_3ac5dfe37b2b$-- Allow authenticated users to delete village images
DROP POLICY IF EXISTS "Authenticated users can delete village images" ON storage.objects$bootstrap_sql_3ac5dfe37b2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ac5dfe37b2b$;

DO $bootstrap_do_cb66949f3d5f$
BEGIN
  EXECUTE $bootstrap_sql_cb66949f3d5f$CREATE POLICY "Authenticated users can delete village images"
ON storage.objects FOR DELETE
USING (bucket_id = 'village-images' AND auth.role() = 'authenticated')$bootstrap_sql_cb66949f3d5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb66949f3d5f$;

DO $bootstrap_do_5a8a15504bbd$
BEGIN
  EXECUTE $bootstrap_sql_5a8a15504bbd$
