-- Secure marketplace transfer proofs.
-- Payment proof images contain financial and personal information and must not
-- be publicly readable or mutable by arbitrary authenticated users.

UPDATE storage.buckets
SET public = false
WHERE id = 'payment-proofs';

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

CREATE OR REPLACE FUNCTION public.can_manage_payment_proof(p_object_name text)
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
      AND o.buyer_id = auth.uid()
      AND o.payment_method = 'TRANSFER'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_payment_proof(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_payment_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_payment_proof(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_payment_proof(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can update own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer or admin can delete payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Payment proof owner or merchant can read" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can upload payment proof for own transfer order" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can replace own payment proof" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can delete own payment proof" ON storage.objects;

CREATE POLICY "Payment proof owner or merchant can read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_access_payment_proof(name)
);

CREATE POLICY "Buyer can upload payment proof for own transfer order"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

CREATE POLICY "Buyer can replace own payment proof"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

CREATE POLICY "Buyer can delete own payment proof"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

COMMENT ON FUNCTION public.can_access_payment_proof(text)
IS 'Allows only the buyer, owning merchant, or admin to read a marketplace payment proof object.';
COMMENT ON FUNCTION public.can_manage_payment_proof(text)
IS 'Allows only the buyer who owns a TRANSFER order to create, replace, or delete its proof object.';
