-- Courier delivery flow repair:
-- ASSIGNED means an offer is waiting for a courier decision.
-- courier_id/assigned_at become authoritative only after acceptance.

-- Repair rows created by the older booking/dispatch functions.
UPDATE public.orders o
SET courier_id = NULL,
    assigned_at = NULL,
    updated_at = now()
WHERE o.status = 'ASSIGNED'
  AND EXISTS (
    SELECT 1
    FROM public.delivery_assignments da
    WHERE da.order_id = o.id
      AND da.status = 'OFFERED'
  );

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED')
     OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;

  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.id = p_courier_id
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid())
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED',
      courier_id = NULL,
      assigned_at = NULL,
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (
    p_order_id,
    v_order.status,
    'ASSIGNED',
    auth.uid(),
    'Tawaran dikirim ke kurir; menunggu keputusan kurir',
    jsonb_build_object('courier_id', p_courier_id, 'assignment_id', v_assignment.id)
  );

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada tawaran pengiriman baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/deliveries'
  );

  RETURN v_assignment;
END;
$$;

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
  -- COD is intentionally free for every courier transaction.
  v_cod_fee integer := 0;
  v_shipping integer;
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
    buyer_id, merchant_id, service_type, status, handled_by, delivery_type,
    delivery_address, delivery_phone, delivery_name, delivery_lat, delivery_lng,
    shipping_cost, subtotal, total, notes, payment_method, payment_status,
    buyer_distance_km, is_self_delivery, pickup_address, pickup_lat, pickup_lng,
    package_type, package_weight_kg, courier_notes, scheduled_pickup, cod_service_fee
  ) VALUES (
    auth.uid(), NULL, 'COURIER_DELIVERY', 'ASSIGNED', 'ADMIN', 'INTERNAL',
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
      '/courier/deliveries'
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

CREATE OR REPLACE FUNCTION public.dispatch_courier_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (buyer_id = auth.uid() OR public.is_admin())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.status <> 'ASSIGNED' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;
  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    UPDATE public.orders
    SET courier_id = NULL, assigned_at = NULL, status_updated_at = now(), updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'dispatch_status', 'OFFERED');
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')))
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_order.pickup_lat) / 2), 2)
      + cos(radians(v_order.pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_order.pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    UPDATE public.orders
    SET courier_id = NULL, assigned_at = NULL, updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id AND da.courier_id = v_courier.id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    INSERT INTO public.delivery_assignments(order_id, courier_id, offered_at, expires_at)
    VALUES (p_order_id, v_courier.id, now(), now() + interval '5 minutes')
    RETURNING * INTO v_assignment;
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'OFFERED',
        offered_at = now(),
        expires_at = now() + interval '5 minutes',
        responded_at = NULL,
        rejection_reason = NULL
    WHERE id = v_assignment.id
    RETURNING * INTO v_assignment;
  END IF;

  UPDATE public.orders
  SET courier_id = NULL, assigned_at = NULL, status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.send_notification(
    v_courier.user_id,
    'Pesanan Kurir Baru',
    'Ada pesanan kurir baru di sekitar lokasi Anda',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'courier_id', v_courier.id, 'dispatch_status', 'OFFERED');
END;
$$;

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
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  UPDATE public.delivery_assignments da
  SET expires_at = now() + interval '5 minutes'
  FROM public.orders o
  WHERE da.order_id = o.id
    AND da.courier_id = v_courier_id
    AND da.status = 'OFFERED'
    AND da.expires_at <= now()
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
    AND da.expires_at > now()
    AND o.status = 'ASSIGNED';

  RETURN v_offers;
END;
$$;

REVOKE ALL ON FUNCTION public.create_courier_order(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dispatch_courier_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_courier_delivery_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_courier_order(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_offers() TO authenticated;
NOTIFY pgrst, 'reload schema';
