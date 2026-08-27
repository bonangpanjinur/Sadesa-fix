CREATE TABLE IF NOT EXISTS public.marketplace_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  shipment_number text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','packed','shipped','delivered','cancelled')),
  tracking_number text,
  courier_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  shipped_at timestamptz,
  delivered_at timestamptz,
  UNIQUE(merchant_id, shipment_number)
);
CREATE TABLE IF NOT EXISTS public.marketplace_shipment_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id uuid NOT NULL REFERENCES public.marketplace_shipments(id) ON DELETE CASCADE,
  order_item_id uuid NOT NULL REFERENCES public.order_items(id) ON DELETE RESTRICT,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(shipment_id, order_item_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipments_order ON public.marketplace_shipments(order_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_shipment_items_order_item ON public.marketplace_shipment_items(order_item_id);
ALTER TABLE public.marketplace_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Buyer views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Buyer views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Merchant views own marketplace shipments" ON public.marketplace_shipments;
CREATE POLICY "Merchant views own marketplace shipments" ON public.marketplace_shipments FOR SELECT TO authenticated USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Buyer views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Buyer views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid())));
DROP POLICY IF EXISTS "Merchant views own shipment items" ON public.marketplace_shipment_items;
CREATE POLICY "Merchant views own shipment items" ON public.marketplace_shipment_items FOR SELECT TO authenticated USING (shipment_id IN (SELECT id FROM public.marketplace_shipments WHERE merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()));

CREATE OR REPLACE FUNCTION public.create_marketplace_shipment(p_order_id uuid, p_items jsonb, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_merchant_id uuid; v_shipment_id uuid; v_input jsonb; v_item public.order_items%ROWTYPE; v_product_id uuid; v_order_item_id uuid; v_qty integer; v_shipped integer; v_total integer := 0; v_number text;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid shipment request' USING ERRCODE = '22023'; END IF;
  SELECT o.*, m.id INTO v_order, v_merchant_id FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = p_order_id AND m.user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  v_number := 'SHP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  INSERT INTO public.marketplace_shipments(order_id, merchant_id, shipment_number, tracking_number) VALUES (p_order_id, v_merchant_id, v_number, NULLIF(trim(p_tracking_number), '')) RETURNING id INTO v_shipment_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_order_item_id := NULLIF(v_input->>'order_item_id', '')::uuid; v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_order_item_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid shipment item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_item FROM public.order_items WHERE id = v_order_item_id AND order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(sum(quantity), 0) INTO v_shipped FROM public.marketplace_shipment_items si JOIN public.marketplace_shipments s ON s.id = si.shipment_id WHERE si.order_item_id = v_order_item_id AND s.status <> 'cancelled';
    IF v_shipped + v_qty > v_item.quantity THEN RAISE EXCEPTION 'Shipment quantity exceeds order quantity' USING ERRCODE = '23514'; END IF;
    v_product_id := NULLIF(v_item.product_id::text, '')::uuid;
    INSERT INTO public.marketplace_shipment_items(shipment_id, order_item_id, product_id, quantity) VALUES (v_shipment_id, v_order_item_id, v_product_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('id', v_shipment_id, 'shipment_number', v_number, 'quantity', v_total, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.update_marketplace_shipment_status(p_shipment_id uuid, p_status text, p_tracking_number text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_shipment public.marketplace_shipments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_status NOT IN ('pending','processing','packed','shipped','delivered','cancelled') THEN RAISE EXCEPTION 'Invalid shipment status' USING ERRCODE = '22023'; END IF;
  SELECT s.* INTO v_shipment FROM public.marketplace_shipments s WHERE s.id = p_shipment_id AND (s.merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Shipment access denied' USING ERRCODE = '42501'; END IF;
  UPDATE public.marketplace_shipments SET status = p_status, tracking_number = COALESCE(NULLIF(trim(p_tracking_number), ''), tracking_number), shipped_at = CASE WHEN p_status = 'shipped' AND shipped_at IS NULL THEN now() ELSE shipped_at END, delivered_at = CASE WHEN p_status = 'delivered' AND delivered_at IS NULL THEN now() ELSE delivered_at END WHERE id = p_shipment_id;
  RETURN jsonb_build_object('id', p_shipment_id, 'status', p_status);
END; $$;
REVOKE ALL ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_shipment(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_marketplace_shipment_status(uuid, text, text) TO authenticated;
