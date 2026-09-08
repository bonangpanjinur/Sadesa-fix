-- Validate driver ride transitions on the server.
-- This is intentionally idempotent so it can be replayed with the bootstrap set.
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

  SELECT * INTO v_ride
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

  UPDATE public.ride_requests
  SET status = p_to_status,
      picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
      completed_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completed_at END
  WHERE id = p_ride_id;

  RETURN p_to_status;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;