CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  from_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  to_warehouse_id uuid NOT NULL REFERENCES public.pos_warehouses(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','cancelled')),
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (from_warehouse_id <> to_warehouse_id)
);
CREATE TABLE IF NOT EXISTS public.pos_warehouse_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES public.pos_warehouse_transfers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE RESTRICT,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0)
);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfers_tenant ON public.pos_warehouse_transfers(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_warehouse_transfer_items_transfer ON public.pos_warehouse_transfer_items(transfer_id);
ALTER TABLE public.pos_warehouse_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_warehouse_transfer_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "POS users view warehouse transfers" ON public.pos_warehouse_transfers FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true));
CREATE POLICY "Tenant owners insert warehouse transfers" ON public.pos_warehouse_transfers FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()));
CREATE POLICY "POS users view warehouse transfer items" ON public.pos_warehouse_transfer_items FOR SELECT TO authenticated
  USING (transfer_id IN (SELECT id FROM public.pos_warehouse_transfers WHERE tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true)));

CREATE OR REPLACE FUNCTION public.transfer_stock_between_warehouses(
  p_tenant_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_items jsonb,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_from public.pos_warehouses%ROWTYPE; v_to public.pos_warehouses%ROWTYPE; v_transfer_id uuid; v_item jsonb; v_source public.pos_stock%ROWTYPE; v_dest public.pos_stock%ROWTYPE; v_product_id uuid; v_variant_id uuid; v_qty numeric; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 OR p_from_warehouse_id = p_to_warehouse_id THEN
    RAISE EXCEPTION 'Invalid warehouse transfer' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_from FROM public.pos_warehouses WHERE id = p_from_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  SELECT * INTO v_to FROM public.pos_warehouses WHERE id = p_to_warehouse_id AND tenant_id = p_tenant_id AND is_active FOR UPDATE;
  IF NOT FOUND OR v_from.outlet_id IS NULL OR v_to.outlet_id IS NULL THEN RAISE EXCEPTION 'Warehouse must be active and linked to an outlet' USING ERRCODE = '55000'; END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, v_from.outlet_id) OR NOT public.pos_user_can_access_outlet(p_tenant_id, v_to.outlet_id) THEN RAISE EXCEPTION 'Warehouse transfer access denied' USING ERRCODE = '42501'; END IF;
  INSERT INTO public.pos_warehouse_transfers(tenant_id, from_warehouse_id, to_warehouse_id, notes, created_by)
  VALUES (p_tenant_id, p_from_warehouse_id, p_to_warehouse_id, NULLIF(trim(p_notes), ''), auth.uid()) RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_item->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_item->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_item->>'quantity')::numeric, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Invalid warehouse transfer item' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_from.outlet_id AND warehouse_id = p_from_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_qty THEN RAISE EXCEPTION 'Insufficient available warehouse stock' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_qty;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (p_tenant_id, v_product_id, v_variant_id, v_from.outlet_id, 'transfer_out', -v_qty, v_source.quantity, v_after, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer out', auth.uid());
    SELECT * INTO v_dest FROM public.pos_stock WHERE tenant_id = p_tenant_id AND outlet_id = v_to.outlet_id AND warehouse_id = p_to_warehouse_id AND product_id = v_product_id AND variant_id IS NOT DISTINCT FROM v_variant_id FOR UPDATE;
    IF FOUND THEN
      UPDATE public.pos_stock SET quantity = quantity + v_qty, updated_at = now() WHERE id = v_dest.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, v_dest.quantity, v_dest.quantity + v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, outlet_id, warehouse_id, product_id, variant_id, quantity, reserved_quantity, min_stock)
      VALUES (p_tenant_id, v_to.outlet_id, p_to_warehouse_id, v_product_id, v_variant_id, v_qty, 0, 0);
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (p_tenant_id, v_product_id, v_variant_id, v_to.outlet_id, 'transfer_in', v_qty, 0, v_qty, v_transfer_id, 'pos_warehouse_transfer', 'Warehouse transfer in', auth.uid());
    END IF;
    INSERT INTO public.pos_warehouse_transfer_items(transfer_id, product_id, variant_id, quantity) VALUES (v_transfer_id, v_product_id, v_variant_id, v_qty);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'completed');
END; $$;
REVOKE ALL ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_stock_between_warehouses(uuid, uuid, uuid, jsonb, text) TO authenticated;
