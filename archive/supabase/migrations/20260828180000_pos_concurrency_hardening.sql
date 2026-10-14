-- Concurrency hardening for POS voucher redemption, cash sessions, and returns.

CREATE OR REPLACE FUNCTION public.validate_pos_cash_session_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep service-role/batch imports compatible while enforcing browser actors.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.cashier_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cash session cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_has_role(NEW.tenant_id, ARRAY['owner', 'manager', 'kasir']::text[]) THEN
    RAISE EXCEPTION 'POS role cannot open cash session' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_c3bd64d2c3ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3bd64d2c3ec$;

DO $bootstrap_do_4dabde74ce6d$
BEGIN
  EXECUTE $bootstrap_sql_4dabde74ce6d$DROP TRIGGER IF EXISTS trg_validate_pos_cash_session_actor ON public.pos_cash_sessions$bootstrap_sql_4dabde74ce6d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4dabde74ce6d$;

DO $bootstrap_do_1f91d4260296$
BEGIN
  EXECUTE $bootstrap_sql_1f91d4260296$CREATE TRIGGER trg_validate_pos_cash_session_actor
BEFORE INSERT ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_cash_session_actor()$bootstrap_sql_1f91d4260296$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f91d4260296$;

DO $bootstrap_do_9b0144419a7b$
BEGIN
  EXECUTE $bootstrap_sql_9b0144419a7b$REVOKE ALL ON FUNCTION public.validate_pos_cash_session_actor() FROM PUBLIC, anon, authenticated$bootstrap_sql_9b0144419a7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b0144419a7b$;

DO $bootstrap_do_c6ecc9b605e9$
BEGIN
  EXECUTE $bootstrap_sql_c6ecc9b605e9$GRANT EXECUTE ON FUNCTION public.validate_pos_cash_session_actor() TO service_role$bootstrap_sql_c6ecc9b605e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6ecc9b605e9$;

DO $bootstrap_do_8eefdca48cc1$
BEGIN
  EXECUTE $bootstrap_sql_8eefdca48cc1$CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_voucher_usage_sale_once
  ON public.pos_voucher_usages(voucher_id, sale_id)
  WHERE sale_id IS NOT NULL$bootstrap_sql_8eefdca48cc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8eefdca48cc1$;

DO $bootstrap_do_92be35c5890b$
BEGIN
  EXECUTE $bootstrap_sql_92be35c5890b$DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_returns_total_refund_nonnegative') THEN
    ALTER TABLE public.pos_sale_returns ADD CONSTRAINT pos_sale_returns_total_refund_nonnegative CHECK (total_refund >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_qty_positive') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_qty_positive CHECK (qty > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_values_nonnegative') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_values_nonnegative CHECK (price >= 0 AND subtotal >= 0);
  END IF;
END;
$$$bootstrap_sql_92be35c5890b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92be35c5890b$;

DO $bootstrap_do_cf005a3f17d8$
BEGIN
  EXECUTE $bootstrap_sql_cf005a3f17d8$CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
BEGIN
  SELECT * INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id
    AND tenant_id = NEW.tenant_id
    AND outlet_id = NEW.outlet_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Return sale does not belong to tenant and outlet' USING ERRCODE = '42501';
  END IF;
  IF v_sale.status NOT IN ('completed', 'refunded', 'partially_refunded') THEN
    RAISE EXCEPTION 'Only completed POS sales can be returned' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_cf005a3f17d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf005a3f17d8$;

DO $bootstrap_do_c2c613003b1a$
BEGIN
  EXECUTE $bootstrap_sql_c2c613003b1a$DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_context ON public.pos_sale_returns$bootstrap_sql_c2c613003b1a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2c613003b1a$;

DO $bootstrap_do_6c09b5e54761$
BEGIN
  EXECUTE $bootstrap_sql_6c09b5e54761$CREATE TRIGGER trg_validate_pos_sale_return_context
BEFORE INSERT OR UPDATE OF sale_id, tenant_id, outlet_id
ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_context()$bootstrap_sql_6c09b5e54761$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c09b5e54761$;

DO $bootstrap_do_d287636d81eb$
BEGIN
  EXECUTE $bootstrap_sql_d287636d81eb$CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_item_quantity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed numeric;
  v_returned numeric;
BEGIN
  SELECT si.qty INTO v_allowed
  FROM public.pos_sale_items si
  WHERE si.id = NEW.sale_item_id
    AND si.sale_id = (SELECT sale_id FROM public.pos_sale_returns WHERE id = NEW.return_id)
  FOR UPDATE;
  IF v_allowed IS NULL THEN
    RAISE EXCEPTION 'Return item does not belong to original sale' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(ri.qty), 0) INTO v_returned
  FROM public.pos_sale_return_items ri
  WHERE ri.sale_item_id = NEW.sale_item_id
    AND ri.return_id <> NEW.return_id;
  IF NEW.qty > v_allowed - v_returned THEN
    RAISE EXCEPTION 'Return quantity exceeds purchased quantity' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_d287636d81eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d287636d81eb$;

DO $bootstrap_do_4f4483f3c864$
BEGIN
  EXECUTE $bootstrap_sql_4f4483f3c864$DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_item_quantity ON public.pos_sale_return_items$bootstrap_sql_4f4483f3c864$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f4483f3c864$;

DO $bootstrap_do_8aa1a732254d$
BEGIN
  EXECUTE $bootstrap_sql_8aa1a732254d$CREATE TRIGGER trg_validate_pos_sale_return_item_quantity
BEFORE INSERT OR UPDATE OF return_id, sale_item_id, qty
ON public.pos_sale_return_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_item_quantity()$bootstrap_sql_8aa1a732254d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8aa1a732254d$;

DO $bootstrap_do_36cac23f760e$
BEGIN
  EXECUTE $bootstrap_sql_36cac23f760e$REVOKE ALL ON FUNCTION public.validate_pos_sale_return_context() FROM PUBLIC, anon, authenticated$bootstrap_sql_36cac23f760e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36cac23f760e$;

DO $bootstrap_do_814f0e48a4dc$
BEGIN
  EXECUTE $bootstrap_sql_814f0e48a4dc$REVOKE ALL ON FUNCTION public.validate_pos_sale_return_item_quantity() FROM PUBLIC, anon, authenticated$bootstrap_sql_814f0e48a4dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_814f0e48a4dc$;

DO $bootstrap_do_eea6dd14d168$
BEGIN
  EXECUTE $bootstrap_sql_eea6dd14d168$GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_context() TO service_role$bootstrap_sql_eea6dd14d168$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eea6dd14d168$;

DO $bootstrap_do_0a6e654bfce2$
BEGIN
  EXECUTE $bootstrap_sql_0a6e654bfce2$GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_item_quantity() TO service_role$bootstrap_sql_0a6e654bfce2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a6e654bfce2$;

DO $bootstrap_do_856e136dbf92$
BEGIN
  EXECUTE $bootstrap_sql_856e136dbf92$
