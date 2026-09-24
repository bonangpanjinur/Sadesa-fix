-- Courier verification hardening.
-- Verifikators may review only couriers in villages assigned to one of their
-- active trade groups. Approval mutations go through a narrow RPC so a
-- verifikator cannot edit identity, payout, or operational fields.

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_code text;

CREATE INDEX IF NOT EXISTS idx_couriers_verifikator_code
  ON public.couriers(verifikator_code);

DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers;

DROP POLICY IF EXISTS "Verifikators can review assigned couriers" ON public.couriers;
CREATE POLICY "Verifikators can review assigned couriers"
ON public.couriers
FOR SELECT TO authenticated
USING (
  public.is_verifikator()
  AND (
    EXISTS (
      SELECT 1
      FROM public.trade_groups AS tg
      WHERE tg.verifikator_id = auth.uid()
        AND tg.is_active = true
        AND tg.village_id IS NOT NULL
        AND tg.village_id = couriers.village_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.verifikator_codes AS vc
      WHERE vc.code = couriers.verifikator_code
        AND vc.verifikator_id = auth.uid()
        AND vc.is_active = true
    )
  )
);

CREATE OR REPLACE FUNCTION public.review_courier(
  p_courier_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_is_admin boolean;
  v_is_assigned_verifikator boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Invalid courier review decision' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT public.is_admin() INTO v_is_admin;
  SELECT (
    EXISTS (
      SELECT 1
      FROM public.trade_groups AS tg
      WHERE tg.verifikator_id = auth.uid()
        AND tg.is_active = true
        AND tg.village_id IS NOT NULL
        AND tg.village_id = v_courier.village_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.verifikator_codes AS vc
      WHERE vc.code = v_courier.verifikator_code
        AND vc.verifikator_id = auth.uid()
        AND vc.is_active = true
    )
  ) INTO v_is_assigned_verifikator;

  IF NOT COALESCE(v_is_admin, false) AND NOT v_is_assigned_verifikator THEN
    RAISE EXCEPTION 'Courier is outside your verification scope' USING ERRCODE = '42501';
  END IF;

  IF p_decision = 'APPROVED' THEN
    UPDATE public.couriers
    SET registration_status = 'APPROVED',
        status = 'ACTIVE',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = p_courier_id;
  ELSE
    IF NULLIF(trim(COALESCE(p_reason, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Rejection reason is required' USING ERRCODE = '22023';
    END IF;

    UPDATE public.couriers
    SET registration_status = 'REJECTED',
        status = 'INACTIVE',
        approved_by = auth.uid(),
        approved_at = NULL,
        rejection_reason = trim(p_reason),
        updated_at = now()
    WHERE id = p_courier_id;
  END IF;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.review_courier(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_courier(uuid, text, text) TO authenticated;

-- The bucket is private. Uploads are restricted to the authenticated courier's
-- own namespace: <user_id>/{ktp,photo,vehicle}/filename.
DROP POLICY IF EXISTS "Anyone can upload courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload courier documents" ON storage.objects;
CREATE POLICY "Authenticated users can upload courier documents"
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'courier-documents'
  AND (storage.foldername(storage.objects.name))[1] = auth.uid()::text
  AND (storage.foldername(storage.objects.name))[2] IN ('ktp', 'photo', 'vehicle')
);

DROP POLICY IF EXISTS "Admins can view all courier documents" ON storage.objects;
DROP POLICY IF EXISTS "Assigned verifikators can view courier documents" ON storage.objects;
CREATE POLICY "Assigned verifikators can view courier documents"
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.couriers AS c
      WHERE c.user_id::text = (storage.foldername(storage.objects.name))[1]
        AND (
          EXISTS (
            SELECT 1 FROM public.trade_groups AS tg
            WHERE tg.village_id = c.village_id
              AND tg.verifikator_id = auth.uid()
              AND tg.is_active = true
          )
          OR EXISTS (
            SELECT 1 FROM public.verifikator_codes AS vc
            WHERE vc.code = c.verifikator_code
              AND vc.verifikator_id = auth.uid()
              AND vc.is_active = true
          )
        )
    )
  )
);

COMMENT ON FUNCTION public.review_courier(uuid, text, text) IS
  'Approve or reject a courier only for an admin or a verifikator assigned to the courier village.';
