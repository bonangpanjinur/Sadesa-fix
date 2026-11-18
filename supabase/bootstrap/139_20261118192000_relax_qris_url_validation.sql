-- Accept all valid representations produced by Supabase Storage while keeping
-- the QRIS bucket and merchant-owned qris/{merchant_id}/ prefix mandatory.
CREATE OR REPLACE FUNCTION public.protect_merchant_qris_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_qris text := trim(COALESCE(NEW.qris_image_url, ''));
  v_expected_prefix text := 'qris/' || NEW.id::text || '/';
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

    IF v_qris <> '' AND NOT (
      -- Relative object path: qris/{merchant_id}/...
      v_qris LIKE v_expected_prefix || '%'
      -- Public URL: .../qris-merchant-static/qris/{merchant_id}/...
      OR position('/qris-merchant-static/' || v_expected_prefix IN v_qris) > 0
      -- Signed/object URL representations, still restricted to this bucket/path.
      OR (position('qris-merchant-static' IN v_qris) > 0 AND position(v_expected_prefix IN v_qris) > 0)
    ) THEN
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
