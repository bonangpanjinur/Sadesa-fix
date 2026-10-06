-- SaDesa incremental repeatable bootstrap bundle.
-- Safe to apply after existing canonical bootstrap bundles.

-- ===== BEGIN SOURCE: 20261006180000_checkout_ojek_20km_limit.sql =====
DO $bootstrap_do_d33b4d3a97e7$
BEGIN
  EXECUTE $bootstrap_sql_d33b4d3a97e7$-- Pause expedition delivery at checkout and enforce the Ojek maximum distance
-- at the database boundary. Existing expedition orders remain processable.
CREATE OR REPLACE FUNCTION public.validate_delivery_method_restriction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NEW.delivery_type = 'EXPEDITION' THEN
    -- Preserve existing expedition orders, but do not allow new ones or a
    -- different delivery method to be changed into expedition.
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'Pengiriman ekspedisi sedang tidak tersedia' USING ERRCODE = '22023';
    ELSIF OLD.delivery_type IS DISTINCT FROM 'EXPEDITION' THEN
      RAISE EXCEPTION 'Pengiriman ekspedisi sedang tidak tersedia' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.delivery_type IS DISTINCT FROM 'INTERNAL' OR NEW.merchant_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.buyer_distance_km > 20 THEN
    RAISE EXCEPTION 'Jarak pengiriman Ojek maksimal 20 km' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_d33b4d3a97e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d33b4d3a97e7$;

DO $bootstrap_do_efc9fcf722f4$
BEGIN
  EXECUTE $bootstrap_sql_efc9fcf722f4$DROP TRIGGER IF EXISTS orders_validate_delivery_method ON public.orders$bootstrap_sql_efc9fcf722f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efc9fcf722f4$;

DO $bootstrap_do_5a776e7abd1c$
BEGIN
  EXECUTE $bootstrap_sql_5a776e7abd1c$CREATE TRIGGER orders_validate_delivery_method
  BEFORE INSERT OR UPDATE OF delivery_type, merchant_id, buyer_distance_km,
    delivery_city_name, delivery_district_name
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_delivery_method_restriction()$bootstrap_sql_5a776e7abd1c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a776e7abd1c$;

DO $bootstrap_do_ae3ffb60cf83$
BEGIN
  EXECUTE $bootstrap_sql_ae3ffb60cf83$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ae3ffb60cf83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae3ffb60cf83$;
-- ===== END SOURCE: 20261006180000_checkout_ojek_20km_limit.sql =====
