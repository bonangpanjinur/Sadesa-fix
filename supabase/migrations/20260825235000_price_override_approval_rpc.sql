CREATE OR REPLACE FUNCTION public.decide_pos_price_override(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.pos_price_override_requests%ROWTYPE; v_sale public.pos_sales%ROWTYPE; v_item public.pos_sale_items%ROWTYPE; v_subtotal numeric;
BEGIN
  SELECT * INTO v_request FROM public.pos_price_override_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = v_request.tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Price override approval denied' USING ERRCODE = '42501';
  END IF;
  IF v_request.status <> 'pending' THEN RAISE EXCEPTION 'Price override request already decided' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_price_override_requests SET status = 'rejected', approved_by = auth.uid(), decided_at = now(), reason = COALESCE(NULLIF(trim(p_reason), ''), reason) WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  IF v_request.sale_item_id IS NULL THEN RAISE EXCEPTION 'Price override item is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_item FROM public.pos_sale_items WHERE id = v_request.sale_item_id FOR UPDATE;
  IF NOT FOUND OR (v_request.sale_id IS NOT NULL AND v_item.sale_id <> v_request.sale_id) THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_sale FROM public.pos_sales WHERE id = v_item.sale_id FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN RAISE EXCEPTION 'Only completed POS sales can be price-adjusted' USING ERRCODE = '55000'; END IF;
  IF v_sale.tenant_id <> v_request.tenant_id OR v_sale.outlet_id <> v_request.outlet_id THEN RAISE EXCEPTION 'Price override scope mismatch' USING ERRCODE = '42501'; END IF;
  UPDATE public.pos_sale_items SET price = v_request.requested_price, subtotal = GREATEST(0, (v_request.requested_price * qty) - COALESCE(discount, 0)) WHERE id = v_item.id;
  SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM public.pos_sale_items WHERE sale_id = v_sale.id;
  UPDATE public.pos_sales SET subtotal = v_subtotal, total = GREATEST(0, v_subtotal - COALESCE(discount_amount, 0) + COALESCE(tax_amount, 0)), notes = concat_ws(E'\n', notes, 'Approved price override: ', v_request.id::text) WHERE id = v_sale.id;
  UPDATE public.pos_price_override_requests SET status = 'approved', approved_by = auth.uid(), decided_at = now() WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'sale_id', v_sale.id, 'new_price', v_request.requested_price, 'new_subtotal', v_subtotal);
END; $$;
REVOKE ALL ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_pos_price_override(uuid, boolean, text) TO authenticated;
