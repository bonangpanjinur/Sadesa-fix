-- Keep the courier's active delivery feed authoritative and independent from
-- client-side orders RLS joins. Acceptance still sets orders.courier_id; this
-- function makes the resulting active rows readable through one audited path.
CREATE OR REPLACE FUNCTION public.get_courier_active_deliveries()
RETURNS SETOF public.orders
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT o.*
  FROM public.orders o
  WHERE o.courier_id = v_courier_id
    AND o.service_type = 'COURIER_DELIVERY'
    AND o.status IN ('COURIER_ACCEPTED', 'PICKED_UP', 'DELIVERING')
  ORDER BY o.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_deliveries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_deliveries() TO authenticated;
NOTIFY pgrst, 'reload schema';
