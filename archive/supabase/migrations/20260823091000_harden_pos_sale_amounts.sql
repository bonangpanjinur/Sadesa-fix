-- Server-side price and line arithmetic guard for all POS sale writes.
-- The checkout RPC remains the atomic boundary; this trigger protects direct
-- inserts and prevents a compromised client from inflating line prices.

CREATE OR REPLACE FUNCTION public.validate_pos_sale_item_amounts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale record;
  v_product_price numeric;
  v_variant_price numeric;
BEGIN
  SELECT tenant_id, outlet_id
  INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale does not exist' USING ERRCODE = '23503';
  END IF;

  IF NEW.qty <= 0 OR NEW.price < 0 OR NEW.discount < 0 OR NEW.tax_amount < 0 THEN
    RAISE EXCEPTION 'Invalid POS sale item amount' USING ERRCODE = '22023';
  END IF;

  IF NEW.discount > NEW.price * NEW.qty THEN
    RAISE EXCEPTION 'Line discount exceeds line amount' USING ERRCODE = '22023';
  END IF;

  IF abs(NEW.subtotal - (NEW.price * NEW.qty - NEW.discount)) > 0.01 THEN
    RAISE EXCEPTION 'Line subtotal mismatch' USING ERRCODE = '22023';
  END IF;

  SELECT price
  INTO v_variant_price
  FROM public.pos_product_variants
  WHERE id = NEW.variant_id
    AND product_id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NEW.variant_id IS NOT NULL AND NOT FOUND THEN
    RAISE EXCEPTION 'Product variant does not belong to tenant or product' USING ERRCODE = '42501';
  END IF;

  SELECT price
  INTO v_product_price
  FROM public.pos_products
  WHERE id = NEW.product_id
    AND tenant_id = v_sale.tenant_id
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product does not belong to tenant or is inactive' USING ERRCODE = '42501';
  END IF;

  IF NEW.price > COALESCE(v_variant_price, v_product_price) THEN
    RAISE EXCEPTION 'Sale price exceeds catalog price' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_950b52f9699e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_950b52f9699e$;

DO $bootstrap_do_43a56f318d4a$
BEGIN
  EXECUTE $bootstrap_sql_43a56f318d4a$DROP TRIGGER IF EXISTS validate_pos_sale_item_amounts ON public.pos_sale_items$bootstrap_sql_43a56f318d4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43a56f318d4a$;

DO $bootstrap_do_c1f9f79ad49e$
BEGIN
  EXECUTE $bootstrap_sql_c1f9f79ad49e$CREATE TRIGGER validate_pos_sale_item_amounts
BEFORE INSERT OR UPDATE ON public.pos_sale_items
FOR EACH ROW
EXECUTE FUNCTION public.validate_pos_sale_item_amounts()$bootstrap_sql_c1f9f79ad49e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c1f9f79ad49e$;

DO $bootstrap_do_d4dc71f4bafe$
BEGIN
  EXECUTE $bootstrap_sql_d4dc71f4bafe$REVOKE ALL ON FUNCTION public.validate_pos_sale_item_amounts() FROM PUBLIC$bootstrap_sql_d4dc71f4bafe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4dc71f4bafe$;

DO $bootstrap_do_1fd116080813$
BEGIN
  EXECUTE $bootstrap_sql_1fd116080813$
