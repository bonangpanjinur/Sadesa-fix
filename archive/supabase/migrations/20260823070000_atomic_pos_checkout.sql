-- Atomic POS checkout with request idempotency.
-- All core sale writes and stock mutations execute in one database transaction.

CREATE TABLE IF NOT EXISTS public.pos_sale_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  cashier_id uuid NOT NULL REFERENCES auth.users(id),
  request_key text NOT NULL,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE SET NULL,
  response jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, outlet_id, request_key)
);

CREATE INDEX IF NOT EXISTS idx_pos_sale_requests_created_at
  ON public.pos_sale_requests(created_at DESC);

ALTER TABLE public.pos_sale_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pos_sale_requests FROM anon, authenticated;
GRANT ALL ON public.pos_sale_requests TO service_role;

CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_request_key text,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_sale jsonb,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.pos_sale_requests%ROWTYPE;
  v_request_id uuid;
  v_sale_id uuid;
  v_item jsonb;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_before numeric;
  v_after numeric;
  v_sale_number text;
  v_payment_method text;
  v_total numeric;
  v_response jsonb;
  v_recipe record;
  v_raw public.pos_raw_materials%ROWTYPE;
  v_usage numeric;
  v_customer_segment text;
  v_input_price numeric;
  v_effective_price numeric;
  v_computed_subtotal numeric := 0;
  v_price_override_count integer := 0;
  v_sale_earned integer := 0;
  v_sale_redeemed integer := 0;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;

  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  IF p_request_key IS NULL OR length(trim(p_request_key)) < 16 OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid POS request key' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'POS sale requires at least one item' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_sale_requests(tenant_id, outlet_id, cashier_id, request_key)
  VALUES (p_tenant_id, p_outlet_id, p_cashier_id, trim(p_request_key))
  ON CONFLICT (tenant_id, outlet_id, request_key) DO NOTHING
  RETURNING id INTO v_request_id;

  IF v_request_id IS NULL THEN
    SELECT * INTO v_existing
    FROM public.pos_sale_requests
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND request_key = trim(p_request_key);
    IF v_existing.response IS NULL THEN
      RAISE EXCEPTION 'POS request is already being processed' USING ERRCODE = '55P03';
    END IF;
    RETURN v_existing.response || jsonb_build_object('duplicate', true);
  END IF;

  v_sale_number := NULLIF(trim(p_sale->>'sale_number'), '');
  IF v_sale_number IS NULL THEN
    RAISE EXCEPTION 'Sale number is required' USING ERRCODE = '22023';
  END IF;

  v_payment_method := lower(COALESCE(p_sale->>'payment_method', 'cash'));
  -- The UI historically uses qr_pay; persist it as the schema-supported qris value.
  IF v_payment_method = 'qr_pay' THEN v_payment_method := 'qris'; END IF;
  IF v_payment_method NOT IN ('cash', 'qris', 'transfer', 'debit', 'credit', 'split') THEN
    RAISE EXCEPTION 'Unsupported payment method' USING ERRCODE = '22023';
  END IF;

  v_total := COALESCE((p_sale->>'total')::numeric, 0);
  v_customer_segment := lower(COALESCE(NULLIF(p_sale->>'customer_segment', ''), 'retail'));
  IF v_customer_segment NOT IN ('retail', 'wholesale', 'reseller', 'member', 'outlet') THEN
    RAISE EXCEPTION 'Unsupported customer segment' USING ERRCODE = '22023';
  END IF;
  IF v_total < 0 THEN
    RAISE EXCEPTION 'Invalid sale total' USING ERRCODE = '22023';
  END IF;

  -- Resolve price-book prices before inserting the sale. This makes the
  -- server authoritative for both line prices and the final total.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;
    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      IF COALESCE((p_sale->>'offline_sync')::boolean, false) THEN
        RAISE EXCEPTION 'Price conflict for product %: server price is %, queued price is %', v_item->>'product_id', v_effective_price, v_input_price USING ERRCODE = 'P0001', DETAIL = jsonb_build_object('conflict_type', 'PRICE_CHANGED', 'product_id', v_item->>'product_id', 'queued_price', v_input_price, 'server_price', v_effective_price)::text;
      END IF;
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));
  END LOOP;
  v_total := GREATEST(0, v_computed_subtotal - COALESCE((p_sale->>'discount_amount')::numeric, 0) + COALESCE((p_sale->>'tax_amount')::numeric, 0));

  INSERT INTO public.pos_sales(
    tenant_id, outlet_id, sale_number, cashier_id, cashier_name,
    customer_id, customer_name, subtotal, discount_amount, tax_amount, total,
    payment_method, payment_amount, change_amount, status, notes,
    promotion_id, voucher_id, voucher_code, promotion_discount, voucher_discount,
    loyalty_points_earned, loyalty_points_redeemed, loyalty_discount
  ) VALUES (
    p_tenant_id, p_outlet_id, v_sale_number, p_cashier_id,
    NULLIF(p_sale->>'cashier_name', ''), NULLIF(p_sale->>'customer_id', '')::uuid,
    NULLIF(p_sale->>'customer_name', ''), v_computed_subtotal,
    COALESCE((p_sale->>'discount_amount')::numeric, 0), COALESCE((p_sale->>'tax_amount')::numeric, 0), v_total,
    v_payment_method, COALESCE((p_sale->>'payment_amount')::numeric, v_total),
    COALESCE((p_sale->>'change_amount')::numeric, 0), 'completed', NULLIF(p_sale->>'notes', ''),
    NULLIF(p_sale->>'promotion_id', '')::uuid, NULLIF(p_sale->>'voucher_id', '')::uuid,
    NULLIF(p_sale->>'voucher_code', ''), COALESCE((p_sale->>'promotion_discount')::numeric, 0),
    COALESCE((p_sale->>'voucher_discount')::numeric, 0), COALESCE((p_sale->>'loyalty_points_earned')::integer, 0),
    COALESCE((p_sale->>'loyalty_points_redeemed')::integer, 0), COALESCE((p_sale->>'loyalty_discount')::numeric, 0)
  ) RETURNING id INTO v_sale_id;
  SELECT loyalty_points_earned, loyalty_points_redeemed INTO v_sale_earned, v_sale_redeemed
  FROM public.pos_sales WHERE id = v_sale_id;

  v_computed_subtotal := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := COALESCE((v_item->>'qty')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid item quantity' USING ERRCODE = '22023'; END IF;

    v_input_price := COALESCE((v_item->>'price')::numeric, 0);
    v_effective_price := COALESCE(public.get_effective_pos_price(
      p_tenant_id, p_outlet_id, (v_item->>'product_id')::uuid,
      NULLIF(v_item->>'variant_id', '')::uuid, v_customer_segment
    ), v_input_price);
    IF v_effective_price <> v_input_price THEN
      v_price_override_count := v_price_override_count + 1;
    END IF;
    v_computed_subtotal := v_computed_subtotal + GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0));

    INSERT INTO public.pos_sale_items(
      sale_id, product_id, variant_id, product_name, variant_name, sku,
      qty, price, cost_price, discount, tax_amount, subtotal, notes
    ) VALUES (
      v_sale_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      COALESCE(v_item->>'name', 'Produk'), NULLIF(v_item->>'variant_name', ''), NULLIF(v_item->>'sku', ''),
      v_qty, v_effective_price, COALESCE((v_item->>'cost_price')::numeric, 0),
      COALESCE((v_item->>'discount')::numeric, 0), COALESCE((v_item->>'tax_amount')::numeric, 0),
      GREATEST(0, (v_effective_price * v_qty) - COALESCE((v_item->>'discount')::numeric, 0) + COALESCE((v_item->>'tax_amount')::numeric, 0)), NULLIF(v_item->>'notes', '')
    );

    SELECT * INTO v_stock
    FROM public.pos_stock
    WHERE tenant_id = p_tenant_id
      AND outlet_id = p_outlet_id
      AND product_id = (v_item->>'product_id')::uuid
      AND variant_id IS NOT DISTINCT FROM NULLIF(v_item->>'variant_id', '')::uuid
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stock row not found for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
    END IF;
    v_before := v_stock.quantity;
    v_after := v_before - v_qty;
    IF v_after < 0 THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
    END IF;

    UPDATE public.pos_stock
    SET quantity = v_after, updated_at = now()
    WHERE id = v_stock.id;

    INSERT INTO public.pos_stock_mutations(
      tenant_id, product_id, variant_id, outlet_id, type, quantity,
      quantity_before, quantity_after, reference_id, reference_type, notes, created_by
    ) VALUES (
      p_tenant_id, (v_item->>'product_id')::uuid, NULLIF(v_item->>'variant_id', '')::uuid,
      p_outlet_id, 'sale', -v_qty, v_before, v_after, v_sale_id, 'pos_sale',
      'Atomic POS sale', p_cashier_id
    );
  END LOOP;

  IF v_price_override_count > 0 THEN
    UPDATE public.pos_sales
    SET subtotal = v_computed_subtotal,
        total = GREATEST(0, v_computed_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)),
        notes = concat_ws(' | ', NULLIF(notes, ''), 'Price book: ' || v_customer_segment)
    WHERE id = v_sale_id;
    SELECT total INTO v_total FROM public.pos_sales WHERE id = v_sale_id;
  END IF;

  -- Consume recipe ingredients under row locks in the same transaction.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    FOR v_recipe IN
      SELECT r.raw_material_id, r.qty_needed
      FROM public.pos_recipes r
      WHERE r.tenant_id = p_tenant_id
        AND r.product_id = (v_item->>'product_id')::uuid
    LOOP
      SELECT * INTO v_raw
      FROM public.pos_raw_materials
      WHERE id = v_recipe.raw_material_id
        AND tenant_id = p_tenant_id
        AND (outlet_id = p_outlet_id OR outlet_id IS NULL)
      ORDER BY (outlet_id IS NULL)
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Raw material is unavailable for product %', v_item->>'product_id' USING ERRCODE = 'P0002';
      END IF;
      v_usage := v_recipe.qty_needed * COALESCE((v_item->>'qty')::numeric, 0);
      IF v_raw.current_stock - v_usage < 0 THEN
        RAISE EXCEPTION 'Insufficient raw material stock for product %', v_item->>'product_id' USING ERRCODE = '23514';
      END IF;

      UPDATE public.pos_raw_materials
      SET current_stock = current_stock - v_usage, updated_at = now()
      WHERE id = v_raw.id;
      INSERT INTO public.pos_raw_material_mutations(
        tenant_id, outlet_id, raw_material_id, type, qty,
        qty_before, qty_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, p_outlet_id, v_raw.id, 'usage', -v_usage,
        v_raw.current_stock, v_raw.current_stock - v_usage, v_sale_id, 'pos_sale',
        'Atomic POS sale recipe usage', p_cashier_id
      );
    END LOOP;
  END LOOP;

  -- Keep the customer aggregate in the same transaction when a customer is selected.
  IF NULLIF(p_sale->>'customer_id', '') IS NOT NULL THEN
    UPDATE public.pos_customers
    SET total_purchase = COALESCE(total_purchase, 0) + v_total,
        transaction_count = COALESCE(transaction_count, 0) + 1,
        last_purchase_at = now(),
        loyalty_points = GREATEST(0, COALESCE(loyalty_points, 0)
          - v_sale_redeemed + v_sale_earned),
        updated_at = now()
    WHERE id = (p_sale->>'customer_id')::uuid AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer does not belong to tenant' USING ERRCODE = '42501'; END IF;
  END IF;

  IF NULLIF(p_sale->>'voucher_id', '') IS NOT NULL THEN
    UPDATE public.pos_vouchers
    SET used_count = used_count + 1, updated_at = now()
    WHERE id = (p_sale->>'voucher_id')::uuid AND tenant_id = p_tenant_id
      AND is_active = true AND (usage_limit IS NULL OR used_count < usage_limit);
    IF NOT FOUND THEN RAISE EXCEPTION 'Voucher is no longer available' USING ERRCODE = '23514'; END IF;
    INSERT INTO public.pos_voucher_usages(voucher_id, sale_id, customer_id, customer_name, discount_given)
    VALUES ((p_sale->>'voucher_id')::uuid, v_sale_id, NULLIF(p_sale->>'customer_id', '')::uuid,
      NULLIF(p_sale->>'customer_name', ''), COALESCE((p_sale->>'voucher_discount')::numeric, 0));
  END IF;

  v_response := jsonb_build_object(
    'sale_id', v_sale_id, 'sale_number', v_sale_number, 'total', v_total,
    'payment_method', v_payment_method, 'duplicate', false
  );
  UPDATE public.pos_sale_requests SET sale_id = v_sale_id, response = v_response WHERE id = v_request_id;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  -- The surrounding transaction rolls back sale, items, stock, and request row together.
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_pos_sale(text, uuid, uuid, uuid, jsonb, jsonb) TO authenticated;
