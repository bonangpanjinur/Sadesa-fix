ALTER TABLE public.products ADD COLUMN IF NOT EXISTS reserved_stock integer NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0);

CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','released','consumed','expired')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  consumed_at timestamptz,
  UNIQUE(order_id)
);
CREATE TABLE IF NOT EXISTS public.marketplace_stock_reservation_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.marketplace_stock_reservations(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.product_variants(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  UNIQUE(reservation_id, product_id, variant_id)
);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservations_expiry ON public.marketplace_stock_reservations(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_marketplace_reservation_items_product ON public.marketplace_stock_reservation_items(product_id);
ALTER TABLE public.marketplace_stock_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_stock_reservation_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Buyers view own stock reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (buyer_id = auth.uid());
CREATE POLICY "Merchants view order reservations" ON public.marketplace_stock_reservations FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = order_id AND m.user_id = auth.uid()));
CREATE POLICY "Users view own reservation items" ON public.marketplace_stock_reservation_items FOR SELECT TO authenticated USING (reservation_id IN (SELECT id FROM public.marketplace_stock_reservations WHERE buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = marketplace_stock_reservations.order_id AND m.user_id = auth.uid())));

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_reservation_id uuid; v_input jsonb; v_product public.products%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty integer; v_total integer := 0; v_existing public.marketplace_stock_reservations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR v_order.status IN ('CANCELLED','CANCELED','REJECTED','REFUNDED') THEN RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_existing FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true); END IF;
  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at) VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute')) RETURNING id INTO v_reservation_id;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND OR v_product.stock - v_product.reserved_stock < v_qty THEN RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET reserved_stock = reserved_stock + v_qty, updated_at = now() WHERE id = v_product_id;
    INSERT INTO public.marketplace_stock_reservation_items(reservation_id, product_id, variant_id, quantity) VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty);
    v_total := v_total + v_qty;
  END LOOP;
  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'status', 'active', 'quantity', v_total, 'expires_at', p_expires_at);
END; $$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(p_order_id uuid, p_status text DEFAULT 'released')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  SELECT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer AND NOT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = p_order_id AND m.user_id = auth.uid()) AND NOT public.is_admin() THEN RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501'; END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    UPDATE public.products SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = CASE WHEN p_status IN ('expired','released') THEN p_status ELSE 'released' END, released_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END; $$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res public.marketplace_stock_reservations%ROWTYPE; v_item record; v_product public.products%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true); END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;
  FOR v_item IN SELECT * FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id LOOP
    SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
    IF NOT FOUND OR v_product.reserved_stock < v_item.quantity OR v_product.stock < v_item.quantity THEN RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514'; END IF;
    UPDATE public.products SET stock = stock - v_item.quantity, reserved_stock = reserved_stock - v_item.quantity, sold_count = COALESCE(sold_count, 0) + v_item.quantity, updated_at = now() WHERE id = v_item.product_id;
  END LOOP;
  UPDATE public.marketplace_stock_reservations SET status = 'consumed', consumed_at = now() WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END; $$;

CREATE OR REPLACE FUNCTION public.expire_marketplace_stock_reservations(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order_id uuid; v_count integer := 0;
BEGIN
  FOR v_order_id IN SELECT order_id FROM public.marketplace_stock_reservations WHERE status = 'active' AND expires_at <= now() ORDER BY expires_at FOR UPDATE SKIP LOCKED LIMIT GREATEST(1, LEAST(p_limit, 1000)) LOOP
    PERFORM public.release_marketplace_stock_reservation(v_order_id, 'expired'); v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.marketplace_reservation_order_status_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF lower(COALESCE(NEW.status, '')) IN ('cancelled','canceled','rejected','refunded') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.release_marketplace_stock_reservation(NEW.id, 'released');
  ELSIF lower(COALESCE(NEW.status, '')) IN ('shipped','delivered','completed','done') AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, '')) THEN PERFORM public.consume_marketplace_stock_reservation(NEW.id);
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_marketplace_reservation_order_status ON public.orders;
CREATE TRIGGER trg_marketplace_reservation_order_status AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.marketplace_reservation_order_status_trigger();

REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role;
