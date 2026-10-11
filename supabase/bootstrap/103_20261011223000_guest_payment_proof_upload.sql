-- Bootstrap idempotency marker for standalone deployment migrations.
DO $bootstrap_do_guest_payment_proof_upload_marker$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_guest_payment_proof_upload_marker$;

-- Allow anonymous guest checkout users to upload transfer proofs.
-- The object path carries the SHA-256 guest token hash:
-- orders/{order_id}/{guest_token_hash}/{filename}
-- This does not grant anonymous read access; the bucket remains private.

CREATE OR REPLACE FUNCTION public.can_guest_manage_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
  v_token_hash text;
BEGIN
  IF auth.role() <> 'anon'
     OR split_part(p_object_name, '/', 1) <> 'orders'
     OR array_length(string_to_array(p_object_name, '/'), 1) <> 4 THEN
    RETURN false;
  END IF;

  BEGIN
    v_order_id := split_part(p_object_name, '/', 2)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;

  v_token_hash := split_part(p_object_name, '/', 3);
  IF length(v_token_hash) <> 64
     OR v_token_hash !~ '^[0-9a-f]{64}$'
     OR length(trim(split_part(p_object_name, '/', 4))) = 0 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = v_order_id
      AND o.buyer_id IS NULL
      AND o.guest_access_token_hash = v_token_hash
      AND o.guest_token_expires_at > now()
      AND o.payment_method = 'TRANSFER'
      AND o.payment_status NOT IN ('PAID', 'REFUNDED', 'EXPIRED')
      AND o.status NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_guest_manage_payment_proof(text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.can_guest_manage_payment_proof(text) TO anon, service_role;

DROP POLICY IF EXISTS "Guest can upload own transfer payment proof" ON storage.objects;
CREATE POLICY "Guest can upload own transfer payment proof"
ON storage.objects
FOR INSERT
TO anon
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_guest_manage_payment_proof(name)
);

COMMENT ON FUNCTION public.can_guest_manage_payment_proof(text)
IS 'Allows an untrusted guest to upload one payment-proof object only under the order folder and matching unexpired guest token hash.';

NOTIFY pgrst, 'reload schema';
