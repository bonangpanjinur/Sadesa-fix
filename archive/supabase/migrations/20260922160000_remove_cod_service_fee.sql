-- COD is free for every transaction.
-- Normalize the setting so older clients cannot re-enable a charge.
UPDATE public.app_settings
SET value = jsonb_set(COALESCE(value, '{}'::jsonb), '{service_fee}', '0'::jsonb, true),
    updated_at = now()
WHERE key = 'cod_settings'$bootstrap_sql_c83d50398738$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c83d50398738$;

DO $bootstrap_do_c03136480c2a$
BEGIN
  EXECUTE $bootstrap_sql_c03136480c2a$-- Defense in depth for stale clients or previously deployed checkout functions:
-- strip any COD fee from both the stored fee column and the transaction total.
CREATE OR REPLACE FUNCTION public.normalize_cod_service_fee()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing_fee numeric;
BEGIN
  IF NEW.payment_method = 'COD' THEN
    v_existing_fee := COALESCE(NEW.cod_service_fee, 0);
    NEW.total := GREATEST(0, COALESCE(NEW.total, 0) - v_existing_fee);
    NEW.cod_service_fee := 0;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_c03136480c2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c03136480c2a$;

DO $bootstrap_do_5a03faa935d4$
BEGIN
  EXECUTE $bootstrap_sql_5a03faa935d4$DROP TRIGGER IF EXISTS orders_free_cod_fee ON public.orders$bootstrap_sql_5a03faa935d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a03faa935d4$;

DO $bootstrap_do_5ae2e7071a10$
BEGIN
  EXECUTE $bootstrap_sql_5ae2e7071a10$CREATE TRIGGER orders_free_cod_fee
BEFORE INSERT OR UPDATE OF payment_method, total, cod_service_fee ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.normalize_cod_service_fee()$bootstrap_sql_5ae2e7071a10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ae2e7071a10$;

DO $bootstrap_do_c2562c775d93$
BEGIN
  EXECUTE $bootstrap_sql_c2562c775d93$COMMENT ON FUNCTION public.normalize_cod_service_fee() IS
  'Ensures COD never adds a service fee to an order total.'$bootstrap_sql_c2562c775d93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2562c775d93$;

DO $bootstrap_do_4571a4791cfe$
BEGIN
  EXECUTE $bootstrap_sql_4571a4791cfe$
