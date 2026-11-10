-- Single-merchant checkout and final QR MPM state transitions.
-- Forward-only migration; do not run against production from this task workspace.

CREATE OR REPLACE FUNCTION public.assign_order_payment_intent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_channel text := NULLIF(current_setting('sadesa.checkout_payment_channel', true), '');
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.payment_method = 'TRANSFER' THEN
      NEW.payment_channel := COALESCE(v_channel, 'ADMIN_MANUAL');
      IF NEW.payment_channel NOT IN ('ADMIN_MANUAL', 'QRIS_MPM_GDC') THEN
        RAISE EXCEPTION 'Payment channel transfer tidak valid' USING ERRCODE = '22023';
      END IF;
      NEW.payment_intent := CASE WHEN NEW.payment_channel = 'QRIS_MPM_GDC' THEN 'GDC_MPM' ELSE 'ADMIN_MANUAL' END;
    ELSE
      IF (v_channel IS NOT NULL AND v_channel IS DISTINCT FROM NEW.payment_method)
         OR (NEW.payment_channel IS NOT NULL AND NEW.payment_channel IS DISTINCT FROM NEW.payment_method) THEN
        RAISE EXCEPTION 'Payment channel tidak sesuai dengan metode pembayaran' USING ERRCODE = '22023';
      END IF;
      NEW.payment_intent := NEW.payment_method;
      NEW.payment_channel := NEW.payment_method;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.payment_channel IS DISTINCT FROM OLD.payment_channel
     OR NEW.payment_intent IS DISTINCT FROM OLD.payment_intent THEN
    RAISE EXCEPTION 'Payment intent/channel immutable setelah order dibuat' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.assign_order_payment_intent() FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.marketplace_checkout_request_fingerprints (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_key text NOT NULL,
  payload_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, checkout_key)
);
ALTER TABLE public.marketplace_checkout_request_fingerprints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_checkout_request_fingerprints FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.marketplace_guest_checkout_request_fingerprints (
  guest_session_key_hash text NOT NULL,
  checkout_key text NOT NULL,
  payload_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (guest_session_key_hash, checkout_key)
);
ALTER TABLE public.marketplace_guest_checkout_request_fingerprints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_guest_checkout_request_fingerprints FROM PUBLIC, anon, authenticated;

-- Rebuild the private authoritative checkout core instead of renaming an
-- assumed legacy overload. Some environments retained only the QRIS wrapper,
-- so the old seven-argument function may not exist at migration time.
CREATE OR REPLACE FUNCTION public.create_marketplace_checkout_core(
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
REVOKE ALL ON FUNCTION public.create_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text) TO service_role;

-- Preserve the current payment-intent binding while rejecting cross-merchant calls
-- and binding every authenticated idempotency key to its first exact payload.
CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL, p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_user_id uuid := auth.uid();
  v_merchant_count integer;
  v_fingerprint text;
  v_existing_fingerprint text;
  v_has_legacy_result boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated checkout is required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one checkout item is required' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(public.normalize_marketplace_checkout_items(p_items)) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya dapat berisi produk dari satu pedagang' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'TRANSFER' THEN
    IF COALESCE(p_payment_channel, 'ADMIN_MANUAL') NOT IN ('ADMIN_MANUAL', 'QRIS_MPM_GDC') THEN
      RAISE EXCEPTION 'Payment channel transfer tidak valid' USING ERRCODE = '22023';
    END IF;
  ELSIF p_payment_channel IS NOT NULL AND p_payment_channel <> p_payment_method THEN
    RAISE EXCEPTION 'Payment channel tidak sesuai dengan metode pembayaran' USING ERRCODE = '22023';
  END IF;

  v_fingerprint := encode(digest(jsonb_build_object(
    'items', public.normalize_marketplace_checkout_items(p_items),
    'delivery', COALESCE(p_delivery, '{}'::jsonb),
    'delivery_type', p_delivery_type,
    'payment_method', p_payment_method,
    'payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END),
    'voucher_id', p_voucher_id,
    'distance_km', p_distance_km
  )::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':' || trim(p_checkout_key), 0));

  SELECT payload_fingerprint INTO v_existing_fingerprint
  FROM public.marketplace_checkout_request_fingerprints
  WHERE user_id = v_user_id AND checkout_key = trim(p_checkout_key)
  FOR UPDATE;
  IF v_existing_fingerprint IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.marketplace_checkout_idempotency
      WHERE user_id = v_user_id AND checkout_key = trim(p_checkout_key)
    ) INTO v_has_legacy_result;
    IF v_has_legacy_result THEN
      RAISE EXCEPTION 'Checkout key lama tidak dapat digunakan ulang; pulihkan pesanan yang sudah dibuat' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.marketplace_checkout_request_fingerprints(user_id, checkout_key, payload_fingerprint)
    VALUES (v_user_id, trim(p_checkout_key), v_fingerprint);
  ELSIF v_existing_fingerprint <> v_fingerprint THEN
    RAISE EXCEPTION 'Checkout key sudah terikat pada payload lain' USING ERRCODE = '23505';
  END IF;

  PERFORM set_config('sadesa.checkout_payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END), true);
  v_result := public.create_marketplace_checkout_core(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_checkout_key
  );
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.create_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_checkout_key, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text) TO authenticated, service_role;

-- The client supplies one 256-bit guest access token and retains it with the
-- checkout key. The database stores only its hash and restores that token on retry.
-- Rebuild the private guest checkout core for the same reason as the
-- authenticated core: do not depend on a historical overload being present.
CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout_core(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL,
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
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_server_distance numeric;
  v_shipping_total integer := 0;
  v_guest_access_token text;
  v_guest_token_expires_at timestamptz;
  v_guest_contact_hash text;
  v_existing jsonb;
  v_result jsonb;
  v_session_hash text;
  v_effective_checkout_key text;
  v_items jsonb;
  v_contract jsonb;
  v_contracts jsonb := '[]'::jsonb;
BEGIN
  IF p_guest_checkout_key IS NULL OR length(trim(p_guest_checkout_key)) < 16 OR length(trim(p_guest_checkout_key)) > 128
     OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid checkout request' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(COALESCE(p_delivery->>'name', '')), '') IS NULL
     OR length(trim(p_delivery->>'name')) > 200
     OR NULLIF(trim(COALESCE(p_delivery->>'phone', '')), '') IS NULL
     OR length(trim(p_delivery->>'phone')) > 40 THEN
    RAISE EXCEPTION 'Invalid guest contact' USING ERRCODE = '22023';
  END IF;
  IF p_voucher_id IS NOT NULL THEN
    RAISE EXCEPTION 'Account vouchers are not available for guest checkout' USING ERRCODE = '22023';
  END IF;
  v_items := public.normalize_marketplace_checkout_items(p_items);
  v_effective_checkout_key := COALESCE(NULLIF(trim(p_checkout_key), ''), trim(p_guest_checkout_key));
  IF length(v_effective_checkout_key) < 16 OR length(v_effective_checkout_key) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  v_session_hash := encode(digest(trim(p_guest_checkout_key), 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_session_hash || ':' || v_effective_checkout_key, 0));
  SELECT result INTO v_existing FROM public.marketplace_guest_checkout_idempotency
  WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_effective_checkout_key;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  v_guest_access_token := encode(gen_random_bytes(32), 'hex');
  v_guest_token_expires_at := now() + interval '30 days';
  v_guest_contact_hash := encode(digest(lower(trim(p_delivery->>'phone')), 'sha256'), 'hex');
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
  IF p_payment_method <> 'TRANSFER' THEN
    RAISE EXCEPTION 'Guest payment method is unavailable' USING ERRCODE = '22023';
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
  IF v_merchant_count > 1 THEN
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
    IF EXISTS (SELECT 1 FROM public.voucher_usages WHERE voucher_id = p_voucher_id AND user_id IS NULL) THEN
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
    ELSIF v_delivery_lat IS NULL OR v_delivery_lng IS NULL
       OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL
       OR v_delivery_lat < -90 OR v_delivery_lat > 90
       OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180
       OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    ELSE
      v_server_distance := 6371 * 2 * asin(sqrt(
        power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
        + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
        * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
      ));
    END IF;
    v_contract := public.marketplace_shipping_contract_quote(
      v_items, p_delivery, p_delivery_type, v_subtotal, v_server_distance, v_merchant_id, NULL
    );
    v_shipping := (v_contract->>'shipping_cost')::integer;
    v_shipping_total := v_shipping_total + v_shipping;
    v_contracts := v_contracts || jsonb_build_array(v_contract);
    v_total := GREATEST(0, v_subtotal + v_shipping + v_cod_fee - v_discount);
    INSERT INTO public.orders (
      buyer_id, guest_access_token_hash, guest_token_expires_at, guest_contact_hash, merchant_id, status, handled_by, delivery_type,
      delivery_address, delivery_phone, delivery_name, shipping_cost,
      subtotal, total, notes, flash_sale_discount, payment_method,
      payment_status, confirmation_deadline, cod_service_fee, buyer_distance_km, shipping_pricing_contract,
      delivery_lat, delivery_lng, delivery_province_id, delivery_province_name,
      delivery_city_id, delivery_city_name, delivery_district_id, delivery_district_name
    ) VALUES (
      NULL, encode(digest(v_guest_access_token, 'sha256'), 'hex'), v_guest_token_expires_at, v_guest_contact_hash, v_merchant_id, v_status, 'ADMIN', p_delivery_type,
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

    PERFORM public.reserve_marketplace_stock_guest(
      v_order_id,
      (SELECT jsonb_agg(jsonb_build_object('product_id', product_id, 'variant_id', NULL, 'quantity', quantity))
       FROM checkout_lines WHERE merchant_id = v_merchant_id),
      v_guest_access_token,
      COALESCE(v_deadline, now() + interval '30 minutes')
    );

    IF p_voucher_id IS NOT NULL THEN
      INSERT INTO public.voucher_usages(voucher_id, user_id, order_id, discount_amount)
      VALUES (p_voucher_id, NULL, v_order_id, v_discount);
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
    'shipping_pricing_contracts', v_contracts,
    'guest_access_token', v_guest_access_token,
    'guest_token_expires_at', v_guest_token_expires_at
  );
  v_result := v_result - 'guest_access_token';
  INSERT INTO public.marketplace_guest_checkout_idempotency(guest_session_key_hash, checkout_key, result)
  VALUES (v_session_hash, v_effective_checkout_key, v_result);
  RETURN v_result || jsonb_build_object('guest_access_token', v_guest_access_token);
END;
$$;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_guest_access_token text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL, p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_session_hash text;
  v_checkout_key text;
  v_fingerprint text;
  v_existing_fingerprint text;
  v_merchant_count integer;
  v_order_id uuid;
  v_order_ids jsonb;
  v_access_token text;
  v_has_legacy_result boolean;
  v_updated integer;
BEGIN
  IF p_guest_checkout_key IS NULL OR length(trim(p_guest_checkout_key)) < 16 OR length(trim(p_guest_checkout_key)) > 128
     OR p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128
     OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid guest checkout request' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method <> 'TRANSFER' OR COALESCE(p_payment_channel, 'ADMIN_MANUAL') <> 'ADMIN_MANUAL' THEN
    RAISE EXCEPTION 'Guest checkout hanya mendukung pembayaran manual Admin Sadesa' USING ERRCODE = '22023';
  END IF;
  IF p_voucher_id IS NOT NULL THEN
    RAISE EXCEPTION 'Account vouchers are not available for guest checkout' USING ERRCODE = '22023';
  END IF;
  IF p_guest_access_token IS NULL OR p_guest_access_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Guest access token tidak valid' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(public.normalize_marketplace_checkout_items(p_items)) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya dapat berisi produk dari satu pedagang' USING ERRCODE = '22023';
  END IF;

  v_session_hash := encode(digest(trim(p_guest_checkout_key), 'sha256'), 'hex');
  v_checkout_key := trim(p_checkout_key);
  v_fingerprint := encode(digest(jsonb_build_object(
    'items', public.normalize_marketplace_checkout_items(p_items),
    'delivery', COALESCE(p_delivery, '{}'::jsonb),
    'delivery_type', p_delivery_type,
    'payment_method', p_payment_method,
    'payment_channel', 'ADMIN_MANUAL',
    'voucher_id', p_voucher_id,
    'distance_km', p_distance_km
  )::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_session_hash || ':' || v_checkout_key, 0));

  SELECT payload_fingerprint INTO v_existing_fingerprint
  FROM public.marketplace_guest_checkout_request_fingerprints
  WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_checkout_key
  FOR UPDATE;
  IF v_existing_fingerprint IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.marketplace_guest_checkout_idempotency
      WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_checkout_key
    ) INTO v_has_legacy_result;
    IF v_has_legacy_result THEN
      RAISE EXCEPTION 'Checkout key lama tidak dapat digunakan ulang; pulihkan pesanan yang sudah dibuat' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.marketplace_guest_checkout_request_fingerprints(guest_session_key_hash, checkout_key, payload_fingerprint)
    VALUES (v_session_hash, v_checkout_key, v_fingerprint);
  ELSIF v_existing_fingerprint <> v_fingerprint THEN
    RAISE EXCEPTION 'Checkout key sudah terikat pada payload lain' USING ERRCODE = '23505';
  END IF;

  PERFORM set_config('sadesa.checkout_payment_channel', 'ADMIN_MANUAL', true);
  v_result := public.create_guest_marketplace_checkout_core(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_guest_checkout_key, p_checkout_key
  );
  v_access_token := p_guest_access_token;
  IF v_access_token IS NULL OR v_access_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Guest access token tidak tersedia; pesanan perlu dipulihkan' USING ERRCODE = '22023';
  END IF;

  v_order_ids := COALESCE(v_result->'order_ids', jsonb_build_array(v_result->>'primary_order_id'));
  FOR v_order_id IN SELECT value::uuid FROM jsonb_array_elements_text(v_order_ids) AS id(value)
  LOOP
    UPDATE public.orders
    SET guest_access_token_hash = encode(digest(v_access_token, 'sha256'), 'hex')
    WHERE id = v_order_id AND buyer_id IS NULL;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated <> 1 THEN
      RAISE EXCEPTION 'Guest order access could not be bound to checkout attempt' USING ERRCODE = '42501';
    END IF;
  END LOOP;
  RETURN (v_result - 'guest_access_token') || jsonb_build_object('guest_access_token', v_access_token);
END;
$$;
-- Keep the old RPC signature usable during rollout, but route it through the
-- same fingerprinted function with a deterministic per-attempt access token.
CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL, p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_access_token text;
BEGIN
  IF p_guest_checkout_key IS NULL OR p_checkout_key IS NULL THEN
    RAISE EXCEPTION 'Guest checkout attempt key is required' USING ERRCODE = '22023';
  END IF;
  v_access_token := encode(digest(trim(p_guest_checkout_key) || ':' || trim(p_checkout_key), 'sha256'), 'hex');
  RETURN public.create_guest_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    v_access_token, p_voucher_id, p_distance_km,
    p_guest_checkout_key, p_checkout_key, p_payment_channel
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,text,uuid,numeric,text,text,text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,text,uuid,numeric,text,text,text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon, authenticated;

-- Payment callbacks must be bound to the provider's per-attempt external ID,
-- immutable merchant/order intent, exact amount and currency, and a live pending row.
DROP FUNCTION IF EXISTS public.settle_gdc_qris_mpm_payment(uuid,uuid,text,numeric,timestamptz);
CREATE OR REPLACE FUNCTION public.settle_gdc_qris_mpm_payment(
  p_order_id uuid,
  p_partner_reference_no uuid,
  p_reference_no text,
  p_external_id uuid,
  p_currency text,
  p_paid_amount numeric,
  p_paid_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_reservation public.marketplace_stock_reservations%ROWTYPE;
  v_paid_at timestamptz := COALESCE(p_paid_at, now());
  v_updated integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC payment settlement requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no IS DISTINCT FROM p_partner_reference_no
     OR (v_payment.reference_no IS NOT NULL AND v_payment.reference_no IS DISTINCT FROM p_reference_no)
     OR v_payment.provider_external_id IS DISTINCT FROM p_external_id
     OR p_currency <> 'IDR'
     OR v_payment.currency IS DISTINCT FROM p_currency
     OR v_payment.amount IS DISTINCT FROM p_paid_amount
     OR p_reference_no IS NULL OR length(trim(p_reference_no)) = 0 THEN
    RAISE EXCEPTION 'GDC payment identity or amount mismatch' USING ERRCODE = '23P01';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.payment_channel <> 'QRIS_MPM_GDC' OR v_order.payment_intent <> 'GDC_MPM' THEN
    RAISE EXCEPTION 'Order is not bound to GDC QR MPM' USING ERRCODE = '22023';
  END IF;
  IF v_order.total IS DISTINCT FROM p_paid_amount THEN
    RAISE EXCEPTION 'GDC payment does not match order total' USING ERRCODE = '23P01';
  END IF;
  IF v_payment.status = 'PAID' AND v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'PAID');
  END IF;
  IF v_payment.status = 'PAID' OR v_order.payment_status = 'PAID' THEN
    RAISE EXCEPTION 'GDC order and payment ledger state do not match' USING ERRCODE = '23P01';
  END IF;
  IF v_order.confirmation_deadline IS NULL
     OR v_paid_at > v_order.confirmation_deadline
     OR v_paid_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'GDC payment arrived outside the order payment window' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_reservation
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id AND status = 'active' AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Marketplace stock reservation is no longer active' USING ERRCODE = '22023';
  END IF;
  IF v_payment.status NOT IN ('PENDING', 'CREATING', 'UNKNOWN')
     OR v_order.payment_status NOT IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
     OR v_order.status NOT IN ('PENDING_PAYMENT', 'NEW') THEN
    RAISE EXCEPTION 'GDC payment is no longer eligible for settlement' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders
  SET payment_status = 'PAID', payment_paid_at = v_paid_at,
      status = CASE WHEN status = 'NEW' THEN status ELSE 'CONFIRMED' END,
      updated_at = now()
  WHERE id = p_order_id;
  UPDATE public.gdc_qris_mpm_payments
  SET reference_no = COALESCE(reference_no, p_reference_no), status = 'PAID', paid_at = v_paid_at,
      provider_response_code = '00', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('PENDING', 'CREATING', 'UNKNOWN');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN RAISE EXCEPTION 'GDC payment status changed during settlement' USING ERRCODE = '40001'; END IF;
  RETURN jsonb_build_object('success', true, 'status', 'PAID', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,uuid,text,numeric,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,uuid,text,numeric,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.record_gdc_qris_mpm_failure(
  p_order_id uuid,
  p_partner_reference_no uuid,
  p_reference_no text,
  p_external_id uuid,
  p_currency text,
  p_paid_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC failure recording requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no IS DISTINCT FROM p_partner_reference_no
     OR (v_payment.reference_no IS NOT NULL AND v_payment.reference_no IS DISTINCT FROM p_reference_no)
     OR v_payment.provider_external_id IS DISTINCT FROM p_external_id
     OR p_currency <> 'IDR'
     OR v_payment.currency IS DISTINCT FROM p_currency
     OR v_payment.amount IS DISTINCT FROM p_paid_amount THEN
    RAISE EXCEPTION 'GDC failure identity or amount mismatch' USING ERRCODE = '23P01';
  END IF;
  IF v_payment.status IN ('FAILED', 'EXPIRED') THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', v_payment.status);
  END IF;
  IF v_payment.status NOT IN ('PENDING', 'CREATING', 'UNKNOWN') THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', v_payment.status);
  END IF;
  UPDATE public.gdc_qris_mpm_payments
  SET reference_no = COALESCE(reference_no, p_reference_no), status = 'FAILED',
      provider_response_code = '06', last_error = 'Provider reported a failed QR transaction', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('PENDING', 'CREATING', 'UNKNOWN');
  RETURN jsonb_build_object('success', true, 'status', 'FAILED', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.record_gdc_qris_mpm_failure(uuid,uuid,text,uuid,text,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_gdc_qris_mpm_failure(uuid,uuid,text,uuid,text,numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.request_gdc_qris_mpm_manual_fallback(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_destination jsonb;
  v_has_admin_destination boolean;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC manual fallback requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GDC payment record not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.payment_channel <> 'QRIS_MPM_GDC' OR v_order.payment_intent <> 'GDC_MPM' THEN
    RAISE EXCEPTION 'Order is not bound to GDC QR MPM' USING ERRCODE = '22023';
  END IF;
  IF v_payment.status NOT IN ('FAILED', 'EXPIRED', 'MANUAL_FALLBACK_PENDING') THEN
    RAISE EXCEPTION 'Manual fallback is allowed only after a final provider failure' USING ERRCODE = '22023';
  END IF;
  IF v_order.payment_status NOT IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
     OR v_order.status NOT IN ('PENDING_PAYMENT', 'NEW') THEN
    RAISE EXCEPTION 'Order is no longer eligible for manual fallback' USING ERRCODE = '22023';
  END IF;
  IF v_order.confirmation_deadline IS NULL OR v_order.confirmation_deadline <= now() THEN
    RAISE EXCEPTION 'Order payment deadline has passed' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id AND status = 'active' AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Marketplace stock reservation is no longer active' USING ERRCODE = '22023'; END IF;
  v_destination := COALESCE(v_order.payment_destination_snapshot, '{}'::jsonb);
  v_has_admin_destination := v_destination->>'fallback_source' = 'ADMIN'
    AND ((NULLIF(btrim(COALESCE(v_destination->>'bank_name', '')), '') IS NOT NULL
          AND NULLIF(btrim(COALESCE(v_destination->>'bank_account_number', '')), '') IS NOT NULL)
      OR NULLIF(btrim(COALESCE(v_destination->>'qris_image_url', '')), '') IS NOT NULL);
  IF NOT v_has_admin_destination THEN
    RAISE EXCEPTION 'Admin payment instructions were not snapshotted for this order' USING ERRCODE = '22023';
  END IF;
  IF v_payment.status = 'MANUAL_FALLBACK_PENDING' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'MANUAL_FALLBACK_PENDING');
  END IF;
  UPDATE public.gdc_qris_mpm_payments
  SET status = 'MANUAL_FALLBACK_PENDING', qr_content = NULL,
      last_error = 'Manual Admin fallback locked after provider final failure', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('FAILED', 'EXPIRED');
  RETURN jsonb_build_object('success', true, 'status', 'MANUAL_FALLBACK_PENDING', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.request_gdc_qris_mpm_manual_fallback(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_gdc_qris_mpm_manual_fallback(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
