-- DesaMart canonical bootstrap migration.
-- Source: 20261002130000_inventory_atomicity_hardening.sql
DO $bootstrap_do_inventory_atomicity_hardening$
BEGIN
  EXECUTE $bootstrap_sql_inventory_atomicity_hardening$-- Inventory atomicity and role hardening.
-- Safe to replay; all functions/policies/triggers are recreated idempotently.

CREATE OR REPLACE FUNCTION public.prevent_pos_stock_below_reserved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.quantity < NEW.reserved_quantity THEN
    RAISE EXCEPTION 'Stock quantity cannot be lower than reserved quantity' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS pos_stock_reserved_floor ON public.pos_stock;
CREATE TRIGGER pos_stock_reserved_floor
  BEFORE INSERT OR UPDATE OF quantity, reserved_quantity ON public.pos_stock
  FOR EACH ROW EXECUTE FUNCTION public.prevent_pos_stock_below_reserved();

CREATE OR REPLACE FUNCTION public.consume_pos_stock_reservation(
  p_reservation_id uuid,
  p_reference_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.pos_stock_reservations%ROWTYPE;
  v_item record;
  v_stock public.pos_stock%ROWTYPE;
  v_total numeric := 0;
BEGIN
  SELECT * INTO v_res FROM public.pos_stock_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_res.tenant_id, v_res.outlet_id) THEN
    RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501';
  END IF;
  IF v_res.status <> 'active' THEN
    RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', v_res.status);
  END IF;
  FOR v_item IN SELECT * FROM public.pos_stock_reservation_items WHERE reservation_id = p_reservation_id LOOP
    SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_item.stock_id FOR UPDATE;
    IF NOT FOUND OR v_stock.quantity < v_item.quantity THEN
      RAISE EXCEPTION 'Reserved stock is no longer available' USING ERRCODE = '23514';
    END IF;
    UPDATE public.pos_stock
    SET reserved_quantity = reserved_quantity - v_item.quantity, updated_at = now()
    WHERE id = v_stock.id;
    v_total := v_total + v_item.quantity;
  END LOOP;
  UPDATE public.pos_stock_reservations
  SET status = 'consumed', released_at = now()
  WHERE id = p_reservation_id;
  RETURN jsonb_build_object('reservation_id', p_reservation_id, 'status', 'consumed', 'quantity', v_total, 'reference_id', p_reference_id);
END;
$$;
REVOKE ALL ON FUNCTION public.consume_pos_stock_reservation(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_pos_stock_reservation(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_pos_raw_material(
  p_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_name text,
  p_unit text,
  p_initial_stock numeric,
  p_min_stock numeric,
  p_cost_per_unit numeric,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_material public.pos_raw_materials%ROWTYPE;
  v_initial numeric := COALESCE(p_initial_stock, 0);
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_name), '') IS NULL OR v_initial < 0 OR COALESCE(p_min_stock, 0) < 0 OR COALESCE(p_cost_per_unit, 0) < 0
     OR NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','staff_gudang','purchasing'])
     OR (p_outlet_id IS NOT NULL AND NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)) THEN
    RAISE EXCEPTION 'Raw material access or input denied' USING ERRCODE = '42501';
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO public.pos_raw_materials(tenant_id, outlet_id, name, unit, current_stock, min_stock, cost_per_unit, description)
    VALUES (p_tenant_id, p_outlet_id, trim(p_name), COALESCE(NULLIF(trim(p_unit), ''), 'gram'), v_initial, COALESCE(p_min_stock, 0), COALESCE(p_cost_per_unit, 0), NULLIF(trim(p_description), ''))
    RETURNING * INTO v_material;
    IF v_initial > 0 THEN
      INSERT INTO public.pos_raw_material_mutations(tenant_id, outlet_id, raw_material_id, type, qty, qty_before, qty_after, notes, created_by)
      VALUES (p_tenant_id, p_outlet_id, v_material.id, 'initial', v_initial, 0, v_initial, 'Stok awal', auth.uid());
    END IF;
  ELSE
    SELECT * INTO v_material FROM public.pos_raw_materials WHERE id = p_id AND tenant_id = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Raw material not found' USING ERRCODE = 'P0002'; END IF;
    UPDATE public.pos_raw_materials
    SET outlet_id = p_outlet_id, name = trim(p_name), unit = COALESCE(NULLIF(trim(p_unit), ''), unit),
        min_stock = COALESCE(p_min_stock, 0), cost_per_unit = COALESCE(p_cost_per_unit, 0),
        description = NULLIF(trim(p_description), ''), updated_at = now()
    WHERE id = p_id
    RETURNING * INTO v_material;
  END IF;
  RETURN jsonb_build_object('id', v_material.id, 'current_stock', v_material.current_stock);
END;
$$;
REVOKE ALL ON FUNCTION public.save_pos_raw_material(uuid, uuid, uuid, text, text, numeric, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_pos_raw_material(uuid, uuid, uuid, text, text, numeric, numeric, numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.adjust_pos_raw_material(
  p_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_material public.pos_raw_materials%ROWTYPE;
  v_after numeric;
  v_delta numeric;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR p_type NOT IN ('purchase','adjustment','usage','waste','return')
     OR NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','staff_gudang','purchasing'])
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Raw material adjustment denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_material FROM public.pos_raw_materials
  WHERE id = p_id AND tenant_id = p_tenant_id AND (outlet_id = p_outlet_id OR outlet_id IS NULL)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Raw material not found' USING ERRCODE = 'P0002'; END IF;
  v_delta := CASE WHEN p_type IN ('usage','waste','return') THEN -p_quantity ELSE p_quantity END;
  v_after := v_material.current_stock + v_delta;
  IF v_after < 0 THEN RAISE EXCEPTION 'Insufficient raw material stock' USING ERRCODE = '23514'; END IF;
  UPDATE public.pos_raw_materials SET current_stock = v_after, updated_at = now() WHERE id = v_material.id;
  INSERT INTO public.pos_raw_material_mutations(tenant_id, outlet_id, raw_material_id, type, qty, qty_before, qty_after, notes, created_by)
  VALUES (p_tenant_id, p_outlet_id, v_material.id, p_type, v_delta, v_material.current_stock, v_after, NULLIF(trim(p_notes), ''), auth.uid());
  RETURN jsonb_build_object('id', v_material.id, 'quantity_before', v_material.current_stock, 'quantity_after', v_after, 'delta', v_delta);
END;
$$;
REVOKE ALL ON FUNCTION public.adjust_pos_raw_material(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_pos_raw_material(uuid, uuid, uuid, text, numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.receive_pos_stock_batch(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_stock_id uuid,
  p_batch_number text,
  p_expiry_date date,
  p_quantity numeric,
  p_unit_cost numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock public.pos_stock%ROWTYPE;
  v_batch public.pos_stock_batches%ROWTYPE;
  v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NULLIF(trim(p_batch_number), '') IS NULL
     OR p_unit_cost IS NULL OR p_unit_cost < 0 OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid stock batch receipt' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
  v_after := v_stock.quantity + p_quantity;
  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_batches(tenant_id, outlet_id, stock_id, product_id, variant_id, batch_number, expiry_date, quantity, unit_cost)
  VALUES (p_tenant_id, p_outlet_id, v_stock.id, v_stock.product_id, v_stock.variant_id, trim(p_batch_number), p_expiry_date, p_quantity, p_unit_cost)
  RETURNING * INTO v_batch;
  INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
  VALUES (p_tenant_id, v_stock.product_id, v_stock.variant_id, p_outlet_id, 'purchase', p_quantity, v_stock.quantity, v_after, v_batch.id, 'stock_batch', 'Atomic batch receipt', auth.uid());
  RETURN jsonb_build_object('batch_id', v_batch.id, 'stock_id', v_stock.id, 'quantity_after', v_after);
END;
$$;
REVOKE ALL ON FUNCTION public.receive_pos_stock_batch(uuid, uuid, uuid, text, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_pos_stock_batch(uuid, uuid, uuid, text, date, numeric, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_pos_stock_transfer(p_transfer_id uuid, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer public.pos_stock_transfers%ROWTYPE;
  v_transfer_item public.pos_stock_transfer_items%ROWTYPE;
  v_input jsonb;
  v_source public.pos_stock%ROWTYPE;
  v_destination public.pos_stock%ROWTYPE;
  v_sent numeric;
  v_received numeric;
  v_after numeric;
  v_count integer := 0;
  v_expected integer;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid()) OR (public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.from_outlet_id) AND public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.to_outlet_id))) THEN
    RAISE EXCEPTION 'Transfer completion denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'approved' OR jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'Transfer is not ready for completion' USING ERRCODE = '55000'; END IF;
  SELECT count(*) INTO v_expected FROM public.pos_stock_transfer_items WHERE transfer_id = p_transfer_id;
  IF jsonb_array_length(p_items) <> v_expected THEN RAISE EXCEPTION 'All transfer items must be completed together' USING ERRCODE = '22023'; END IF;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_transfer_item FROM public.pos_stock_transfer_items WHERE id = (v_input->>'item_id')::uuid AND transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer item not found' USING ERRCODE = 'P0002'; END IF;
    v_count := v_count + 1;
    v_sent := COALESCE((v_input->>'qty_sent')::numeric, v_transfer_item.qty_requested);
    v_received := COALESCE((v_input->>'qty_received')::numeric, v_sent);
    IF v_sent <= 0 OR v_received < 0 OR v_received > v_sent OR v_sent > v_transfer_item.qty_requested THEN RAISE EXCEPTION 'Invalid transfer receive quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_source FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.from_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF NOT FOUND OR v_source.quantity - v_source.reserved_quantity < v_sent THEN RAISE EXCEPTION 'Insufficient source stock for transfer' USING ERRCODE = '23514'; END IF;
    v_after := v_source.quantity - v_sent;
    UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_source.id;
    INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
    VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.from_outlet_id, 'transfer_out', -v_sent, v_source.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer keluar', auth.uid());
    SELECT * INTO v_destination FROM public.pos_stock WHERE tenant_id = v_transfer.tenant_id AND outlet_id = v_transfer.to_outlet_id AND product_id = v_transfer_item.product_id AND variant_id IS NOT DISTINCT FROM v_transfer_item.variant_id FOR UPDATE;
    IF FOUND THEN
      v_after := v_destination.quantity + v_received;
      UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_destination.id;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, 'transfer_in', v_received, v_destination.quantity, v_after, v_transfer.id, 'stock_transfer', 'Atomic transfer masuk', auth.uid());
    ELSE
      INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock) VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, v_received, 0) RETURNING * INTO v_destination;
      INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, reference_id, reference_type, notes, created_by)
      VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, 'transfer_in', v_received, 0, v_received, v_transfer.id, 'stock_transfer', 'Atomic transfer masuk', auth.uid());
    END IF;
    UPDATE public.pos_stock_transfer_items SET qty_sent = v_sent, qty_received = v_received WHERE id = v_transfer_item.id;
  END LOOP;
  IF v_count <> v_expected THEN RAISE EXCEPTION 'Transfer item set is incomplete' USING ERRCODE = '22023'; END IF;
  UPDATE public.pos_stock_transfers SET status = 'completed', completed_by = auth.uid(), completed_at = now() WHERE id = p_transfer_id;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', 'completed');
END;
$$;
REVOKE ALL ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) TO authenticated;

DROP POLICY IF EXISTS "tenant_raw_materials" ON public.pos_raw_materials;
DROP POLICY IF EXISTS "tenant_raw_material_mutations" ON public.pos_raw_material_mutations;
DROP POLICY IF EXISTS "POS users view raw materials" ON public.pos_raw_materials;
DROP POLICY IF EXISTS "POS inventory manage raw materials" ON public.pos_raw_materials;
DROP POLICY IF EXISTS "POS users view raw material mutations" ON public.pos_raw_material_mutations;
CREATE POLICY "POS users view raw materials" ON public.pos_raw_materials FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()) OR (outlet_id IS NOT NULL AND public.pos_user_can_access_outlet(tenant_id, outlet_id)));
CREATE POLICY "POS inventory manage raw materials" ON public.pos_raw_materials FOR ALL TO authenticated
  USING (public.pos_user_has_role(tenant_id, ARRAY['owner','manager','staff_gudang','purchasing']) AND (outlet_id IS NOT NULL AND public.pos_user_can_access_outlet(tenant_id, outlet_id)))
  WITH CHECK (public.pos_user_has_role(tenant_id, ARRAY['owner','manager','staff_gudang','purchasing']) AND (outlet_id IS NOT NULL AND public.pos_user_can_access_outlet(tenant_id, outlet_id)));
CREATE POLICY "POS users view raw material mutations" ON public.pos_raw_material_mutations FOR SELECT TO authenticated
  USING (outlet_id IS NOT NULL AND public.pos_user_can_access_outlet(tenant_id, outlet_id));

NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.create_pos_purchase_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_supplier_id uuid,
  p_supplier_name text,
  p_po_number text,
  p_order_date date,
  p_expected_date date,
  p_subtotal numeric,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_total numeric,
  p_notes text,
  p_items jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_item jsonb;
  v_qty numeric;
  v_product_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','purchasing'])
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR NULLIF(trim(p_supplier_name), '') IS NULL OR NULLIF(trim(p_po_number), '') IS NULL
     OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Purchase order creation denied or invalid' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_purchase_orders(
    tenant_id, outlet_id, supplier_id, supplier_name, po_number, status, order_date,
    expected_date, subtotal, discount_amount, tax_amount, total, amount_paid, notes, created_by
  ) VALUES (
    p_tenant_id, p_outlet_id, p_supplier_id, trim(p_supplier_name), trim(p_po_number), 'draft',
    COALESCE(p_order_date, CURRENT_DATE), p_expected_date, GREATEST(0, COALESCE(p_subtotal, 0)),
    GREATEST(0, COALESCE(p_discount_amount, 0)), GREATEST(0, COALESCE(p_tax_amount, 0)),
    GREATEST(0, COALESCE(p_total, 0)), 0, NULLIF(trim(p_notes), ''), auth.uid()
  ) RETURNING * INTO v_po;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'qty_ordered')::numeric, 0);
    v_product_id := NULLIF(v_item->>'product_id', '')::uuid;
    IF NULLIF(trim(v_item->>'product_name'), '') IS NULL OR v_qty <= 0 OR COALESCE((v_item->>'cost_price')::numeric, 0) < 0 THEN
      RAISE EXCEPTION 'Invalid purchase order item' USING ERRCODE = '22023';
    END IF;
    IF v_product_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.pos_products WHERE id = v_product_id AND tenant_id = p_tenant_id) THEN
      RAISE EXCEPTION 'Purchase order product does not belong to tenant' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.pos_purchase_order_items(
      purchase_order_id, product_id, variant_id, product_name, sku, unit, qty_ordered,
      qty_received, cost_price, discount, subtotal, notes
    ) VALUES (
      v_po.id, v_product_id, NULLIF(v_item->>'variant_id', '')::uuid, trim(v_item->>'product_name'),
      NULLIF(v_item->>'sku', ''), COALESCE(NULLIF(v_item->>'unit', ''), 'pcs'), v_qty, 0,
      COALESCE((v_item->>'cost_price')::numeric, 0), COALESCE((v_item->>'discount')::numeric, 0),
      GREATEST(0, COALESCE((v_item->>'subtotal')::numeric, 0)), NULLIF(v_item->>'notes', '')
    );
  END LOOP;
  RETURN jsonb_build_object('purchase_order_id', v_po.id, 'po_number', v_po.po_number, 'status', v_po.status);
END;
$$;
REVOKE ALL ON FUNCTION public.create_pos_purchase_order(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_purchase_order(uuid, uuid, uuid, text, text, date, date, numeric, numeric, numeric, numeric, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_pos_stock_minimum(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_min_stock numeric
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_stock public.pos_stock%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_min_stock IS NULL OR p_min_stock < 0
     OR NOT public.pos_user_has_role(p_tenant_id, ARRAY['owner','manager','staff_gudang','purchasing'])
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Minimum stock update denied' USING ERRCODE = '42501';
  END IF;
  UPDATE public.pos_stock SET min_stock = p_min_stock, updated_at = now()
  WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  RETURNING * INTO v_stock;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('stock_id', v_stock.id, 'min_stock', v_stock.min_stock);
END;
$$;
REVOKE ALL ON FUNCTION public.set_pos_stock_minimum(uuid, uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pos_stock_minimum(uuid, uuid, uuid, numeric) TO authenticated;
$bootstrap_sql_inventory_atomicity_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_inventory_atomicity_hardening$;
