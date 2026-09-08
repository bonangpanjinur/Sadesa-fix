-- Keep courier ride history and earnings connected to the ride lifecycle.
-- This bundle is safe to replay and does not trust client-provided money fields.

ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS ride_request_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'courier_earnings_ride_request_id_fkey'
      AND conrelid = 'public.courier_earnings'::regclass
  ) THEN
    ALTER TABLE public.courier_earnings
      ADD CONSTRAINT courier_earnings_ride_request_id_fkey
      FOREIGN KEY (ride_request_id)
      REFERENCES public.ride_requests(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_courier_earnings_ride_request
  ON public.courier_earnings(ride_request_id)
  WHERE type = 'RIDE' AND ride_request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ride_requests_driver_history
  ON public.ride_requests(driver_id, created_at DESC);

-- Backfill completed rides that predate the lifecycle ledger.
INSERT INTO public.courier_earnings (
  courier_id,
  ride_request_id,
  amount,
  type,
  status,
  distance_km,
  base_amount,
  created_at
)
SELECT
  r.driver_id,
  r.id,
  COALESCE(r.final_fare, r.estimated_fare),
  'RIDE',
  'PENDING',
  r.distance_km,
  COALESCE(r.final_fare, r.estimated_fare),
  COALESCE(r.completed_at, r.created_at)
FROM public.ride_requests AS r
WHERE r.status = 'COMPLETED'
  AND r.driver_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.courier_earnings AS e
    WHERE e.ride_request_id = r.id
      AND e.type = 'RIDE'
  );

-- Assignment must only be performed by the authenticated, active courier
-- represented by p_courier_id.
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.couriers
    WHERE id = p_courier_id
      AND user_id = auth.uid()
      AND registration_status = 'APPROVED'
      AND status = 'ACTIVE'
      AND is_available = true
  ) THEN
    RAISE EXCEPTION 'Kurir tidak aktif, belum disetujui, atau bukan milik akun ini';
  END IF;

  UPDATE public.ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN false;
  END IF;

  PERFORM public.send_notification(
    passenger_id,
    'Driver Ditemukan! 🏍️',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  )
  FROM public.ride_requests
  WHERE id = p_ride_id;

  RETURN true;
END;
$$;

-- Completion updates the ride and creates exactly one pending earning together.
DROP FUNCTION IF EXISTS public.transition_ride_status(uuid, text);

CREATE OR REPLACE FUNCTION public.transition_ride_status(
  p_ride_id uuid,
  p_to_status text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
  v_final_fare integer;
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid()
    AND registration_status = 'APPROVED'
    AND status = 'ACTIVE'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Kurir tidak aktif atau belum disetujui';
  END IF;

  SELECT *
  INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id
    AND driver_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perjalanan tidak ditemukan atau bukan milik kurir ini';
  END IF;

  IF (v_ride.status, p_to_status) NOT IN (
    ('ACCEPTED', 'PICKED_UP'),
    ('PICKED_UP', 'IN_TRANSIT'),
    ('IN_TRANSIT', 'COMPLETED')
  ) THEN
    RAISE EXCEPTION 'Perubahan status perjalanan tidak valid';
  END IF;

  v_final_fare := COALESCE(v_ride.final_fare, v_ride.estimated_fare);

  UPDATE public.ride_requests
  SET status = p_to_status,
      final_fare = CASE WHEN p_to_status = 'COMPLETED' THEN v_final_fare ELSE final_fare END,
      picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
      completed_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completed_at END
  WHERE id = p_ride_id;

  IF p_to_status = 'COMPLETED' THEN
    INSERT INTO public.courier_earnings (
      courier_id,
      ride_request_id,
      amount,
      type,
      status,
      distance_km,
      base_amount,
      created_at
    )
    SELECT
      v_courier_id,
      p_ride_id,
      v_final_fare,
      'RIDE',
      'PENDING',
      v_ride.distance_km,
      v_final_fare,
      now()
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.courier_earnings
      WHERE ride_request_id = p_ride_id
        AND type = 'RIDE'
    );
  END IF;

  RETURN p_to_status;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_ride(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;