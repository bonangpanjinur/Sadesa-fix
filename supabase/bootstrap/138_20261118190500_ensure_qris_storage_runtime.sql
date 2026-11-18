-- Ensure the QRIS storage runtime exists even when an older deployment did not
-- apply the original static QRIS migration.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'qris-merchant-static',
  'qris-merchant-static',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

DROP POLICY IF EXISTS "Public can view static merchant QRIS" ON storage.objects;
CREATE POLICY "Public can view static merchant QRIS"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'qris-merchant-static');

DROP POLICY IF EXISTS "Merchant uploads own static QRIS" ON storage.objects;
CREATE POLICY "Merchant uploads own static QRIS"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'qris-merchant-static'
  AND (storage.foldername(name))[1] = 'qris'
  AND EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id::text = (storage.foldername(name))[2]
      AND (m.user_id = auth.uid() OR public.is_admin())
  )
);

DROP POLICY IF EXISTS "Merchant updates own static QRIS" ON storage.objects;
CREATE POLICY "Merchant updates own static QRIS"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'qris-merchant-static'
  AND (storage.foldername(name))[1] = 'qris'
  AND EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id::text = (storage.foldername(name))[2]
      AND (m.user_id = auth.uid() OR public.is_admin())
  )
)
WITH CHECK (
  bucket_id = 'qris-merchant-static'
  AND (storage.foldername(name))[1] = 'qris'
  AND EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id::text = (storage.foldername(name))[2]
      AND (m.user_id = auth.uid() OR public.is_admin())
  )
);

DROP POLICY IF EXISTS "Merchant deletes own static QRIS" ON storage.objects;
CREATE POLICY "Merchant deletes own static QRIS"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'qris-merchant-static'
  AND (storage.foldername(name))[1] = 'qris'
  AND EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id::text = (storage.foldername(name))[2]
      AND (m.user_id = auth.uid() OR public.is_admin())
  )
);

NOTIFY pgrst, 'reload schema';
