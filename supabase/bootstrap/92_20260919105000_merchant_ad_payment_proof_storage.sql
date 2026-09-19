-- Merchant paid-ad payment proofs are uploaded under <merchant_id>/<file>.
-- Keep this separate from buyer order proofs, whose policies are more restrictive.
DROP POLICY IF EXISTS "Merchant can upload ad payment proof" ON storage.objects;
CREATE POLICY "Merchant can upload ad payment proof" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id::text = split_part(name, '/', 1)
        AND m.user_id = auth.uid()
        AND m.registration_status = 'APPROVED'
    )
  );

DROP POLICY IF EXISTS "Merchant can read own ad payment proof" ON storage.objects;
CREATE POLICY "Merchant can read own ad payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1
      FROM public.merchant_ads a
      JOIN public.merchants m ON m.id = a.merchant_id
      WHERE m.id::text = split_part(name, '/', 1)
        AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admin can read ad payment proof" ON storage.objects;
CREATE POLICY "Admin can read ad payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.is_admin());

NOTIFY pgrst, 'reload schema';
