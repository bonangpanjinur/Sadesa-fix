-- Add payment_proof_url column to orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_proof_url TEXT$bootstrap_sql_df53a14b9b7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df53a14b9b7b$;

DO $bootstrap_do_163f389a3f67$
BEGIN
  EXECUTE $bootstrap_sql_163f389a3f67$-- Create storage bucket for payment proofs
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-proofs', 'payment-proofs', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_163f389a3f67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_163f389a3f67$;

DO $bootstrap_do_c25cf3e91497$
BEGIN
  EXECUTE $bootstrap_sql_c25cf3e91497$-- RLS: Public read access for payment proof images
DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects$bootstrap_sql_c25cf3e91497$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c25cf3e91497$;

DO $bootstrap_do_4f4bae40f5f7$
BEGIN
  EXECUTE $bootstrap_sql_4f4bae40f5f7$CREATE POLICY "Payment proofs are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'payment-proofs')$bootstrap_sql_4f4bae40f5f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f4bae40f5f7$;

DO $bootstrap_do_7f6b1abc3347$
BEGIN
  EXECUTE $bootstrap_sql_7f6b1abc3347$-- RLS: Authenticated users can upload payment proofs
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects$bootstrap_sql_7f6b1abc3347$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f6b1abc3347$;

DO $bootstrap_do_ef663b39f790$
BEGIN
  EXECUTE $bootstrap_sql_ef663b39f790$CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated')$bootstrap_sql_ef663b39f790$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef663b39f790$;

DO $bootstrap_do_549f225e9e1f$
BEGIN
  EXECUTE $bootstrap_sql_549f225e9e1f$-- RLS: Users can update their own payment proofs
DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects$bootstrap_sql_549f225e9e1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_549f225e9e1f$;

DO $bootstrap_do_d4dc0b8b946d$
BEGIN
  EXECUTE $bootstrap_sql_d4dc0b8b946d$CREATE POLICY "Users can update their own payment proofs"
ON storage.objects FOR UPDATE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated')$bootstrap_sql_d4dc0b8b946d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4dc0b8b946d$;

DO $bootstrap_do_6609dbbd77d6$
BEGIN
  EXECUTE $bootstrap_sql_6609dbbd77d6$-- RLS: Users can delete their own payment proofs
DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects$bootstrap_sql_6609dbbd77d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6609dbbd77d6$;

DO $bootstrap_do_696bfc270298$
BEGIN
  EXECUTE $bootstrap_sql_696bfc270298$CREATE POLICY "Users can delete their own payment proofs"
ON storage.objects FOR DELETE
USING (bucket_id = 'payment-proofs' AND auth.role() = 'authenticated')$bootstrap_sql_696bfc270298$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_696bfc270298$;

DO $bootstrap_do_4dbcf7061de0$
BEGIN
  EXECUTE $bootstrap_sql_4dbcf7061de0$
