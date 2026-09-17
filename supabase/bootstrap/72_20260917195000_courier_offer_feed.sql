-- Courier offer feed: avoids nested orders RLS hiding an OFFERED assignment
-- before orders.courier_id is populated by acceptance.
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

  -- An offline courier must not lose an offer merely because the five-minute
  -- response window elapsed while the order is still waiting for acceptance.
  UPDATE public.delivery_assignments da
  SET expires_at = now() + interval '5 minutes'
  FROM public.orders o
  WHERE da.order_id = o.id
    AND da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at <= now()
    AND o.status = 'ASSIGNED';

  UPDATE public.orders o
  SET courier_id = da.courier_id,
      assigned_at = COALESCE(o.assigned_at, now()),
      status_updated_at = now(),
      updated_at = now()
  FROM public.delivery_assignments da
  WHERE da.order_id = o.id
    AND da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND o.status = 'ASSIGNED';

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
    AND da.expires_at > now();

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;
NOTIFY pgrst, 'reload schema';
