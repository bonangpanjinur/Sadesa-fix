-- Auth and user-management hardening.
-- Replace roles atomically and prevent accidental removal of the last admin.

CREATE OR REPLACE FUNCTION public.admin_replace_user_roles(
  p_target_user_id uuid,
  p_roles public.app_role[]
)
RETURNS SETOF public.user_roles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_roles public.app_role[];
  v_target_is_admin boolean;
  v_admin_count bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'Target user not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(array_agg(role ORDER BY role), ARRAY['buyer']::public.app_role[])
    INTO v_roles
  FROM (SELECT DISTINCT unnest(COALESCE(p_roles, ARRAY[]::public.app_role[])) AS role) selected;

  IF cardinality(v_roles) = 0 THEN
    v_roles := ARRAY['buyer']::public.app_role[];
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = p_target_user_id AND role = 'admin'
  ) INTO v_target_is_admin;
  SELECT count(*) INTO v_admin_count FROM public.user_roles WHERE role = 'admin';

  IF v_target_is_admin AND NOT ('admin' = ANY(v_roles)) AND v_admin_count <= 1 THEN
    RAISE EXCEPTION 'Cannot remove the last admin' USING ERRCODE = '23514';
  END IF;
  IF p_target_user_id = auth.uid() AND v_target_is_admin AND NOT ('admin' = ANY(v_roles)) THEN
    RAISE EXCEPTION 'Cannot remove your own admin access' USING ERRCODE = '42501';
  END IF;

  PERFORM 1 FROM public.user_roles WHERE user_id = p_target_user_id FOR UPDATE;
  DELETE FROM public.user_roles WHERE user_id = p_target_user_id;
  INSERT INTO public.user_roles(user_id, role)
  SELECT p_target_user_id, role FROM unnest(v_roles) AS role;

  RETURN QUERY SELECT * FROM public.user_roles WHERE user_id = p_target_user_id ORDER BY role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_replace_user_roles(uuid, public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_replace_user_roles(uuid, public.app_role[]) TO authenticated, service_role;

-- The application uses Supabase Auth's resetPasswordForEmail flow. The legacy
-- plaintext token table must not be readable or writable through PostgREST.
DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Anyone can request password reset" ON public.password_reset_tokens;
DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens;
REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated;

-- Align the UI password-reset minimum with registration policy. The actual
-- Supabase Auth password policy remains the server-side authority.
COMMENT ON TABLE public.password_reset_tokens IS
  'Legacy reset table disabled: password reset is handled by Supabase Auth; no public policies.';
