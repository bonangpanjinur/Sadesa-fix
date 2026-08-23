-- Restrict payment-proof uploads to principals who own or fulfill the order.
-- Expected object path: orders/{order_id}/{filename}
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;

CREATE POLICY "Buyer merchant admin can upload payment proofs"
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
);
