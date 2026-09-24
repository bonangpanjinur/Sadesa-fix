-- Admins may view every private courier document through signed URLs.
-- This is intentionally separate from the verifikator scope policy.

DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
CREATE POLICY "Admins can view all courier documents"
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND public.is_admin()
);
