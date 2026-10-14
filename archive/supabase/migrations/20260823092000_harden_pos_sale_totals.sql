-- Validate POS header arithmetic after all sale items have been inserted.
-- A deferred constraint trigger lets the atomic checkout RPC insert the header
-- first and items afterward while still enforcing the invariant at COMMIT.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item_tax numeric;
  v_item_subtotal numeric;
BEGIN
  IF NEW.subtotal < 0 OR NEW.tax_amount < 0 OR NEW.total < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale totals' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(tax_amount), 0), COALESCE(sum(subtotal), 0)
  INTO v_item_tax, v_item_subtotal
  FROM public.pos_sale_items
  WHERE sale_id = NEW.id;

  IF abs(NEW.tax_amount - v_item_tax) > 0.01 THEN
    RAISE EXCEPTION 'Sale tax does not match item tax' USING ERRCODE = '22023';
  END IF;

  -- Header discounts may include promotions, vouchers, or loyalty discounts,
  -- so the valid total may be lower than the item subtotal but never higher
  -- than the subtotal plus tax.
  IF NEW.total > NEW.subtotal + NEW.tax_amount + 0.01 THEN
    RAISE EXCEPTION 'Sale total exceeds subtotal and tax' USING ERRCODE = '22023';
  END IF;

  IF v_item_subtotal > NEW.subtotal + 0.01 THEN
    RAISE EXCEPTION 'Item subtotal exceeds sale subtotal' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_1fd116080813$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1fd116080813$;

DO $bootstrap_do_367a28f615eb$
BEGIN
  EXECUTE $bootstrap_sql_367a28f615eb$DROP TRIGGER IF EXISTS validate_pos_sale_totals ON public.pos_sales$bootstrap_sql_367a28f615eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_367a28f615eb$;

DO $bootstrap_do_4fd1741b22ef$
BEGIN
  EXECUTE $bootstrap_sql_4fd1741b22ef$CREATE CONSTRAINT TRIGGER validate_pos_sale_totals
AFTER INSERT OR UPDATE OF subtotal, tax_amount, total, discount_amount,
  promotion_discount, voucher_discount, loyalty_discount
ON public.pos_sales
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_totals()$bootstrap_sql_4fd1741b22ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fd1741b22ef$;

DO $bootstrap_do_5c88c56a3c8c$
BEGIN
  EXECUTE $bootstrap_sql_5c88c56a3c8c$REVOKE ALL ON FUNCTION public.validate_pos_sale_totals() FROM PUBLIC$bootstrap_sql_5c88c56a3c8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c88c56a3c8c$;

DO $bootstrap_do_20b1c5f31e70$
BEGIN
  EXECUTE $bootstrap_sql_20b1c5f31e70$
