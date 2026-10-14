-- Create storage bucket for review images
INSERT INTO storage.buckets (id, name, public)
VALUES ('review-images', 'review-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_964e276fc32f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_964e276fc32f$;

DO $bootstrap_do_449c53e0822f$
BEGIN
  EXECUTE $bootstrap_sql_449c53e0822f$-- Create policy for users to upload their own review images
DROP POLICY IF EXISTS "Users can upload their own review images" ON storage.objects$bootstrap_sql_449c53e0822f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_449c53e0822f$;

DO $bootstrap_do_986bd97ab1ac$
BEGIN
  EXECUTE $bootstrap_sql_986bd97ab1ac$CREATE POLICY "Users can upload their own review images"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'review-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
)$bootstrap_sql_986bd97ab1ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_986bd97ab1ac$;

DO $bootstrap_do_bf3c6c708adc$
BEGIN
  EXECUTE $bootstrap_sql_bf3c6c708adc$-- Create policy for public read access to review images
DROP POLICY IF EXISTS "Review images are publicly accessible" ON storage.objects$bootstrap_sql_bf3c6c708adc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf3c6c708adc$;

DO $bootstrap_do_177e97b431f0$
BEGIN
  EXECUTE $bootstrap_sql_177e97b431f0$CREATE POLICY "Review images are publicly accessible"
ON storage.objects
FOR SELECT
USING (bucket_id = 'review-images')$bootstrap_sql_177e97b431f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_177e97b431f0$;

DO $bootstrap_do_e5a00ef79596$
BEGIN
  EXECUTE $bootstrap_sql_e5a00ef79596$-- Create policy for users to delete their own review images
DROP POLICY IF EXISTS "Users can delete their own review images" ON storage.objects$bootstrap_sql_e5a00ef79596$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5a00ef79596$;

DO $bootstrap_do_482e021e3e05$
BEGIN
  EXECUTE $bootstrap_sql_482e021e3e05$CREATE POLICY "Users can delete their own review images"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'review-images'
  AND auth.uid()::text = (storage.foldername(name))[1]
)$bootstrap_sql_482e021e3e05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_482e021e3e05$;

DO $bootstrap_do_b33c46c90c74$
BEGIN
  EXECUTE $bootstrap_sql_b33c46c90c74$
