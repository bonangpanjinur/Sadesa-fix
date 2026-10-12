-- P1 checkout hardening: normalize product/variant reservations and separate
-- local courier, merchant self-delivery platform fee, and expedition pricing.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS shipping_weight_kg numeric NOT NULL DEFAULT 1;
COMMENT ON COLUMN public.products.shipping_weight_kg IS
  'Berat satu unit produk dalam kg; dipakai untuk menghitung ongkir rate-card ekspedisi.';
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'products_shipping_weight_kg_valid'
      AND conrelid = 'public.products'::regclass
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_shipping_weight_kg_valid
      CHECK (shipping_weight_kg > 0 AND shipping_weight_kg <= 1000);
  END IF;
END;
$$;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS shipping_pricing_contract jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS merchant_delivery_fee_contract text,
  ADD COLUMN IF NOT EXISTS expedition_service_code_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_service_name_snapshot text;

CREATE TABLE IF NOT EXISTS public.marketplace_expedition_rate_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES public.expedition_providers(id) ON DELETE CASCADE,
  service_code text NOT NULL CHECK (length(btrim(service_code)) BETWEEN 1 AND 40),
  service_name text NOT NULL CHECK (length(btrim(service_name)) BETWEEN 1 AND 120),
  destination_city_id text NOT NULL DEFAULT '*',
  base_fee integer NOT NULL DEFAULT 0 CHECK (base_fee >= 0),
  per_kg_fee integer NOT NULL DEFAULT 0 CHECK (per_kg_fee >= 0),
  min_fee integer NOT NULL DEFAULT 0 CHECK (min_fee >= 0),
  max_fee integer NOT NULL CHECK (max_fee >= min_fee),
  free_shipping_min_order integer,
  eta_min_days integer NOT NULL DEFAULT 1 CHECK (eta_min_days >= 0),
  eta_max_days integer NOT NULL DEFAULT 5 CHECK (eta_max_days >= eta_min_days),
  priority integer NOT NULL DEFAULT 100,
  is_default boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider_id, service_code, destination_city_id)
);
COMMENT ON TABLE public.marketplace_expedition_rate_cards IS
  'Tarif ekspedisi terpisah per provider, layanan, dan tujuan; sengaja tidak di-seed dengan harga tebakan.';
CREATE INDEX IF NOT EXISTS idx_marketplace_expedition_rates_lookup
  ON public.marketplace_expedition_rate_cards (destination_city_id, is_active, is_default, priority);
ALTER TABLE public.marketplace_expedition_rate_cards ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'marketplace_expedition_rate_cards' AND policyname = 'Active expedition rate cards are readable') THEN
    CREATE POLICY "Active expedition rate cards are readable"
      ON public.marketplace_expedition_rate_cards
      FOR SELECT TO anon, authenticated
      USING (is_active AND EXISTS (
        SELECT 1 FROM public.expedition_providers ep
        WHERE ep.id = provider_id AND ep.is_active = true
      ));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'marketplace_expedition_rate_cards' AND policyname = 'Admins manage expedition rate cards') THEN
    CREATE POLICY "Admins manage expedition rate cards"
      ON public.marketplace_expedition_rate_cards
      FOR ALL TO authenticated
      USING (public.is_admin())
      WITH CHECK (public.is_admin());
  END IF;
END;
$$;
GRANT SELECT ON public.marketplace_expedition_rate_cards TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.marketplace_expedition_rate_cards TO authenticated;
GRANT ALL ON public.marketplace_expedition_rate_cards TO service_role;

CREATE OR REPLACE FUNCTION public.normalize_marketplace_checkout_items(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_count integer;
  v_normalized jsonb;
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Cart is empty' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
    WHERE i.product_id IS NULL
       OR i.quantity IS NULL
       OR i.quantity <= 0
       OR i.quantity <> trunc(i.quantity)
  ) THEN
    RAISE EXCEPTION 'Invalid checkout item' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) INTO v_count
  FROM (
    SELECT i.product_id, i.variant_id, sum(i.quantity) AS quantity
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
    GROUP BY i.product_id, i.variant_id
    HAVING sum(i.quantity) > 1000
  ) invalid_groups;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Combined product quantity exceeds the checkout limit' USING ERRCODE = '22023';
  END IF;
  SELECT jsonb_agg(
    jsonb_build_object(
      'product_id', grouped.product_id,
      'variant_id', grouped.variant_id,
      'quantity', grouped.quantity::integer
    ) ORDER BY grouped.product_id, grouped.variant_id NULLS FIRST
  ) INTO v_normalized
  FROM (
    SELECT i.product_id, i.variant_id, sum(i.quantity) AS quantity
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
    GROUP BY i.product_id, i.variant_id
  ) grouped;
  RETURN v_normalized;
END;
$$;
REVOKE ALL ON FUNCTION public.normalize_marketplace_checkout_items(jsonb) FROM PUBLIC, anon, authenticated;

-- Rename the previous reservation implementations once; the public signatures
-- remain unchanged and all callers now pass normalized quantities to the legacy
-- stock validation and allocation logic.
DO $$
BEGIN
  IF to_regprocedure('public.reserve_marketplace_stock_unaggregated(uuid,jsonb,timestamptz)') IS NULL
     AND to_regprocedure('public.reserve_marketplace_stock(uuid,jsonb,timestamptz)') IS NOT NULL THEN
    ALTER FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz)
      RENAME TO reserve_marketplace_stock_unaggregated;
  END IF;
  IF to_regprocedure('public.reserve_marketplace_stock_guest_unaggregated(uuid,jsonb,text,timestamptz)') IS NULL
     AND to_regprocedure('public.reserve_marketplace_stock_guest(uuid,jsonb,text,timestamptz)') IS NOT NULL THEN
    ALTER FUNCTION public.reserve_marketplace_stock_guest(uuid, jsonb, text, timestamptz)
      RENAME TO reserve_marketplace_stock_guest_unaggregated;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.reserve_marketplace_stock_unaggregated(
    p_order_id,
    public.normalize_marketplace_checkout_items(p_items),
    p_expires_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock_unaggregated(uuid, jsonb, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;

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
BEGIN
  RETURN public.reserve_marketplace_stock_guest_unaggregated(
    p_order_id,
    public.normalize_marketplace_checkout_items(p_items),
    p_guest_access_token,
    p_expires_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock_guest_unaggregated(uuid, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock_guest(uuid, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.marketplace_expedition_shipping_quote(
  p_items jsonb,
  p_delivery jsonb,
  p_subtotal integer,
  p_merchant_id uuid,
  p_rate_card_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items jsonb;
  v_weight numeric;
  v_city_id text;
  v_rate record;
  v_weight_fee integer;
  v_shipping integer;
BEGIN
  v_items := public.normalize_marketplace_checkout_items(p_items);
  SELECT COALESCE(sum(p.shipping_weight_kg * i.quantity), 0)
    INTO v_weight
  FROM jsonb_to_recordset(v_items) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id
  WHERE p.merchant_id = p_merchant_id;
  IF v_weight <= 0 THEN
    RAISE EXCEPTION 'Cannot determine expedition package weight' USING ERRCODE = '22023';
  END IF;
  v_city_id := COALESCE(NULLIF(p_delivery->>'city_id', ''), '*');

  SELECT r.*, ep.name AS provider_name, ep.logo_url AS provider_logo_url,
         ep.tracking_website AS provider_tracking_website
    INTO v_rate
  FROM public.marketplace_expedition_rate_cards r
  JOIN public.expedition_providers ep ON ep.id = r.provider_id AND ep.is_active = true
  WHERE r.is_active = true
    AND r.destination_city_id IN ('*', v_city_id)
    AND (p_rate_card_id IS NULL OR r.id = p_rate_card_id)
  ORDER BY (r.destination_city_id = v_city_id) DESC,
           r.is_default DESC,
           r.priority ASC,
           r.base_fee ASC,
           r.id
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tarif ekspedisi untuk tujuan ini belum tersedia' USING ERRCODE = '22023';
  END IF;

  v_weight_fee := ceil(v_weight * v_rate.per_kg_fee)::integer;
  IF v_rate.free_shipping_min_order IS NOT NULL
     AND p_subtotal >= v_rate.free_shipping_min_order THEN
    v_shipping := 0;
  ELSE
    v_shipping := LEAST(v_rate.max_fee, GREATEST(v_rate.min_fee, v_rate.base_fee + v_weight_fee));
  END IF;
  RETURN jsonb_build_object(
    'contract', 'EXPEDITION_PROVIDER_WEIGHT_V1',
    'rate_card_id', v_rate.id,
    'provider_id', v_rate.provider_id,
    'provider_name', v_rate.provider_name,
    'provider_logo_url', v_rate.provider_logo_url,
    'tracking_website', v_rate.provider_tracking_website,
    'service_code', v_rate.service_code,
    'service_name', v_rate.service_name,
    'destination_city_id', v_city_id,
    'weight_kg', round(v_weight, 3),
    'base_fee', v_rate.base_fee,
    'per_kg_fee', v_rate.per_kg_fee,
    'weight_fee', v_weight_fee,
    'shipping_cost', v_shipping,
    'eta_min_days', v_rate.eta_min_days,
    'eta_max_days', v_rate.eta_max_days,
    'quoted_at', now()
  );
END;
$$;
REVOKE ALL ON FUNCTION public.marketplace_expedition_shipping_quote(jsonb, jsonb, integer, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.marketplace_shipping_contract_quote(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_subtotal integer,
  p_distance_km numeric,
  p_merchant_id uuid,
  p_rate_card_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings jsonb;
  v_shipping integer := 0;
BEGIN
  IF p_delivery_type = 'PICKUP' THEN
    RETURN jsonb_build_object('contract', 'PICKUP_FREE_V1', 'shipping_cost', 0);
  ELSIF p_delivery_type = 'EXPEDITION' THEN
    RETURN public.marketplace_expedition_shipping_quote(
      p_items, p_delivery, p_subtotal, p_merchant_id, p_rate_card_id
    );
  ELSIF p_delivery_type <> 'INTERNAL' THEN
    RAISE EXCEPTION 'Unsupported delivery pricing contract' USING ERRCODE = '22023';
  END IF;

  SELECT value INTO v_settings FROM public.app_settings WHERE key = 'shipping_base_fee';
  IF p_subtotal < COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000) THEN
    v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
      + round(GREATEST(p_distance_km, 0) * COALESCE((v_settings->>'per_km_fee')::integer, 2000));
    v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
      GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
  END IF;
  RETURN jsonb_build_object(
    'contract', 'LOCAL_COURIER_DISTANCE_V1',
    'distance_km', round(GREATEST(p_distance_km, 0)::numeric, 2),
    'shipping_cost', v_shipping
  );
END;
$$;
REVOKE ALL ON FUNCTION public.marketplace_shipping_contract_quote(jsonb, jsonb, text, integer, numeric, uuid, uuid) FROM PUBLIC, anon, authenticated;

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
  v_merchant_count integer := 0;
  v_subtotal integer := 0;
  v_discount integer := 0;
  v_total integer := 0;
  v_shipping_contract jsonb;
  v_quantity integer;
  v_unit_price integer;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_distance numeric := 0;
  v_voucher public.vouchers%ROWTYPE;
  v_now timestamptz := now();
  v_rate_card_id uuid;
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
  FOR v_item IN SELECT value FROM jsonb_array_elements(public.normalize_marketplace_checkout_items(p_items)) LOOP
    v_quantity := (v_item->>'quantity')::integer;
    SELECT * INTO v_product FROM public.products
    WHERE id = (v_item->>'product_id')::uuid AND is_active IS TRUE;
    IF NOT FOUND OR v_product.merchant_id IS NULL THEN
      RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_merchant_id IS NULL THEN
      v_merchant_id := v_product.merchant_id;
      v_merchant_count := 1;
    ELSIF v_merchant_id <> v_product.merchant_id THEN
      v_merchant_count := 2;
    END IF;
    SELECT COALESCE(fs.flash_price, v_product.price) INTO v_unit_price
    FROM (SELECT 1) base
    LEFT JOIN LATERAL (
      SELECT flash_price FROM public.flash_sales
      WHERE product_id = v_product.id AND merchant_id = v_product.merchant_id
        AND status = 'ACTIVE' AND start_time <= v_now AND end_time > v_now
        AND stock_available > stock_sold
      ORDER BY end_time ASC LIMIT 1
    ) fs ON true;
    v_subtotal := v_subtotal + v_quantity * v_unit_price;
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
      IF v_voucher.max_discount IS NOT NULL THEN v_discount := LEAST(v_discount, v_voucher.max_discount); END IF;
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
       OR v_delivery_lat < -90 OR v_delivery_lat > 90 OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180 OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    END IF;
    v_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
      power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
      + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
      * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
    ))));
  END IF;
  v_rate_card_id := NULLIF(p_delivery->>'expedition_rate_card_id', '')::uuid;
  v_shipping_contract := public.marketplace_shipping_contract_quote(
    p_items, p_delivery, p_delivery_type, v_subtotal, v_distance, v_merchant_id, v_rate_card_id
  );
  v_total := GREATEST(0, v_subtotal + (v_shipping_contract->>'shipping_cost')::integer - v_discount);
  RETURN jsonb_build_object(
    'subtotal', v_subtotal,
    'shipping_cost', (v_shipping_contract->>'shipping_cost')::integer,
    'voucher_discount', v_discount,
    'total', v_total,
    'distance_km', round(v_distance::numeric, 2),
    'shipping_contract', v_shipping_contract,
    'quoted_at', v_now
  );
END;
$$;
REVOKE ALL ON FUNCTION public.quote_marketplace_checkout(jsonb, jsonb, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_marketplace_checkout(jsonb, jsonb, text, uuid) TO anon, authenticated;

-- Keep the checkout RPC/idempotency signature stable while recalculating the
-- final shipping charge from the same contract shown by quote_marketplace_checkout.
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
  v_items jsonb;
  v_merchant_count integer;
  v_merchant_id uuid;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_server_distance numeric := 0;
  v_order public.orders%ROWTYPE;
  v_contract jsonb;
  v_shipping integer;
  v_total integer;
  v_shipping_sum integer := 0;
  v_total_sum integer := 0;
  v_contracts jsonb := '[]'::jsonb;
  v_rate_card_id uuid;
  v_order_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  v_items := public.normalize_marketplace_checkout_items(p_items);
  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(v_items) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count = 0 THEN RAISE EXCEPTION 'Cart is empty or contains invalid products' USING ERRCODE = '22023'; END IF;
  IF p_payment_method IN ('ONLINE', 'TRANSFER') AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Pembayaran online dan transfer hanya tersedia untuk checkout satu toko' USING ERRCODE = '22023';
  END IF;
  SELECT p.merchant_id INTO v_merchant_id
  FROM jsonb_to_recordset(v_items) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id LIMIT 1;
  IF p_delivery_type = 'PICKUP' THEN
    v_server_distance := NULL;
  ELSE
    v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
    v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng FROM public.merchants WHERE id = v_merchant_id;
    IF v_delivery_lat IS NULL OR v_delivery_lng IS NULL OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL
       OR v_delivery_lat < -90 OR v_delivery_lat > 90 OR v_merchant_lat < -90 OR v_merchant_lat > 90
       OR v_delivery_lng < -180 OR v_delivery_lng > 180 OR v_merchant_lng < -180 OR v_merchant_lng > 180 THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    END IF;
    v_server_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
      power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
      + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
      * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
    ))));
  END IF;
  v_result := public.create_marketplace_checkout_legacy(
    v_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, v_server_distance
  );
  v_rate_card_id := NULLIF(p_delivery->>'expedition_rate_card_id', '')::uuid;
  FOR v_order_id IN
    SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_result->'order_ids', '[]'::jsonb)) AS ids(value)
  LOOP
    SELECT * INTO v_order FROM public.orders WHERE id = v_order_id FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;
    v_contract := public.marketplace_shipping_contract_quote(
      v_items, p_delivery, p_delivery_type, v_order.subtotal, v_server_distance,
      v_order.merchant_id, v_rate_card_id
    );
    v_shipping := (v_contract->>'shipping_cost')::integer;
    v_total := GREATEST(0, v_order.subtotal + v_shipping + COALESCE(v_order.cod_service_fee, 0)
      - COALESCE(v_order.flash_sale_discount, 0));
    UPDATE public.orders SET
      shipping_cost = v_shipping,
      total = v_total,
      shipping_pricing_contract = v_contract,
      expedition_provider_id = CASE WHEN p_delivery_type = 'EXPEDITION' THEN (v_contract->>'provider_id')::uuid ELSE NULL END,
      expedition_name_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'provider_name' ELSE NULL END,
      expedition_logo_url_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'provider_logo_url' ELSE NULL END,
      expedition_tracking_url_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'tracking_website' ELSE NULL END,
      expedition_service_code_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'service_code' ELSE NULL END,
      expedition_service_name_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'service_name' ELSE NULL END
    WHERE id = v_order.id;
    v_shipping_sum := v_shipping_sum + v_shipping;
    v_total_sum := v_total_sum + v_total;
    v_contracts := v_contracts || jsonb_build_array(v_contract);
  END LOOP;
  v_result := v_result || jsonb_build_object(
    'shipping_cost', v_shipping_sum,
    'total', v_total_sum,
    'shipping_pricing_contracts', v_contracts
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;

-- Guest checkout keeps its public signature and idempotency contract; the
-- wrapper normalizes cart lines before the legacy checkout and snapshots rates.
DO $$
BEGIN
  IF to_regprocedure('public.create_guest_marketplace_checkout_unpriced(jsonb,jsonb,text,text,uuid,numeric,text,text)') IS NULL
     AND to_regprocedure('public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text)') IS NOT NULL THEN
    ALTER FUNCTION public.create_guest_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text)
      RENAME TO create_guest_marketplace_checkout_unpriced;
  END IF;
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
  v_items jsonb;
  v_result jsonb;
  v_stored_result jsonb;
  v_session_hash text;
  v_effective_key text;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_id uuid;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_distance numeric := 0;
  v_order public.orders%ROWTYPE;
  v_contract jsonb;
  v_rate_card_id uuid;
  v_shipping integer;
  v_total integer;
  v_shipping_sum integer := 0;
  v_total_sum integer := 0;
  v_contracts jsonb := '[]'::jsonb;
  v_order_id uuid;
BEGIN
  v_items := public.normalize_marketplace_checkout_items(p_items);
  v_result := public.create_guest_marketplace_checkout_unpriced(
    v_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id,
    p_distance_km, p_guest_checkout_key, p_checkout_key
  );
  IF v_result ? 'shipping_pricing_contracts' THEN RETURN v_result; END IF;
  v_session_hash := encode(digest(trim(p_guest_checkout_key), 'sha256'), 'hex');
  v_effective_key := COALESCE(NULLIF(trim(p_checkout_key), ''), trim(p_guest_checkout_key));
  v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
  v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
  v_rate_card_id := NULLIF(p_delivery->>'expedition_rate_card_id', '')::uuid;
  IF p_delivery_type <> 'PICKUP' THEN
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng
    FROM public.merchants
    WHERE id = (SELECT p.merchant_id FROM jsonb_to_recordset(v_items) AS i(product_id uuid, variant_id uuid, quantity integer)
                JOIN public.products p ON p.id = i.product_id LIMIT 1);
    IF v_delivery_lat IS NULL OR v_delivery_lng IS NULL OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    END IF;
    v_distance := 6371 * 2 * asin(sqrt(LEAST(1, GREATEST(0,
      power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
      + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
      * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
    ))));
  END IF;
  FOR v_order_id IN
    SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_result->'order_ids', '[]'::jsonb)) AS ids(value)
  LOOP
    SELECT * INTO v_order FROM public.orders WHERE id = v_order_id FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;
    v_contract := public.marketplace_shipping_contract_quote(
      v_items, p_delivery, p_delivery_type, v_order.subtotal, v_distance, v_order.merchant_id, v_rate_card_id
    );
    v_shipping := (v_contract->>'shipping_cost')::integer;
    v_total := GREATEST(0, v_order.subtotal + v_shipping + COALESCE(v_order.cod_service_fee, 0)
      - COALESCE(v_order.flash_sale_discount, 0));
    UPDATE public.orders SET
      shipping_cost = v_shipping,
      total = v_total,
      shipping_pricing_contract = v_contract,
      expedition_provider_id = CASE WHEN p_delivery_type = 'EXPEDITION' THEN (v_contract->>'provider_id')::uuid ELSE NULL END,
      expedition_name_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'provider_name' ELSE NULL END,
      expedition_logo_url_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'provider_logo_url' ELSE NULL END,
      expedition_tracking_url_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'tracking_website' ELSE NULL END,
      expedition_service_code_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'service_code' ELSE NULL END,
      expedition_service_name_snapshot = CASE WHEN p_delivery_type = 'EXPEDITION' THEN v_contract->>'service_name' ELSE NULL END
    WHERE id = v_order.id;
    v_shipping_sum := v_shipping_sum + v_shipping;
    v_total_sum := v_total_sum + v_total;
    v_contracts := v_contracts || jsonb_build_array(v_contract);
  END LOOP;
  v_result := v_result || jsonb_build_object(
    'shipping_cost', v_shipping_sum,
    'total', v_total_sum,
    'shipping_pricing_contracts', v_contracts
  );
  v_stored_result := v_result - 'guest_access_token';
  UPDATE public.marketplace_guest_checkout_idempotency
  SET result = v_stored_result
  WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_effective_key;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout_unpriced(jsonb, jsonb, text, text, uuid, numeric, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text, text) TO anon;

-- The buyer-facing parcel charge and the merchant's own-delivery platform
-- commission are separate contracts and are snapshotted independently.
CREATE OR REPLACE FUNCTION public.snapshot_merchant_self_delivery_fee_contract()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.is_self_delivery IS TRUE AND COALESCE(OLD.is_self_delivery, false) IS FALSE THEN
    NEW.merchant_delivery_fee_contract := 'MERCHANT_SELF_DELIVERY_PLATFORM_PERCENT_V1';
  END IF;
  RETURN NEW;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'snapshot_merchant_self_delivery_fee_contract'
      AND tgrelid = 'public.orders'::regclass
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER snapshot_merchant_self_delivery_fee_contract
    BEFORE UPDATE OF is_self_delivery ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.snapshot_merchant_self_delivery_fee_contract();
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
