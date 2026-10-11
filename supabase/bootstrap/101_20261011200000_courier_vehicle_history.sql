-- Durable audit trail for courier vehicle changes.
DO $bootstrap_do_courier_vehicle_history$
BEGIN
  CREATE TABLE IF NOT EXISTS public.courier_vehicle_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
    changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    previous_vehicle_type TEXT NOT NULL,
    previous_vehicle_plate TEXT,
    new_vehicle_type TEXT NOT NULL,
    new_vehicle_plate TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE INDEX IF NOT EXISTS idx_courier_vehicle_history_courier_changed_at
    ON public.courier_vehicle_history(courier_id, changed_at DESC);

  ALTER TABLE public.courier_vehicle_history ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Couriers can view own vehicle history" ON public.courier_vehicle_history;
  CREATE POLICY "Couriers can view own vehicle history"
    ON public.courier_vehicle_history
    FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1
        FROM public.couriers c
        WHERE c.id = courier_vehicle_history.courier_id
          AND c.user_id = auth.uid()
      )
    );

  REVOKE ALL ON TABLE public.courier_vehicle_history FROM PUBLIC, anon;
  GRANT SELECT ON TABLE public.courier_vehicle_history TO authenticated;

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
    current_courier public.couriers%ROWTYPE;
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

    SELECT * INTO current_courier
    FROM public.couriers
    WHERE user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Profil ojek tidak ditemukan' USING ERRCODE = 'P0002';
    END IF;

    IF current_courier.vehicle_type IS DISTINCT FROM p_vehicle_type
      OR current_courier.vehicle_plate IS DISTINCT FROM normalized_plate THEN
      INSERT INTO public.courier_vehicle_history (
        courier_id,
        changed_by,
        previous_vehicle_type,
        previous_vehicle_plate,
        new_vehicle_type,
        new_vehicle_plate
      ) VALUES (
        current_courier.id,
        auth.uid(),
        current_courier.vehicle_type,
        current_courier.vehicle_plate,
        p_vehicle_type,
        normalized_plate
      );

      UPDATE public.couriers
      SET vehicle_type = p_vehicle_type,
          vehicle_plate = normalized_plate,
          updated_at = now()
      WHERE id = current_courier.id;
    END IF;

    RETURN QUERY SELECT p_vehicle_type, normalized_plate;
  END;
  $function$;

  REVOKE ALL ON FUNCTION public.update_own_courier_vehicle(TEXT, TEXT) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.update_own_courier_vehicle(TEXT, TEXT) TO authenticated;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END;
$bootstrap_do_courier_vehicle_history$;
