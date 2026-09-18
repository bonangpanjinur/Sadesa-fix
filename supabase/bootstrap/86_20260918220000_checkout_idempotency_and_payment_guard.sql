-- Checkout hardening: serialize retries by buyer/key and reject unsupported
-- multi-merchant payment methods before the authoritative order function runs.

CREATE TABLE IF NOT EXISTS public.marketplace_checkout_idempotency (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_key text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, checkout_key)
);

ALTER TABLE public.marketplace_checkout_idempotency ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_checkout_idempotency FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing jsonb;
  v_result jsonb;
  v_merchant_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;

  -- This advisory transaction lock makes a timeout/retry wait for the first
  -- attempt, then return its committed result instead of creating duplicates.
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing
  FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS i(product_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count = 0 THEN
    RAISE EXCEPTION 'Cart is empty or contains invalid products' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method IN ('ONLINE', 'TRANSFER') AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Pembayaran online dan transfer hanya tersedia untuk checkout satu toko' USING ERRCODE = '22023';
  END IF;

  v_result := public.create_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
COMMENT ON TABLE public.marketplace_checkout_idempotency IS 'Authoritative checkout results keyed per buyer to make retries safe.';
