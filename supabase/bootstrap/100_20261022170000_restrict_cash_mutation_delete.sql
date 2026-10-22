-- Kas & Bank permission hardening.
-- Direct deletion is not available to browser roles. Authorized owner/admin
-- users must use the audited RPC below so closed sessions cannot be rewritten.

ALTER TABLE public.pos_cash_mutations
  ADD COLUMN IF NOT EXISTS deletion_reason text;

DROP POLICY IF EXISTS "tenant_owner_manage_cash_mutations" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "tenant_users_select_cash_mutations" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "tenant_users_manage_own_mutations" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "cash_mutations_select_authorized_users" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "cash_mutations_insert_active_users" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "cash_mutations_update_owners" ON public.pos_cash_mutations;
DROP POLICY IF EXISTS "cash_mutations_delete_owners_or_admins" ON public.pos_cash_mutations;

CREATE POLICY "cash_mutations_select_authorized_users"
ON public.pos_cash_mutations
FOR SELECT
USING (
  public.is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = pos_cash_mutations.tenant_id
      AND t.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_users pu
    WHERE pu.tenant_id = pos_cash_mutations.tenant_id
      AND pu.user_id = auth.uid()
      AND pu.is_active = true
  )
);

CREATE POLICY "cash_mutations_insert_active_users"
ON public.pos_cash_mutations
FOR INSERT
WITH CHECK (
  public.is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = pos_cash_mutations.tenant_id
      AND t.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_users pu
    WHERE pu.tenant_id = pos_cash_mutations.tenant_id
      AND pu.user_id = auth.uid()
      AND pu.is_active = true
  )
);

CREATE POLICY "cash_mutations_update_owners"
ON public.pos_cash_mutations
FOR UPDATE
USING (
  public.is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = pos_cash_mutations.tenant_id
      AND t.user_id = auth.uid()
  )
)
WITH CHECK (
  public.is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = pos_cash_mutations.tenant_id
      AND t.user_id = auth.uid()
  )
);

-- Keep DELETE explicit and narrow. The table privilege is revoked below;
-- deletion is only possible through delete_pos_cash_mutation().
CREATE POLICY "cash_mutations_delete_owners_or_admins"
ON public.pos_cash_mutations
FOR DELETE
USING (
  public.is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = pos_cash_mutations.tenant_id
      AND t.user_id = auth.uid()
  )
);

REVOKE DELETE ON TABLE public.pos_cash_mutations FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_pos_cash_mutation(
  p_mutation_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mutation public.pos_cash_mutations%ROWTYPE;
  v_session public.pos_cash_sessions%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_mutation_id IS NULL OR v_reason IS NULL OR length(v_reason) < 5 THEN
    RAISE EXCEPTION 'A deletion reason of at least 5 characters is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_mutation
  FROM public.pos_cash_mutations
  WHERE id = p_mutation_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash mutation not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.pos_tenants t
      WHERE t.id = v_mutation.tenant_id
        AND t.user_id = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'Only the tenant owner or super admin can delete Kas & Bank entries' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.pos_cash_sessions
  WHERE id = v_mutation.cash_session_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Closed cash sessions cannot be deleted; create a reversal instead' USING ERRCODE = '55000';
  END IF;

  -- The delete audit trigger captures this reason from OLD values without
  -- creating a second, duplicate audit row.
  UPDATE public.pos_cash_mutations
  SET deletion_reason = v_reason
  WHERE id = v_mutation.id;

  DELETE FROM public.pos_cash_mutations WHERE id = v_mutation.id;

  IF v_mutation.type = 'in' THEN
    UPDATE public.pos_cash_sessions
    SET cash_in_total = GREATEST(COALESCE(cash_in_total, 0) - v_mutation.amount, 0)
    WHERE id = v_mutation.cash_session_id;
  ELSE
    UPDATE public.pos_cash_sessions
    SET cash_out_total = GREATEST(COALESCE(cash_out_total, 0) - v_mutation.amount, 0)
    WHERE id = v_mutation.cash_session_id;
  END IF;

  RETURN jsonb_build_object(
    'mutation_id', v_mutation.id,
    'status', 'deleted',
    'deleted_by', auth.uid(),
    'reason', v_reason
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_pos_cash_mutation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_pos_cash_mutation(uuid, text) TO authenticated;
