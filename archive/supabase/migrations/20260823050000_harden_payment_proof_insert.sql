-- Restrict payment-proof uploads to principals who own or fulfill the order.
-- Expected object path: orders/{order_id}/{filename}
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects$bootstrap_sql_c7ca0c1f1526$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7ca0c1f1526$;

DO $bootstrap_do_8010ebcc574e$
BEGIN
  EXECUTE $bootstrap_sql_8010ebcc574e$DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects$bootstrap_sql_8010ebcc574e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8010ebcc574e$;

DO $bootstrap_do_23ba9ba2ab92$
BEGIN
  EXECUTE $bootstrap_sql_23ba9ba2ab92$CREATE POLICY "Buyer merchant admin can upload payment proofs"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      WHERE o.id::text = (storage.foldername(name))[2]
        AND (o.buyer_id = auth.uid() OR m.user_id = auth.uid())
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN (
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  )
)$bootstrap_sql_23ba9ba2ab92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23ba9ba2ab92$;

DO $bootstrap_do_8693b95ec211$
BEGIN
  EXECUTE $bootstrap_sql_8693b95ec211$
