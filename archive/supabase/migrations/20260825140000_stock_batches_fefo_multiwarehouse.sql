CREATE TABLE IF NOT EXISTS public.pos_warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid REFERENCES public.pos_outlets(id) ON DELETE SET NULL,
  name text NOT NULL,
  code text NOT NULL,
  warehouse_type text NOT NULL DEFAULT 'warehouse' CHECK (warehouse_type IN ('warehouse','outlet','vehicle','transit')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
)$bootstrap_sql_52250dfab36f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52250dfab36f$;

DO $bootstrap_do_b97307bfc3ea$
BEGIN
  EXECUTE $bootstrap_sql_b97307bfc3ea$ALTER TABLE public.pos_stock ADD COLUMN IF NOT EXISTS warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL$bootstrap_sql_b97307bfc3ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b97307bfc3ea$;

DO $bootstrap_do_7b4f4ae8e3d5$
BEGIN
  EXECUTE $bootstrap_sql_7b4f4ae8e3d5$CREATE TABLE IF NOT EXISTS public.pos_stock_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES public.pos_warehouses(id) ON DELETE SET NULL,
  stock_id uuid REFERENCES public.pos_stock(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.pos_product_variants(id) ON DELETE SET NULL,
  batch_number text NOT NULL,
  expiry_date date,
  quantity numeric(15,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit_cost numeric(15,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, outlet_id, product_id, variant_id, batch_number)
)$bootstrap_sql_7b4f4ae8e3d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b4f4ae8e3d5$;

DO $bootstrap_do_e2f4b0b9765e$
BEGIN
  EXECUTE $bootstrap_sql_e2f4b0b9765e$CREATE INDEX IF NOT EXISTS idx_pos_stock_batches_fefo
  ON public.pos_stock_batches(tenant_id, outlet_id, product_id, variant_id, expiry_date NULLS LAST, received_at)$bootstrap_sql_e2f4b0b9765e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e2f4b0b9765e$;

DO $bootstrap_do_39d4d87d80bd$
BEGIN
  EXECUTE $bootstrap_sql_39d4d87d80bd$ALTER TABLE public.pos_warehouses ENABLE ROW LEVEL SECURITY$bootstrap_sql_39d4d87d80bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39d4d87d80bd$;

DO $bootstrap_do_181eafc5a27c$
BEGIN
  EXECUTE $bootstrap_sql_181eafc5a27c$ALTER TABLE public.pos_stock_batches ENABLE ROW LEVEL SECURITY$bootstrap_sql_181eafc5a27c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_181eafc5a27c$;

DO $bootstrap_do_ca3c12b8a90a$
BEGIN
  EXECUTE $bootstrap_sql_ca3c12b8a90a$DROP POLICY IF EXISTS "POS users view warehouses" ON public.pos_warehouses$bootstrap_sql_ca3c12b8a90a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca3c12b8a90a$;

DO $bootstrap_do_059393fa3003$
BEGIN
  EXECUTE $bootstrap_sql_059393fa3003$CREATE POLICY "POS users view warehouses" ON public.pos_warehouses FOR SELECT TO authenticated
  USING (tenant_id IN (SELECT tenant_id FROM public.pos_users WHERE user_id = auth.uid() AND is_active = true) OR tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_059393fa3003$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_059393fa3003$;

DO $bootstrap_do_091a607f902a$
BEGIN
  EXECUTE $bootstrap_sql_091a607f902a$DROP POLICY IF EXISTS "Tenant owners manage warehouses" ON public.pos_warehouses$bootstrap_sql_091a607f902a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_091a607f902a$;

DO $bootstrap_do_9cecc273ed15$
BEGIN
  EXECUTE $bootstrap_sql_9cecc273ed15$CREATE POLICY "Tenant owners manage warehouses" ON public.pos_warehouses FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_9cecc273ed15$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cecc273ed15$;

DO $bootstrap_do_95dbddae9d2b$
BEGIN
  EXECUTE $bootstrap_sql_95dbddae9d2b$DROP POLICY IF EXISTS "POS users view stock batches" ON public.pos_stock_batches$bootstrap_sql_95dbddae9d2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95dbddae9d2b$;

DO $bootstrap_do_a771393d2a6a$
BEGIN
  EXECUTE $bootstrap_sql_a771393d2a6a$CREATE POLICY "POS users view stock batches" ON public.pos_stock_batches FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_a771393d2a6a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a771393d2a6a$;

DO $bootstrap_do_1d8738c3b16e$
BEGIN
  EXECUTE $bootstrap_sql_1d8738c3b16e$DROP POLICY IF EXISTS "Tenant owners manage stock batches" ON public.pos_stock_batches$bootstrap_sql_1d8738c3b16e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d8738c3b16e$;

DO $bootstrap_do_533bc4214b33$
BEGIN
  EXECUTE $bootstrap_sql_533bc4214b33$CREATE POLICY "Tenant owners manage stock batches" ON public.pos_stock_batches FOR ALL TO authenticated
  USING (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid()))$bootstrap_sql_533bc4214b33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_533bc4214b33$;

DO $bootstrap_do_e391f78d47c5$
BEGIN
  EXECUTE $bootstrap_sql_e391f78d47c5$CREATE OR REPLACE FUNCTION public.consume_pos_stock_fefo(
  p_tenant_id uuid, p_outlet_id uuid, p_product_id uuid, p_variant_id uuid, p_quantity numeric, p_reference_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_remaining numeric := p_quantity; v_batch record; v_take numeric; v_consumed numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid FEFO consumption request' USING ERRCODE = '42501';
  END IF;
  FOR v_batch IN SELECT * FROM public.pos_stock_batches
    WHERE tenant_id = p_tenant_id AND outlet_id = p_outlet_id AND product_id = p_product_id
      AND variant_id IS NOT DISTINCT FROM p_variant_id AND quantity > 0
    ORDER BY expiry_date NULLS LAST, received_at, id FOR UPDATE LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_remaining, v_batch.quantity);
    UPDATE public.pos_stock_batches SET quantity = quantity - v_take WHERE id = v_batch.id;
    v_remaining := v_remaining - v_take;
    v_consumed := v_consumed + v_take;
  END LOOP;
  IF v_remaining > 0 THEN RAISE EXCEPTION 'Insufficient FEFO batch stock' USING ERRCODE = '23514'; END IF;
  RETURN jsonb_build_object('product_id', p_product_id, 'consumed', v_consumed, 'remaining', v_remaining, 'reference_id', p_reference_id);
END; $$$bootstrap_sql_e391f78d47c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e391f78d47c5$;

DO $bootstrap_do_9ca1d744cfa8$
BEGIN
  EXECUTE $bootstrap_sql_9ca1d744cfa8$REVOKE ALL ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) FROM PUBLIC, anon$bootstrap_sql_9ca1d744cfa8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ca1d744cfa8$;

DO $bootstrap_do_ed2796bbf20e$
BEGIN
  EXECUTE $bootstrap_sql_ed2796bbf20e$GRANT EXECUTE ON FUNCTION public.consume_pos_stock_fefo(uuid, uuid, uuid, uuid, numeric, uuid) TO authenticated$bootstrap_sql_ed2796bbf20e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed2796bbf20e$;

DO $bootstrap_do_a6381b343b4d$
BEGIN
  EXECUTE $bootstrap_sql_a6381b343b4d$
