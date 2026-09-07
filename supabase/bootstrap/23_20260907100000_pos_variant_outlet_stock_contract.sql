-- Phase 2: one stock identity for every sellable unit.
--
-- A product without variants uses (pos_product, NULL, outlet).
-- A product with variants uses (pos_product, pos_variant, outlet).
-- Marketplace reservations and projection must never fall back from a variant
-- row to the parent product row.

ALTER TABLE public.pos_product_variants
  ADD COLUMN IF NOT EXISTS merchant_variant_id uuid
    REFERENCES public.product_variants(id) ON DELETE SET NULL;

ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS reserved_stock integer NOT NULL DEFAULT 0
    CHECK (reserved_stock >= 0);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_variants_tenant_merchant_variant
  ON public.pos_product_variants(tenant_id, merchant_variant_id)
  WHERE merchant_variant_id IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.pos_stock
    WHERE variant_id IS NULL
    GROUP BY product_id, outlet_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate base POS stock rows exist for a product and outlet';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pos_stock
    WHERE variant_id IS NOT NULL
    GROUP BY product_id, variant_id, outlet_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate variant POS stock rows exist for a product and outlet';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_stock_product_outlet_base_unique
  ON public.pos_stock(product_id, outlet_id)
  WHERE variant_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_stock_product_variant_outlet_unique
  ON public.pos_stock(product_id, variant_id, outlet_id)
  WHERE variant_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.validate_pos_stock_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada tenant dan produk POS yang sama'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada outlet tenant yang sama'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.variant_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE id = NEW.variant_id
      AND product_id = NEW.product_id
      AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian stok tidak cocok dengan produk dan tenant'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.quantity < 0 OR COALESCE(NEW.reserved_quantity, 0) < 0
     OR COALESCE(NEW.reserved_quantity, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'Stok dan reservasi tidak boleh negatif atau melebihi stok fisik'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_stock_scope ON public.pos_stock;
CREATE TRIGGER trg_validate_pos_stock_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id, variant_id, outlet_id, quantity, reserved_quantity
ON public.pos_stock
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_stock_scope();

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variant_to_pos(
  p_variant_id uuid,
  p_tenant_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_variant public.product_variants%ROWTYPE;
  v_pos_product_id uuid;
  v_pos_variant_id uuid;
BEGIN
  SELECT pv.* INTO v_variant
  FROM public.product_variants pv
  JOIN public.products p ON p.id = pv.product_id
  WHERE pv.id = p_variant_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT pp.id INTO v_pos_product_id
  FROM public.pos_products pp
  WHERE pp.tenant_id = p_tenant_id
    AND pp.merchant_product_id = v_variant.product_id
  LIMIT 1;
  IF v_pos_product_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_pos_variant_id
  FROM public.pos_product_variants
  WHERE tenant_id = p_tenant_id
    AND merchant_variant_id = p_variant_id
  LIMIT 1;

  IF v_pos_variant_id IS NULL THEN
    INSERT INTO public.pos_product_variants (
      product_id, tenant_id, merchant_variant_id, name, sku, price,
      cost_price, is_active
    )
    SELECT
      v_pos_product_id, p_tenant_id, v_variant.id, v_variant.name, v_variant.sku,
      pp.price + COALESCE(v_variant.price_adjustment, 0), pp.cost_price, v_variant.is_active
    FROM public.pos_products pp
    WHERE pp.id = v_pos_product_id
    RETURNING id INTO v_pos_variant_id;
  ELSE
    UPDATE public.pos_product_variants ppv
    SET product_id = v_pos_product_id,
        name = v_variant.name,
        sku = v_variant.sku,
        price = (SELECT pp.price FROM public.pos_products pp WHERE pp.id = v_pos_product_id)
          + COALESCE(v_variant.price_adjustment, 0),
        is_active = v_variant.is_active,
        updated_at = now()
    WHERE ppv.id = v_pos_variant_id;
  END IF;

  UPDATE public.pos_products
  SET has_variants = true, updated_at = now()
  WHERE id = v_pos_product_id;

  RETURN v_pos_variant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_pos_stock_rows_for_product(
  p_product_id uuid,
  p_tenant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_outlet public.pos_outlets%ROWTYPE;
  v_variant public.pos_product_variants%ROWTYPE;
  v_has_active_variants boolean;
BEGIN
  IF p_product_id IS NULL THEN RETURN; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE product_id = p_product_id AND tenant_id = p_tenant_id AND is_active = true
  ) INTO v_has_active_variants;

  FOR v_outlet IN
    SELECT * FROM public.pos_outlets
    WHERE tenant_id = p_tenant_id AND is_active = true
  LOOP
    IF v_has_active_variants THEN
      FOR v_variant IN
        SELECT * FROM public.pos_product_variants
        WHERE product_id = p_product_id AND tenant_id = p_tenant_id AND is_active = true
      LOOP
        INSERT INTO public.pos_stock (
          tenant_id, product_id, variant_id, outlet_id, quantity, min_stock
        )
        VALUES (p_tenant_id, p_product_id, v_variant.id, v_outlet.id, 0, 0)
        ON CONFLICT (product_id, variant_id, outlet_id)
        WHERE variant_id IS NOT NULL DO NOTHING;
      END LOOP;
    ELSE
      INSERT INTO public.pos_stock (
        tenant_id, product_id, variant_id, outlet_id, quantity, min_stock
      )
      VALUES (p_tenant_id, p_product_id, NULL, v_outlet.id, 0, 0)
      ON CONFLICT (product_id, outlet_id)
      WHERE variant_id IS NULL DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variants_for_product(
  p_product_id uuid,
  p_tenant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_variant public.product_variants%ROWTYPE;
  v_pos_product_id uuid;
BEGIN
  SELECT id INTO v_pos_product_id
  FROM public.pos_products
  WHERE tenant_id = p_tenant_id
    AND merchant_product_id = p_product_id
  LIMIT 1;
  IF v_pos_product_id IS NULL THEN RETURN; END IF;

  FOR v_variant IN
    SELECT * FROM public.product_variants
    WHERE product_id = p_product_id
  LOOP
    PERFORM public.sync_merchant_product_variant_to_pos(v_variant.id, p_tenant_id);
  END LOOP;

  UPDATE public.pos_products
  SET has_variants = EXISTS (
        SELECT 1 FROM public.pos_product_variants
        WHERE product_id = v_pos_product_id AND tenant_id = p_tenant_id AND is_active = true
      ),
      updated_at = now()
  WHERE id = v_pos_product_id;

  PERFORM public.ensure_pos_stock_rows_for_product(v_pos_product_id, p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variants_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT pt.*
    FROM public.pos_tenants pt
    JOIN public.products p ON p.merchant_id = pt.merchant_id
    WHERE p.id = NEW.product_id AND pt.is_active = true
  LOOP
    PERFORM public.sync_merchant_product_variants_for_product(NEW.product_id, v_tenant.id);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_variants ON public.product_variants;
CREATE TRIGGER trg_sync_merchant_product_variants
AFTER INSERT OR UPDATE OF name, price_adjustment, sku, is_active, product_id
ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.sync_merchant_product_variants_trigger();

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variant_delete_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT pt.*
    FROM public.pos_tenants pt
    JOIN public.products p ON p.merchant_id = pt.merchant_id
    WHERE p.id = OLD.product_id AND pt.is_active = true
  LOOP
    UPDATE public.pos_product_variants
    SET is_active = false, updated_at = now()
    WHERE tenant_id = v_tenant.id
      AND merchant_variant_id = OLD.id;

    UPDATE public.pos_products pp
    SET has_variants = EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE product_id = pp.id AND tenant_id = v_tenant.id AND is_active = true
    ),
    updated_at = now()
    WHERE pp.tenant_id = v_tenant.id AND pp.merchant_product_id = OLD.product_id;
  END LOOP;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_variant_delete ON public.product_variants;
CREATE TRIGGER trg_sync_merchant_product_variant_delete
BEFORE DELETE ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.sync_merchant_product_variant_delete_trigger();

ALTER TABLE public.marketplace_stock_allocations
  ADD COLUMN IF NOT EXISTS pos_variant_id uuid
    REFERENCES public.pos_product_variants(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_internal(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_mapping record;
  v_variant record;
  v_available numeric;
  v_projected_stock integer;
  v_processed integer := 0;
  v_updated integer := 0;
BEGIN
  PERFORM set_config('app.pos_stock_projection', 'on', true);
  SELECT * INTO v_tenant FROM public.pos_tenants WHERE id = p_tenant_id;
  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN jsonb_build_object('tenant_id', p_tenant_id, 'processed', 0, 'updated', 0, 'status', 'unmapped');
  END IF;

  FOR v_mapping IN
    SELECT pp.id AS pos_product_id,
           COALESCE(ms.marketplace_product_id, pp.merchant_product_id) AS marketplace_product_id,
           ms.id AS sync_id,
           EXISTS (
             SELECT 1 FROM public.pos_product_variants ppv
             WHERE ppv.product_id = pp.id AND ppv.tenant_id = pp.tenant_id AND ppv.is_active = true
           ) AS has_active_variants
    FROM public.pos_products pp
    LEFT JOIN public.pos_marketplace_sync ms
      ON ms.tenant_id = pp.tenant_id AND ms.pos_product_id = pp.id
    JOIN public.products marketplace_product
      ON marketplace_product.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
      AND marketplace_product.merchant_id = v_tenant.merchant_id
    WHERE pp.tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pp.id = p_pos_product_id)
      AND (ms.id IS NULL OR (ms.sync_stock = true AND ms.sync_status = 'synced'))
  LOOP
    v_processed := v_processed + 1;
    SELECT COALESCE(SUM(GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)), 0)
    INTO v_available
    FROM public.pos_stock ps
    JOIN public.pos_outlets po ON po.id = ps.outlet_id
      AND po.tenant_id = ps.tenant_id AND po.is_active = true
    WHERE ps.tenant_id = p_tenant_id
      AND ps.product_id = v_mapping.pos_product_id
      AND (
        (v_mapping.has_active_variants AND ps.variant_id IS NOT NULL)
        OR (NOT v_mapping.has_active_variants AND ps.variant_id IS NULL)
      );

    v_projected_stock := GREATEST(0, ROUND(v_available))::integer;
    UPDATE public.products
    SET stock = v_projected_stock, updated_at = now()
    WHERE id = v_mapping.marketplace_product_id
      AND merchant_id = v_tenant.merchant_id
      AND stock IS DISTINCT FROM v_projected_stock;
    IF FOUND THEN v_updated := v_updated + 1; END IF;

    IF v_mapping.sync_id IS NOT NULL THEN
      UPDATE public.pos_marketplace_sync
      SET last_synced_at = now(), sync_status = 'synced', error_message = NULL, updated_at = now()
      WHERE id = v_mapping.sync_id;
    END IF;

    FOR v_variant IN
      SELECT ppv.id AS pos_variant_id, ppv.merchant_variant_id
      FROM public.pos_product_variants ppv
      WHERE ppv.product_id = v_mapping.pos_product_id
        AND ppv.tenant_id = p_tenant_id
        AND ppv.is_active = true
        AND ppv.merchant_variant_id IS NOT NULL
    LOOP
      SELECT COALESCE(SUM(GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)), 0)
      INTO v_available
      FROM public.pos_stock ps
      JOIN public.pos_outlets po ON po.id = ps.outlet_id
        AND po.tenant_id = ps.tenant_id AND po.is_active = true
      WHERE ps.tenant_id = p_tenant_id
        AND ps.product_id = v_mapping.pos_product_id
        AND ps.variant_id = v_variant.pos_variant_id;
      v_projected_stock := GREATEST(0, ROUND(v_available))::integer;
      UPDATE public.product_variants
      SET stock = v_projected_stock, updated_at = now()
      WHERE id = v_variant.merchant_variant_id
        AND stock IS DISTINCT FROM v_projected_stock;
      IF FOUND THEN v_updated := v_updated + 1; END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('tenant_id', p_tenant_id, 'processed', v_processed, 'updated', v_updated, 'status', 'success');
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
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  SELECT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer AND NOT EXISTS (
    SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND m.user_id = auth.uid()
  ) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501';
  END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active' FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NOT DISTINCT FROM v_allocation.pos_variant_id;
    UPDATE public.marketplace_stock_allocations
    SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
        released_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.* FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (SELECT 1 FROM public.marketplace_stock_allocations a WHERE a.reservation_item_id = i.id)
  LOOP
    IF v_item.variant_id IS NOT NULL THEN
      UPDATE public.product_variants
      SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
      WHERE id = v_item.variant_id;
    ELSE
      UPDATE public.products
      SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
      WHERE id = v_item.product_id;
    END IF;
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
  v_variant public.product_variants%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true); END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active' FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_allocation.quantity, 0),
        reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NOT DISTINCT FROM v_allocation.pos_variant_id;
    UPDATE public.marketplace_stock_allocations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.* FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (SELECT 1 FROM public.marketplace_stock_allocations a WHERE a.reservation_item_id = i.id)
  LOOP
    IF v_item.variant_id IS NOT NULL THEN
      SELECT * INTO v_variant FROM public.product_variants WHERE id = v_item.variant_id FOR UPDATE;
      IF NOT FOUND OR v_variant.reserved_stock < v_item.quantity OR v_variant.stock < v_item.quantity THEN
        RAISE EXCEPTION 'Reserved marketplace variant stock is no longer available' USING ERRCODE = '23514';
      END IF;
      UPDATE public.product_variants
      SET stock = stock - v_item.quantity,
          reserved_stock = reserved_stock - v_item.quantity,
          updated_at = now()
      WHERE id = v_item.variant_id;
    ELSE
      SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
      IF NOT FOUND OR v_product.reserved_stock < v_item.quantity OR v_product.stock < v_item.quantity THEN
        RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products
      SET stock = stock - v_item.quantity,
          reserved_stock = reserved_stock - v_item.quantity,
          sold_count = COALESCE(sold_count, 0) + v_item.quantity,
          updated_at = now()
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  UPDATE public.marketplace_stock_reservations SET status = 'consumed', consumed_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_product_variant_to_pos(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_merchant_product_variants_for_product(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_stock_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;