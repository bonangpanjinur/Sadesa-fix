CREATE OR REPLACE FUNCTION public.receive_pos_purchase_order(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_input jsonb;
  v_item public.pos_purchase_order_items%ROWTYPE;
  v_stock public.pos_stock%ROWTYPE;
  v_qty numeric;
  v_after numeric;
  v_any boolean := false;
  v_all_received boolean := true;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_purchase_order_id IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Invalid purchase receiving request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_po.status IN ('cancelled', 'received') THEN
    RAISE EXCEPTION 'Purchase order is not receivable' USING ERRCODE = '55000';
  END IF;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF NULLIF(v_input->>'item_id', '') IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid received item' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_item FROM public.pos_purchase_order_items
    WHERE id = (v_input->>'item_id')::uuid AND purchase_order_id = p_purchase_order_id
    FOR UPDATE;
    IF NOT FOUND OR v_item.qty_received + v_qty > v_item.qty_ordered THEN
      RAISE EXCEPTION 'Received quantity exceeds ordered quantity' USING ERRCODE = '23514';
    END IF;
    v_any := true;
    UPDATE public.pos_purchase_order_items SET qty_received = qty_received + v_qty WHERE id = v_item.id;
    IF v_item.product_id IS NOT NULL THEN
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id
        AND product_id = v_item.product_id AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
      ELSE
        v_after := v_qty;
        INSERT INTO public.pos_stock(tenant_id, product_id, variant_id, outlet_id, quantity, min_stock)
        VALUES (p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, v_after, 0)
        RETURNING * INTO v_stock;
      END IF;
      INSERT INTO public.pos_stock_mutations(
        tenant_id, product_id, variant_id, outlet_id, type, quantity,
        quantity_before, quantity_after, reference_id, reference_type, notes, created_by
      ) VALUES (
        p_tenant_id, v_item.product_id, v_item.variant_id, p_outlet_id, 'purchase', v_qty,
        v_after - v_qty, v_after, p_purchase_order_id, 'purchase_order',
        'Atomic purchase receiving ' || v_po.po_number, auth.uid()
      );
    END IF;
  END LOOP;
  IF NOT v_any THEN RAISE EXCEPTION 'No items received' USING ERRCODE = '22023'; END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM public.pos_purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id AND qty_received < qty_ordered
  ) INTO v_all_received;
  UPDATE public.pos_purchase_orders
  SET status = CASE WHEN v_all_received THEN 'received' ELSE 'partial' END,
      received_date = CURRENT_DATE, updated_by = auth.uid(), updated_at = now()
  WHERE id = p_purchase_order_id;
  RETURN jsonb_build_object('purchase_order_id', p_purchase_order_id, 'status', CASE WHEN v_all_received THEN 'received' ELSE 'partial' END);
END;
$$$bootstrap_sql_812a971e3080$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_812a971e3080$;

DO $bootstrap_do_30f0cc30cee3$
BEGIN
  EXECUTE $bootstrap_sql_30f0cc30cee3$REVOKE ALL ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon$bootstrap_sql_30f0cc30cee3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_30f0cc30cee3$;

DO $bootstrap_do_2dc9f28167ac$
BEGIN
  EXECUTE $bootstrap_sql_2dc9f28167ac$GRANT EXECUTE ON FUNCTION public.receive_pos_purchase_order(uuid, uuid, uuid, jsonb) TO authenticated$bootstrap_sql_2dc9f28167ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dc9f28167ac$;

DO $bootstrap_do_d558dab27285$
BEGIN
  EXECUTE $bootstrap_sql_d558dab27285$
