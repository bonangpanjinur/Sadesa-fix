-- COD is free for every transaction.
-- Normalize the setting so older clients cannot re-enable a charge.
UPDATE public.app_settings
SET value = jsonb_set(COALESCE(value, '{}'::jsonb), '{service_fee}', '0'::jsonb, true),
    updated_at = now()
WHERE key = 'cod_settings';

-- Defense in depth for stale clients or previously deployed checkout functions:
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
$$;

DROP TRIGGER IF EXISTS orders_free_cod_fee ON public.orders;
CREATE TRIGGER orders_free_cod_fee
BEFORE INSERT OR UPDATE OF payment_method, total, cod_service_fee ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.normalize_cod_service_fee();

COMMENT ON FUNCTION public.normalize_cod_service_fee() IS
  'Ensures COD never adds a service fee to an order total.';
