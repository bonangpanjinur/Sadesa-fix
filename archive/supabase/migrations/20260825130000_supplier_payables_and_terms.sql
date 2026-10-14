ALTER TABLE public.pos_purchase_orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid','partial','paid','overdue')),
  ADD COLUMN IF NOT EXISTS payment_terms_days integer NOT NULL DEFAULT 0 CHECK (payment_terms_days >= 0),
  ADD COLUMN IF NOT EXISTS due_date date,
  ADD COLUMN IF NOT EXISTS amount_due numeric(15,2) NOT NULL DEFAULT 0$bootstrap_sql_9f92ac2d81b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f92ac2d81b4$;

DO $bootstrap_do_ca9a28ac0634$
BEGIN
  EXECUTE $bootstrap_sql_ca9a28ac0634$UPDATE public.pos_purchase_orders
SET amount_due = GREATEST(0, total - amount_paid),
    due_date = COALESCE(due_date, order_date + payment_terms_days),
    payment_status = CASE WHEN amount_paid >= total AND total > 0 THEN 'paid' WHEN amount_paid > 0 THEN 'partial' ELSE 'unpaid' END
WHERE amount_due = 0 OR due_date IS NULL$bootstrap_sql_ca9a28ac0634$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca9a28ac0634$;

DO $bootstrap_do_7aaf3d3227de$
BEGIN
  EXECUTE $bootstrap_sql_7aaf3d3227de$CREATE TABLE IF NOT EXISTS public.pos_supplier_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  purchase_order_id uuid NOT NULL REFERENCES public.pos_purchase_orders(id) ON DELETE RESTRICT,
  supplier_id uuid REFERENCES public.pos_suppliers(id) ON DELETE SET NULL,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash','transfer','debit','credit','other')),
  reference text,
  notes text,
  paid_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_7aaf3d3227de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7aaf3d3227de$;

DO $bootstrap_do_683775f46515$
BEGIN
  EXECUTE $bootstrap_sql_683775f46515$CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_po ON public.pos_supplier_payments(purchase_order_id, paid_at DESC)$bootstrap_sql_683775f46515$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_683775f46515$;

DO $bootstrap_do_8a652630c972$
BEGIN
  EXECUTE $bootstrap_sql_8a652630c972$CREATE INDEX IF NOT EXISTS idx_pos_supplier_payments_supplier ON public.pos_supplier_payments(tenant_id, supplier_id, paid_at DESC)$bootstrap_sql_8a652630c972$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a652630c972$;

DO $bootstrap_do_1876ced3b149$
BEGIN
  EXECUTE $bootstrap_sql_1876ced3b149$ALTER TABLE public.pos_supplier_payments ENABLE ROW LEVEL SECURITY$bootstrap_sql_1876ced3b149$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1876ced3b149$;

DO $bootstrap_do_817309a46a2e$
BEGIN
  EXECUTE $bootstrap_sql_817309a46a2e$DROP POLICY IF EXISTS "POS users view supplier payments" ON public.pos_supplier_payments$bootstrap_sql_817309a46a2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_817309a46a2e$;

DO $bootstrap_do_3f1920be35e9$
BEGIN
  EXECUTE $bootstrap_sql_3f1920be35e9$CREATE POLICY "POS users view supplier payments" ON public.pos_supplier_payments FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_3f1920be35e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f1920be35e9$;

DO $bootstrap_do_426120c34bed$
BEGIN
  EXECUTE $bootstrap_sql_426120c34bed$DROP POLICY IF EXISTS "POS users create supplier payments" ON public.pos_supplier_payments$bootstrap_sql_426120c34bed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_426120c34bed$;

DO $bootstrap_do_00949d19802b$
BEGIN
  EXECUTE $bootstrap_sql_00949d19802b$CREATE POLICY "POS users create supplier payments" ON public.pos_supplier_payments FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_00949d19802b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00949d19802b$;

DO $bootstrap_do_cadc7b1fab11$
BEGIN
  EXECUTE $bootstrap_sql_cadc7b1fab11$CREATE OR REPLACE FUNCTION public.record_supplier_payment(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_purchase_order_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.pos_purchase_orders%ROWTYPE;
  v_payment_id uuid;
  v_new_paid numeric;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR p_amount IS NULL OR p_amount <= 0
     OR p_payment_method NOT IN ('cash','transfer','debit','credit','other')
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid supplier payment' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_po FROM public.pos_purchase_orders
  WHERE id = p_purchase_order_id AND tenant_id = p_tenant_id AND outlet_id = p_outlet_id FOR UPDATE;
  IF NOT FOUND OR v_po.status = 'cancelled' THEN RAISE EXCEPTION 'Purchase order is not payable' USING ERRCODE = '55000'; END IF;
  IF p_amount > GREATEST(0, v_po.total - v_po.amount_paid) THEN RAISE EXCEPTION 'Payment exceeds outstanding balance' USING ERRCODE = '23514'; END IF;
  INSERT INTO public.pos_supplier_payments(tenant_id, outlet_id, purchase_order_id, supplier_id, amount, payment_method, reference, notes, created_by)
  VALUES (p_tenant_id, p_outlet_id, p_purchase_order_id, v_po.supplier_id, p_amount, p_payment_method, NULLIF(trim(p_reference), ''), NULLIF(trim(p_notes), ''), auth.uid())
  RETURNING id INTO v_payment_id;
  v_new_paid := v_po.amount_paid + p_amount;
  v_status := CASE WHEN v_new_paid >= v_po.total THEN 'paid' WHEN v_new_paid > 0 THEN 'partial' ELSE 'unpaid' END;
  UPDATE public.pos_purchase_orders
  SET amount_paid = v_new_paid, amount_due = GREATEST(0, total - v_new_paid), payment_status = v_status, updated_by = auth.uid(), updated_at = now()
  WHERE id = v_po.id;
  RETURN jsonb_build_object('payment_id', v_payment_id, 'purchase_order_id', v_po.id, 'amount_paid', v_new_paid, 'amount_due', GREATEST(0, v_po.total - v_new_paid), 'payment_status', v_status);
END; $$$bootstrap_sql_cadc7b1fab11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cadc7b1fab11$;

DO $bootstrap_do_1dcd9948a8d5$
BEGIN
  EXECUTE $bootstrap_sql_1dcd9948a8d5$REVOKE ALL ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) FROM PUBLIC, anon$bootstrap_sql_1dcd9948a8d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1dcd9948a8d5$;

DO $bootstrap_do_517a6a5119b9$
BEGIN
  EXECUTE $bootstrap_sql_517a6a5119b9$GRANT EXECUTE ON FUNCTION public.record_supplier_payment(uuid, uuid, uuid, numeric, text, text, text) TO authenticated$bootstrap_sql_517a6a5119b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_517a6a5119b9$;

DO $bootstrap_do_52250dfab36f$
BEGIN
  EXECUTE $bootstrap_sql_52250dfab36f$
