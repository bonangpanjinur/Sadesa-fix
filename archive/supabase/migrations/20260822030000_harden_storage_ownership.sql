-- Storage hardening for sensitive documents and merchant gallery.

-- The legacy merchants bucket contains KTP/certificate paths and must not be
-- publicly readable. Public storefront images use dedicated public buckets.
UPDATE storage.buckets
SET public = false
WHERE id = 'merchants'$bootstrap_sql_76866591b886$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76866591b886$;

DO $bootstrap_do_b911dbbbef11$
BEGIN
  EXECUTE $bootstrap_sql_b911dbbbef11$DROP POLICY IF EXISTS "Public view merchants bucket" ON storage.objects$bootstrap_sql_b911dbbbef11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b911dbbbef11$;

DO $bootstrap_do_e4bc9219fb33$
BEGIN
  EXECUTE $bootstrap_sql_e4bc9219fb33$DROP POLICY IF EXISTS "Allow users to upload certificates" ON storage.objects$bootstrap_sql_e4bc9219fb33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4bc9219fb33$;

DO $bootstrap_do_5e86062204f4$
BEGIN
  EXECUTE $bootstrap_sql_5e86062204f4$DROP POLICY IF EXISTS "Allow users to upload ktp" ON storage.objects$bootstrap_sql_5e86062204f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e86062204f4$;

DO $bootstrap_do_274c28eb5abd$
BEGIN
  EXECUTE $bootstrap_sql_274c28eb5abd$DROP POLICY IF EXISTS "Owners and reviewers can read merchant documents" ON storage.objects$bootstrap_sql_274c28eb5abd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_274c28eb5abd$;

DO $bootstrap_do_59c77c7027df$
BEGIN
  EXECUTE $bootstrap_sql_59c77c7027df$CREATE POLICY "Owners and reviewers can read merchant documents"
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
)$bootstrap_sql_59c77c7027df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59c77c7027df$;

DO $bootstrap_do_eb1d26ba2d9c$
BEGIN
  EXECUTE $bootstrap_sql_eb1d26ba2d9c$DROP POLICY IF EXISTS "Owners can upload merchant documents" ON storage.objects$bootstrap_sql_eb1d26ba2d9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb1d26ba2d9c$;

DO $bootstrap_do_ca04b671a6da$
BEGIN
  EXECUTE $bootstrap_sql_ca04b671a6da$CREATE POLICY "Owners can upload merchant documents"
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
)$bootstrap_sql_ca04b671a6da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca04b671a6da$;

DO $bootstrap_do_b14b58775d13$
BEGIN
  EXECUTE $bootstrap_sql_b14b58775d13$DROP POLICY IF EXISTS "Owners can update merchant documents" ON storage.objects$bootstrap_sql_b14b58775d13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b14b58775d13$;

DO $bootstrap_do_c826ecfe2b73$
BEGIN
  EXECUTE $bootstrap_sql_c826ecfe2b73$CREATE POLICY "Owners can update merchant documents"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)
WITH CHECK (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)$bootstrap_sql_c826ecfe2b73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c826ecfe2b73$;

DO $bootstrap_do_2c2ab7dff541$
BEGIN
  EXECUTE $bootstrap_sql_2c2ab7dff541$DROP POLICY IF EXISTS "Owners can delete merchant documents" ON storage.objects$bootstrap_sql_2c2ab7dff541$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c2ab7dff541$;

DO $bootstrap_do_fffdb3533cce$
BEGIN
  EXECUTE $bootstrap_sql_fffdb3533cce$CREATE POLICY "Owners can delete merchant documents"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchants'
  AND (owner = auth.uid() OR public.is_admin() OR public.is_verifikator())
)$bootstrap_sql_fffdb3533cce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fffdb3533cce$;

DO $bootstrap_do_86a58dff39d5$
BEGIN
  EXECUTE $bootstrap_sql_86a58dff39d5$-- Merchant gallery remains publicly readable, but writes are restricted to the
-- merchant owner, the related village administrator, or platform admin.
DROP POLICY IF EXISTS "Authenticated users can upload merchant gallery images" ON storage.objects$bootstrap_sql_86a58dff39d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86a58dff39d5$;

DO $bootstrap_do_be83b6f7cec3$
BEGIN
  EXECUTE $bootstrap_sql_be83b6f7cec3$DROP POLICY IF EXISTS "Users can update own merchant gallery images" ON storage.objects$bootstrap_sql_be83b6f7cec3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be83b6f7cec3$;

DO $bootstrap_do_8cbf12aa191a$
BEGIN
  EXECUTE $bootstrap_sql_8cbf12aa191a$DROP POLICY IF EXISTS "Users can delete own merchant gallery images" ON storage.objects$bootstrap_sql_8cbf12aa191a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cbf12aa191a$;

DO $bootstrap_do_0a295af57559$
BEGIN
  EXECUTE $bootstrap_sql_0a295af57559$DROP POLICY IF EXISTS "Merchant owners can upload gallery images" ON storage.objects$bootstrap_sql_0a295af57559$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a295af57559$;

DO $bootstrap_do_f44fe8ced471$
BEGIN
  EXECUTE $bootstrap_sql_f44fe8ced471$CREATE POLICY "Merchant owners can upload gallery images"
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
)$bootstrap_sql_f44fe8ced471$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f44fe8ced471$;

DO $bootstrap_do_52db7e9fb654$
BEGIN
  EXECUTE $bootstrap_sql_52db7e9fb654$DROP POLICY IF EXISTS "Merchant owners can update gallery images" ON storage.objects$bootstrap_sql_52db7e9fb654$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52db7e9fb654$;

DO $bootstrap_do_1f6b64295f5d$
BEGIN
  EXECUTE $bootstrap_sql_1f6b64295f5d$CREATE POLICY "Merchant owners can update gallery images"
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
)$bootstrap_sql_1f6b64295f5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f6b64295f5d$;

DO $bootstrap_do_971a6977a9e1$
BEGIN
  EXECUTE $bootstrap_sql_971a6977a9e1$DROP POLICY IF EXISTS "Merchant owners can delete gallery images" ON storage.objects$bootstrap_sql_971a6977a9e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_971a6977a9e1$;

DO $bootstrap_do_61abdcd298dd$
BEGIN
  EXECUTE $bootstrap_sql_61abdcd298dd$CREATE POLICY "Merchant owners can delete gallery images"
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
)$bootstrap_sql_61abdcd298dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_61abdcd298dd$;

DO $bootstrap_do_fcef8adf1a7b$
BEGIN
  EXECUTE $bootstrap_sql_fcef8adf1a7b$
