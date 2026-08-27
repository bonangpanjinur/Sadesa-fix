ALTER TABLE public.approval_requests ADD COLUMN IF NOT EXISTS request_context jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.request_pos_stock_adjustment(
  p_stock_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_quantity numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_stock public.pos_stock%ROWTYPE; v_request_id uuid; v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid stock adjustment request' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE CASE WHEN p_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment cannot reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.approval_requests(tenant_id, requester_id, request_type, subject_id, requested_amount, reason, request_context)
  VALUES (p_tenant_id, auth.uid(), 'stock_adjustment', p_stock_id, p_quantity, COALESCE(NULLIF(trim(p_notes), ''), 'Stock adjustment requires approval'), jsonb_build_object('type', p_type, 'notes', NULLIF(trim(p_notes), ''), 'outlet_id', p_outlet_id, 'quantity_before', v_stock.quantity, 'quantity_after_requested', v_after))
  RETURNING id INTO v_request_id;
  RETURN jsonb_build_object('request_id', v_request_id, 'status', 'pending');
END; $$;

CREATE OR REPLACE FUNCTION public.decide_pos_stock_adjustment(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.approval_requests%ROWTYPE; v_stock public.pos_stock%ROWTYPE; v_type text; v_after numeric; v_delta numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Stock adjustment approval denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_request FROM public.approval_requests WHERE id = p_request_id AND request_type = 'stock_adjustment' FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'pending' THEN RAISE EXCEPTION 'Stock adjustment approval is not pending' USING ERRCODE = '55000'; END IF;
  IF NOT p_approve THEN
    UPDATE public.approval_requests SET status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
    RETURN jsonb_build_object('request_id', p_request_id, 'status', 'rejected');
  END IF;
  v_type := v_request.request_context->>'type';
  SELECT * INTO v_stock FROM public.pos_stock WHERE id = v_request.subject_id AND tenant_id = v_request.tenant_id FOR UPDATE;
  IF NOT FOUND OR v_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN RAISE EXCEPTION 'Stock adjustment target is invalid' USING ERRCODE = 'P0002'; END IF;
  v_after := CASE WHEN v_type = 'adjustment' THEN v_request.requested_amount ELSE CASE WHEN v_type IN ('initial','purchase','return_sale','transfer_in') THEN v_stock.quantity + v_request.requested_amount ELSE v_stock.quantity - v_request.requested_amount END END;
  IF v_after < v_stock.reserved_quantity THEN RAISE EXCEPTION 'Adjustment would reduce stock below reserved quantity' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;
  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(tenant_id, product_id, variant_id, outlet_id, type, quantity, quantity_before, quantity_after, notes, created_by, reference_id, reference_type)
  VALUES (v_request.tenant_id, v_stock.product_id, v_stock.variant_id, (v_request.request_context->>'outlet_id')::uuid, v_type, v_delta, v_stock.quantity, v_after, COALESCE(NULLIF(trim(p_notes), ''), v_request.reason), auth.uid(), p_request_id, 'stock_adjustment_approval');
  UPDATE public.approval_requests SET status = 'approved', approved_level = required_level, decided_by = auth.uid(), decided_at = now(), decision_notes = NULLIF(trim(p_notes), '') WHERE id = p_request_id;
  RETURN jsonb_build_object('request_id', p_request_id, 'status', 'approved', 'stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END; $$;

REVOKE ALL ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_pos_stock_adjustment(uuid, uuid, uuid, text, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_pos_stock_adjustment(uuid, boolean, text) TO authenticated;
