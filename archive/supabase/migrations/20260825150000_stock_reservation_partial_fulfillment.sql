ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0)$bootstrap_sql_a6381b343b4d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6381b343b4d$;

DO $bootstrap_do_059bcd885ae6$
BEGIN
  EXECUTE $bootstrap_sql_059bcd885ae6$CREATE TABLE IF NOT EXISTS public.pos_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
)$bootstrap_sql_059bcd885ae6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_059bcd885ae6$;

DO $bootstrap_do_a2cb4f22da8e$
BEGIN
  EXECUTE $bootstrap_sql_a2cb4f22da8e$CREATE TABLE IF NOT EXISTS public.pos_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.pos_stock_reservations(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id),
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, stock_id)
)$bootstrap_sql_a2cb4f22da8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2cb4f22da8e$;

DO $bootstrap_do_d1c520cd144d$
BEGIN
  EXECUTE $bootstrap_sql_d1c520cd144d$CREATE INDEX IF NOT EXISTS idx_pos_reservations_order ON public.pos_stock_reservations(order_id, status)$bootstrap_sql_d1c520cd144d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d1c520cd144d$;

DO $bootstrap_do_8bfc958b1790$
BEGIN
  EXECUTE $bootstrap_sql_8bfc958b1790$CREATE INDEX IF NOT EXISTS idx_pos_reservations_expiry ON public.pos_stock_reservations(status, expires_at)$bootstrap_sql_8bfc958b1790$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8bfc958b1790$;

DO $bootstrap_do_b4fd7bd113f6$
BEGIN
  EXECUTE $bootstrap_sql_b4fd7bd113f6$CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipments (
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
)$bootstrap_sql_b4fd7bd113f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b4fd7bd113f6$;

DO $bootstrap_do_4866205cd1e8$
BEGIN
  EXECUTE $bootstrap_sql_4866205cd1e8$CREATE TABLE IF NOT EXISTS public.pos_fulfillment_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.pos_fulfillment_shipments(id) ON DELETE CASCADE,
  order_item_id uuid REFERENCES public.order_items(id) ON DELETE SET NULL,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
)$bootstrap_sql_4866205cd1e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4866205cd1e8$;

DO $bootstrap_do_a1b545136066$
BEGIN
  EXECUTE $bootstrap_sql_a1b545136066$ALTER TABLE public.pos_stock_reservations ENABLE ROW LEVEL SECURITY$bootstrap_sql_a1b545136066$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1b545136066$;

DO $bootstrap_do_4dd9b6626ad0$
BEGIN
  EXECUTE $bootstrap_sql_4dd9b6626ad0$ALTER TABLE public.pos_stock_reservation_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_4dd9b6626ad0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dd9b6626ad0$;

DO $bootstrap_do_061a21354cc4$
BEGIN
  EXECUTE $bootstrap_sql_061a21354cc4$ALTER TABLE public.pos_fulfillment_shipments ENABLE ROW LEVEL SECURITY$bootstrap_sql_061a21354cc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_061a21354cc4$;

DO $bootstrap_do_ff810752b8cb$
BEGIN
  EXECUTE $bootstrap_sql_ff810752b8cb$ALTER TABLE public.pos_fulfillment_shipment_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_ff810752b8cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff810752b8cb$;

DO $bootstrap_do_4829c821022c$
BEGIN
  EXECUTE $bootstrap_sql_4829c821022c$DROP POLICY IF EXISTS "POS users view reservations" ON public.pos_stock_reservations$bootstrap_sql_4829c821022c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4829c821022c$;

DO $bootstrap_do_a3d3c7995e57$
BEGIN
  EXECUTE $bootstrap_sql_a3d3c7995e57$CREATE POLICY "POS users view reservations" ON public.pos_stock_reservations FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_a3d3c7995e57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3d3c7995e57$;

DO $bootstrap_do_90cf8f95db28$
BEGIN
  EXECUTE $bootstrap_sql_90cf8f95db28$DROP POLICY IF EXISTS "POS users view reservation items" ON public.pos_stock_reservation_items$bootstrap_sql_90cf8f95db28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90cf8f95db28$;

DO $bootstrap_do_cde80b1e81e7$
BEGIN
  EXECUTE $bootstrap_sql_cde80b1e81e7$CREATE POLICY "POS users view reservation items" ON public.pos_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.pos_stock_reservations WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)))$bootstrap_sql_cde80b1e81e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cde80b1e81e7$;

DO $bootstrap_do_b039c6ebd120$
BEGIN
  EXECUTE $bootstrap_sql_b039c6ebd120$DROP POLICY IF EXISTS "POS users view shipments" ON public.pos_fulfillment_shipments$bootstrap_sql_b039c6ebd120$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b039c6ebd120$;

DO $bootstrap_do_c304c3b5def9$
BEGIN
  EXECUTE $bootstrap_sql_c304c3b5def9$CREATE POLICY "POS users view shipments" ON public.pos_fulfillment_shipments FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_c304c3b5def9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c304c3b5def9$;

DO $bootstrap_do_4c8e6106ab30$
BEGIN
  EXECUTE $bootstrap_sql_4c8e6106ab30$DROP POLICY IF EXISTS "POS users view shipment items" ON public.pos_fulfillment_shipment_items$bootstrap_sql_4c8e6106ab30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c8e6106ab30$;

DO $bootstrap_do_a867a1c22dd3$
BEGIN
  EXECUTE $bootstrap_sql_a867a1c22dd3$CREATE POLICY "POS users view shipment items" ON public.pos_fulfillment_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.pos_fulfillment_shipments WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)))$bootstrap_sql_a867a1c22dd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a867a1c22dd3$;

DO $bootstrap_do_566836b1cf74$
BEGIN
  EXECUTE $bootstrap_sql_566836b1cf74$CREATE OR REPLACE FUNCTION public.reserve_pos_stock(
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
END; $$$bootstrap_sql_566836b1cf74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_566836b1cf74$;

DO $bootstrap_do_32bd443424e0$
BEGIN
  EXECUTE $bootstrap_sql_32bd443424e0$CREATE OR REPLACE FUNCTION public.release_pos_stock_reservation(p_reservation_id uuid)
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
END; $$$bootstrap_sql_32bd443424e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_32bd443424e0$;

DO $bootstrap_do_5fb69ca17bd4$
BEGIN
  EXECUTE $bootstrap_sql_5fb69ca17bd4$REVOKE ALL ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon$bootstrap_sql_5fb69ca17bd4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fb69ca17bd4$;

DO $bootstrap_do_6bc9ba83b25e$
BEGIN
  EXECUTE $bootstrap_sql_6bc9ba83b25e$REVOKE ALL ON FUNCTION public.release_pos_stock_reservation(uuid) FROM PUBLIC, anon$bootstrap_sql_6bc9ba83b25e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6bc9ba83b25e$;

DO $bootstrap_do_d66090baa116$
BEGIN
  EXECUTE $bootstrap_sql_d66090baa116$GRANT EXECUTE ON FUNCTION public.reserve_pos_stock(uuid, uuid, uuid, jsonb, timestamptz) TO authenticated$bootstrap_sql_d66090baa116$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d66090baa116$;

DO $bootstrap_do_bb6e30067a03$
BEGIN
  EXECUTE $bootstrap_sql_bb6e30067a03$GRANT EXECUTE ON FUNCTION public.release_pos_stock_reservation(uuid) TO authenticated$bootstrap_sql_bb6e30067a03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb6e30067a03$;

DO $bootstrap_do_bf6570997cd5$
BEGIN
  EXECUTE $bootstrap_sql_bf6570997cd5$
