-- Restore the authoritative marketplace checkout implementation.
-- Some deployed databases contain a broken 7-argument wrapper which calls
-- create_marketplace_checkout(..., p_checkout_key, NULL), i.e. a nonexistent
-- 8-argument overload. This migration replaces its body with the canonical
-- server-authoritative 7-argument checkout implementation from the repository.
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
  v_item jsonb;
  v_product public.products%ROWTYPE;
  v_merchant_id uuid;
  v_order_id uuid;
  v_primary_order_id uuid;
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_quantity integer;
  v_subtotal integer;
  v_shipping integer;
  v_cod_fee integer := 0;
  v_discount integer := 0;
  v_total integer;
  v_voucher public.vouchers%ROWTYPE;
  v_voucher_merchant uuid;
  v_merchant_count integer;
  v_settings jsonb;
  v_cod_settings jsonb;
  v_unit_price integer;
  v_item_subtotal integer;
  v_status text;
  v_payment_status text;
  v_deadline timestamptz;
  v_merchant_item jsonb;
  v_existing jsonb;
  v_result jsonb;
  v_items jsonb;
  v_contract jsonb;
  v_contracts jsonb := '[]'::jsonb;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_server_distance numeric := 0;
  v_shipping_total integer := 0;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid checkout request' USING ERRCODE = '22023';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  v_items := public.normalize_marketplace_checkout_items(p_items);
  IF p_delivery_type NOT IN ('PICKUP', 'INTERNAL', 'EXPEDITION') THEN
    RAISE EXCEPTION 'Invalid delivery type' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type <> 'PICKUP'
     AND NULLIF(btrim(COALESCE(p_delivery->>'address', '')), '') IS NULL THEN
    RAISE EXCEPTION 'Delivery address is required' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type <> 'PICKUP'
     AND (jsonb_typeof(p_delivery->'lat') IS DISTINCT FROM 'number'
       OR jsonb_typeof(p_delivery->'lng') IS DISTINCT FROM 'number') THEN
    RAISE EXCEPTION 'Valid delivery coordinates are required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_delivery->>'name', '')), '') IS NULL
     OR length(btrim(p_delivery->>'name')) > 200
     OR NULLIF(btrim(COALESCE(p_delivery->>'phone', '')), '') IS NULL
     OR length(btrim(p_delivery->>'phone')) > 40 THEN
    RAISE EXCEPTION 'Invalid delivery contact' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method NOT IN ('COD', 'TRANSFER', 'ONLINE') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'ONLINE' AND (
    SELECT count(DISTINCT p.merchant_id)
    FROM jsonb_array_elements(v_items) x
    JOIN public.products p ON p.id = NULLIF(x->>'product_id', '')::uuid
  ) > 1 THEN
    RAISE EXCEPTION 'Online checkout supports one merchant per invoice' USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE checkout_lines (
    product_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    product_name text NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    line_total integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    IF NULLIF(v_item->>'product_id', '') IS NULL THEN
      RAISE EXCEPTION 'Product is required' USING ERRCODE = '22023';
    END IF;
    v_quantity := (v_item->>'quantity')::integer;
    IF v_quantity IS NULL OR v_quantity <= 0 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Invalid product quantity' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid
    FOR UPDATE;
    IF NOT FOUND OR v_product.is_active IS NOT TRUE THEN
      RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.merchant_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = v_product.merchant_id
        AND m.registration_status = 'APPROVED'
        AND m.status = 'ACTIVE'
        AND m.is_open = true
    ) THEN
      RAISE EXCEPTION 'Merchant is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.stock < v_quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_product.name USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(fs.flash_price, v_product.price)
      INTO v_unit_price
    FROM (SELECT 1) base
    LEFT JOIN LATERAL (
      SELECT flash_price
      FROM public.flash_sales
      WHERE product_id = v_product.id
        AND merchant_id = v_product.merchant_id
        AND status = 'ACTIVE'
        AND start_time <= now()
        AND end_time > now()
        AND stock_available > stock_sold
      ORDER BY end_time ASC
      LIMIT 1
    ) fs ON true;
    v_item_subtotal := v_unit_price * v_quantity;
    INSERT INTO checkout_lines VALUES (
      v_product.id, v_product.merchant_id, v_product.name,
      v_quantity, v_unit_price, v_item_subtotal
    );
  END LOOP;

  SELECT count(DISTINCT merchant_id) INTO v_merchant_count FROM checkout_lines;
  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya tersedia untuk satu toko dalam satu transaksi' USING ERRCODE = '22023';
  END IF;
  IF p_voucher_id IS NOT NULL AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Voucher checkout must contain one merchant' USING ERRCODE = '22023';
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher FROM public.vouchers WHERE id = p_voucher_id FOR UPDATE;
    IF NOT FOUND OR v_voucher.is_active IS NOT TRUE
       OR v_voucher.start_date > now()
       OR (v_voucher.end_date IS NOT NULL AND v_voucher.end_date < now()) THEN
      RAISE EXCEPTION 'Voucher is invalid or expired' USING ERRCODE = '22023';
    END IF;
    SELECT merchant_id INTO v_voucher_merchant FROM checkout_lines LIMIT 1;
    IF v_voucher.merchant_id IS NOT NULL AND v_voucher.merchant_id <> v_voucher_merchant THEN
      RAISE EXCEPTION 'Voucher does not apply to this merchant' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.voucher_usages WHERE voucher_id = p_voucher_id AND user_id = auth.uid()) THEN
      RAISE EXCEPTION 'Voucher has already been used' USING ERRCODE = '23505';
    END IF;
    IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
      RAISE EXCEPTION 'Voucher usage limit reached' USING ERRCODE = '23505';
    END IF;
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines);
    IF v_subtotal < COALESCE(v_voucher.min_order_amount, 0) THEN
      RAISE EXCEPTION 'Minimum order for voucher is not met' USING ERRCODE = '22023';
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

  SELECT value INTO v_cod_settings FROM public.app_settings WHERE key = 'cod_settings';
  IF p_payment_method = 'COD' THEN
    IF COALESCE((v_cod_settings->>'enabled')::boolean, true) IS NOT TRUE THEN
      RAISE EXCEPTION 'COD is currently unavailable' USING ERRCODE = '22023';
    END IF;
    -- COD remains available, but it is always free of charge.
    v_cod_fee := 0;
  END IF;

  IF p_payment_method = 'COD' THEN
    v_status := 'PENDING_CONFIRMATION';
    v_payment_status := 'COD';
    v_deadline := now() + make_interval(mins => COALESCE((v_cod_settings->>'confirmation_timeout_minutes')::integer, 15));
  ELSIF p_payment_method = 'TRANSFER' THEN
    v_status := 'PENDING_PAYMENT';
    v_payment_status := 'PENDING_TRANSFER';
    v_deadline := NULL;
  ELSE
    v_status := 'NEW';
    v_payment_status := 'UNPAID';
    v_deadline := NULL;
  END IF;

  FOR v_merchant_id IN SELECT DISTINCT merchant_id FROM checkout_lines ORDER BY merchant_id LOOP
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines WHERE merchant_id = v_merchant_id);
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng
    FROM public.merchants WHERE id = v_merchant_id FOR SHARE;
    v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
    v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
    IF p_delivery_type = 'PICKUP' THEN
      v_server_distance := 0;
    ELSIF v_delivery_lat IS NULL OR v_delivery_lng IS NULL OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL
       OR v_delivery_lat < -90 OR v_delivery_lat > 90
       OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180
       OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    ELSE
      v_server_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
        power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
        + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
        * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
      ))));
    END IF;
    v_contract := public.marketplace_shipping_contract_quote(
      v_items, p_delivery, p_delivery_type, v_subtotal, v_server_distance, v_merchant_id, NULL
    );
    v_shipping := (v_contract->>'shipping_cost')::integer;
    v_shipping_total := v_shipping_total + v_shipping;
    v_contracts := v_contracts || jsonb_build_array(v_contract);
    v_total := GREATEST(0, v_subtotal + v_shipping + v_cod_fee - v_discount);
    INSERT INTO public.orders (
      buyer_id, merchant_id, status, handled_by, delivery_type,
      delivery_address, delivery_phone, delivery_name, shipping_cost,
      subtotal, total, notes, flash_sale_discount, payment_method,
      payment_status, confirmation_deadline, cod_service_fee, buyer_distance_km, shipping_pricing_contract,
      delivery_lat, delivery_lng, delivery_province_id, delivery_province_name,
      delivery_city_id, delivery_city_name, delivery_district_id, delivery_district_name
    ) VALUES (
      auth.uid(), v_merchant_id, v_status, 'ADMIN', p_delivery_type,
      NULLIF(p_delivery->>'address', ''), NULLIF(p_delivery->>'phone', ''), NULLIF(p_delivery->>'name', ''),
      v_shipping, v_subtotal, v_total, NULLIF(p_delivery->>'notes', ''), v_discount,
      p_payment_method, v_payment_status, v_deadline, v_cod_fee, v_server_distance, v_contract,
      (p_delivery->>'lat')::numeric, (p_delivery->>'lng')::numeric,
      NULLIF(p_delivery->>'province_id', ''), NULLIF(p_delivery->>'province_name', ''),
      NULLIF(p_delivery->>'city_id', ''), NULLIF(p_delivery->>'city_name', ''),
      NULLIF(p_delivery->>'district_id', ''), NULLIF(p_delivery->>'district_name', '')
    ) RETURNING id INTO v_order_id;
    v_order_ids := array_append(v_order_ids, v_order_id);
    IF v_primary_order_id IS NULL THEN v_primary_order_id := v_order_id; END IF;

    INSERT INTO public.order_items(order_id, product_id, product_name, product_price, quantity, subtotal)
    SELECT v_order_id, product_id, product_name, unit_price, quantity, line_total
    FROM checkout_lines WHERE merchant_id = v_merchant_id;

    PERFORM public.reserve_marketplace_stock(
      v_order_id,
      (SELECT jsonb_agg(jsonb_build_object('product_id', product_id, 'variant_id', NULL, 'quantity', quantity))
       FROM checkout_lines WHERE merchant_id = v_merchant_id),
      COALESCE(v_deadline, now() + interval '30 minutes')
    );

    IF p_voucher_id IS NOT NULL THEN
      INSERT INTO public.voucher_usages(voucher_id, user_id, order_id, discount_amount)
      VALUES (p_voucher_id, auth.uid(), v_order_id, v_discount);
      UPDATE public.vouchers SET used_count = used_count + 1, updated_at = now()
      WHERE id = p_voucher_id;
    END IF;
  END LOOP;

  v_result := jsonb_build_object(
    'order_ids', to_jsonb(v_order_ids),
    'primary_order_id', v_primary_order_id,
    'subtotal', (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines),
    'shipping_cost', v_shipping_total,
    'voucher_discount', v_discount,
    'cod_service_fee', v_cod_fee,
    'shipping_pricing_contracts', v_contracts
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
