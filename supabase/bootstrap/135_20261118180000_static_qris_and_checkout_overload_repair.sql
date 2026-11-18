-- Static merchant QRIS and checkout RPC overload repair.
-- Merchants upload their own static QRIS image; dynamic QRIS remains an
-- admin/provider concern and is intentionally not changed here.

-- PostgREST cannot resolve an RPC when a stale legacy signature remains
-- alongside the canonical checkout function. Keep only the 7-argument
-- p_checkout_key contract used by the current frontend.
DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text);
DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric);
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;

-- QRIS images are public payment instructions, but writes are scoped to the
-- owning merchant's qris/<merchant_id>/ prefix (or an admin).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'qris-merchant-static',
  'qris-merchant-static',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png'];

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

-- The existing trigger was designed for admin-issued QRIS. For the static
-- merchant flow, allow only the owning active merchant to set a URL that
-- points into its own public QRIS prefix; all other QRIS mutations remain
-- admin-only.
CREATE OR REPLACE FUNCTION public.protect_merchant_qris_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.qris_image_url IS DISTINCT FROM OLD.qris_image_url
     AND NOT public.is_admin() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = NEW.id
        AND m.user_id = auth.uid()
        AND m.status = 'ACTIVE'
        AND m.registration_status = 'APPROVED'
    ) THEN
      RAISE EXCEPTION 'Hanya pemilik merchant aktif yang dapat mengatur QRIS statis' USING ERRCODE = '42501';
    END IF;
    IF NEW.qris_image_url IS NOT NULL
       AND position('/storage/v1/object/public/qris-merchant-static/qris/' || NEW.id::text || '/' IN NEW.qris_image_url) = 0 THEN
      RAISE EXCEPTION 'URL QRIS harus berasal dari storage QRIS merchant' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_merchant_qris_assignment_trigger ON public.merchants;
CREATE TRIGGER protect_merchant_qris_assignment_trigger
BEFORE UPDATE OF qris_image_url ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.protect_merchant_qris_assignment();

NOTIFY pgrst, 'reload schema';
