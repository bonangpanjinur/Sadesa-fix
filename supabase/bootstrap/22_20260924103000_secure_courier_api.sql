-- Security hardening: prevent direct table reads from exposing courier PII.
-- Public consumers must use public_couriers (masked/approximate fields) or the
-- scoped RPC below for an active order/ride they are authorized to view.

-- Keep this migration safe when deployed after an older bootstrap that does
-- not yet contain the courier assignment/rating columns used by the RPC.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_id uuid REFERENCES public.couriers(id);

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS rating_avg numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rating_count integer NOT NULL DEFAULT 0;

DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers;

CREATE OR REPLACE FUNCTION public.get_courier_contact(
  p_courier_id uuid,
  p_order_id uuid DEFAULT NULL,
  p_ride_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  name text,
  phone text,
  vehicle_type text,
  vehicle_plate text,
  photo_url text,
  rating_avg numeric,
  rating_count integer,
  current_lat numeric,
  current_lng numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.user_id,
    c.name,
    c.phone,
    c.vehicle_type,
    c.vehicle_plate,
    c.photo_url,
    c.rating_avg,
    c.rating_count,
    c.current_lat,
    c.current_lng
  FROM public.couriers AS c
  WHERE c.id = p_courier_id
    AND c.registration_status = 'APPROVED'
    AND c.status = 'ACTIVE'
    AND (
      EXISTS (
        SELECT 1
        FROM public.orders AS o
        WHERE p_order_id IS NOT NULL
          AND o.id = p_order_id
          AND o.buyer_id = auth.uid()
          AND o.courier_id = c.id
          AND o.status NOT IN ('CANCELED', 'CANCELLED')
      )
      OR EXISTS (
        SELECT 1
        FROM public.ride_requests AS r
        WHERE p_ride_id IS NOT NULL
          AND r.id = p_ride_id
          AND r.passenger_id = auth.uid()
          AND r.driver_id = c.id
          AND r.status NOT IN ('CANCELED', 'CANCELLED')
      )
      OR EXISTS (
        SELECT 1
        FROM public.user_roles AS ur
        WHERE ur.user_id = auth.uid()
          AND ur.role = 'admin'
      )
      OR c.user_id = auth.uid()
    );
$$;

REVOKE EXECUTE ON FUNCTION public.get_courier_contact(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_courier_contact(uuid, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.get_courier_contact(uuid, uuid, uuid) IS
  'Returns courier contact/location only to the courier owner, an admin, or the buyer/passenger of the referenced order/ride.';
