-- New courier registrations currently accept motorcycles only.
-- Existing courier profiles remain editable through update_own_courier_vehicle.
DO $bootstrap_do_courier_vehicle_profile$
BEGIN
  CREATE OR REPLACE FUNCTION public.enforce_courier_registration_motor()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $function$
  BEGIN
    IF TG_OP = 'INSERT' THEN
      NEW.vehicle_type := 'motor';
    END IF;
    RETURN NEW;
  END;
  $function$;

  DROP TRIGGER IF EXISTS enforce_courier_registration_motor ON public.couriers;
  CREATE TRIGGER enforce_courier_registration_motor
    BEFORE INSERT ON public.couriers
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_courier_registration_motor();

  CREATE OR REPLACE FUNCTION public.update_own_courier_vehicle(
    p_vehicle_type TEXT,
    p_vehicle_plate TEXT DEFAULT NULL
  )
  RETURNS TABLE(vehicle_type TEXT, vehicle_plate TEXT)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $function$
  DECLARE
    normalized_plate TEXT := NULLIF(upper(trim(p_vehicle_plate)), '');
  BEGIN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_vehicle_type NOT IN ('motor', 'mobil', 'sepeda') THEN
      RAISE EXCEPTION 'Jenis kendaraan tidak valid' USING ERRCODE = '22023';
    END IF;

    IF normalized_plate IS NOT NULL AND length(normalized_plate) > 20 THEN
      RAISE EXCEPTION 'Nomor plat kendaraan terlalu panjang' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    UPDATE public.couriers
    SET vehicle_type = p_vehicle_type,
        vehicle_plate = normalized_plate,
        updated_at = now()
    WHERE user_id = auth.uid()
    RETURNING public.couriers.vehicle_type, public.couriers.vehicle_plate;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Profil ojek tidak ditemukan' USING ERRCODE = 'P0002';
    END IF;
  END;
  $function$;

  REVOKE ALL ON FUNCTION public.update_own_courier_vehicle(TEXT, TEXT) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.update_own_courier_vehicle(TEXT, TEXT) TO authenticated;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END;
$bootstrap_do_courier_vehicle_profile$;
