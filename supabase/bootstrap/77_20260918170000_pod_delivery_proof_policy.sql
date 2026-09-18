-- Align POD storage access with the current orders.delivery_proof_url column.
-- The bucket configuration is intentionally not updated here: migration 76
-- already creates/configures pod-images, and avoiding a second relation lock
-- prevents a deadlock with concurrent storage metadata access. The bucket
-- remains private; clients must use createSignedUrl().

DROP POLICY IF EXISTS "POD images: read by order parties" ON storage.objects;
DROP POLICY IF EXISTS "POD images: read by delivery parties" ON storage.objects;
CREATE POLICY "POD images: read by delivery parties"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND (
    is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.orders o
      LEFT JOIN public.merchants m ON m.id = o.merchant_id
      LEFT JOIN public.couriers c ON c.id = o.courier_id
      WHERE o.delivery_proof_url IS NOT NULL
        AND (
          o.delivery_proof_url = storage.objects.name
          OR o.delivery_proof_url LIKE '%/' || storage.objects.name
          OR o.delivery_proof_url LIKE '%/pod-images/' || storage.objects.name
        )
        AND (
          o.buyer_id = auth.uid()
          OR m.user_id = auth.uid()
          OR c.user_id = auth.uid()
        )
    )
  )
);

DROP POLICY IF EXISTS "POD images: upload by courier or merchant" ON storage.objects;
DROP POLICY IF EXISTS "Couriers upload delivery proof images" ON storage.objects;
CREATE POLICY "Couriers upload delivery proof images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
  )
);

DROP POLICY IF EXISTS "Couriers delete own delivery proof images" ON storage.objects;
CREATE POLICY "Couriers delete own delivery proof images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
  )
);

NOTIFY pgrst, 'reload schema';
