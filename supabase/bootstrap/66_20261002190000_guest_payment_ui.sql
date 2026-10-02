-- Guest payment UI support: token-scoped payment context and private proof objects.
CREATE OR REPLACE FUNCTION public.get_guest_order_payment_context(p_order_id uuid, p_guest_access_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant public.merchants%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex')
    AND guest_token_expires_at > now();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501';
  END IF;
  IF v_order.payment_method <> 'TRANSFER' THEN
    RAISE EXCEPTION 'Guest transfer payment is unavailable' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_merchant FROM public.merchants WHERE id = v_order.merchant_id;
  RETURN jsonb_build_object(
    'id', v_order.id,
    'total', v_order.total,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'merchant_id', v_order.merchant_id,
    'merchant_name', v_merchant.name,
    'created_at', v_order.created_at,
    'payment_proof_url', v_order.payment_proof_url,
    'confirmation_deadline', v_order.confirmation_deadline,
    'bank_name', v_merchant.bank_name,
    'bank_account_number', v_merchant.bank_account_number,
    'bank_account_name', v_merchant.bank_account_name,
    'qris_image_url', v_merchant.qris_image_url
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_guest_order_payment_context(uuid, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.get_guest_order_payment_context(uuid, text) TO anon;

DROP POLICY IF EXISTS "Guest can upload own transfer proof" ON storage.objects;
CREATE POLICY "Guest can upload own transfer proof" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND split_part(name, '/', 1) = 'orders'
    AND length(split_part(name, '/', 2)) > 0
    AND length(split_part(name, '/', 3)) = 64
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = split_part(name, '/', 2)
        AND o.guest_access_token_hash = split_part(name, '/', 3)
        AND o.payment_method = 'TRANSFER'
        AND o.guest_token_expires_at > now()
    )
  );

DROP POLICY IF EXISTS "Guest can read own transfer proof" ON storage.objects;
CREATE POLICY "Guest can read own transfer proof" ON storage.objects
  FOR SELECT TO anon
  USING (
    bucket_id = 'payment-proofs'
    AND split_part(name, '/', 1) = 'orders'
    AND length(split_part(name, '/', 3)) = 64
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id::text = split_part(name, '/', 2)
        AND o.guest_access_token_hash = split_part(name, '/', 3)
        AND o.guest_token_expires_at > now()
    )
  );

DO $bootstrap_do_guest_payment_ui$
BEGIN
  EXECUTE $bootstrap_sql_guest_payment_ui$COMMENT ON FUNCTION public.get_guest_order_payment_context(uuid, text) IS 'Returns minimum transfer-payment context after validating a guest access token.'$bootstrap_sql_guest_payment_ui$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_guest_payment_ui$;
