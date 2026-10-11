-- Bootstrap idempotency marker for standalone deployment migrations.
DO $bootstrap_do_fix_payment_proof_read_policy_marker$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_fix_payment_proof_read_policy_marker$;

-- Repair the marketplace payment-proof SELECT policy.
-- The legacy production policy read the merchant table name instead of the
-- storage object path and therefore rejected valid merchant signed-URL requests.

CREATE OR REPLACE FUNCTION public.can_access_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
BEGIN
  IF auth.uid() IS NULL OR split_part(p_object_name, '/', 1) <> 'orders' THEN
    RETURN false;
  END IF;

  BEGIN
    v_order_id := split_part(p_object_name, '/', 2)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;

  RETURN EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = v_order_id
      AND (
        o.buyer_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.merchants m
          WHERE m.id = o.merchant_id
            AND m.user_id = auth.uid()
        )
        OR public.is_admin()
      )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_payment_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_payment_proof(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Payment proof owner or merchant can read" ON storage.objects;

CREATE POLICY "Payment proof owner or merchant can read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_access_payment_proof(name)
);
