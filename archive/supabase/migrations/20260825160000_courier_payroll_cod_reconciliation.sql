CREATE TABLE IF NOT EXISTS public.courier_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  base_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (base_amount >= 0),
  per_km_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (per_km_amount >= 0),
  bonus_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (bonus_amount >= 0),
  penalty_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (penalty_amount >= 0),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_bf6570997cd5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf6570997cd5$;

DO $bootstrap_do_27dc15ca657e$
BEGIN
  EXECUTE $bootstrap_sql_27dc15ca657e$ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS distance_km numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS base_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS penalty_amount numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rule_id uuid REFERENCES public.courier_commission_rules(id),
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz$bootstrap_sql_27dc15ca657e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27dc15ca657e$;

DO $bootstrap_do_e3d917bc0d34$
BEGIN
  EXECUTE $bootstrap_sql_e3d917bc0d34$CREATE TABLE IF NOT EXISTS public.courier_cod_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  expected_cash numeric(15,2) NOT NULL CHECK (expected_cash >= 0),
  collected_cash numeric(15,2) NOT NULL CHECK (collected_cash >= 0),
  variance numeric(15,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','matched','shortage','overage','approved','disputed')),
  proof_url text,
  notes text,
  submitted_by uuid REFERENCES auth.users(id),
  reviewed_by uuid REFERENCES auth.users(id),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  UNIQUE(courier_id, order_id)
)$bootstrap_sql_e3d917bc0d34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e3d917bc0d34$;

DO $bootstrap_do_4dd5bd6959e7$
BEGIN
  EXECUTE $bootstrap_sql_4dd5bd6959e7$CREATE INDEX IF NOT EXISTS idx_courier_cod_status ON public.courier_cod_reconciliations(courier_id, status, submitted_at DESC)$bootstrap_sql_4dd5bd6959e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dd5bd6959e7$;

DO $bootstrap_do_8c19b569de35$
BEGIN
  EXECUTE $bootstrap_sql_8c19b569de35$ALTER TABLE public.courier_commission_rules ENABLE ROW LEVEL SECURITY$bootstrap_sql_8c19b569de35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c19b569de35$;

DO $bootstrap_do_394b60a8dd74$
BEGIN
  EXECUTE $bootstrap_sql_394b60a8dd74$ALTER TABLE public.courier_cod_reconciliations ENABLE ROW LEVEL SECURITY$bootstrap_sql_394b60a8dd74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_394b60a8dd74$;

DO $bootstrap_do_3de236fedd56$
BEGIN
  EXECUTE $bootstrap_sql_3de236fedd56$DROP POLICY IF EXISTS "Admins manage courier commission rules" ON public.courier_commission_rules$bootstrap_sql_3de236fedd56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3de236fedd56$;

DO $bootstrap_do_bdb16c7511df$
BEGIN
  EXECUTE $bootstrap_sql_bdb16c7511df$CREATE POLICY "Admins manage courier commission rules" ON public.courier_commission_rules FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_bdb16c7511df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdb16c7511df$;

DO $bootstrap_do_40ab4bb7d8a6$
BEGIN
  EXECUTE $bootstrap_sql_40ab4bb7d8a6$DROP POLICY IF EXISTS "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations$bootstrap_sql_40ab4bb7d8a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40ab4bb7d8a6$;

DO $bootstrap_do_87ec02311652$
BEGIN
  EXECUTE $bootstrap_sql_87ec02311652$CREATE POLICY "Couriers view own COD reconciliation" ON public.courier_cod_reconciliations FOR SELECT TO authenticated
  USING (courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_87ec02311652$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_87ec02311652$;

DO $bootstrap_do_f88f0f808bb4$
BEGIN
  EXECUTE $bootstrap_sql_f88f0f808bb4$DROP POLICY IF EXISTS "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations$bootstrap_sql_f88f0f808bb4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f88f0f808bb4$;

DO $bootstrap_do_74b3c352c728$
BEGIN
  EXECUTE $bootstrap_sql_74b3c352c728$CREATE POLICY "Couriers submit own COD reconciliation" ON public.courier_cod_reconciliations FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid() AND courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()))$bootstrap_sql_74b3c352c728$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_74b3c352c728$;

DO $bootstrap_do_198e75811f5f$
BEGIN
  EXECUTE $bootstrap_sql_198e75811f5f$DROP POLICY IF EXISTS "Admins manage COD reconciliation" ON public.courier_cod_reconciliations$bootstrap_sql_198e75811f5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_198e75811f5f$;

DO $bootstrap_do_280dd971954b$
BEGIN
  EXECUTE $bootstrap_sql_280dd971954b$CREATE POLICY "Admins manage COD reconciliation" ON public.courier_cod_reconciliations FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_280dd971954b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_280dd971954b$;

DO $bootstrap_do_8370f5a736df$
BEGIN
  EXECUTE $bootstrap_sql_8370f5a736df$CREATE OR REPLACE FUNCTION public.submit_courier_cod_reconciliation(
  p_courier_id uuid, p_order_id uuid, p_collected_cash numeric, p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_id uuid; v_expected numeric; v_variance numeric; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_courier_owner(auth.uid(), p_courier_id) OR p_collected_cash IS NULL OR p_collected_cash < 0 THEN
    RAISE EXCEPTION 'COD reconciliation access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND courier_id = p_courier_id FOR SHARE;
  IF NOT FOUND OR v_order.payment_method <> 'COD' OR v_order.status NOT IN ('DONE','DELIVERED') THEN
    RAISE EXCEPTION 'Order is not eligible for COD reconciliation' USING ERRCODE = '55000';
  END IF;
  v_expected := v_order.total + COALESCE(v_order.shipping_cost, 0);
  v_variance := p_collected_cash - v_expected;
  v_status := CASE WHEN v_variance = 0 THEN 'matched' WHEN v_variance < 0 THEN 'shortage' ELSE 'overage' END;
  INSERT INTO public.courier_cod_reconciliations(courier_id, order_id, expected_cash, collected_cash, variance, status, notes, submitted_by)
  VALUES (p_courier_id, p_order_id, v_expected, p_collected_cash, v_variance, v_status, NULLIF(trim(p_notes), ''), auth.uid())
  ON CONFLICT (courier_id, order_id) DO UPDATE SET
    collected_cash = EXCLUDED.collected_cash, variance = EXCLUDED.variance, status = EXCLUDED.status,
    notes = EXCLUDED.notes, submitted_by = auth.uid(), submitted_at = now(), reviewed_by = NULL, reviewed_at = NULL
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'expected_cash', v_expected, 'collected_cash', p_collected_cash, 'variance', v_variance, 'status', v_status);
END; $$$bootstrap_sql_8370f5a736df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8370f5a736df$;

DO $bootstrap_do_4915abcd1179$
BEGIN
  EXECUTE $bootstrap_sql_4915abcd1179$CREATE OR REPLACE FUNCTION public.review_courier_cod_reconciliation(p_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() OR p_status NOT IN ('approved','disputed') THEN
    RAISE EXCEPTION 'COD review denied' USING ERRCODE = '42501';
  END IF;
  UPDATE public.courier_cod_reconciliations SET status = p_status, notes = COALESCE(NULLIF(trim(p_notes), ''), notes), reviewed_by = auth.uid(), reviewed_at = now() WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COD reconciliation not found' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END; $$$bootstrap_sql_4915abcd1179$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4915abcd1179$;

DO $bootstrap_do_ba9078c1a17b$
BEGIN
  EXECUTE $bootstrap_sql_ba9078c1a17b$REVOKE ALL ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) FROM PUBLIC, anon$bootstrap_sql_ba9078c1a17b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba9078c1a17b$;

DO $bootstrap_do_a459289f76a2$
BEGIN
  EXECUTE $bootstrap_sql_a459289f76a2$REVOKE ALL ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) FROM PUBLIC, anon$bootstrap_sql_a459289f76a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a459289f76a2$;

DO $bootstrap_do_abbde3fafe7a$
BEGIN
  EXECUTE $bootstrap_sql_abbde3fafe7a$GRANT EXECUTE ON FUNCTION public.submit_courier_cod_reconciliation(uuid, uuid, numeric, text) TO authenticated$bootstrap_sql_abbde3fafe7a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_abbde3fafe7a$;

DO $bootstrap_do_38cf3d697180$
BEGIN
  EXECUTE $bootstrap_sql_38cf3d697180$GRANT EXECUTE ON FUNCTION public.review_courier_cod_reconciliation(uuid, text, text) TO authenticated$bootstrap_sql_38cf3d697180$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_38cf3d697180$;

DO $bootstrap_do_e807d34a5c5c$
BEGIN
  EXECUTE $bootstrap_sql_e807d34a5c5c$
