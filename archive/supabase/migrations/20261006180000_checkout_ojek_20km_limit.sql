-- Pause expedition delivery at checkout and enforce the Ojek maximum distance
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
$$;

DROP TRIGGER IF EXISTS orders_validate_delivery_method ON public.orders;
CREATE TRIGGER orders_validate_delivery_method
  BEFORE INSERT OR UPDATE OF delivery_type, merchant_id, buyer_distance_km,
    delivery_city_name, delivery_district_name
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_delivery_method_restriction();

NOTIFY pgrst, 'reload schema';
