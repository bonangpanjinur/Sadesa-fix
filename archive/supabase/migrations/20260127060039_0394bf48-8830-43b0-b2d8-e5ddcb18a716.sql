-- Create storage buckets for images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES 
  ('product-images', 'product-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('tourism-images', 'tourism-images', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('profile-images', 'profile-images', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('merchant-images', 'merchant-images', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING;

-- RLS for product-images: Merchants can upload to their own folder
DROP POLICY IF EXISTS "Anyone can view product images" ON storage.objects;
CREATE POLICY "Anyone can view product images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Merchants can upload product images" ON storage.objects;
CREATE POLICY "Merchants can upload product images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'product-images' 
  AND (
    is_admin() OR 
    EXISTS (
      SELECT 1 FROM public.merchants 
      WHERE merchants.user_id = auth.uid() 
      AND merchants.status = 'ACTIVE'
    )
  )
);

DROP POLICY IF EXISTS "Merchants can update own product images" ON storage.objects;
CREATE POLICY "Merchants can update own product images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'product-images' 
  AND (
    is_admin() OR 
    EXISTS (
      SELECT 1 FROM public.merchants 
      WHERE merchants.user_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "Merchants can delete own product images" ON storage.objects;
CREATE POLICY "Merchants can delete own product images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'product-images' 
  AND (
    is_admin() OR 
    EXISTS (
      SELECT 1 FROM public.merchants 
      WHERE merchants.user_id = auth.uid()
    )
  )
);

-- RLS for tourism-images: Admin desa can upload
DROP POLICY IF EXISTS "Anyone can view tourism images" ON storage.objects;
CREATE POLICY "Anyone can view tourism images"
ON storage.objects FOR SELECT
USING (bucket_id = 'tourism-images');

DROP POLICY IF EXISTS "Admin desa can upload tourism images" ON storage.objects;
CREATE POLICY "Admin desa can upload tourism images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

DROP POLICY IF EXISTS "Admin desa can update tourism images" ON storage.objects;
CREATE POLICY "Admin desa can update tourism images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

DROP POLICY IF EXISTS "Admin desa can delete tourism images" ON storage.objects;
CREATE POLICY "Admin desa can delete tourism images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'tourism-images' 
  AND (is_admin() OR is_admin_desa())
);

-- RLS for profile-images: Users can upload their own
DROP POLICY IF EXISTS "Anyone can view profile images" ON storage.objects;
CREATE POLICY "Anyone can view profile images"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-images');

DROP POLICY IF EXISTS "Users can upload own profile image" ON storage.objects;
CREATE POLICY "Users can upload own profile image"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'profile-images' 
  AND auth.uid() IS NOT NULL
);

DROP POLICY IF EXISTS "Users can update own profile image" ON storage.objects;
CREATE POLICY "Users can update own profile image"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'profile-images' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can delete own profile image" ON storage.objects;
CREATE POLICY "Users can delete own profile image"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'profile-images' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS for merchant-images: Merchants can upload their store image
DROP POLICY IF EXISTS "Anyone can view merchant images" ON storage.objects;
CREATE POLICY "Anyone can view merchant images"
ON storage.objects FOR SELECT
USING (bucket_id = 'merchant-images');

DROP POLICY IF EXISTS "Merchants can upload merchant images" ON storage.objects;
CREATE POLICY "Merchants can upload merchant images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'merchant-images' 
  AND (
    is_admin() OR 
    auth.uid() IS NOT NULL
  )
);

DROP POLICY IF EXISTS "Merchants can update own merchant images" ON storage.objects;
CREATE POLICY "Merchants can update own merchant images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'merchant-images' 
  AND (
    is_admin() OR 
    EXISTS (
      SELECT 1 FROM public.merchants 
      WHERE merchants.user_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "Merchants can delete own merchant images" ON storage.objects;
CREATE POLICY "Merchants can delete own merchant images"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'merchant-images' 
  AND (
    is_admin() OR 
    EXISTS (
      SELECT 1 FROM public.merchants 
      WHERE merchants.user_id = auth.uid()
    )
  )
);

-- Add avatar_url to profiles
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS avatar_url TEXT;