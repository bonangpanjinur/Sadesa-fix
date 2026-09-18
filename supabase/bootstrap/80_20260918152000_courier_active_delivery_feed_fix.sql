-- Include merchant-originated internal deliveries in the courier active feed.
-- The previous feed only allowed COURIER_DELIVERY, which hid marketplace orders
-- after a courier accepted them even though they were not completed yet.

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
    -- Include direct courier and merchant marketplace deliveries, but never
    -- passenger ride records if legacy rows share the orders table.
    AND (o.service_type IN ('COURIER_DELIVERY', 'MARKETPLACE') OR o.service_type IS NULL)
    AND o.status IN ('COURIER_ACCEPTED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING')
  ORDER BY o.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_deliveries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_deliveries() TO authenticated;
NOTIFY pgrst, 'reload schema';
