-- Storage hardening for sensitive documents and merchant gallery.

-- The legacy merchants bucket contains KTP/certificate paths and must not be
-- publicly readable. Public storefront images use dedicated public buckets.
UPDATE storage.buckets
SET public = false
WHERE id = 'merchants';

DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects;

DROP POLICY IF EXISTS "Owners and reviewers can read merchant documents" ON storage.objects;
CREATE POLICY "Owners and reviewers can read merchant documents"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'merchants'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR public.is_verifikator()
    OR (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
  )
);

DROP POLICY IF EXISTS "Owners can upload merchant documents" ON storage.objects;
CREATE POLICY "Owners can upload merchant documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchants'
  AND (
    (
      (storage.foldername(name))[1] IN ('ktp', 'certificate')
      AND (storage.foldername(name))[2] = auth.uid()::text
    )
    OR public.is_admin()
    OR public.is_verifikator()
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
);

DROP POLICY IF EXISTS "Owners can update merchant documents" ON storage.objects;
CREATE POLICY "Owners can update merchant documents"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)
WITH CHECK (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

DROP POLICY IF EXISTS "Owners can delete merchant documents" ON storage.objects;
CREATE POLICY "Owners can delete merchant documents"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
);

-- Merchant gallery remains publicly readable, but writes are restricted to the
-- merchant owner, the related village administrator, or platform admin.
DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects;

DROP POLICY IF EXISTS "Merchant owners can upload gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can upload gallery images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
  AND COALESCE(metadata->>'mimetype', '') IN ('image/jpeg', 'image/png', 'image/webp')
);

DROP POLICY IF EXISTS "Merchant owners can update gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can update gallery images"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
)
WITH CHECK (
  bucket_id = 'merchant-gallery'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);

DROP POLICY IF EXISTS "Merchant owners can delete gallery images" ON storage.objects;
CREATE POLICY "Merchant owners can delete gallery images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchant-gallery'
  AND (
    owner = auth.uid()
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE (storage.foldername(name))[1] = m.id::text
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_villages uv
      WHERE (storage.foldername(name))[1] = 'villages'
        AND (storage.foldername(name))[2] = uv.village_id::text
        AND uv.user_id = auth.uid()
        AND uv.role = 'admin_desa'
    )
  )
);
