CREATE OR REPLACE FUNCTION public.create_pos_stock_transfer(
  p_tenant_id uuid,
  p_transfer_number text,
  p_from_outlet_id uuid,
  p_to_outlet_id uuid,
  p_notes text,
  p_items jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_transfer_id uuid;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true
    UNION ALL SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN RAISE EXCEPTION 'Transfer creation denied' USING ERRCODE = '42501'; END IF;
  IF p_from_outlet_id = p_to_outlet_id OR NULLIF(trim(p_transfer_number), '') IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid stock transfer' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_from_outlet_id AND tenant_id = p_tenant_id)
     OR NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_to_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Transfer outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_stock_transfers(tenant_id, transfer_number, from_outlet_id, to_outlet_id, status, notes, requested_by)
  VALUES (p_tenant_id, trim(p_transfer_number), p_from_outlet_id, p_to_outlet_id, 'pending', NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_transfer_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'qty_requested')::numeric, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Invalid transfer quantity' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_product FROM public.pos_products WHERE id = (v_item->>'product_id')::uuid AND tenant_id = p_tenant_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer product does not belong to tenant' USING ERRCODE = '42501'; END IF;
    INSERT INTO public.pos_stock_transfer_items(transfer_id, product_id, variant_id, product_name, sku, unit, qty_requested, qty_sent, qty_received)
    VALUES (v_transfer_id, v_product.id, NULLIF(v_item->>'variant_id', '')::uuid, v_product.name, v_product.sku, COALESCE(v_product.unit, 'pcs'), v_qty, 0, 0);
  END LOOP;
  RETURN jsonb_build_object('transfer_id', v_transfer_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_transfer(p_transfer_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_transfer public.pos_stock_transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Transfer approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'pending' THEN RAISE EXCEPTION 'Transfer is no longer pending' USING ERRCODE = '55000'; END IF;
  IF p_approve THEN
    UPDATE public.pos_stock_transfers SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_transfer_id;
  ELSE
    UPDATE public.pos_stock_transfers SET status = 'rejected', rejection_reason = COALESCE(NULLIF(trim(p_reason), ''), 'Ditolak supervisor') WHERE id = p_transfer_id;
  END IF;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END);
END; $$;

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
BEGIN
  SELECT * INTO v_transfer FROM public.pos_stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_transfer.tenant_id AND t.user_id = auth.uid()) OR (public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.from_outlet_id) AND public.pos_user_can_access_outlet(v_transfer.tenant_id, v_transfer.to_outlet_id))) THEN
    RAISE EXCEPTION 'Transfer completion denied' USING ERRCODE = '42501';
  END IF;
  IF v_transfer.status <> 'approved' OR jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'Transfer is not ready for completion' USING ERRCODE = '55000'; END IF;
  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_transfer_item FROM public.pos_stock_transfer_items WHERE id = (v_input->>'item_id')::uuid AND transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer item not found' USING ERRCODE = 'P0002'; END IF;
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
      INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock) VALUES (v_transfer.tenant_id, v_transfer_item.product_id, v_transfer_item.variant_id, v_transfer.to_outlet_id, v_received, 0);
    END IF;
    UPDATE public.pos_stock_transfer_items SET qty_sent = v_sent, qty_received = v_received WHERE id = v_transfer_item.id;
  END LOOP;
  UPDATE public.pos_stock_transfers SET status = 'completed', completed_by = auth.uid(), completed_at = now() WHERE id = p_transfer_id;
  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'status', 'completed');
END; $$;

REVOKE ALL ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_stock_transfer(uuid, text, uuid, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_transfer(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_pos_stock_transfer(uuid, jsonb) TO authenticated;
