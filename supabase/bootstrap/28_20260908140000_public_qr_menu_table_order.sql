-- Public QR menu and table-order contract.
-- Customer-facing reads/writes are deliberately exposed through scoped
-- SECURITY DEFINER RPCs instead of the tenant RLS tables.

ALTER TABLE public.pos_table_orders
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'internal';

ALTER TABLE public.pos_table_orders
  DROP CONSTRAINT IF EXISTS pos_table_orders_source_check;

ALTER TABLE public.pos_table_orders
  ADD CONSTRAINT pos_table_orders_source_check
  CHECK (source IN ('internal', 'table_qr'));

CREATE INDEX IF NOT EXISTS idx_pos_table_orders_public_status
  ON public.pos_table_orders(tenant_id, id, status);

CREATE TABLE IF NOT EXISTS public.pos_table_order_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.pos_table_orders(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE RESTRICT,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'consumed', 'released')),
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz,
  released_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_pos_table_order_stock_reservations_order
  ON public.pos_table_order_stock_reservations(order_id, status);

ALTER TABLE public.pos_table_order_stock_reservations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view table order stock reservations"
  ON public.pos_table_order_stock_reservations;
CREATE POLICY "POS users view table order stock reservations"
  ON public.pos_table_order_stock_reservations
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
    OR tenant_id IN (
      SELECT tenant_id
      FROM public.pos_users
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE OR REPLACE FUNCTION public.reserve_pos_table_order_stock(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty numeric;
  v_stock_id uuid;
BEGIN
  SELECT *
  INTO v_order
  FROM public.pos_table_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order meja tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_order.items)
  LOOP
    SELECT *
    INTO v_product
    FROM public.pos_products
    WHERE id = (v_item->>'product_id')::uuid
      AND tenant_id = v_order.tenant_id
      AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk order tidak tersedia' USING ERRCODE = '22023';
    END IF;

    v_qty := (v_item->>'qty')::numeric;
    IF v_product.is_stock_tracked THEN
      UPDATE public.pos_stock
      SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_qty,
          updated_at = now()
      WHERE tenant_id = v_order.tenant_id
        AND product_id = v_product.id
        AND outlet_id = v_order.outlet_id
        AND GREATEST(quantity - COALESCE(reserved_quantity, 0), 0) >= v_qty
      RETURNING id INTO v_stock_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Stok produk % tidak mencukupi', v_product.name
          USING ERRCODE = '55000';
      END IF;

      INSERT INTO public.pos_table_order_stock_reservations(
        order_id, tenant_id, product_id, outlet_id, quantity
      )
      VALUES (
        v_order.id, v_order.tenant_id, v_product.id, v_order.outlet_id, v_qty
      );
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_pos_table_order_stock(
  p_order_id uuid,
  p_status text DEFAULT 'released'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation public.pos_table_order_stock_reservations%ROWTYPE;
BEGIN
  FOR v_reservation IN
    SELECT *
    FROM public.pos_table_order_stock_reservations
    WHERE order_id = p_order_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(
          COALESCE(reserved_quantity, 0) - v_reservation.quantity, 0
        ),
        updated_at = now()
    WHERE tenant_id = v_reservation.tenant_id
      AND product_id = v_reservation.product_id
      AND outlet_id = v_reservation.outlet_id;

    UPDATE public.pos_table_order_stock_reservations
    SET status = CASE WHEN p_status = 'expired' THEN 'released' ELSE 'released' END,
        released_at = now()
    WHERE id = v_reservation.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_pos_table_order_stock(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation public.pos_table_order_stock_reservations%ROWTYPE;
BEGIN
  FOR v_reservation IN
    SELECT *
    FROM public.pos_table_order_stock_reservations
    WHERE order_id = p_order_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_reservation.quantity, 0),
        reserved_quantity = GREATEST(
          COALESCE(reserved_quantity, 0) - v_reservation.quantity, 0
        ),
        updated_at = now()
    WHERE tenant_id = v_reservation.tenant_id
      AND product_id = v_reservation.product_id
      AND outlet_id = v_reservation.outlet_id;

    UPDATE public.pos_table_order_stock_reservations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_reservation.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_table_order_stock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'cancelled' THEN
    PERFORM public.release_pos_table_order_stock(NEW.id, 'released');
  ELSIF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('served', 'paid') THEN
    PERFORM public.consume_pos_table_order_stock(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pos_table_order_stock_lifecycle
  ON public.pos_table_orders;
CREATE TRIGGER trg_pos_table_order_stock_lifecycle
  AFTER UPDATE OF status ON public.pos_table_orders
  FOR EACH ROW EXECUTE FUNCTION public.sync_pos_table_order_stock();

REVOKE ALL ON FUNCTION public.reserve_pos_table_order_stock(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_pos_table_order_stock(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.consume_pos_table_order_stock(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_table_order_stock()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_pos_menu(
  p_tenant_id uuid,
  p_table_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_table public.pos_tables%ROWTYPE;
  v_outlet_id uuid;
BEGIN
  IF NOT public.is_pos_tenant_active(p_tenant_id) THEN
    RAISE EXCEPTION 'Menu POS sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;

  SELECT *
  INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Toko tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF p_table_id IS NOT NULL THEN
    SELECT *
    INTO v_table
    FROM public.pos_tables
    WHERE id = p_table_id
      AND tenant_id = p_tenant_id
      AND is_active = true
      AND status <> 'cleaning';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Meja tidak valid atau sudah tidak aktif' USING ERRCODE = 'P0002';
    END IF;

    v_outlet_id := v_table.outlet_id;
  END IF;

  RETURN jsonb_build_object(
    'tenant', jsonb_build_object(
      'id', v_tenant.id,
      'name', v_tenant.name,
      'logo_url', v_tenant.logo_url,
      'address', v_tenant.address,
      'phone', v_tenant.phone,
      'currency', v_tenant.currency
    ),
    'table', CASE WHEN p_table_id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_table.id,
      'name', v_table.name,
      'outlet_id', v_table.outlet_id,
      'status', v_table.status
    ) END,
    'categories', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'sort_order', c.sort_order
        )
        ORDER BY c.sort_order, c.name
      )
      FROM public.pos_categories c
      WHERE c.tenant_id = p_tenant_id
        AND c.is_active = true
    ), '[]'::jsonb),
    'products', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'price', p.price,
          'original_price', NULL,
          'category_id', p.category_id,
          'description', p.description,
          'image_url', p.image_url,
          'unit', p.unit,
          'is_available',
            CASE
              WHEN NOT p.is_stock_tracked THEN true
              ELSE COALESCE((
                SELECT SUM(GREATEST(s.quantity - COALESCE(s.reserved_quantity, 0), 0))
                FROM public.pos_stock s
                WHERE s.tenant_id = p_tenant_id
                  AND s.product_id = p.id
                  AND (v_outlet_id IS NULL OR s.outlet_id = v_outlet_id)
              ), 0) > 0
            END
        )
        ORDER BY COALESCE(c.sort_order, 2147483647), p.name
      )
      FROM public.pos_products p
      LEFT JOIN public.pos_categories c
        ON c.id = p.category_id
       AND c.tenant_id = p_tenant_id
       AND c.is_active = true
      WHERE p.tenant_id = p_tenant_id
        AND p.is_active = true
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_public_pos_table_order(
  p_tenant_id uuid,
  p_table_id uuid,
  p_customer_name text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
  v_order public.pos_table_orders%ROWTYPE;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty integer;
  v_notes text;
  v_items jsonb := '[]'::jsonb;
  v_order_number text;
BEGIN
  IF NOT public.is_pos_tenant_active(p_tenant_id) THEN
    RAISE EXCEPTION 'POS sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'Item pesanan tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_table
  FROM public.pos_tables
  WHERE id = p_table_id
    AND tenant_id = p_tenant_id
    AND is_active = true
    AND status <> 'cleaning'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Meja tidak valid atau sudah tidak aktif' USING ERRCODE = 'P0002';
  END IF;

  IF v_table.outlet_id IS NULL THEN
    RAISE EXCEPTION 'QR meja belum terhubung ke outlet' USING ERRCODE = '55000';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF jsonb_typeof(v_item) <> 'object'
       OR NULLIF(v_item->>'product_id', '') IS NULL
       OR (v_item ? 'qty') IS FALSE THEN
      RAISE EXCEPTION 'Format item pesanan tidak valid' USING ERRCODE = '22023';
    END IF;

    v_qty := (v_item->>'qty')::integer;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
      RAISE EXCEPTION 'Jumlah item pesanan tidak valid' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_product
    FROM public.pos_products
    WHERE id = (v_item->>'product_id')::uuid
      AND tenant_id = p_tenant_id
      AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk tidak tersedia' USING ERRCODE = '22023';
    END IF;

    IF v_product.is_stock_tracked AND NOT EXISTS (
      SELECT 1
      FROM public.pos_stock s
      WHERE s.tenant_id = p_tenant_id
        AND s.product_id = v_product.id
        AND (v_table.outlet_id IS NULL OR s.outlet_id = v_table.outlet_id)
        AND GREATEST(s.quantity - COALESCE(s.reserved_quantity, 0), 0) >= v_qty
    ) THEN
      RAISE EXCEPTION 'Stok produk % tidak mencukupi', v_product.name USING ERRCODE = '55000';
    END IF;

    v_notes := NULLIF(left(COALESCE(v_item->>'notes', ''), 500), '');
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'qty', v_qty,
      'price', v_product.price,
      'subtotal', v_product.price * v_qty,
      'notes', v_notes
    ));
  END LOOP;

  v_order_number := 'QR-' ||
    to_char(now(), 'YYMMDDHH24MISS') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));

  INSERT INTO public.pos_table_orders(
    tenant_id, outlet_id, table_id, table_name, order_number, status,
    items, customer_name, notes, source
  )
  VALUES (
    p_tenant_id, v_table.outlet_id, v_table.id, v_table.name, v_order_number,
    'pending', v_items, NULLIF(left(COALESCE(p_customer_name, 'Tamu'), 120), ''),
    NULLIF(left(COALESCE(p_notes, ''), 1000), ''), 'table_qr'
  )
  RETURNING * INTO v_order;

  PERFORM public.reserve_pos_table_order_stock(v_order.id);

  IF v_table.status = 'available' OR v_table.status = 'reserved' THEN
    UPDATE public.pos_tables
    SET status = 'occupied', updated_at = now()
    WHERE id = v_table.id;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'table_id', v_order.table_id,
    'table_name', v_order.table_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_pos_table_order(
  p_tenant_id uuid,
  p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  SELECT *
  INTO v_order
  FROM public.pos_table_orders
  WHERE id = p_order_id
    AND tenant_id = p_tenant_id
    AND source = 'table_qr';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pesanan tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'items', v_order.items,
    'notes', v_order.notes,
    'customer_name', v_order.customer_name,
    'table_id', v_order.table_id,
    'table_name', v_order.table_name,
    'source', v_order.source,
    'cooking_started_at', v_order.cooking_started_at,
    'ready_at', v_order.ready_at,
    'served_at', v_order.served_at,
    'created_at', v_order.created_at,
    'updated_at', v_order.updated_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_pos_menu(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_public_pos_table_order(uuid, uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_pos_table_order(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_pos_menu(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_public_pos_table_order(uuid, uuid, text, text, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_pos_table_order(uuid, uuid) TO anon, authenticated;