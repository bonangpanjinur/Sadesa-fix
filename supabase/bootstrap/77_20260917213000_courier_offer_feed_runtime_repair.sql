-- Runtime repair for the courier offer feed used by /courier/deliveries.
-- The courier must be able to read an offer assigned to their account before acceptance.
CREATE OR REPLACE FUNCTION public.get_courier_delivery_offers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
  v_offers jsonb;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', da.id,
    'order_id', da.order_id,
    'expires_at', da.expires_at,
    'orders', jsonb_build_object(
      'total', o.total,
      'shipping_cost', o.shipping_cost,
      'courier_earning_estimate', o.courier_earning_estimate,
      'courier_platform_fee', o.courier_platform_fee,
      'pickup_address', o.pickup_address,
      'pickup_lat', o.pickup_lat,
      'pickup_lng', o.pickup_lng,
      'delivery_name', o.delivery_name,
      'delivery_address', o.delivery_address,
      'delivery_lat', o.delivery_lat,
      'delivery_lng', o.delivery_lng,
      'notes', o.notes,
      'merchants', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('name', m.name, 'address', m.address) END
    )
  ) ORDER BY da.offered_at DESC), '[]'::jsonb)
  INTO v_offers
  FROM public.delivery_assignments da
  JOIN public.orders o ON o.id = da.order_id
  LEFT JOIN public.merchants m ON m.id = o.merchant_id
  WHERE da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
    AND o.status = 'ASSIGNED';

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;

-- Keep the active delivery feed authoritative and independent from client-side
-- orders RLS joins. Acceptance still sets orders.courier_id; this function makes
-- the resulting active rows readable through one audited path.
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
