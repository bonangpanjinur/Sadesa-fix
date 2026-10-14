-- Privatize the payment-proofs bucket
UPDATE storage.buckets SET public = false WHERE id = 'payment-proofs'$bootstrap_sql_b11386b87a3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b11386b87a3f$;

DO $bootstrap_do_6739d4a259d4$
BEGIN
  EXECUTE $bootstrap_sql_6739d4a259d4$-- Drop old permissive policies
DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects$bootstrap_sql_6739d4a259d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6739d4a259d4$;

DO $bootstrap_do_fa57fdaab263$
BEGIN
  EXECUTE $bootstrap_sql_fa57fdaab263$DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects$bootstrap_sql_fa57fdaab263$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa57fdaab263$;

DO $bootstrap_do_3d3f48c36e0a$
BEGIN
  EXECUTE $bootstrap_sql_3d3f48c36e0a$DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects$bootstrap_sql_3d3f48c36e0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d3f48c36e0a$;

DO $bootstrap_do_a098753fb316$
BEGIN
  EXECUTE $bootstrap_sql_a098753fb316$DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects$bootstrap_sql_a098753fb316$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a098753fb316$;

DO $bootstrap_do_08be33e2c317$
BEGIN
  EXECUTE $bootstrap_sql_08be33e2c317$-- SELECT: buyer (owner of order), merchant of order, or admin
-- Path convention: orders/{order_id}/{filename}
DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects$bootstrap_sql_08be33e2c317$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08be33e2c317$;

DO $bootstrap_do_7fa431a3db6c$
BEGIN
  EXECUTE $bootstrap_sql_7fa431a3db6c$CREATE POLICY "Buyer/merchant/admin can view payment proofs"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      LEFT JOIN public.merchants m ON o.merchant_id = m.id
      WHERE o.id::text = (storage.foldername(name))[2]
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid())
    )
  )
)$bootstrap_sql_7fa431a3db6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7fa431a3db6c$;

DO $bootstrap_do_b73233152fe6$
BEGIN
  EXECUTE $bootstrap_sql_b73233152fe6$-- INSERT: any authenticated user (validated at app level via order ownership)
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects$bootstrap_sql_b73233152fe6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b73233152fe6$;

DO $bootstrap_do_2780c25405be$
BEGIN
  EXECUTE $bootstrap_sql_2780c25405be$CREATE POLICY "Authenticated users can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'payment-proofs')$bootstrap_sql_2780c25405be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2780c25405be$;

DO $bootstrap_do_6270cd2065e6$
BEGIN
  EXECUTE $bootstrap_sql_6270cd2065e6$-- UPDATE: only the buyer of the order
DROP POLICY IF EXISTS "Buyer can update own payment proofs" ON storage.objects$bootstrap_sql_6270cd2065e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6270cd2065e6$;

DO $bootstrap_do_8b1148fe0b7b$
BEGIN
  EXECUTE $bootstrap_sql_8b1148fe0b7b$CREATE POLICY "Buyer can update own payment proofs"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id::text = (storage.foldername(name))[2]
      AND o.buyer_id = auth.uid()
  )
)$bootstrap_sql_8b1148fe0b7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b1148fe0b7b$;

DO $bootstrap_do_e4df3a5090d8$
BEGIN
  EXECUTE $bootstrap_sql_e4df3a5090d8$-- DELETE: only buyer or admin
DROP POLICY IF EXISTS "Buyer or admin can delete payment proofs" ON storage.objects$bootstrap_sql_e4df3a5090d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4df3a5090d8$;

DO $bootstrap_do_e7ba94770205$
BEGIN
  EXECUTE $bootstrap_sql_e7ba94770205$CREATE POLICY "Buyer or admin can delete payment proofs"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = (storage.foldername(name))[2]
        AND o.buyer_id = auth.uid()
    )
  )
)$bootstrap_sql_e7ba94770205$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7ba94770205$;

DO $bootstrap_do_1c55a96a1160$
BEGIN
  EXECUTE $bootstrap_sql_1c55a96a1160$
