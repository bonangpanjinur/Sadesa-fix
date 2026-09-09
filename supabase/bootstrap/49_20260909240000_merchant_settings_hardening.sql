-- Harden merchant settings ownership and storage paths.
-- Merchants may edit operational/profile settings only. Approval, ownership,
-- verification and financial ledger fields remain admin/verifikator controlled.

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants;
CREATE POLICY "Merchants can update own data"
  ON public.merchants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.protect_merchant_control_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service-role operations and admin/verifikator workflows are allowed to
  -- change control-plane fields.
  IF auth.uid() IS NULL OR public.is_admin() OR public.is_verifikator() THEN
    RETURN NEW;
  END IF;

  IF OLD.user_id = auth.uid() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.user_id IS DISTINCT FROM OLD.user_id
      OR NEW.registration_status IS DISTINCT FROM OLD.registration_status
      OR NEW.status IS DISTINCT FROM OLD.status
      OR NEW.is_verified IS DISTINCT FROM OLD.is_verified
      OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
      OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
      OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
      OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
      OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
      OR NEW.verifikator_id IS DISTINCT FROM OLD.verifikator_id
      OR NEW.available_balance IS DISTINCT FROM OLD.available_balance
      OR NEW.pending_balance IS DISTINCT FROM OLD.pending_balance
      OR NEW.total_withdrawn IS DISTINCT FROM OLD.total_withdrawn
      OR NEW.current_subscription_id IS DISTINCT FROM OLD.current_subscription_id
      OR NEW.rating_avg IS DISTINCT FROM OLD.rating_avg
      OR NEW.rating_count IS DISTINCT FROM OLD.rating_count
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
      OR NEW.registered_at IS DISTINCT FROM OLD.registered_at
      OR NEW.village_id IS DISTINCT FROM OLD.village_id
      OR NEW.verifikator_code IS DISTINCT FROM OLD.verifikator_code THEN
      RAISE EXCEPTION 'merchant control fields can only be changed by admin or verifikator'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_merchant_control_fields ON public.merchants;
CREATE TRIGGER protect_merchant_control_fields
  BEFORE UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_merchant_control_fields();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'merchant-images',
  'merchant-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

DROP POLICY IF EXISTS "Merchants can upload merchant images" ON storage.objects;
CREATE POLICY "Merchants can upload merchant images"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  );

DROP POLICY IF EXISTS "Merchants can update own merchant images" ON storage.objects;
CREATE POLICY "Merchants can update own merchant images"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  )
  WITH CHECK (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  );

DROP POLICY IF EXISTS "Merchants can delete own merchant images" ON storage.objects;
CREATE POLICY "Merchants can delete own merchant images"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  );

NOTIFY pgrst, 'reload schema';