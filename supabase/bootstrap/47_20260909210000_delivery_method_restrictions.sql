-- Local ojek/kurir delivery is limited to 10 km and the merchant's
-- kecamatan/kabupaten. Orders outside that scope must use EXPEDITION.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_province_id text,
  ADD COLUMN IF NOT EXISTS delivery_province_name text,
  ADD COLUMN IF NOT EXISTS delivery_city_id text,
  ADD COLUMN IF NOT EXISTS delivery_city_name text,
  ADD COLUMN IF NOT EXISTS delivery_district_id text,
  ADD COLUMN IF NOT EXISTS delivery_district_name text;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_delivery_type_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_delivery_type_check
  CHECK (delivery_type IN ('PICKUP', 'INTERNAL', 'EXPEDITION'));

CREATE OR REPLACE FUNCTION public.validate_delivery_method_restriction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_destination_city text;
  v_destination_district text;
  v_merchant_city text;
  v_merchant_district text;
BEGIN
  IF NEW.delivery_type <> 'INTERNAL' OR NEW.merchant_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_merchant
  FROM public.merchants
  WHERE id = NEW.merchant_id;

  IF NEW.buyer_distance_km > 10 THEN
    RAISE EXCEPTION 'Local delivery is limited to 10 km; use EXPEDITION'
      USING ERRCODE = '22023';
  END IF;

  -- Only compare administrative regions when both sides have a value. Older
  -- merchants may not have region metadata yet; distance remains authoritative.
  v_destination_city := regexp_replace(lower(coalesce(NEW.delivery_city_name, '')), '\m(kabupaten|kab\.?|kota)\M', '', 'g');
  v_destination_district := regexp_replace(lower(coalesce(NEW.delivery_district_name, '')), '\m(kecamatan|kec\.?)\M', '', 'g');
  v_merchant_city := regexp_replace(lower(coalesce(v_merchant.city, '')), '\m(kabupaten|kab\.?|kota)\M', '', 'g');
  v_merchant_district := regexp_replace(lower(coalesce(v_merchant.district, '')), '\m(kecamatan|kec\.?)\M', '', 'g');

  IF v_destination_city <> '' AND v_merchant_city <> ''
     AND regexp_replace(v_destination_city, '[^a-z0-9]+', '', 'g')
        <> regexp_replace(v_merchant_city, '[^a-z0-9]+', '', 'g') THEN
    RAISE EXCEPTION 'Different kabupaten/kota requires EXPEDITION'
      USING ERRCODE = '22023';
  END IF;

  IF v_destination_district <> '' AND v_merchant_district <> ''
     AND regexp_replace(v_destination_district, '[^a-z0-9]+', '', 'g')
        <> regexp_replace(v_merchant_district, '[^a-z0-9]+', '', 'g') THEN
    RAISE EXCEPTION 'Different kecamatan requires EXPEDITION'
      USING ERRCODE = '22023';
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

GRANT EXECUTE ON FUNCTION public.validate_delivery_method_restriction() TO authenticated;
NOTIFY pgrst, 'reload schema';