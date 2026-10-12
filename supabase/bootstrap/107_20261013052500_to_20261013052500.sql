-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

-- ===== BEGIN SOURCE: 20261013052500_marketplace_checkout_shipping_quote.sql =====
DO $bootstrap_do_813cab9d4b8e$
BEGIN
  EXECUTE $bootstrap_sql_813cab9d4b8e$-- Server-authoritative checkout quote and distance calculation.
-- The quote and order creation both derive distance from the stored merchant
-- coordinates and the destination coordinates; client-supplied distance is
-- deliberately ignored for authenticated checkouts.
CREATE OR REPLACE FUNCTION public.quote_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_voucher_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_product public.products%ROWTYPE;
  v_merchant_id uuid;
  v_merchant_count integer;
  v_subtotal integer := 0;
  v_shipping integer := 0;
  v_discount integer := 0;
  v_total integer := 0;
  v_quantity integer;
  v_unit_price integer;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_distance numeric := 0;
  v_settings jsonb;
  v_voucher public.vouchers%ROWTYPE;
  v_now timestamptz := now();
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Cart is empty' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type NOT IN ('PICKUP', 'INTERNAL', 'EXPEDITION') THEN
    RAISE EXCEPTION 'Invalid delivery type' USING ERRCODE = '22023';
  END IF;
  IF p_voucher_id IS NOT NULL AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Voucher requires an account' USING ERRCODE = '42501';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF NULLIF(v_item->>'product_id', '') IS NULL THEN
      RAISE EXCEPTION 'Product is required' USING ERRCODE = '22023';
    END IF;
    v_quantity := (v_item->>'quantity')::integer;
    IF v_quantity IS NULL OR v_quantity <= 0 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Invalid product quantity' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_product FROM public.products
    WHERE id = (v_item->>'product_id')::uuid AND is_active IS TRUE;
    IF NOT FOUND OR v_product.merchant_id IS NULL THEN
      RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = '22023';
    END IF;
    SELECT COALESCE(fs.flash_price, v_product.price) INTO v_unit_price
    FROM (SELECT 1) base
    LEFT JOIN LATERAL (
      SELECT flash_price FROM public.flash_sales
      WHERE product_id = v_product.id
        AND merchant_id = v_product.merchant_id
        AND status = 'ACTIVE'
        AND start_time <= v_now
        AND end_time > v_now
        AND stock_available > stock_sold
      ORDER BY end_time ASC LIMIT 1
    ) fs ON true;
    IF v_merchant_id IS NULL THEN
      v_merchant_id := v_product.merchant_id;
      v_merchant_count := 1;
    ELSIF v_merchant_id <> v_product.merchant_id THEN
      v_merchant_count := 2;
    END IF;
    v_subtotal := v_subtotal + (v_quantity * v_unit_price);
  END LOOP;

  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya tersedia untuk satu toko dalam satu transaksi' USING ERRCODE = '22023';
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher FROM public.vouchers WHERE id = p_voucher_id;
    IF NOT FOUND OR v_voucher.is_active IS NOT TRUE
       OR v_voucher.start_date > v_now
       OR (v_voucher.end_date IS NOT NULL AND v_voucher.end_date < v_now)
       OR (v_voucher.merchant_id IS NOT NULL AND v_voucher.merchant_id <> v_merchant_id)
       OR EXISTS (SELECT 1 FROM public.voucher_usages WHERE voucher_id = p_voucher_id AND user_id = auth.uid())
       OR (v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit)
       OR v_subtotal < COALESCE(v_voucher.min_order_amount, 0) THEN
      RAISE EXCEPTION 'Voucher is invalid or unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_voucher.discount_type = 'percentage' THEN
      v_discount := floor(v_subtotal * v_voucher.discount_value / 100.0);
      IF v_voucher.max_discount IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_voucher.max_discount);
      END IF;
    ELSE
      v_discount := v_voucher.discount_value;
    END IF;
    v_discount := GREATEST(0, LEAST(v_discount, v_subtotal));
  END IF;

  IF p_delivery_type <> 'PICKUP' THEN
    v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
    v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng
    FROM public.merchants WHERE id = v_merchant_id;
    IF v_delivery_lat IS NULL OR v_delivery_lng IS NULL
       OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL
       OR v_delivery_lat < -90 OR v_delivery_lat > 90
       OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180
       OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    END IF;
    v_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
      power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
      + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
      * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
    ))));
    SELECT value INTO v_settings FROM public.app_settings WHERE key = 'shipping_base_fee';
    IF v_subtotal < COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000) THEN
      v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
        + round(v_distance * COALESCE((v_settings->>'per_km_fee')::integer, 2000));
      v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
        GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
    END IF;
  END IF;

  v_total := GREATEST(0, v_subtotal + v_shipping - v_discount);
  RETURN jsonb_build_object(
    'subtotal', v_subtotal,
    'shipping_cost', v_shipping,
    'voucher_discount', v_discount,
    'total', v_total,
    'distance_km', round(v_distance::numeric, 2),
    'quoted_at', v_now
  );
END;
$$$bootstrap_sql_813cab9d4b8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_813cab9d4b8e$;

DO $bootstrap_do_450aa6e474b2$
BEGIN
  EXECUTE $bootstrap_sql_450aa6e474b2$REVOKE ALL ON FUNCTION public.quote_marketplace_checkout(jsonb, jsonb, text, uuid) FROM PUBLIC$bootstrap_sql_450aa6e474b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_450aa6e474b2$;

DO $bootstrap_do_9a734c5e487d$
BEGIN
  EXECUTE $bootstrap_sql_9a734c5e487d$GRANT EXECUTE ON FUNCTION public.quote_marketplace_checkout(jsonb, jsonb, text, uuid) TO anon, authenticated$bootstrap_sql_9a734c5e487d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a734c5e487d$;

DO $bootstrap_do_a7f67d452782$
BEGIN
  EXECUTE $bootstrap_sql_a7f67d452782$-- Preserve the existing idempotency contract while replacing the client
-- distance with a distance derived from the submitted coordinates and the
-- merchant's coordinates stored in the database.
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
  v_merchant_id uuid;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_server_distance numeric := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS i(product_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count = 0 THEN
    RAISE EXCEPTION 'Cart is empty or contains invalid products' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method IN ('ONLINE', 'TRANSFER') AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Pembayaran online dan transfer hanya tersedia untuk checkout satu toko' USING ERRCODE = '22023';
  END IF;
  SELECT p.merchant_id INTO v_merchant_id
  FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS i(product_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id
  LIMIT 1;
  IF p_delivery_type = 'PICKUP' THEN
    v_server_distance := NULL;
  ELSE
    v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
    v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng
    FROM public.merchants WHERE id = v_merchant_id;
    IF v_delivery_lat IS NULL OR v_delivery_lng IS NULL
       OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL
       OR v_delivery_lat < -90 OR v_delivery_lat > 90
       OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180
       OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    END IF;
    v_server_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
      power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
      + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
      * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
    ))));
  END IF;

  v_result := public.create_marketplace_checkout_legacy(
    p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, v_server_distance
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$$bootstrap_sql_a7f67d452782$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7f67d452782$;

DO $bootstrap_do_4ad42407a64f$
BEGIN
  EXECUTE $bootstrap_sql_4ad42407a64f$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon$bootstrap_sql_4ad42407a64f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ad42407a64f$;

DO $bootstrap_do_761dab7f5e53$
BEGIN
  EXECUTE $bootstrap_sql_761dab7f5e53$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role$bootstrap_sql_761dab7f5e53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_761dab7f5e53$;

DO $bootstrap_do_ce27d3ba194f$
BEGIN
  EXECUTE $bootstrap_sql_ce27d3ba194f$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ce27d3ba194f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce27d3ba194f$;

-- ===== END SOURCE: 20261013052500_marketplace_checkout_shipping_quote.sql =====
