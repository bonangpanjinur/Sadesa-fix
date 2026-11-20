-- Marketplace checkout must not depend on a merchant's POS subscription state.
-- Use outlet-level POS stock only while the linked POS tenant is active; otherwise
-- keep checkout on the marketplace product/variant stock reservation path.
-- POS write guards remain unchanged for all POS operations.
CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock_unaggregated(
  p_order_id uuid,
  p_items jsonb,
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
  IF auth.uid() IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR lower(COALESCE(v_order.status, '')) IN ('cancelled', 'canceled', 'rejected', 'refunded') THEN
    RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true);
  END IF;

  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at)
  VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute'))
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
    WHERE pt.merchant_id = v_order.merchant_id AND public.is_pos_tenant_active(pt.id)
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
