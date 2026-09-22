-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 52_20260911110000_ride_authoritative_mutations.sql .. 65_20260914150000_driver_workflow_hardening.sql

-- ===== BEGIN BUNDLE: 52_20260911110000_ride_authoritative_mutations.sql =====
-- Phase 1: make passenger ride mutations server-authoritative.
-- Safe to replay after the existing ride schema and transition RPC migrations.

CREATE OR REPLACE FUNCTION public.create_ride_request(
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_pickup_address text,
  p_destination_lat numeric,
  p_destination_lng numeric,
  p_destination_address text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_distance numeric;
  v_settings jsonb;
  v_base numeric;
  v_per_km numeric;
  v_min numeric;
  v_max numeric;
  v_fare numeric;
  v_ride_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF p_pickup_lat NOT BETWEEN -90 AND 90 OR p_destination_lat NOT BETWEEN -90 AND 90
     OR p_pickup_lng NOT BETWEEN -180 AND 180 OR p_destination_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'Invalid ride coordinates' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_pickup_address, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_destination_address, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Pickup and destination addresses are required' USING ERRCODE = '22023';
  END IF;

  v_distance := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2)
    + cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat))
    * power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2)
  ));
  IF v_distance IS NULL OR v_distance <= 0 OR v_distance > 10 THEN
    RAISE EXCEPTION 'Ride distance must be greater than 0 and no more than 10 km' USING ERRCODE = '22023';
  END IF;

  SELECT value INTO v_settings
  FROM public.app_settings
  WHERE key = 'ride_fare_settings';
  v_base := COALESCE((v_settings->>'base_fare')::numeric, 5000);
  v_per_km := COALESCE((v_settings->>'per_km_fare')::numeric, 3000);
  v_min := COALESCE((v_settings->>'min_fare')::numeric, 5000);
  v_max := COALESCE((v_settings->>'max_fare')::numeric, 100000);
  v_fare := LEAST(v_max, GREATEST(v_min, round(v_base + v_distance * v_per_km)));

  INSERT INTO public.ride_requests (
    passenger_id, pickup_lat, pickup_lng, pickup_address,
    destination_lat, destination_lng, destination_address,
    distance_km, estimated_fare, status
  ) VALUES (
    auth.uid(), p_pickup_lat, p_pickup_lng, left(btrim(p_pickup_address), 500),
    p_destination_lat, p_destination_lng, left(btrim(p_destination_address), 500),
    round(v_distance, 2), v_fare, 'SEARCHING'
  )
  RETURNING id INTO v_ride_id;

  RETURN v_ride_id;
END;
$$;

-- Preserve the existing signature for older clients, but bind the courier to auth.uid().
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_passenger_id uuid;
  v_updated integer;
BEGIN
  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
    AND user_id = auth.uid()
    AND registration_status = 'APPROVED'
    AND status = 'ACTIVE'
    AND is_available = true
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Courier identity is invalid or unavailable' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL
  RETURNING passenger_id INTO v_passenger_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN false;
  END IF;

  PERFORM public.send_notification(
    v_passenger_id,
    'Driver Ditemukan!',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  );
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_ride(p_ride_id uuid, p_reason text DEFAULT 'Dibatalkan oleh penumpang')
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id uuid;
  v_updated integer;
BEGIN
  UPDATE public.ride_requests
  SET status = 'CANCELLED',
      cancelled_at = now(),
      cancellation_reason = left(NULLIF(btrim(COALESCE(p_reason, '')), ''), 500),
      updated_at = now()
  WHERE id = p_ride_id
    AND passenger_id = auth.uid()
    AND status IN ('SEARCHING', 'ACCEPTED')
  RETURNING driver_id INTO v_driver_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Ride is not available for cancellation' USING ERRCODE = '22023';
  END IF;

  IF v_driver_id IS NOT NULL THEN
    PERFORM public.send_notification(
      (SELECT user_id FROM public.couriers WHERE id = v_driver_id),
      'Perjalanan Dibatalkan',
      'Penumpang membatalkan perjalanan ojek',
      'ride',
      '/courier/rides'
    );
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_ride_rating(
  p_ride_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '22023';
  END IF;

  UPDATE public.ride_requests
  SET rating = p_rating,
      rating_comment = NULLIF(left(btrim(COALESCE(p_comment, '')), 500), ''),
      updated_at = now()
  WHERE id = p_ride_id
    AND passenger_id = auth.uid()
    AND status = 'COMPLETED'
    AND rating IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Ride is not eligible for rating or has already been rated' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object('ride_id', p_ride_id, 'rating', p_rating);
END;
$$;

-- All sensitive ride mutations now go through the RPCs above.
REVOKE INSERT, UPDATE ON public.ride_requests FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_ride_request(numeric, numeric, text, numeric, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_ride(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_ride_rating(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 52_20260911110000_ride_authoritative_mutations.sql =====

-- ===== BEGIN BUNDLE: 53_20260911120000_courier_booking_dispatch.sql =====
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
  -- COD is intentionally free for every courier transaction.
  v_cod_fee integer := 0;
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
    UPDATE public.orders
    SET courier_id = v_courier.id,
        assigned_at = COALESCE(assigned_at, now()),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = v_order.id;
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
-- ===== END BUNDLE: 53_20260911120000_courier_booking_dispatch.sql =====

-- ===== BEGIN BUNDLE: 54_20260912202000_delivery_assignments_updated_at_compatibility.sql =====
-- Keep delivery offer RPCs compatible with projects created before the
-- delivery_assignments.updated_at column was introduced.
ALTER TABLE public.delivery_assignments
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.delivery_assignments
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;
-- ===== END BUNDLE: 54_20260912202000_delivery_assignments_updated_at_compatibility.sql =====

-- ===== BEGIN BUNDLE: 55_20260912204000_allow_expedition_handoff.sql =====
-- Allow the merchant expedition handoff action to move an order from
-- PROCESSED directly to SENT. Other status transitions remain restricted.
CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL,
  p_is_self_delivery boolean DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_allowed boolean := false;
  v_from text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = auth.uid()
  LIMIT 1;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_from := v_order.status;
  v_allowed := CASE
    WHEN v_from IN ('NEW', 'PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED', 'CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PENDING_PAYMENT' AND p_to_status IN ('CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status IN ('READY', 'DELIVERING', 'ASSIGNED', 'CANCELED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION' THEN true
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000';
  END IF;

  UPDATE public.orders SET
    status = p_to_status,
    is_self_delivery = COALESCE(p_is_self_delivery, is_self_delivery),
    confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
    ready_at = CASE WHEN p_to_status = 'READY' THEN now() ELSE ready_at END,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from, p_to_status, auth.uid(), NULLIF(trim(p_reason), ''));

  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 55_20260912204000_allow_expedition_handoff.sql =====

-- ===== BEGIN BUNDLE: 56_20260912211000_add_expedition_tracking_fields.sql =====
-- Store the two required shipment details on the order itself.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS expedition_name text,
  ADD COLUMN IF NOT EXISTS tracking_number text;

CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL,
  p_is_self_delivery boolean DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_allowed boolean := false;
  v_from text;
  v_payload jsonb := CASE WHEN left(trim(coalesce(p_reason, '')), 1) = '{' THEN p_reason::jsonb ELSE '{}'::jsonb END;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_from := v_order.status;
  v_allowed := CASE
    WHEN v_from IN ('NEW', 'PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED', 'CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PENDING_PAYMENT' AND p_to_status IN ('CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status IN ('READY', 'DELIVERING', 'ASSIGNED', 'CANCELED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION' THEN true
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000'; END IF;

  IF p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION'
     AND (NULLIF(trim(v_payload->>'expedition_name'), '') IS NULL
       OR NULLIF(trim(v_payload->>'tracking_number'), '') IS NULL) THEN
    RAISE EXCEPTION 'Expedition name and tracking number are required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET
    status = p_to_status,
    is_self_delivery = COALESCE(p_is_self_delivery, is_self_delivery),
    expedition_name = COALESCE(NULLIF(v_payload->>'expedition_name', ''), expedition_name),
    tracking_number = COALESCE(NULLIF(v_payload->>'tracking_number', ''), tracking_number),
    confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
    ready_at = CASE WHEN p_to_status = 'READY' THEN now() ELSE ready_at END,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from, p_to_status, auth.uid(), CASE WHEN v_payload ? 'type' THEN 'Diserahkan ke ekspedisi' ELSE NULLIF(trim(p_reason), '') END);
  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 56_20260912211000_add_expedition_tracking_fields.sql =====

-- ===== BEGIN BUNDLE: 57_20260912220000_buyer_order_cancellation.sql =====
-- Authoritative buyer cancellation path.
-- Stock reservation release is handled by the existing order-status trigger.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS cancellation_type text;

CREATE OR REPLACE FUNCTION public.buyer_cancel_order(
  p_order_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
  v_previous_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF length(COALESCE(v_reason, '')) < 3 OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'Cancellation reason is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_previous_status := v_order.status;
  IF v_previous_status NOT IN ('NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION') THEN
    RAISE EXCEPTION 'Order cannot be canceled from status %', v_previous_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET status = 'CANCELED',
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      cancellation_reason = v_reason,
      cancellation_type = 'BUYER',
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_previous_status, 'CANCELED', auth.uid(), v_reason);

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'from_status', v_previous_status,
    'to_status', 'CANCELED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buyer_cancel_order(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_cancel_order(uuid, text) TO authenticated;

-- Buyer mutations must go through scoped RPCs, never a broad row update.
DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders;
REVOKE UPDATE ON public.orders FROM authenticated, anon;

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 57_20260912220000_buyer_order_cancellation.sql =====

-- ===== BEGIN BUNDLE: 58_20260912230500_refund_shortfall_policy.sql =====
-- Refund shortfall policy.
-- A successful buyer refund must never be hidden by clamping a merchant balance
-- to zero. The deducted amount and any unpaid remainder are recorded separately.

CREATE TABLE IF NOT EXISTS public.merchant_refund_shortfalls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id uuid NOT NULL UNIQUE REFERENCES public.refund_settlements(id) ON DELETE RESTRICT,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
  refund_request_id uuid NOT NULL UNIQUE REFERENCES public.refund_requests(id) ON DELETE RESTRICT,
  amount numeric NOT NULL CHECK (amount > 0),
  deducted_amount numeric NOT NULL DEFAULT 0 CHECK (deducted_amount >= 0),
  outstanding_amount numeric NOT NULL CHECK (outstanding_amount >= 0),
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RECOVERED')),
  recovered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.merchant_refund_shortfalls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins manage refund shortfalls" ON public.merchant_refund_shortfalls;
CREATE POLICY "Admins manage refund shortfalls" ON public.merchant_refund_shortfalls
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON public.merchant_refund_shortfalls FROM anon, authenticated;
GRANT SELECT ON public.merchant_refund_shortfalls TO authenticated;

CREATE INDEX IF NOT EXISTS idx_refund_shortfalls_merchant_status
  ON public.merchant_refund_shortfalls(merchant_id, status);

CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_balance numeric := 0;
  v_deducted numeric := 0;
  v_shortfall numeric := 0;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Settlement worker access required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_settlement FROM public.refund_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Settlement not found' USING ERRCODE = 'P0002'; END IF;
  IF v_settlement.status = 'COMPLETED' THEN
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED', 'duplicate', true);
  END IF;
  IF NOT p_success THEN
    UPDATE public.refund_settlements
      SET status = 'FAILED', last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now()
      WHERE id = p_settlement_id;
    UPDATE public.refund_requests SET settlement_status = 'FAILED', updated_at = now()
      WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;

  SELECT COALESCE(m.available_balance, 0) INTO v_balance
    FROM public.merchants m WHERE m.id = v_settlement.merchant_id FOR UPDATE;
  v_deducted := LEAST(GREATEST(v_balance, 0), v_settlement.amount);
  v_shortfall := GREATEST(v_settlement.amount - v_deducted, 0);

  UPDATE public.refund_settlements
    SET status = 'COMPLETED', provider_reference = left(p_provider_reference, 200),
        updated_at = now(), completed_at = now()
    WHERE id = p_settlement_id;
  UPDATE public.refund_requests SET settlement_status = 'COMPLETED', updated_at = now()
    WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now()
    WHERE id = v_settlement.order_id;
  UPDATE public.merchants
    SET available_balance = COALESCE(available_balance, 0) - v_deducted, updated_at = now()
    WHERE id = v_settlement.merchant_id;

  IF v_shortfall > 0 THEN
    INSERT INTO public.merchant_refund_shortfalls(
      settlement_id, merchant_id, order_id, refund_request_id,
      amount, deducted_amount, outstanding_amount, status
    ) VALUES (
      v_settlement.id, v_settlement.merchant_id, v_settlement.order_id, v_settlement.refund_request_id,
      v_settlement.amount, v_deducted, v_shortfall, 'OPEN'
    ) ON CONFLICT (settlement_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'id', p_settlement_id,
    'status', 'COMPLETED',
    'deducted_amount', v_deducted,
    'shortfall_amount', v_shortfall,
    'shortfall_status', CASE WHEN v_shortfall > 0 THEN 'OPEN' ELSE 'NONE' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) TO service_role;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 58_20260912230500_refund_shortfall_policy.sql =====

-- ===== BEGIN BUNDLE: 59_20260912233000_village_tourism_feature_schema.sql =====
-- Village tourism feature contract.
-- The frontend uses these tables; keep this migration idempotent so it can be
-- replayed by the canonical bootstrap deployment.

ALTER TABLE public.villages
  ADD COLUMN IF NOT EXISTS province_code text,
  ADD COLUMN IF NOT EXISTS regency_code text,
  ADD COLUMN IF NOT EXISTS district_code text,
  ADD COLUMN IF NOT EXISTS village_code text,
  ADD COLUMN IF NOT EXISTS subdistrict text,
  ADD COLUMN IF NOT EXISTS gallery_urls text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS social_media jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS website text,
  ADD COLUMN IF NOT EXISTS qr_code_url text;

CREATE TABLE IF NOT EXISTS public.tourism_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  description text,
  image_url text,
  price numeric NOT NULL DEFAULT 0 CHECK (price >= 0),
  duration_days integer NOT NULL DEFAULT 1 CHECK (duration_days BETWEEN 1 AND 365),
  min_persons integer NOT NULL DEFAULT 1 CHECK (min_persons >= 1),
  max_persons integer NOT NULL DEFAULT 20 CHECK (max_persons >= min_persons),
  includes text[] NOT NULL DEFAULT '{}',
  itinerary jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  guide_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tourism_guides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  phone text,
  specialization text,
  languages text[] NOT NULL DEFAULT '{}',
  photo_url text,
  daily_rate numeric NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  bio text,
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.tourism_packages
  DROP CONSTRAINT IF EXISTS tourism_packages_guide_id_fkey;
ALTER TABLE public.tourism_packages
  ADD CONSTRAINT tourism_packages_guide_id_fkey FOREIGN KEY (guide_id)
  REFERENCES public.tourism_guides(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.tourism_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid REFERENCES public.tourism_packages(id) ON DELETE SET NULL,
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  guide_id uuid REFERENCES public.tourism_guides(id) ON DELETE SET NULL,
  visit_date date NOT NULL,
  persons integer NOT NULL CHECK (persons >= 1),
  total_price numeric NOT NULL DEFAULT 0 CHECK (total_price >= 0),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
  payment_status text NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID', 'PAID', 'REFUNDED')),
  notes text,
  contact_name text NOT NULL,
  contact_phone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.village_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  description text,
  event_type text NOT NULL DEFAULT 'lainnya',
  location text,
  start_date date NOT NULL,
  end_date date,
  organizer text,
  status text NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'ongoing', 'completed', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS public.donation_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  village_id uuid NOT NULL REFERENCES public.villages(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 180),
  description text,
  story text,
  image_url text,
  target_amount numeric NOT NULL CHECK (target_amount > 0),
  current_amount numeric NOT NULL DEFAULT 0 CHECK (current_amount >= 0),
  donor_count integer NOT NULL DEFAULT 0 CHECK (donor_count >= 0),
  category text NOT NULL DEFAULT 'lainnya',
  deadline date,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.donations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.donation_campaigns(id) ON DELETE CASCADE,
  donor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  amount numeric NOT NULL CHECK (amount > 0),
  message text,
  is_anonymous boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID', 'CANCELLED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tourism_packages_village ON public.tourism_packages(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tourism_guides_village ON public.tourism_guides(village_id, name);
CREATE INDEX IF NOT EXISTS idx_tourism_bookings_village ON public.tourism_bookings(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_village_events_village ON public.village_events(village_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_donation_campaigns_village ON public.donation_campaigns(village_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_donations_campaign ON public.donations(campaign_id, created_at DESC);

ALTER TABLE public.tourism_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism_guides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tourism_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.village_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

-- Public read paths.
DROP POLICY IF EXISTS "Public can view active tourism packages" ON public.tourism_packages;
CREATE POLICY "Public can view active tourism packages" ON public.tourism_packages
  FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Public can view available guides" ON public.tourism_guides;
CREATE POLICY "Public can view available guides" ON public.tourism_guides
  FOR SELECT USING (is_available = true);
DROP POLICY IF EXISTS "Public can view village events" ON public.village_events;
CREATE POLICY "Public can view village events" ON public.village_events
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Public can view active campaigns" ON public.donation_campaigns;
CREATE POLICY "Public can view active campaigns" ON public.donation_campaigns
  FOR SELECT USING (is_active = true);

-- Admin desa ownership helper is intentionally repeated in each policy so RLS
-- remains correct even when a user is assigned to more than one village.
DROP POLICY IF EXISTS "Village admins manage tourism packages" ON public.tourism_packages;
CREATE POLICY "Village admins manage tourism packages" ON public.tourism_packages
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_packages.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_packages.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage tourism guides" ON public.tourism_guides;
CREATE POLICY "Village admins manage tourism guides" ON public.tourism_guides
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_guides.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_guides.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage village events" ON public.village_events;
CREATE POLICY "Village admins manage village events" ON public.village_events
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = village_events.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = village_events.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));
DROP POLICY IF EXISTS "Village admins manage donation campaigns" ON public.donation_campaigns;
CREATE POLICY "Village admins manage donation campaigns" ON public.donation_campaigns
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = donation_campaigns.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = donation_campaigns.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));

DROP POLICY IF EXISTS "Buyers view own tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Buyers view own tourism bookings" ON public.tourism_bookings FOR SELECT USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Buyers create tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Buyers create tourism bookings" ON public.tourism_bookings FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Village admins manage tourism bookings" ON public.tourism_bookings;
CREATE POLICY "Village admins manage tourism bookings" ON public.tourism_bookings
  FOR ALL USING (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_bookings.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'))
  WITH CHECK (public.is_admin() OR EXISTS (SELECT 1 FROM public.user_villages uv WHERE uv.village_id = tourism_bookings.village_id AND uv.user_id = auth.uid() AND uv.role = 'admin_desa'));

DROP POLICY IF EXISTS "Public can view donations" ON public.donations;
CREATE POLICY "Public can view donations" ON public.donations FOR SELECT USING (status = 'PAID');
DROP POLICY IF EXISTS "Authenticated users create donations" ON public.donations;
CREATE POLICY "Authenticated users create donations" ON public.donations FOR INSERT WITH CHECK (donor_id IS NULL OR donor_id = auth.uid());
DROP POLICY IF EXISTS "Village admins view campaign donations" ON public.donations;
CREATE POLICY "Village admins view campaign donations" ON public.donations FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.donation_campaigns c JOIN public.user_villages uv ON uv.village_id = c.village_id WHERE c.id = donations.campaign_id AND (public.is_admin() OR (uv.user_id = auth.uid() AND uv.role = 'admin_desa')))
);

GRANT SELECT ON public.tourism_packages, public.tourism_guides, public.village_events, public.donation_campaigns, public.donations TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tourism_packages, public.tourism_guides, public.tourism_bookings, public.village_events, public.donation_campaigns, public.donations TO authenticated;
GRANT ALL ON public.tourism_packages, public.tourism_guides, public.tourism_bookings, public.village_events, public.donation_campaigns, public.donations TO service_role;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 59_20260912233000_village_tourism_feature_schema.sql =====

-- ===== BEGIN BUNDLE: 60_20260912233500_remove_merchant_transition_legacy_overload.sql =====
-- Keep one canonical merchant transition signature.
-- The 3-argument overload could be selected by stale clients/PostgREST and
-- bypass the expedition/self-delivery fields expected by the current UI.
DROP FUNCTION IF EXISTS public.merchant_transition_order(uuid, text, text);
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 60_20260912233500_remove_merchant_transition_legacy_overload.sql =====

-- ===== BEGIN BUNDLE: 60_20260921190000_admin_direct_chat.sql =====
-- Admin direct chat: admin can start a new conversation with any active merchant or courier.
-- This is independent from order/ride chat and does not require a prior message.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS direct_admin_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS direct_target_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_one_context;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_one_context CHECK (
  (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'direct' AND order_id IS NULL AND ride_request_id IS NULL AND (
    (merchant_id IS NOT NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
    OR (merchant_id IS NULL AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL)
  ))
);

ALTER TABLE public.chat_participants DROP CONSTRAINT IF EXISTS chat_participants_role_check;
ALTER TABLE public.chat_participants ADD CONSTRAINT chat_participants_role_check
  CHECK (role IN ('admin', 'buyer', 'merchant', 'courier', 'passenger'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier'));

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_admin_direct_uidx
  ON public.chat_conversations(direct_admin_user_id, direct_target_user_id, conversation_type)
  WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
  p_target_user_id uuid,
  p_target_role text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_type text;
  v_target_exists boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid() OR p_target_role NOT IN ('merchant', 'courier') THEN
    RAISE EXCEPTION 'invalid chat target' USING ERRCODE = '22023';
  END IF;

  IF p_target_role = 'merchant' THEN
    SELECT EXISTS (SELECT 1 FROM public.merchants WHERE user_id = p_target_user_id AND status = 'ACTIVE') INTO v_target_exists;
    v_type := 'admin_merchant';
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.couriers WHERE user_id = p_target_user_id AND registration_status = 'APPROVED') INTO v_target_exists;
    v_type := 'admin_courier';
  END IF;
  IF NOT v_target_exists THEN
    RAISE EXCEPTION 'chat target account not found or inactive' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (context_type, conversation_type, direct_admin_user_id, direct_target_user_id)
  VALUES ('direct', v_type, auth.uid(), p_target_user_id)
  ON CONFLICT (direct_admin_user_id, direct_target_user_id, conversation_type)
    WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES (v_conversation_id, auth.uid(), 'admin'), (v_conversation_id, p_target_user_id, p_target_role)
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET left_at = NULL, role = EXCLUDED.role;
  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated;
-- ===== END BUNDLE: 60_20260921190000_admin_direct_chat.sql =====

-- ===== BEGIN BUNDLE: 61_20260913102500_remove_legacy_quota_overloads.sql =====
-- RPC overload cleanup.
-- The canonical quota function is:
--   use_merchant_quota(uuid)
--   use_merchant_quota_v2(uuid, integer, uuid DEFAULT NULL)
-- The old two-argument v2 function has the same effective call shape as the
-- canonical three-argument function because p_order_id has a default. Remove
-- it so PostgREST and PL/pgSQL cannot resolve a stale/ambiguous overload.
DROP FUNCTION IF EXISTS public.use_merchant_quota_v2(uuid, integer);

-- This older quota function was already deprecated in the application and is
-- not referenced by current source or RLS policies. Keep only the one-credit
-- wrapper and deduct_merchant_quota(uuid, integer).
DROP FUNCTION IF EXISTS public.use_merchant_quota(uuid, integer);

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 61_20260913102500_remove_legacy_quota_overloads.sql =====

-- ===== BEGIN BUNDLE: 62_20260913104000_expedition_provider_master.sql =====
-- Dynamic expedition provider master.
CREATE TABLE IF NOT EXISTS public.expedition_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  logo_url text,
  tracking_website text NOT NULL CHECK (tracking_website ~ '^https?://'),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT expedition_providers_name_unique UNIQUE (name)
);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS expedition_provider_id uuid REFERENCES public.expedition_providers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS expedition_name_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_logo_url_snapshot text,
  ADD COLUMN IF NOT EXISTS expedition_tracking_url_snapshot text;

CREATE INDEX IF NOT EXISTS idx_expedition_providers_active_order
  ON public.expedition_providers(is_active, sort_order, name);
CREATE INDEX IF NOT EXISTS idx_orders_expedition_provider
  ON public.orders(expedition_provider_id);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('expedition-logos', 'expedition-logos', true, 2097152, ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml'])
ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml'];

ALTER TABLE public.expedition_providers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view active expedition providers" ON public.expedition_providers;
CREATE POLICY "Anyone can view active expedition providers" ON public.expedition_providers
  FOR SELECT USING (is_active = true OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage expedition providers" ON public.expedition_providers;
CREATE POLICY "Admins manage expedition providers" ON public.expedition_providers
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Public can view expedition logos" ON storage.objects;
CREATE POLICY "Public can view expedition logos" ON storage.objects
  FOR SELECT USING (bucket_id = 'expedition-logos');
DROP POLICY IF EXISTS "Admins upload expedition logos" ON storage.objects;
CREATE POLICY "Admins upload expedition logos" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'expedition-logos' AND public.is_admin());
DROP POLICY IF EXISTS "Admins update expedition logos" ON storage.objects;
CREATE POLICY "Admins update expedition logos" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'expedition-logos' AND public.is_admin())
  WITH CHECK (bucket_id = 'expedition-logos' AND public.is_admin());
DROP POLICY IF EXISTS "Admins delete expedition logos" ON storage.objects;
CREATE POLICY "Admins delete expedition logos" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'expedition-logos' AND public.is_admin());

GRANT SELECT ON public.expedition_providers TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.expedition_providers TO authenticated;
GRANT ALL ON public.expedition_providers TO service_role;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 62_20260913104000_expedition_provider_master.sql =====

-- ===== BEGIN BUNDLE: 63_20260913104500_expedition_provider_handoff_snapshot.sql =====
-- Extend the canonical merchant handoff to persist provider identity and
-- immutable display snapshots for historical orders.
CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL,
  p_is_self_delivery boolean DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_allowed boolean := false;
  v_from text;
  v_payload jsonb := CASE WHEN left(trim(coalesce(p_reason, '')), 1) = '{' THEN p_reason::jsonb ELSE '{}'::jsonb END;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_from := v_order.status;
  v_allowed := CASE
    WHEN v_from IN ('NEW', 'PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED', 'CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PENDING_PAYMENT' AND p_to_status IN ('CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status IN ('READY', 'DELIVERING', 'ASSIGNED', 'CANCELED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION' THEN true
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000'; END IF;

  IF p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION'
     AND (NULLIF(trim(v_payload->>'expedition_provider_id'), '') IS NULL
       OR NULLIF(trim(v_payload->>'expedition_name'), '') IS NULL
       OR NULLIF(trim(v_payload->>'tracking_number'), '') IS NULL
       OR NULLIF(trim(v_payload->>'expedition_tracking_url'), '') IS NULL) THEN
    RAISE EXCEPTION 'Expedition provider, name, tracking website, and tracking number are required' USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION'
     AND NOT EXISTS (SELECT 1 FROM public.expedition_providers ep WHERE ep.id = (v_payload->>'expedition_provider_id')::uuid AND ep.is_active = true) THEN
    RAISE EXCEPTION 'Expedition provider is not active or does not exist' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET
    status = p_to_status,
    is_self_delivery = COALESCE(p_is_self_delivery, is_self_delivery),
    expedition_provider_id = CASE WHEN p_to_status = 'SENT' THEN (v_payload->>'expedition_provider_id')::uuid ELSE expedition_provider_id END,
    expedition_name = COALESCE(NULLIF(v_payload->>'expedition_name', ''), expedition_name),
    tracking_number = COALESCE(NULLIF(v_payload->>'tracking_number', ''), tracking_number),
    expedition_name_snapshot = COALESCE(NULLIF(v_payload->>'expedition_name', ''), expedition_name_snapshot),
    expedition_logo_url_snapshot = COALESCE(NULLIF(v_payload->>'expedition_logo_url', ''), expedition_logo_url_snapshot),
    expedition_tracking_url_snapshot = COALESCE(NULLIF(v_payload->>'expedition_tracking_url', ''), expedition_tracking_url_snapshot),
    confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
    ready_at = CASE WHEN p_to_status = 'READY' THEN now() ELSE ready_at END,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from, p_to_status, auth.uid(), CASE WHEN v_payload ? 'type' THEN 'Diserahkan ke ekspedisi' ELSE NULLIF(trim(p_reason), '') END);
  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 63_20260913104500_expedition_provider_handoff_snapshot.sql =====

-- ===== BEGIN BUNDLE: 64_20260913105000_optional_expedition_tracking_website.sql =====
ALTER TABLE public.expedition_providers ALTER COLUMN tracking_website DROP NOT NULL;
ALTER TABLE public.expedition_providers DROP CONSTRAINT IF EXISTS expedition_providers_tracking_website_check;
ALTER TABLE public.expedition_providers ADD CONSTRAINT expedition_providers_tracking_website_check CHECK (tracking_website IS NULL OR tracking_website ~ '^https?://');

-- Extend the canonical merchant handoff to persist provider identity and
-- immutable display snapshots for historical orders.
CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL,
  p_is_self_delivery boolean DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_allowed boolean := false;
  v_from text;
  v_payload jsonb := CASE WHEN left(trim(coalesce(p_reason, '')), 1) = '{' THEN p_reason::jsonb ELSE '{}'::jsonb END;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_from := v_order.status;
  v_allowed := CASE
    WHEN v_from IN ('NEW', 'PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED', 'CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PENDING_PAYMENT' AND p_to_status IN ('CANCELED', 'REJECTED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status IN ('READY', 'DELIVERING', 'ASSIGNED', 'CANCELED') THEN true
    WHEN v_from = 'PROCESSED' AND p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION' THEN true
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false
  END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000'; END IF;

  IF p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION'
     AND (NULLIF(trim(v_payload->>'expedition_provider_id'), '') IS NULL
       OR NULLIF(trim(v_payload->>'expedition_name'), '') IS NULL
       OR NULLIF(trim(v_payload->>'tracking_number'), '') IS NULL
        ) THEN
    RAISE EXCEPTION 'Expedition provider, name, and tracking number are required' USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'SENT' AND v_order.delivery_type = 'EXPEDITION'
     AND NOT EXISTS (SELECT 1 FROM public.expedition_providers ep WHERE ep.id = (v_payload->>'expedition_provider_id')::uuid AND ep.is_active = true) THEN
    RAISE EXCEPTION 'Expedition provider is not active or does not exist' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET
    status = p_to_status,
    is_self_delivery = COALESCE(p_is_self_delivery, is_self_delivery),
    expedition_provider_id = CASE WHEN p_to_status = 'SENT' THEN (v_payload->>'expedition_provider_id')::uuid ELSE expedition_provider_id END,
    expedition_name = COALESCE(NULLIF(v_payload->>'expedition_name', ''), expedition_name),
    tracking_number = COALESCE(NULLIF(v_payload->>'tracking_number', ''), tracking_number),
    expedition_name_snapshot = COALESCE(NULLIF(v_payload->>'expedition_name', ''), expedition_name_snapshot),
    expedition_logo_url_snapshot = COALESCE(NULLIF(v_payload->>'expedition_logo_url', ''), expedition_logo_url_snapshot),
    expedition_tracking_url_snapshot = COALESCE(NULLIF(v_payload->>'expedition_tracking_url', ''), expedition_tracking_url_snapshot),
    confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
    ready_at = CASE WHEN p_to_status = 'READY' THEN now() ELSE ready_at END,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from, p_to_status, auth.uid(), CASE WHEN v_payload ? 'type' THEN 'Diserahkan ke ekspedisi' ELSE NULLIF(trim(p_reason), '') END);
  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 64_20260913105000_optional_expedition_tracking_website.sql =====

-- ===== BEGIN BUNDLE: 65_20260914150000_driver_workflow_hardening.sql =====
-- Driver workflow hardening: explicit pickup/earning contract and safe release actions.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_earning_estimate integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_released_at timestamptz,
  ADD COLUMN IF NOT EXISTS courier_release_reason text;

UPDATE public.orders
SET courier_earning_estimate = shipping_cost,
    courier_platform_fee = 0
WHERE courier_earning_estimate = 0 AND shipping_cost > 0;

CREATE OR REPLACE FUNCTION public.courier_release_order(p_order_id uuid, p_reason text)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_from_status text;
  v_reason text := NULLIF(left(btrim(p_reason), 500), '');
BEGIN
  IF v_reason IS NULL THEN RAISE EXCEPTION 'Release reason is required' USING ERRCODE = '22023'; END IF;
  SELECT id INTO v_courier_id FROM public.couriers WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED' LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND courier_id = v_courier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501'; END IF;
  IF v_order.status NOT IN ('COURIER_ACCEPTED','PICKED_UP','SENT','DELIVERING') THEN
    RAISE EXCEPTION 'Order cannot be released from status %', v_order.status USING ERRCODE = '22023';
  END IF;
  v_from_status := v_order.status;
  UPDATE public.delivery_assignments SET status = 'CANCELED', responded_at = now(), rejection_reason = v_reason, updated_at = now()
    WHERE order_id = p_order_id AND courier_id = v_courier_id AND status = 'ACCEPTED';
  UPDATE public.orders SET courier_id = NULL, status = 'ASSIGNED', courier_released_at = now(), courier_release_reason = v_reason, status_updated_at = now(), updated_at = now()
    WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (p_order_id, v_from_status, 'ASSIGNED', auth.uid(), 'Kurir melepas tugas: ' || v_reason);
  IF v_order.buyer_id IS NOT NULL THEN
    PERFORM public.send_notification(v_order.buyer_id, 'Pesanan perlu kurir baru', 'Kurir melepas tugas: ' || v_reason, 'order', '/orders/' || p_order_id::text);
  END IF;
  IF v_order.merchant_id IS NOT NULL THEN
    PERFORM public.send_notification(m.user_id, 'Kurir melepas pesanan', 'Pesanan dikembalikan untuk penugasan ulang.', 'order', '/merchant/orders')
      FROM public.merchants m WHERE m.id = v_order.merchant_id AND m.user_id IS NOT NULL;
  END IF;
  RETURN v_order;
END; $$;

GRANT EXECUTE ON FUNCTION public.courier_release_order(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.driver_cancel_ride(p_ride_id uuid, p_reason text)
RETURNS public.ride_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
  v_reason text := NULLIF(left(btrim(p_reason), 500), '');
BEGIN
  IF v_reason IS NULL THEN RAISE EXCEPTION 'Cancellation reason is required' USING ERRCODE = '22023'; END IF;
  SELECT id INTO v_courier_id FROM public.couriers WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED' LIMIT 1;
  SELECT * INTO v_ride FROM public.ride_requests WHERE id = p_ride_id AND driver_id = v_courier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ride access denied' USING ERRCODE = '42501'; END IF;
  IF v_ride.status NOT IN ('ACCEPTED','PICKED_UP','IN_TRANSIT') THEN RAISE EXCEPTION 'Ride cannot be canceled from status %', v_ride.status USING ERRCODE = '22023'; END IF;
  UPDATE public.ride_requests SET status = 'CANCELED', cancelled_at = now(), cancellation_reason = v_reason, updated_at = now() WHERE id = p_ride_id RETURNING * INTO v_ride;
  IF v_ride.passenger_id IS NOT NULL THEN
    PERFORM public.send_notification(v_ride.passenger_id, 'Perjalanan dibatalkan driver', 'Driver membatalkan perjalanan: ' || v_reason, 'ride', '/ride/' || p_ride_id::text);
  END IF;
  RETURN v_ride;
END; $$;
GRANT EXECUTE ON FUNCTION public.driver_cancel_ride(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 65_20260914150000_driver_workflow_hardening.sql =====

