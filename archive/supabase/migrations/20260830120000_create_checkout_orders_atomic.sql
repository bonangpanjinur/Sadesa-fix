-- Checkout transaction boundary: prices, totals, stock and merchant quota are
-- calculated and committed together by the database.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_request_id text;

CREATE UNIQUE INDEX IF NOT EXISTS orders_buyer_checkout_request_uidx
  ON public.orders (buyer_id, checkout_request_id)
  WHERE checkout_request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.create_checkout_orders(
  p_items jsonb,
  p_delivery_type text,
  p_delivery_name text,
  p_delivery_phone text,
  p_delivery_address text DEFAULT NULL,
  p_delivery_lat numeric DEFAULT NULL,
  p_delivery_lng numeric DEFAULT NULL,
  p_payment_method text DEFAULT 'COD',
  p_distance_km numeric DEFAULT 0,
  p_notes text DEFAULT NULL,
  p_checkout_request_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_line record;
  v_merchant record;
  v_product public.products%ROWTYPE;
  v_order_id uuid;
  v_order_ids jsonb := '[]'::jsonb;
  v_existing jsonb;
  v_subtotal integer;
  v_shipping integer;
  v_cod_fee integer;
  v_total integer;
  v_credits integer;
  v_distance numeric;
  v_shipping_settings jsonb;
  v_cod_settings jsonb;
  v_base_fee integer;
  v_per_km_fee integer;
  v_min_fee integer;
  v_max_fee integer;
  v_free_shipping_min integer;
  v_cod_fee_setting integer;
  v_expiry timestamptz;
  v_has_subscription boolean;
  v_quota_ok boolean;
  v_free_quota integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Cart is empty' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type NOT IN ('PICKUP', 'INTERNAL') THEN
    RAISE EXCEPTION 'Invalid delivery type' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method NOT IN ('COD', 'TRANSFER', 'ONLINE') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE = '22023';
  END IF;
  IF nullif(trim(p_delivery_name), '') IS NULL OR nullif(trim(p_delivery_phone), '') IS NULL THEN
    RAISE EXCEPTION 'Delivery name and phone are required' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type = 'INTERNAL' AND nullif(trim(p_delivery_address), '') IS NULL THEN
    RAISE EXCEPTION 'Delivery address is required' USING ERRCODE = '22023';
  END IF;
  IF p_distance_km IS NULL OR p_distance_km < 0 OR p_distance_km > 500 THEN
    RAISE EXCEPTION 'Invalid delivery distance' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_lat IS NOT NULL AND abs(p_delivery_lat) > 90 THEN
    RAISE EXCEPTION 'Invalid delivery latitude' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_lng IS NOT NULL AND abs(p_delivery_lng) > 180 THEN
    RAISE EXCEPTION 'Invalid delivery longitude' USING ERRCODE = '22023';
  END IF;
  IF p_checkout_request_id IS NOT NULL
     AND (length(trim(p_checkout_request_id)) < 8 OR length(p_checkout_request_id) > 120) THEN
    RAISE EXCEPTION 'Invalid checkout request id' USING ERRCODE = '22023';
  END IF;

  -- An idempotent retry returns the orders created by the first request.
  IF p_checkout_request_id IS NOT NULL THEN
    SELECT jsonb_agg(jsonb_build_object(
      'order_id', o.id,
      'merchant_id', o.merchant_id,
      'subtotal', o.subtotal,
      'shipping_cost', o.shipping_cost,
      'total', o.total,
      'status', o.status,
      'payment_status', o.payment_status
    ) ORDER BY o.created_at)
    INTO v_existing
    FROM public.orders o
    WHERE o.buyer_id = v_user_id
      AND o.checkout_request_id = p_checkout_request_id;
    IF v_existing IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'orders', v_existing);
    END IF;
  END IF;

  -- Normalize and validate the client cart. Only product_id and quantity are
  -- accepted; client-supplied price, subtotal, merchant and stock are ignored.
  CREATE TEMP TABLE checkout_lines (
    product_id uuid PRIMARY KEY,
    quantity integer NOT NULL CHECK (quantity > 0)
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF NULLIF(v_item->>'product_id', '') IS NULL
       OR (v_item->>'quantity') !~ '^[0-9]+$'
       OR (v_item->>'quantity')::integer <= 0
       OR (v_item->>'quantity')::integer > 999 THEN
      RAISE EXCEPTION 'Invalid checkout item' USING ERRCODE = '22023';
    END IF;
    INSERT INTO checkout_lines(product_id, quantity)
    VALUES ((v_item->>'product_id')::uuid, (v_item->>'quantity')::integer)
    ON CONFLICT (product_id) DO UPDATE
      SET quantity = checkout_lines.quantity + EXCLUDED.quantity;
  END LOOP;

  IF EXISTS (SELECT 1 FROM checkout_lines WHERE quantity > 999) THEN
    RAISE EXCEPTION 'Item quantity is too large' USING ERRCODE = '22023';
  END IF;

  -- Lock products in deterministic product_id order. This prevents two
  -- concurrent checkouts from overselling the same stock.
  FOR v_line IN
    SELECT cl.product_id, cl.quantity
    FROM checkout_lines cl
    ORDER BY cl.product_id
  LOOP
    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_line.product_id
    FOR UPDATE;
    IF NOT FOUND OR v_product.is_active IS NOT TRUE THEN
      RAISE EXCEPTION 'Product is unavailable: %', v_line.product_id USING ERRCODE = 'P0002';
    END IF;
    IF v_product.stock - COALESCE(v_product.reserved_stock, 0) < v_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_product.name USING ERRCODE = '23514';
    END IF;
  END LOOP;

  SELECT COALESCE(value, '{}'::jsonb) INTO v_shipping_settings
  FROM public.app_settings WHERE key = 'shipping_base_fee' LIMIT 1;
  v_base_fee := COALESCE((v_shipping_settings->>'base_fee')::integer, 5000);
  v_per_km_fee := COALESCE((v_shipping_settings->>'per_km_fee')::integer, 2000);
  v_min_fee := COALESCE((v_shipping_settings->>'min_fee')::integer, 5000);
  v_max_fee := COALESCE((v_shipping_settings->>'max_fee')::integer, 50000);
  v_free_shipping_min := COALESCE((v_shipping_settings->>'free_shipping_min_order')::integer, 100000);
  v_distance := round(COALESCE(p_distance_km, 0)::numeric, 2);

  SELECT COALESCE(value, '{}'::jsonb) INTO v_cod_settings
  FROM public.app_settings WHERE key = 'cod_settings' LIMIT 1;
  v_cod_fee_setting := COALESCE((v_cod_settings->>'service_fee')::integer, 0);

  -- One order is created per merchant, matching the current marketplace model.
  FOR v_merchant IN
    SELECT p.merchant_id,
           sum(p.price * cl.quantity)::integer AS subtotal,
           sum(get_quota_cost(p.price) * cl.quantity)::integer AS credits
    FROM checkout_lines cl
    JOIN public.products p ON p.id = cl.product_id
    GROUP BY p.merchant_id
    ORDER BY p.merchant_id
  LOOP
    v_subtotal := v_merchant.subtotal;
    v_shipping := CASE
      WHEN p_delivery_type = 'PICKUP' OR v_subtotal >= v_free_shipping_min THEN 0
      ELSE LEAST(v_max_fee, GREATEST(v_min_fee, v_base_fee + round(v_per_km_fee * v_distance)::integer))
    END;
    v_cod_fee := CASE WHEN p_payment_method = 'COD' THEN v_cod_fee_setting ELSE 0 END;
    v_total := v_subtotal + v_shipping + v_cod_fee;
    v_credits := v_merchant.credits;
    v_expiry := CASE WHEN p_payment_method = 'COD' THEN now() + interval '30 minutes'
                     ELSE now() + interval '60 minutes' END;

    -- Serialize checkout per merchant. Premium quota is reserved by the
    -- existing atomic function; free quota is counted while this merchant row
    -- is locked, so two parallel checkouts cannot both pass the limit.
    PERFORM 1 FROM public.merchants WHERE id = v_merchant.merchant_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Merchant is unavailable' USING ERRCODE = 'P0002';
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM public.merchant_subscriptions
      WHERE merchant_id = v_merchant.merchant_id AND status = 'ACTIVE' AND expired_at > now()
    ) INTO v_has_subscription;
    IF v_has_subscription THEN
      SELECT EXISTS (
        SELECT 1 FROM public.merchant_subscriptions
        WHERE merchant_id = v_merchant.merchant_id AND status = 'ACTIVE'
          AND expired_at > now() AND transaction_quota - used_quota >= v_credits
      ) INTO v_quota_ok;
      IF v_quota_ok THEN
        v_quota_ok := public.deduct_merchant_quota(v_merchant.merchant_id, v_credits);
      END IF;
    ELSE
      SELECT COALESCE((value->>'limit')::integer, 100) INTO v_free_quota
      FROM public.app_settings WHERE key = 'free_tier_quota' LIMIT 1;
      v_free_quota := COALESCE(v_free_quota, 100);
      SELECT count(*) + 1 <= v_free_quota INTO v_quota_ok
      FROM public.orders
      WHERE merchant_id = v_merchant.merchant_id
        AND created_at >= date_trunc('month', now());
    END IF;
    IF NOT COALESCE(v_quota_ok, false) THEN
      RAISE EXCEPTION 'Merchant quota is insufficient' USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.orders(
      buyer_id, merchant_id, status, handled_by, delivery_type,
      delivery_name, delivery_phone, delivery_address, delivery_lat, delivery_lng,
      shipping_cost, subtotal, total, notes, payment_method, payment_status,
      confirmation_deadline, cod_service_fee, buyer_distance_km, checkout_request_id
    ) VALUES (
      v_user_id, v_merchant.merchant_id,
      CASE WHEN p_payment_method = 'COD' THEN 'PENDING_CONFIRMATION'
           WHEN p_payment_method IN ('TRANSFER', 'ONLINE') THEN 'PENDING_PAYMENT'
           ELSE 'NEW' END,
      'ADMIN', p_delivery_type, trim(p_delivery_name), trim(p_delivery_phone),
      p_delivery_address, p_delivery_lat, p_delivery_lng, v_shipping, v_subtotal,
      v_total, p_notes,
      p_payment_method,
      CASE WHEN p_payment_method = 'COD' THEN 'COD'
           WHEN p_payment_method = 'TRANSFER' THEN 'PENDING_TRANSFER'
           ELSE 'UNPAID' END,
      CASE WHEN p_payment_method = 'COD' THEN v_expiry ELSE NULL END,
      v_cod_fee, v_distance, p_checkout_request_id
    ) RETURNING id INTO v_order_id;

    INSERT INTO public.order_items(order_id, product_id, product_name, product_price, quantity, subtotal)
    SELECT v_order_id, p.id, p.name, p.price, cl.quantity, p.price * cl.quantity
    FROM checkout_lines cl
    JOIN public.products p ON p.id = cl.product_id
    WHERE p.merchant_id = v_merchant.merchant_id
    ORDER BY p.id;

    PERFORM public.reserve_marketplace_stock(
      v_order_id,
      (SELECT jsonb_agg(jsonb_build_object(
        'product_id', cl.product_id,
        'variant_id', NULL,
        'quantity', cl.quantity
      ) ORDER BY cl.product_id) FROM checkout_lines cl
       JOIN public.products p ON p.id = cl.product_id
       WHERE p.merchant_id = v_merchant.merchant_id),
      v_expiry
    );

    v_order_ids := v_order_ids || jsonb_build_array(jsonb_build_object(
      'order_id', v_order_id,
      'merchant_id', v_merchant.merchant_id,
      'subtotal', v_subtotal,
      'shipping_cost', v_shipping,
      'total', v_total,
      'status', CASE WHEN p_payment_method = 'COD' THEN 'PENDING_CONFIRMATION' ELSE 'PENDING_PAYMENT' END,
      'payment_status', CASE WHEN p_payment_method = 'COD' THEN 'COD' WHEN p_payment_method = 'TRANSFER' THEN 'PENDING_TRANSFER' ELSE 'UNPAID' END
    ));
  END LOOP;

  RETURN jsonb_build_object('success', true, 'idempotent', false, 'orders', v_order_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.create_checkout_orders(
  jsonb, text, text, text, text, numeric, numeric, text, numeric, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_checkout_orders(
  jsonb, text, text, text, text, numeric, numeric, text, numeric, text, text
) TO authenticated;
