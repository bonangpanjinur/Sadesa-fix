-- Restrict verifikators to merchants and couriers registered with their own
-- verifikator code. Village/group membership is intentionally not used as a
-- fallback because it can expose another verifikator's referrals.

DROP POLICY IF EXISTS "Verifikator can manage merchants" ON public.merchants;
DROP POLICY IF EXISTS "Authenticated users view active merchants" ON public.merchants;
CREATE POLICY "Authenticated users view active merchants"
ON public.merchants
FOR SELECT TO authenticated
USING (
  NOT public.is_verifikator()
  AND (
    user_id = auth.uid()
    OR (status = 'ACTIVE' AND registration_status = 'APPROVED')
    OR public.is_admin()
  )
);

DROP POLICY IF EXISTS "Verifikators can view own merchants" ON public.merchants;
CREATE POLICY "Verifikators can view own merchants"
ON public.merchants
FOR SELECT TO authenticated
USING (
  public.is_verifikator()
  AND EXISTS (
    SELECT 1
    FROM public.verifikator_codes AS vc
    WHERE vc.code = merchants.verifikator_code
      AND vc.verifikator_id = auth.uid()
      AND vc.is_active = true
  )
);

DROP POLICY IF EXISTS "Verifikators can update own merchants" ON public.merchants;
CREATE POLICY "Verifikators can update own merchants"
ON public.merchants
FOR UPDATE TO authenticated
USING (
  public.is_verifikator()
  AND EXISTS (
    SELECT 1
    FROM public.verifikator_codes AS vc
    WHERE vc.code = merchants.verifikator_code
      AND vc.verifikator_id = auth.uid()
      AND vc.is_active = true
  )
)
WITH CHECK (
  public.is_verifikator()
  AND EXISTS (
    SELECT 1
    FROM public.verifikator_codes AS vc
    WHERE vc.code = merchants.verifikator_code
      AND vc.verifikator_id = auth.uid()
      AND vc.is_active = true
  )
);

DROP POLICY IF EXISTS "Verifikators can review assigned couriers" ON public.couriers;
CREATE POLICY "Verifikators can review assigned couriers"
ON public.couriers
FOR SELECT TO authenticated
USING (
  public.is_verifikator()
  AND EXISTS (
    SELECT 1
    FROM public.verifikator_codes AS vc
    WHERE vc.code = couriers.verifikator_code
      AND vc.verifikator_id = auth.uid()
      AND vc.is_active = true
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
  SELECT EXISTS (
    SELECT 1
    FROM public.verifikator_codes AS vc
    WHERE vc.code = v_courier.verifikator_code
      AND vc.verifikator_id = auth.uid()
      AND vc.is_active = true
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
      JOIN public.verifikator_codes AS vc
        ON vc.code = c.verifikator_code
       AND vc.verifikator_id = auth.uid()
       AND vc.is_active = true
      WHERE c.user_id::text = (storage.foldername(storage.objects.name))[1]
    )
  )
);

COMMENT ON FUNCTION public.review_courier(uuid, text, text) IS
  'Approve or reject a courier only for an admin or the verifikator who owns the courier referral code.';
