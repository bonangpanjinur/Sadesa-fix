-- Storage for merchant paid-ad creatives.
-- Kept separate from payment proofs so public campaign assets and private
-- financial evidence can be governed independently.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects;
CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads');

NOTIFY pgrst, 'reload schema';
