-- Role jasa resmi dan onboarding yang hanya dapat dipicu oleh akun pembeli.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'service_provider';

CREATE OR REPLACE FUNCTION public.activate_service_provider()
RETURNS public.app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.has_role(auth.uid(), 'buyer') THEN
    RAISE EXCEPTION 'Buyer role is required before becoming a service provider';
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (auth.uid(), 'service_provider')
  ON CONFLICT (user_id, role) DO NOTHING;

  RETURN 'service_provider'::public.app_role;
END;
$$;

REVOKE ALL ON FUNCTION public.activate_service_provider() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_service_provider() TO authenticated;

DROP POLICY IF EXISTS "providers manage own profile" ON public.service_profiles;
CREATE POLICY "providers manage own profile" ON public.service_profiles
FOR ALL
USING (provider_id = auth.uid() AND public.has_role(auth.uid(), 'service_provider') OR public.is_admin(auth.uid()))
WITH CHECK (provider_id = auth.uid() AND public.has_role(auth.uid(), 'service_provider') OR public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "requesters create requests" ON public.service_requests;
CREATE POLICY "requesters create requests" ON public.service_requests
FOR INSERT
WITH CHECK (requester_id = auth.uid() AND public.has_role(auth.uid(), 'buyer'));
