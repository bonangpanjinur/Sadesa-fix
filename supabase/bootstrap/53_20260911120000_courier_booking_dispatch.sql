-- Phase 2: turn the courier booking form into an authoritative order and dispatch request.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS pickup_address text,
  ADD COLUMN IF NOT EXISTS pickup_lat numeric,
  ADD COLUMN IF NOT EXISTS pickup_lng numeric,
  ADD COLUMN IF NOT EXISTS package_type text,
  ADD COLUMN IF NOT EXISTS package_weight_kg numeric,
  ADD COLUMN IF NOT EXISTS courier_notes text,
  ADD COLUMN IF NOT EXISTS scheduled_pickup boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.create_courier_order(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_pickup_lat numeric := (p_request->>'pickup_lat')::numeric;
  v_pickup_lng numeric := (p_request->>'pickup_lng')::numeric;
  v_destination_lat numeric := (p_request->>'destination_lat')::numeric;
  v_destination_lng numeric := (p_request->>'destination_lng')::numeric;
  v_distance numeric;
  v_weight numeric := COALESCE((p_request->>'weight_kg')::numeric, 1);
  v_base integer;
  v_cod_fee integer := CASE WHEN COALESCE((p_request->>'cod')::boolean, false) THEN 2000 ELSE 0 END;
  v_shipping integer;
  v_order_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF v_pickup_lat NOT BETWEEN -90 AND 90 OR v_destination_lat NOT BETWEEN -90 AND 90
     OR v_pickup_lng NOT BETWEEN -180 AND 180 OR v_destination_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid courier coordinates' USING ERRCODE = '22023';
  END IF;
  IF v_weight <= 0 OR v_weight > 50 THEN
    RAISE EXCEPTION 'Package weight must be between 0 and 50 kg' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(p_request->>'pickup_address'), '') IS NULL
     OR NULLIF(btrim(p_request->>'destination_address'), '') IS NULL
     OR NULLIF(btrim(p_request->>'recipient_name'), '') IS NULL
     OR NULLIF(btrim(p_request->>'recipient_phone'), '') IS NULL
     OR NULLIF(btrim(p_request->>'package_type'), '') IS NULL THEN
    RAISE EXCEPTION 'Courier address, recipient, and package details are required' USING ERRCODE = '22023';
  END IF;

  v_distance := 6371 * 2 * asin(sqrt(
    power(sin(radians(v_destination_lat - v_pickup_lat) / 2), 2)
    + cos(radians(v_pickup_lat)) * cos(radians(v_destination_lat))
    * power(sin(radians(v_destination_lng - v_pickup_lng) / 2), 2)
  ));
  IF v_distance IS NULL OR v_distance <= 0 OR v_distance > 10 THEN
    RAISE EXCEPTION 'Internal courier service supports distances up to 10 km' USING ERRCODE = '22023';
  END IF;

  v_base := CASE WHEN v_distance <= 3 THEN 8000 WHEN v_distance <= 7 THEN 12000 ELSE 18000 END;
  v_shipping := v_base + (GREATEST(0, v_weight - 2) * 2500)::integer;

  INSERT INTO public.orders (
    buyer_id, merchant_id, status, handled_by, delivery_type,
    delivery_address, delivery_phone, delivery_name, delivery_lat, delivery_lng,
    shipping_cost, subtotal, total, notes, payment_method, payment_status,
    buyer_distance_km, is_self_delivery, pickup_address, pickup_lat, pickup_lng,
    package_type, package_weight_kg, courier_notes, scheduled_pickup, cod_service_fee
  ) VALUES (
    auth.uid(), NULL, 'ASSIGNED', 'ADMIN', 'INTERNAL',
    left(btrim(p_request->>'destination_address'), 500),
    left(btrim(p_request->>'recipient_phone'), 40),
    left(btrim(p_request->>'recipient_name'), 160), v_destination_lat, v_destination_lng,
    v_shipping, 0, v_shipping + v_cod_fee, NULLIF(left(btrim(p_request->>'notes'), 1000), ''),
    'COD', 'COD', round(v_distance, 2), false,
    left(btrim(p_request->>'pickup_address'), 500), v_pickup_lat, v_pickup_lng,
    left(btrim(p_request->>'package_type'), 160), v_weight,
    NULLIF(left(btrim(p_request->>'notes'), 1000), ''),
    COALESCE((p_request->>'scheduled')::boolean, false), v_cod_fee
  ) RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (v_order.id, NULL, 'ASSIGNED', auth.uid(), 'Courier booking dibuat oleh buyer');

  -- Offer the nearest eligible courier. The order remains ASSIGNED when no courier is online,
  -- so a later dispatch worker can safely retry without losing the booking.
  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_pickup_lat) / 2), 2)
      + cos(radians(v_pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NOT NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
    VALUES (v_order.id, v_courier.id, auth.uid())
    RETURNING * INTO v_assignment;
    PERFORM public.send_notification(
      v_courier.user_id,
      'Pesanan Kurir Baru',
      'Ada pesanan kurir baru di sekitar lokasi Anda',
      'order',
      '/courier/rides'
    );
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'assignment_id', v_assignment.id,
    'status', v_order.status,
    'distance_km', round(v_distance, 2),
    'shipping_cost', v_shipping,
    'cod_fee', v_cod_fee,
    'dispatch_status', CASE WHEN v_assignment.id IS NULL THEN 'WAITING_FOR_COURIER' ELSE 'OFFERED' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_courier_order(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_courier_order(jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
