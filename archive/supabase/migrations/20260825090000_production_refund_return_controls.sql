-- Production return/refund controls.
ALTER TABLE public.pos_sale_returns
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'approved'
    CHECK (status IN ('pending', 'approved', 'rejected', 'processed')),
  ADD COLUMN IF NOT EXISTS refund_fee numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS processed_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text$bootstrap_sql_6d7fdeb68b4e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d7fdeb68b4e$;

DO $bootstrap_do_44e17a0322d5$
BEGIN
  EXECUTE $bootstrap_sql_44e17a0322d5$CREATE INDEX IF NOT EXISTS idx_pos_sale_returns_status
  ON public.pos_sale_returns(tenant_id, outlet_id, status, created_at DESC)$bootstrap_sql_44e17a0322d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44e17a0322d5$;

DO $bootstrap_do_41ec4cd5b2b0$
BEGIN
  EXECUTE $bootstrap_sql_41ec4cd5b2b0$CREATE OR REPLACE FUNCTION public.request_pos_sale_return(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_sale_id uuid,
  p_reason text,
  p_refund_method text,
  p_restock boolean,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
  v_return_id uuid;
  v_return_number text;
  v_item jsonb;
  v_sale_item public.pos_sale_items%ROWTYPE;
  v_qty numeric;
  v_refunded numeric;
  v_total numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id)
     OR p_sale_id IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR p_refund_method NOT IN ('cash', 'store_credit') THEN
    RAISE EXCEPTION 'Invalid return request' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_sale FROM public.pos_sales
  WHERE id = p_sale_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_sale.status <> 'completed' THEN
    RAISE EXCEPTION 'Sale is not eligible for return' USING ERRCODE = '55000';
  END IF;

  v_return_number := 'RTN-' || to_char(clock_timestamp(), 'YYMMDDHH24MISSMS');
  INSERT INTO public.pos_sale_returns(
    tenant_id, sale_id, outlet_id, return_number, reason, refund_method,
    total_refund, restock, created_by, status
  ) VALUES (
    p_tenant_id, p_sale_id, p_outlet_id, v_return_number, NULLIF(trim(p_reason), ''),
    p_refund_method, 0, COALESCE(p_restock, true), auth.uid(), 'pending'
  ) RETURNING id INTO v_return_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF NULLIF(v_item->>'sale_item_id', '') IS NULL
       OR (v_item->>'qty')::numeric <= 0 THEN
      RAISE EXCEPTION 'Invalid return item' USING ERRCODE = '22023';
    END IF;
    v_qty := (v_item->>'qty')::numeric;
    SELECT * INTO v_sale_item FROM public.pos_sale_items
    WHERE id = (v_item->>'sale_item_id')::uuid AND sale_id = p_sale_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sale item not found' USING ERRCODE = 'P0002'; END IF;
    SELECT COALESCE(SUM(qty), 0) INTO v_refunded
    FROM public.pos_sale_return_items ri
    JOIN public.pos_sale_returns r ON r.id = ri.return_id
    WHERE ri.sale_item_id = v_sale_item.id AND r.status IN ('pending', 'approved', 'processed');
    IF v_refunded + v_qty > v_sale_item.qty THEN
      RAISE EXCEPTION 'Return quantity exceeds sold quantity' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.pos_sale_return_items(return_id, sale_item_id, product_id, product_name, qty, price, subtotal)
    VALUES (v_return_id, v_sale_item.id, v_sale_item.product_id, v_sale_item.product_name, v_qty, v_sale_item.price, v_qty * v_sale_item.price);
    v_total := v_total + v_qty * v_sale_item.price;
  END LOOP;

  UPDATE public.pos_sale_returns SET total_refund = v_total WHERE id = v_return_id;
  RETURN jsonb_build_object('return_id', v_return_id, 'return_number', v_return_number, 'status', 'pending', 'total_refund', v_total);
END;
$$$bootstrap_sql_41ec4cd5b2b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41ec4cd5b2b0$;

DO $bootstrap_do_d0a2efb63d1e$
BEGIN
  EXECUTE $bootstrap_sql_d0a2efb63d1e$CREATE OR REPLACE FUNCTION public.approve_pos_sale_return(
  p_return_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_return public.pos_sale_returns%ROWTYPE;
  v_item record;
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
BEGIN
  IF auth.uid() IS NULL OR p_return_id IS NULL THEN
    RAISE EXCEPTION 'Invalid return approval' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_return FROM public.pos_sale_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND OR NOT public.pos_user_can_access_outlet(v_return.tenant_id, v_return.outlet_id) THEN
    RAISE EXCEPTION 'Return access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_return.tenant_id AND t.user_id = auth.uid()
  )) THEN
    RAISE EXCEPTION 'Return approval requires supervisor access' USING ERRCODE = '42501';
  END IF;
  IF v_return.status <> 'pending' THEN
    RAISE EXCEPTION 'Return is already processed' USING ERRCODE = '55000';
  END IF;
  IF NOT p_approve THEN
    UPDATE public.pos_sale_returns
    SET status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = NULLIF(trim(p_rejection_reason), '')
    WHERE id = p_return_id;
    RETURN jsonb_build_object('return_id', p_return_id, 'status', 'rejected');
  END IF;

  IF v_return.restock THEN
    FOR v_item IN SELECT * FROM public.pos_sale_return_items WHERE return_id = p_return_id LOOP
      SELECT * INTO v_stock FROM public.pos_stock
      WHERE tenant_id = v_return.tenant_id AND outlet_id = v_return.outlet_id
        AND product_id = v_item.product_id
        AND variant_id IS NOT DISTINCT FROM v_item.variant_id
      FOR UPDATE;
      IF FOUND THEN
        v_after := v_stock.quantity + v_item.qty;
        UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
        INSERT INTO public.pos_stock_mutations(
          tenant_id, product_id, variant_id, outlet_id, type, quantity,
          quantity_before, quantity_after, reference_id, reference_type, notes, created_by
        ) VALUES (
          v_return.tenant_id, v_item.product_id, v_stock.variant_id, v_return.outlet_id, 'return_sale',
          v_item.qty, v_stock.quantity, v_after, p_return_id, 'pos_sale_return', 'Approved sale return', auth.uid()
        );
      END IF;
    END LOOP;
  END IF;

  UPDATE public.pos_sale_returns
  SET status = 'processed', approved_by = auth.uid(), approved_at = now(), processed_at = now()
  WHERE id = p_return_id;
  RETURN jsonb_build_object('return_id', p_return_id, 'status', 'processed', 'total_refund', v_return.total_refund);
END;
$$$bootstrap_sql_d0a2efb63d1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d0a2efb63d1e$;

DO $bootstrap_do_08ab50bd950d$
BEGIN
  EXECUTE $bootstrap_sql_08ab50bd950d$REVOKE ALL ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) FROM PUBLIC, anon$bootstrap_sql_08ab50bd950d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08ab50bd950d$;

DO $bootstrap_do_337e9329fe49$
BEGIN
  EXECUTE $bootstrap_sql_337e9329fe49$REVOKE ALL ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_337e9329fe49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_337e9329fe49$;

DO $bootstrap_do_99cf8ebf75b9$
BEGIN
  EXECUTE $bootstrap_sql_99cf8ebf75b9$GRANT EXECUTE ON FUNCTION public.request_pos_sale_return(uuid, uuid, uuid, text, text, boolean, jsonb) TO authenticated$bootstrap_sql_99cf8ebf75b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99cf8ebf75b9$;

DO $bootstrap_do_6f712854c00b$
BEGIN
  EXECUTE $bootstrap_sql_6f712854c00b$GRANT EXECUTE ON FUNCTION public.approve_pos_sale_return(uuid, boolean, text) TO authenticated$bootstrap_sql_6f712854c00b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f712854c00b$;

DO $bootstrap_do_5ff4303b46bf$
BEGIN
  EXECUTE $bootstrap_sql_5ff4303b46bf$
