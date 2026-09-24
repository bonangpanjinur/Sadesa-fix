-- Enforce the mandatory document contract at the database boundary.
-- Direct clients must not be able to create a courier with blank references.

ALTER TABLE public.couriers
  DROP CONSTRAINT IF EXISTS couriers_document_paths_not_blank;

ALTER TABLE public.couriers
  ADD CONSTRAINT couriers_document_paths_not_blank CHECK (
    length(trim(ktp_image_url)) > 0
    AND length(trim(photo_url)) > 0
    AND length(trim(vehicle_image_url)) > 0
  );

-- Keep the bucket private and repair environments with an older policy set.
INSERT INTO storage.buckets (id, name, public)
VALUES ('courier-documents', 'courier-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload courier documents" ON storage.objects;
CREATE POLICY "Authenticated users can upload courier documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'courier-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND (storage.foldername(name))[2] IN ('ktp', 'photo', 'vehicle')
);

DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
CREATE POLICY "Admins can view all courier documents"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'courier-documents' AND public.is_admin());

DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects;
CREATE POLICY "Couriers can view own documents"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
