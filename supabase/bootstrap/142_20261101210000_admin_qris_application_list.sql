-- Secure admin-only listing endpoint for QRIS application review.
-- SECURITY DEFINER avoids client-side RLS/relationship visibility issues while
-- the explicit admin check prevents disclosure to non-admin callers.
CREATE OR REPLACE FUNCTION public.admin_list_qris_applications()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT to_jsonb(a) || jsonb_build_object(
    'merchant', jsonb_build_object('name', m.name, 'city', m.city)
  )
  FROM public.qris_applications AS a
  LEFT JOIN public.merchants AS m ON m.id = a.merchant_id
  ORDER BY a.submitted_at DESC, a.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_qris_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_qris_applications() TO authenticated;
NOTIFY pgrst, 'reload schema';
