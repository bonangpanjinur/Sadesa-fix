-- Create storage bucket for courier documents
INSERT INTO storage.buckets (id, name, public) VALUES ('courier-documents', 'courier-documents', false);

-- Storage policies for courier-documents bucket (safe to retry)
DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects;

DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
CREATE POLICY "Anyone can upload courier documents" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'courier-documents');

DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
CREATE POLICY "Admins can view all courier documents" ON storage.objects
FOR SELECT USING (bucket_id = 'courier-documents' AND (is_admin() OR is_verifikator()));

DROP POLICY IF EXISTS "Couriers can view own documents" ON storage.objects;
CREATE POLICY "Couriers can view own documents" ON storage.objects
FOR SELECT USING (
    bucket_id = 'courier-documents' 
    AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Admins can delete courier documents" ON storage.objects;
CREATE POLICY "Admins can delete courier documents" ON storage.objects
FOR DELETE USING (bucket_id = 'courier-documents' AND is_admin());