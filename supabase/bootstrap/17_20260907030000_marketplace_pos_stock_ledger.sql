-- Cross-channel stock ledger for marketplace reservations.
--
-- POS-linked products reserve physical stock per outlet instead of only
-- incrementing products.reserved_stock. The marketplace projection remains
-- products.stock, while this table is the durable allocation/audit record.

CREATE TABLE IF NOT EXISTS public.marketplace_stock_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.marketplace_stock_reservations(id) ON DELETE CASCADE,
  reservation_item_id uuid NOT NULL REFERENCES public.marketplace_stock_reservation_items(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  pos_product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE RESTRICT,
  quantity numeric NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'consumed', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  consumed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_marketplace_allocations_reservation
  ON public.marketplace_stock_allocations(reservation_id, status);
CREATE INDEX IF NOT EXISTS idx_marketplace_allocations_outlet_product
  ON public.marketplace_stock_allocations(tenant_id, outlet_id, pos_product_id, status);

ALTER TABLE public.marketplace_stock_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own marketplace stock allocations" ON public.marketplace_stock_allocations;
CREATE POLICY "Users view own marketplace stock allocations"
  ON public.marketplace_stock_allocations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.marketplace_stock_reservations r
      JOIN public.orders o ON o.id = r.order_id
      WHERE r.id = reservation_id
        AND (
          r.buyer_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.merchants m
            WHERE m.id = o.merchant_id AND m.user_id = auth.uid()
          )
          OR public.is_admin()
        )
    )
  );

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
DECLARE
  v_order public.orders%ROWTYPE;
  v_reservation_id uuid;
  v_input jsonb;
  v_product public.products%ROWTYPE;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty integer;
  v_total integer := 0;
  v_existing public.marketplace_stock_reservations%ROWTYPE;
  v_tenant_id uuid;
  v_pos_product_id uuid;
  v_item_id uuid;
  v_remaining numeric;
  v_available numeric;
  v_allocated numeric;
  v_stock record;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND OR lower(COALESCE(v_order.status, '')) IN
     ('cancelled', 'canceled', 'rejected', 'refunded') THEN
    RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'reservation_id', v_existing.id,
      'status', v_existing.status,
      'duplicate', true
    );
  END IF;

  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at)
  VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute'))
  RETURNING id INTO v_reservation_id;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_product_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not found' USING ERRCODE = '23503';
    END IF;

    INSERT INTO public.marketplace_stock_reservation_items(
      reservation_id, product_id, variant_id, quantity
    )
    VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty)
    RETURNING id INTO v_item_id;

    -- A POS-linked product with no variant uses outlet stock as its physical
    -- source. Allocate deterministically so concurrent buyers lock the same
    -- rows in the same order and cannot oversell an outlet.
    v_tenant_id := NULL;
    v_pos_product_id := NULL;
    IF v_variant_id IS NULL THEN
      SELECT pt.id, pp.id
      INTO v_tenant_id, v_pos_product_id
      FROM public.pos_tenants pt
      JOIN public.pos_products pp
        ON pp.tenant_id = pt.id
       AND pp.merchant_product_id = v_product_id
       AND pp.is_active = true
      WHERE pt.merchant_id = v_order.merchant_id
        AND pt.is_active = true
      ORDER BY pt.created_at, pp.created_at
      LIMIT 1;
    END IF;

    IF v_pos_product_id IS NOT NULL THEN
      v_remaining := v_qty;
      FOR v_stock IN
        SELECT ps.id, ps.outlet_id, ps.quantity, COALESCE(ps.reserved_quantity, 0) AS reserved_quantity
        FROM public.pos_stock ps
        JOIN public.pos_outlets po
          ON po.id = ps.outlet_id
         AND po.tenant_id = ps.tenant_id
         AND po.is_active = true
        WHERE ps.tenant_id = v_tenant_id
          AND ps.product_id = v_pos_product_id
          AND ps.variant_id IS NULL
        ORDER BY ps.outlet_id, ps.id
        FOR UPDATE
      LOOP
        EXIT WHEN v_remaining <= 0;
        v_available := GREATEST(v_stock.quantity - v_stock.reserved_quantity, 0);
        v_allocated := LEAST(v_available, v_remaining);
        IF v_allocated > 0 THEN
          UPDATE public.pos_stock
          SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_allocated,
              updated_at = now()
          WHERE id = v_stock.id;

          INSERT INTO public.marketplace_stock_allocations(
            reservation_id, reservation_item_id, tenant_id, pos_product_id,
            product_id, outlet_id, quantity
          )
          VALUES (
            v_reservation_id, v_item_id, v_tenant_id, v_pos_product_id,
            v_product_id, v_stock.outlet_id, v_allocated
          );
          v_remaining := v_remaining - v_allocated;
        END IF;
      END LOOP;

      IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Insufficient POS outlet stock' USING ERRCODE = '23514';
      END IF;
    ELSE
      -- Legacy marketplace-only products retain their existing reservation
      -- counter and continue to use the marketplace stock lifecycle.
      IF v_product.stock - v_product.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products
      SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_product_id;
    END IF;
    v_total := v_total + v_qty;
  END LOOP;

  RETURN jsonb_build_object(
    'reservation_id', v_reservation_id,
    'status', 'active',
    'quantity', v_total,
    'expires_at', p_expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(
  p_order_id uuid,
  p_status text DEFAULT 'released'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_res
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()
  ) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer
     AND NOT EXISTS (
       SELECT 1 FROM public.orders o
       JOIN public.merchants m ON m.id = o.merchant_id
       WHERE o.id = p_order_id AND m.user_id = auth.uid()
     )
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501';
  END IF;
  IF v_res.status <> 'active' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status);
  END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NULL;
    UPDATE public.marketplace_stock_allocations
    SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
        released_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.*
    FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (
        SELECT 1 FROM public.marketplace_stock_allocations a
        WHERE a.reservation_item_id = i.id
      )
  LOOP
    UPDATE public.products
    SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity),
        updated_at = now()
    WHERE id = v_item.product_id;
  END LOOP;

  UPDATE public.marketplace_stock_reservations
  SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
      released_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_product public.products%ROWTYPE;
BEGIN
  SELECT * INTO v_res
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true);
  END IF;
  IF v_res.status <> 'active' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status);
  END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_allocation.quantity, 0),
        reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NULL;
    UPDATE public.marketplace_stock_allocations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.*
    FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (
        SELECT 1 FROM public.marketplace_stock_allocations a
        WHERE a.reservation_item_id = i.id
      )
  LOOP
    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
    FOR UPDATE;
    IF NOT FOUND OR v_product.reserved_stock < v_item.quantity
       OR v_product.stock < v_item.quantity THEN
      RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514';
    END IF;
    UPDATE public.products
    SET stock = stock - v_item.quantity,
        reserved_stock = reserved_stock - v_item.quantity,
        sold_count = COALESCE(sold_count, 0) + v_item.quantity,
        updated_at = now()
    WHERE id = v_item.product_id;
  END LOOP;

  UPDATE public.marketplace_stock_reservations
  SET status = 'consumed', consumed_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;