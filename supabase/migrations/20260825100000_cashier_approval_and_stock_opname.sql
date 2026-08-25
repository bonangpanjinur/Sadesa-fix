-- Cashier approval controls ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_void_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid NOT NULL REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_void_pending_sale ON public.pos_void_requests(sale_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.pos_price_override_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.pos_sales(id) ON DELETE CASCADE,
  sale_item_id uuid REFERENCES public.pos_sale_items(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  original_price numeric(15,2) NOT NULL,
  requested_price numeric(15,2) NOT NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK (original_price >= 0 AND requested_price >= 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_price_override_pending ON public.pos_price_override_requests(tenant_id, outlet_id, status, created_at DESC);

ALTER TABLE public.pos_void_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_price_override_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "POS users view own void requests" ON public.pos_void_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users create void requests" ON public.pos_void_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users view price overrides" ON public.pos_price_override_requests FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users create price overrides" ON public.pos_price_override_requests FOR INSERT TO authenticated
  WITH CHECK (requested_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.request_pos_void(
  p_tenant_id uuid, p_outlet_id uuid, p_sale_id uuid, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sale public.pos_sales%ROWTYPE; v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_reason), '') IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid void request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  INSERT INTO public.pos_void_requests(tenant_id, outlet_id, sale_id, requested_by, reason)
  VALUES (p_tenant_id, p_outlet_id, p_sale_id, auth.uid(), trim(p_reason)) RETURNING id INTO v_id;
  RETURN jsonb_build_object('request_id', v_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_void(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req public.pos_void_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_after numeric;
BEGIN
  SELECT * INTO v_req FROM public.pos_void_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_req.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Void approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'Void request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_void_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_req.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Sale is not eligible for void' USING ERRCODE = '55000'; END IF;
  UPDATE public.pos_sales SET status = 'void', voided_by = auth.uid(), voided_at = now(), void_reason = v_req.reason WHERE id = v_sale.id;
  FOR v_item IN SELECT * FROM public.pos_sale_items WHERE sale_id = v_sale.id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE tenant_id = v_sale.tenant_id AND outlet_id = v_sale.outlet_id AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_stock.quantity + v_item.qty;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_sale.tenant_id, v_item.product_id, v_item.variant_id, v_sale.outlet_id, 'return_sale', v_item.qty, v_stock.quantity, v_after, v_sale.id, 'pos_sale_void', 'Approved POS void', auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_void_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id);
END; $$;

-- Stock opname -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pos_stock_opnames (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  opname_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','counting','approved','cancelled')),
  reason text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.pos_stock_opname_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opname_id uuid NOT NULL REFERENCES public.pos_stock_opnames(id) ON DELETE CASCADE,
  stock_id uuid NOT NULL REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  system_quantity numeric(15,3) NOT NULL,
  counted_quantity numeric(15,3) NOT NULL CHECK (counted_quantity >= 0),
  difference numeric(15,3) NOT NULL,
  notes text
);
ALTER TABLE public.pos_stock_opnames ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_stock_opname_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "POS users view stock opnames" ON public.pos_stock_opnames FOR SELECT TO authenticated USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users create stock opnames" ON public.pos_stock_opnames FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
CREATE POLICY "POS users view stock opname items" ON public.pos_stock_opname_items FOR SELECT TO authenticated USING (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE public.pos_user_can_access_outlet(tenant_id, outlet_id)));
CREATE POLICY "POS users create stock opname items" ON public.pos_stock_opname_items FOR INSERT TO authenticated WITH CHECK (opname_id IN (SELECT id FROM public.pos_stock_opnames WHERE created_by = auth.uid() AND status IN ('draft','counting')));

CREATE OR REPLACE FUNCTION public.approve_pos_stock_opname(p_opname_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_opname public.pos_stock_opnames%ROWTYPE; v_item record; v_stock public.pos_stock%ROWTYPE; v_delta numeric;
BEGIN
  SELECT * INTO v_opname FROM public.pos_stock_opnames WHERE id = p_opname_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_opname.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Stock opname approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_opname.status NOT IN ('draft','counting') THEN RAISE EXCEPTION 'Stock opname already decided' USING ERRCODE = '55000'; END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_opname_items WHERE opname_id = p_opname_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id AND tenant_id = v_opname.tenant_id AND outlet_id = v_opname.outlet_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
    v_delta := v_item.counted_quantity - v_stock.quantity;
    IF v_delta <> 0 THEN
      UPDATE public.pos_stock SET quantity = v_item.counted_quantity, updated_at = now() WHERE id = v_stock.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_opname.tenant_id, v_stock.product_id, v_stock.variant_id, v_opname.outlet_id, 'opname', v_delta, v_stock.quantity, v_item.counted_quantity, p_opname_id, 'stock_opname', COALESCE(v_item.notes, v_opname.reason), auth.uid());
    END IF;
  END LOOP;
  UPDATE public.pos_stock_opnames SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_opname_id;
  RETURN jsonb_build_object('opname_id', p_opname_id, 'status', 'approved');
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_void(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_pos_stock_opname(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_void(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_void(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_pos_stock_opname(uuid) TO authenticated;
