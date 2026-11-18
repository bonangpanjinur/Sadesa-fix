-- Runtime repair for databases where an older bootstrap bundle left a stale
-- checkout overload behind. PostgREST must see exactly the canonical 7-arg
-- authenticated function; guest checkout remains an 8-arg function with its
-- own name.
DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text);
DROP FUNCTION IF EXISTS public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric);
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;

-- Keep the QRIS bucket compatible with older uploads that used WebP.
UPDATE storage.buckets
SET public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'qris-merchant-static';

NOTIFY pgrst, 'reload schema';
