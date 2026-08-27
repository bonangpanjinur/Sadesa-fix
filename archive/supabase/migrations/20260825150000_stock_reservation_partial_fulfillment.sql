ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0);

CREATE TABLE IF NOT EXISTS public.pos_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.pos_stock_reservations(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id),
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, stock_id)
);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_order ON public.pos_stock_reservations(order_id, status);
CREATE INDEX IF NOT EXISTS idx_pos_reservations_expiry ON public.pos_stock_reservations(status, expires_at);

CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  courier_id uuid REFERENCES auth.users(id),
  tracking_number text,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(tenant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.pos_fulfillment_shipments(id) ON DELETE CASCADE,
  order_item_id uuid REFERENCES public.order_items(id) ON DELETE SET NULL,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);

ALTER TABLE public.pos_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_reservation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_fulfillment_shipment_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "POS users view reservations" ON public.pos_stock_reservations FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users view reservation items" ON public.pos_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.pos_stock_reservations WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
CREATE POLICY "POS users view shipments" ON public.pos_fulfillment_shipments FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users view shipment items" ON public.pos_fulfillment_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.pos_fulfillment_shipments WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));

CREATE OR REPLACE FUNCTION public.reserve_pos_stock(
  p_tenant_id uuid, p_outlet_id uuid, p_order_id uuid, p_items jsonb, p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reservation_id uuid; v_input jsonb; v_stock public.pos_stock%ROWTYPE; v_qty numeric; v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock reservation' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_reservations(tenant_id, outlet_id, order_id, expires_at, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_order_id, p_expires_at, auth.uid()) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'stock_id', '') IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = (v_input->>'stock_id')::uuid AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
    IF NOT FOUND OR v_stock.quantity - v_stock.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available stock for reservation' USING ERRCODE = '23514'; END IF;
    UPDATE public.pos_stock SET reserved_quantity = reserved_quantity + v_qty, updated_at = now() WHERE id = v_stock.id;
    INSERT INTO public.pos_stock_reservation_items(reservation_id, stock_id, product_id, variant_id, quantity)
    VALUES (v_reservation_id, v_stock.id, v_stock.product_id, v_stock.variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'quantity', v_total, 'status', 'active');
END; $$;

CREATE OR REPLACE FUNCTION public.release_pos_stock_reservation(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.pos_stock_reservations%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.pos_stock_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_res.tenant_id, v_res.outlet_id) THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_reservation_items WHERE reservation_id = p_reservation_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id FOR UPDATE;
    IF FOUND THEN UPDATE public.pos_stock SET reserved_quantity = GREATEST(0, reserved_quantity - v_item.quantity), updated_at = now() WHERE id = v_stock.id; END IF;
  END LOOP;
  UPDATE public.pos_stock_reservations SET status = 'released', released_at = now() WHERE id = p_reservation_id;
  RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', 'released');
END; $$;

REVOKE ALL ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_pos_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_pos_stock_reservation(uuid) TO authenticated;
