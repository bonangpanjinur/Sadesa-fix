-- P1 inventory ledger and cashier-session hardening.

ALTER TABLE public.pos_sales
  ADD COLUMN IF NOT EXISTS cash_session_id uuid REFERENCES public.pos_cash_sessions(id) ON DELETE SET NULL$bootstrap_sql_3c5e95bfc443$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c5e95bfc443$;

DO $bootstrap_do_5d006af57992$
BEGIN
  EXECUTE $bootstrap_sql_5d006af57992$CREATE INDEX IF NOT EXISTS idx_pos_sales_cash_session
  ON public.pos_sales(cash_session_id, created_at DESC)$bootstrap_sql_5d006af57992$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d006af57992$;

DO $bootstrap_do_4292a6fa0e56$
BEGIN
  EXECUTE $bootstrap_sql_4292a6fa0e56$CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_cash_session_per_cashier_outlet
  ON public.pos_cash_sessions(tenant_id, outlet_id, cashier_id)
  WHERE status = 'open' AND cashier_id IS NOT NULL$bootstrap_sql_4292a6fa0e56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4292a6fa0e56$;

DO $bootstrap_do_ac624cb8486d$
BEGIN
  EXECUTE $bootstrap_sql_ac624cb8486d$CREATE OR REPLACE FUNCTION public.assign_pos_sale_cash_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cash_session_id IS NULL THEN
    SELECT id INTO NEW.cash_session_id
    FROM public.pos_cash_sessions
    WHERE tenant_id = NEW.tenant_id
      AND outlet_id = NEW.outlet_id
      AND cashier_id = NEW.cashier_id
      AND status = 'open'
    ORDER BY opened_at DESC
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_ac624cb8486d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ac624cb8486d$;

DO $bootstrap_do_8b1fd898e080$
BEGIN
  EXECUTE $bootstrap_sql_8b1fd898e080$DROP TRIGGER IF EXISTS assign_pos_sale_cash_session ON public.pos_sales$bootstrap_sql_8b1fd898e080$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b1fd898e080$;

DO $bootstrap_do_fbc2916ad332$
BEGIN
  EXECUTE $bootstrap_sql_fbc2916ad332$CREATE TRIGGER assign_pos_sale_cash_session
  BEFORE INSERT ON public.pos_sales
  FOR EACH ROW EXECUTE FUNCTION public.assign_pos_sale_cash_session()$bootstrap_sql_fbc2916ad332$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbc2916ad332$;

DO $bootstrap_do_5703f9e6c551$
BEGIN
  EXECUTE $bootstrap_sql_5703f9e6c551$CREATE OR REPLACE FUNCTION public.open_cash_session(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_cashier_id uuid,
  p_cashier_name text,
  p_opening_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_session public.pos_cash_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_cashier_id THEN
    RAISE EXCEPTION 'Cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;
  IF p_opening_balance IS NULL OR p_opening_balance < 0 THEN
    RAISE EXCEPTION 'Invalid opening balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pos_cash_sessions(
    tenant_id, outlet_id, cashier_id, cashier_name, session_number,
    status, opening_balance, cash_sales_total, non_cash_sales_total,
    cash_in_total, cash_out_total, notes_open
  ) VALUES (
    p_tenant_id, p_outlet_id, p_cashier_id, COALESCE(NULLIF(trim(p_cashier_name), ''), 'Kasir'),
    'KAS-' || to_char(now(), 'YYMMDD-HH24MISS') || '-' || substr(p_cashier_id::text, 1, 6),
    'open', p_opening_balance, 0, 0, 0, 0, NULLIF(trim(p_notes), '')
  ) RETURNING * INTO v_session;

  RETURN jsonb_build_object('session_id', v_session.id, 'session_number', v_session.session_number, 'status', v_session.status);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Cashier already has an open session for this outlet' USING ERRCODE = '23505';
END;
$$$bootstrap_sql_5703f9e6c551$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5703f9e6c551$;

DO $bootstrap_do_425aa7adcd47$
BEGIN
  EXECUTE $bootstrap_sql_425aa7adcd47$CREATE OR REPLACE FUNCTION public.record_cash_mutation(
  p_session_id uuid,
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_type text,
  p_category text,
  p_amount numeric,
  p_description text,
  p_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_mutation_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_type NOT IN ('in', 'out') OR NULLIF(trim(p_description), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid cash mutation' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session FROM public.pos_cash_sessions
  WHERE id = p_session_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.pos_cash_mutations(
    tenant_id, outlet_id, cash_session_id, type, category, amount, description, reference, created_by
  ) VALUES (
    p_tenant_id, p_outlet_id, p_session_id, p_type, COALESCE(NULLIF(trim(p_category), ''), 'other'),
    p_amount, trim(p_description), NULLIF(trim(p_reference), ''), auth.uid()
  ) RETURNING id INTO v_mutation_id;

  IF p_type = 'in' THEN
    UPDATE public.pos_cash_sessions SET cash_in_total = COALESCE(cash_in_total, 0) + p_amount WHERE id = p_session_id;
  ELSE
    UPDATE public.pos_cash_sessions SET cash_out_total = COALESCE(cash_out_total, 0) + p_amount WHERE id = p_session_id;
  END IF;
  RETURN jsonb_build_object('mutation_id', v_mutation_id, 'session_id', p_session_id);
END;
$$$bootstrap_sql_425aa7adcd47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_425aa7adcd47$;

DO $bootstrap_do_1aa2443ff687$
BEGIN
  EXECUTE $bootstrap_sql_1aa2443ff687$CREATE OR REPLACE FUNCTION public.close_cash_session(
  p_session_id uuid,
  p_closing_balance numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.pos_cash_sessions%ROWTYPE;
  v_cash_sales numeric := 0;
  v_non_cash_sales numeric := 0;
  v_cash_in numeric := 0;
  v_cash_out numeric := 0;
  v_expected numeric;
  v_difference numeric;
BEGIN
  IF auth.uid() IS NULL OR p_closing_balance IS NULL OR p_closing_balance < 0 THEN
    RAISE EXCEPTION 'Invalid closing balance' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_session FROM public.pos_cash_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'open' THEN
    RAISE EXCEPTION 'Cash session is not open' USING ERRCODE = '55000';
  END IF;
  IF v_session.cashier_id <> auth.uid() AND NOT EXISTS (
    SELECT 1 FROM public.pos_tenants t WHERE t.id = v_session.tenant_id AND t.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Cash session access denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(CASE WHEN payment_method = 'cash' THEN total ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN payment_method <> 'cash' THEN total ELSE 0 END), 0)
  INTO v_cash_sales, v_non_cash_sales
  FROM public.pos_sales
  WHERE cash_session_id = p_session_id AND status = 'completed';

  SELECT COALESCE(SUM(CASE WHEN type = 'in' THEN amount ELSE 0 END), 0),
         COALESCE(SUM(CASE WHEN type = 'out' THEN amount ELSE 0 END), 0)
  INTO v_cash_in, v_cash_out
  FROM public.pos_cash_mutations
  WHERE cash_session_id = p_session_id;

  v_expected := v_session.opening_balance + v_cash_sales + v_cash_in - v_cash_out;
  v_difference := p_closing_balance - v_expected;

  UPDATE public.pos_cash_sessions
  SET status = 'closed', closing_balance = p_closing_balance, expected_balance = v_expected,
      difference = v_difference, cash_sales_total = v_cash_sales,
      non_cash_sales_total = v_non_cash_sales, cash_in_total = v_cash_in,
      cash_out_total = v_cash_out, notes_close = NULLIF(trim(p_notes), ''), closed_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'session_id', p_session_id, 'expected_balance', v_expected,
    'closing_balance', p_closing_balance, 'difference', v_difference,
    'cash_sales_total', v_cash_sales, 'non_cash_sales_total', v_non_cash_sales,
    'cash_in_total', v_cash_in, 'cash_out_total', v_cash_out
  );
END;
$$$bootstrap_sql_1aa2443ff687$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1aa2443ff687$;

DO $bootstrap_do_099ab5177969$
BEGIN
  EXECUTE $bootstrap_sql_099ab5177969$CREATE OR REPLACE FUNCTION public.adjust_pos_stock(
  p_stock_id uuid,
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
  v_stock public.pos_stock%ROWTYPE;
  v_after numeric;
  v_delta numeric;
BEGIN
  IF p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('initial','purchase','adjustment','return_sale','transfer_in','transfer_out') THEN
    RAISE EXCEPTION 'Invalid stock adjustment' USING ERRCODE = '22023';
  END IF;
  IF NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'POS outlet access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_stock FROM public.pos_stock
  WHERE id = p_stock_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock row not found' USING ERRCODE = 'P0002'; END IF;

  v_after := CASE WHEN p_type = 'adjustment' THEN p_quantity ELSE
    CASE WHEN p_type IN ('purchase','return_sale','transfer_in','initial')
      THEN v_stock.quantity + p_quantity ELSE v_stock.quantity - p_quantity END END;
  IF v_after < 0 THEN RAISE EXCEPTION 'Insufficient stock' USING ERRCODE = '23514'; END IF;
  v_delta := v_after - v_stock.quantity;

  UPDATE public.pos_stock SET quantity = v_after, updated_at = now() WHERE id = v_stock.id;
  INSERT INTO public.pos_stock_mutations(
    tenant_id, product_id, variant_id, outlet_id, type, quantity,
    quantity_before, quantity_after, notes, created_by
  ) VALUES (
    p_tenant_id, v_stock.product_id, v_stock.variant_id, p_outlet_id, p_type,
    v_delta, v_stock.quantity, v_after, NULLIF(trim(p_notes), ''), auth.uid()
  );
  RETURN jsonb_build_object('stock_id', v_stock.id, 'quantity_before', v_stock.quantity, 'quantity_after', v_after, 'delta', v_delta);
END;
$$$bootstrap_sql_099ab5177969$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_099ab5177969$;

DO $bootstrap_do_db0508e1d8ff$
BEGIN
  EXECUTE $bootstrap_sql_db0508e1d8ff$REVOKE ALL ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon$bootstrap_sql_db0508e1d8ff$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db0508e1d8ff$;

DO $bootstrap_do_dcf78bdf569f$
BEGIN
  EXECUTE $bootstrap_sql_dcf78bdf569f$REVOKE ALL ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) FROM PUBLIC, anon$bootstrap_sql_dcf78bdf569f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dcf78bdf569f$;

DO $bootstrap_do_c4fc63884c8b$
BEGIN
  EXECUTE $bootstrap_sql_c4fc63884c8b$REVOKE ALL ON FUNCTION public.close_cash_session(uuid, numeric, text) FROM PUBLIC, anon$bootstrap_sql_c4fc63884c8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c4fc63884c8b$;

DO $bootstrap_do_0aa05bf2cb63$
BEGIN
  EXECUTE $bootstrap_sql_0aa05bf2cb63$REVOKE ALL ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) FROM PUBLIC, anon$bootstrap_sql_0aa05bf2cb63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0aa05bf2cb63$;

DO $bootstrap_do_41f78e214e3d$
BEGIN
  EXECUTE $bootstrap_sql_41f78e214e3d$GRANT EXECUTE ON FUNCTION public.open_cash_session(uuid, uuid, uuid, text, numeric, text) TO authenticated$bootstrap_sql_41f78e214e3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41f78e214e3d$;

DO $bootstrap_do_607ea0bf76ef$
BEGIN
  EXECUTE $bootstrap_sql_607ea0bf76ef$GRANT EXECUTE ON FUNCTION public.record_cash_mutation(uuid, uuid, uuid, text, text, numeric, text, text) TO authenticated$bootstrap_sql_607ea0bf76ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_607ea0bf76ef$;

DO $bootstrap_do_2d7c282246c1$
BEGIN
  EXECUTE $bootstrap_sql_2d7c282246c1$GRANT EXECUTE ON FUNCTION public.close_cash_session(uuid, numeric, text) TO authenticated$bootstrap_sql_2d7c282246c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d7c282246c1$;

DO $bootstrap_do_8a54ef53e7ce$
BEGIN
  EXECUTE $bootstrap_sql_8a54ef53e7ce$GRANT EXECUTE ON FUNCTION public.adjust_pos_stock(uuid, uuid, uuid, text, numeric, text) TO authenticated$bootstrap_sql_8a54ef53e7ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a54ef53e7ce$;

DO $bootstrap_do_1f9a0ad229bb$
BEGIN
  EXECUTE $bootstrap_sql_1f9a0ad229bb$
