-- Guest checkout phase 1: schema and token-scoped RPC foundation.
-- Forward-only, safe to apply after the existing checkout/reservation bundles.

ALTER TABLE public.orders
  ALTER COLUMN buyer_id DROP NOT NULL;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS guest_access_token_hash text,
  ADD COLUMN IF NOT EXISTS guest_token_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS guest_claimed_at timestamptz,
  ADD COLUMN IF NOT EXISTS guest_contact_hash text;
ALTER TABLE public.marketplace_stock_reservations
  ALTER COLUMN buyer_id DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_guest_access_token_hash ON public.orders(guest_access_token_hash) WHERE guest_access_token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_guest_token_expiry ON public.orders(guest_token_expires_at) WHERE guest_access_token_hash IS NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_identity_required') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_identity_required CHECK (buyer_id IS NOT NULL OR guest_access_token_hash IS NOT NULL) NOT VALID;
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.marketplace_guest_checkout_idempotency (
  guest_session_key_hash text NOT NULL, checkout_key text NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (guest_session_key_hash, checkout_key)
);
ALTER TABLE public.marketplace_guest_checkout_idempotency ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_guest_checkout_idempotency FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock_guest(
  p_order_id uuid,
  p_items jsonb,
  p_guest_access_token text,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reservation_id uuid;
  v_input jsonb;
  v_product public.products%ROWTYPE;
  v_variant public.product_variants%ROWTYPE;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty numeric;
  v_total numeric := 0;
  v_existing public.marketplace_stock_reservations%ROWTYPE;
  v_tenant_id uuid;
  v_pos_product_id uuid;
  v_pos_variant_id uuid;
  v_item_id uuid;
  v_remaining numeric;
  v_available numeric;
  v_allocated numeric;
  v_stock record;
BEGIN
  IF p_guest_access_token IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex')
    AND guest_token_expires_at > now() FOR UPDATE;
  IF NOT FOUND OR lower(COALESCE(v_order.status, '')) IN ('cancelled', 'canceled', 'rejected', 'refunded') THEN
    RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true);
  END IF;

  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at)
  VALUES (p_order_id, NULL, GREATEST(p_expires_at, now() + interval '1 minute'))
  RETURNING id INTO v_reservation_id;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = '23503'; END IF;
    IF v_variant_id IS NOT NULL THEN
      SELECT * INTO v_variant FROM public.product_variants
      WHERE id = v_variant_id AND product_id = v_product_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Variant does not belong to product' USING ERRCODE = '23514'; END IF;
    END IF;

    INSERT INTO public.marketplace_stock_reservation_items(reservation_id, product_id, variant_id, quantity)
    VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty)
    RETURNING id INTO v_item_id;

    SELECT pt.id, pp.id, ppv.id
    INTO v_tenant_id, v_pos_product_id, v_pos_variant_id
    FROM public.pos_tenants pt
    JOIN public.pos_products pp ON pp.tenant_id = pt.id
      AND pp.merchant_product_id = v_product_id AND pp.is_active = true
    LEFT JOIN public.pos_product_variants ppv ON ppv.product_id = pp.id
      AND ppv.tenant_id = pp.tenant_id AND ppv.merchant_variant_id = v_variant_id
      AND ppv.is_active = true
    WHERE pt.merchant_id = v_order.merchant_id AND pt.is_active = true
      AND (v_variant_id IS NULL OR ppv.id IS NOT NULL)
    ORDER BY pt.created_at, pp.created_at
    LIMIT 1;

    IF v_pos_product_id IS NOT NULL AND (v_variant_id IS NULL OR v_pos_variant_id IS NOT NULL) THEN
      v_remaining := v_qty;
      FOR v_stock IN
        SELECT ps.id, ps.outlet_id, ps.quantity, COALESCE(ps.reserved_quantity, 0) AS reserved_quantity
        FROM public.pos_stock ps
        JOIN public.pos_outlets po ON po.id = ps.outlet_id
          AND po.tenant_id = ps.tenant_id AND po.is_active = true
        WHERE ps.tenant_id = v_tenant_id
          AND ps.product_id = v_pos_product_id
          AND ps.variant_id IS NOT DISTINCT FROM v_pos_variant_id
        ORDER BY ps.outlet_id, ps.id
        FOR UPDATE
      LOOP
        EXIT WHEN v_remaining <= 0;
        v_available := GREATEST(v_stock.quantity - v_stock.reserved_quantity, 0);
        v_allocated := LEAST(v_available, v_remaining);
        IF v_allocated > 0 THEN
          UPDATE public.pos_stock
          SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_allocated, updated_at = now()
          WHERE id = v_stock.id;
          INSERT INTO public.marketplace_stock_allocations(
            reservation_id, reservation_item_id, tenant_id, pos_product_id, pos_variant_id,
            product_id, outlet_id, quantity
          )
          VALUES (
            v_reservation_id, v_item_id, v_tenant_id, v_pos_product_id, v_pos_variant_id,
            v_product_id, v_stock.outlet_id, v_allocated
          );
          v_remaining := v_remaining - v_allocated;
        END IF;
      END LOOP;
      IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Insufficient POS outlet stock' USING ERRCODE = '23514';
      END IF;
    ELSIF v_variant_id IS NOT NULL THEN
      IF v_variant.stock - v_variant.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace variant stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.product_variants
      SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_variant_id;
    ELSE
      IF v_product.stock - v_product.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_product_id;
    END IF;
    v_total := v_total + v_qty;
  END LOOP;

  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'status', 'active', 'quantity', v_total, 'expires_at', p_expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
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
  IF p_payment_method NOT IN ('TRANSFER', 'ONLINE') THEN
    RAISE EXCEPTION 'Guest payment method is unavailable' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'ONLINE' AND NOT COALESCE((SELECT (value->>'enabled')::boolean FROM public.app_settings WHERE key = 'payment_xendit'), false) THEN
    RAISE EXCEPTION 'Pembayaran online sedang tidak tersedia' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'ONLINE' AND (
    SELECT count(DISTINCT p.merchant_id)
    FROM jsonb_array_elements(p_items) x
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

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
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
      v_shipping := 0;
      v_server_distance := 0;
    ELSIF v_delivery_lat IS NULL OR v_delivery_lng IS NULL
       OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    ELSE
      v_server_distance := 6371 * 2 * asin(sqrt(
        power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
        + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
        * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
      ));
      SELECT value INTO v_settings FROM public.app_settings WHERE key = 'shipping_base_fee';
      IF v_subtotal >= COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000) THEN
        v_shipping := 0;
      ELSE
        v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
          + round(v_server_distance * COALESCE((v_settings->>'per_km_fee')::integer, 2000));
        v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
          GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
      END IF;
    END IF;
    v_shipping_total := v_shipping_total + v_shipping;
    v_total := GREATEST(0, v_subtotal + v_shipping + v_cod_fee - v_discount);
    INSERT INTO public.orders (
      buyer_id, guest_access_token_hash, guest_token_expires_at, guest_contact_hash, merchant_id, status, handled_by, delivery_type,
      delivery_address, delivery_phone, delivery_name, shipping_cost,
      subtotal, total, notes, flash_sale_discount, payment_method,
      payment_status, confirmation_deadline, cod_service_fee, buyer_distance_km,
      delivery_lat, delivery_lng, delivery_province_id, delivery_province_name,
      delivery_city_id, delivery_city_name, delivery_district_id, delivery_district_name
    ) VALUES (
      NULL, encode(digest(v_guest_access_token, 'sha256'), 'hex'), v_guest_token_expires_at, v_guest_contact_hash, v_merchant_id, v_status, 'ADMIN', p_delivery_type,
      NULLIF(p_delivery->>'address', ''), NULLIF(p_delivery->>'phone', ''), NULLIF(p_delivery->>'name', ''),
      v_shipping, v_subtotal, v_total, NULLIF(p_delivery->>'notes', ''), v_discount,
      p_payment_method, v_payment_status, v_deadline, v_cod_fee, v_server_distance,
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
    'guest_access_token', v_guest_access_token,
    'guest_token_expires_at', v_guest_token_expires_at
  );
  v_result := v_result - 'guest_access_token';
  INSERT INTO public.marketplace_guest_checkout_idempotency(guest_session_key_hash, checkout_key, result)
  VALUES (v_session_hash, v_effective_checkout_key, v_result);
  RETURN v_result || jsonb_build_object('guest_access_token', v_guest_access_token);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock_guest(uuid, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) TO anon;

CREATE OR REPLACE FUNCTION public.get_guest_order_status(p_order_id uuid, p_guest_access_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_items jsonb;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex') AND guest_token_expires_at > now();
  IF NOT FOUND THEN RAISE EXCEPTION 'Order status unavailable' USING ERRCODE = '42501'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', product_name, 'quantity', quantity, 'price', product_price, 'subtotal', subtotal) ORDER BY product_name), '[]'::jsonb) INTO v_items FROM public.order_items WHERE order_id = p_order_id;
  RETURN jsonb_build_object('order_id', v_order.id, 'created_at', v_order.created_at, 'merchant_name', (SELECT m.name FROM public.merchants m WHERE m.id = v_order.merchant_id), 'items', v_items, 'subtotal', v_order.subtotal, 'shipping_cost', v_order.shipping_cost, 'total', v_order.total, 'status', v_order.status, 'payment_method', v_order.payment_method, 'payment_status', v_order.payment_status, 'guest_token_expires_at', v_order.guest_token_expires_at);
END; $$;
REVOKE ALL ON FUNCTION public.get_guest_order_status(uuid, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.get_guest_order_status(uuid, text) TO anon;

CREATE OR REPLACE FUNCTION public.guest_submit_payment_proof(p_order_id uuid, p_guest_access_token text, p_payment_proof_url text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex') AND guest_token_expires_at > now() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501'; END IF;
  IF v_order.payment_method <> 'TRANSFER' OR v_order.payment_status IN ('PAID','REFUNDED','EXPIRED') OR v_order.status IN ('CANCELLED','CANCELED','REJECTED','REFUNDED') OR length(trim(COALESCE(p_payment_proof_url, ''))) < 1 OR length(p_payment_proof_url) > 2000 THEN RAISE EXCEPTION 'Order is not accepting transfer proof' USING ERRCODE = '22023'; END IF;
  UPDATE public.orders SET payment_proof_url = trim(p_payment_proof_url), updated_at = now() WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', trim(p_payment_proof_url));
END; $$;
REVOKE ALL ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) TO anon;

DO $bootstrap_do_guest_checkout_phase1$
BEGIN
  EXECUTE $bootstrap_sql_guest_checkout_phase1$COMMENT ON TABLE public.marketplace_guest_checkout_idempotency IS 'Guest checkout retries are scoped by hashed guest session and checkout key; raw access tokens are never persisted.'$bootstrap_sql_guest_checkout_phase1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_guest_checkout_phase1$;
