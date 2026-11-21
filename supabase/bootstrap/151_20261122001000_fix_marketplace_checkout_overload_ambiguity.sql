-- Repair the live GDC checkout wrapper without changing the checkout implementation.
-- The seven-argument implementation is preserved in the private helper created by the
-- earlier checkout repair. Calling the public RPC by its overloaded name from the
-- eight-argument wrapper is ambiguous because p_payment_channel has a default.
CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_payment_channel IS NOT NULL
     AND p_payment_channel <> 'QRIS_MPM_GDC' THEN
    RAISE EXCEPTION 'Invalid payment channel' USING ERRCODE = '22023';
  END IF;

  IF p_payment_channel = 'QRIS_MPM_GDC'
     AND p_payment_method <> 'TRANSFER' THEN
    RAISE EXCEPTION 'GDC QRIS requires transfer payment method' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config(
    'sadesa.checkout_payment_channel',
    COALESCE(p_payment_channel, ''),
    true
  );

  v_result := public.create_marketplace_checkout_core(
    p_items,
    p_delivery,
    p_delivery_type,
    p_payment_method,
    p_voucher_id,
    p_distance_km,
    p_checkout_key
  );

  IF p_payment_channel = 'QRIS_MPM_GDC' THEN
    UPDATE public.orders
    SET confirmation_deadline = now() + interval '30 minutes',
        updated_at = now()
    WHERE id IN (
      SELECT value::uuid
      FROM jsonb_array_elements_text(v_result->'order_ids')
    )
      AND confirmation_deadline IS NULL;
  END IF;

  RETURN v_result;
END;
$$;

-- Keep the historical 7-argument object for dependency compatibility, but prevent
-- PostgREST from exposing it as a second candidate for authenticated checkout calls.
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
