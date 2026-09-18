-- Direct courier state machine: all courier mutations are authorized, locked, and audited.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_proof_url text,
  ADD COLUMN IF NOT EXISTS delivery_notes text;

ALTER TABLE public.order_status_history
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('pod-images', 'pod-images', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Couriers upload delivery proof images" ON storage.objects;
CREATE POLICY "Couriers upload delivery proof images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED'
  )
);

DROP POLICY IF EXISTS "Couriers delete own delivery proof images" ON storage.objects;
CREATE POLICY "Couriers delete own delivery proof images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'pod-images'
  AND EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.user_id = auth.uid() AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED'
  )
);

CREATE OR REPLACE FUNCTION public.courier_pickup_order(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status <> 'COURIER_ACCEPTED' THEN
    RAISE EXCEPTION 'Order is not ready for pickup' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders SET status = 'PICKED_UP', picked_up_at = now(), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, 'COURIER_ACCEPTED', 'PICKED_UP', auth.uid(), 'Kurir mengambil barang');
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_start_delivery(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT') THEN
    RAISE EXCEPTION 'Order is not ready for delivery' USING ERRCODE = '22023';
  END IF;
  UPDATE public.orders SET status = 'DELIVERING', status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, 'PICKED_UP', 'DELIVERING', auth.uid(), 'Kurir memulai pengantaran');
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_complete_delivery(p_order_id uuid, p_proof_path text, p_notes text DEFAULT NULL)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_courier_id uuid; v_from_status text;
BEGIN
  SELECT id INTO v_courier_id FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';
  IF v_courier_id IS NULL THEN RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501'; END IF;
  IF NULLIF(trim(p_proof_path), '') IS NULL THEN RAISE EXCEPTION 'Proof of delivery is required' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.service_type <> 'COURIER_DELIVERY' OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED') THEN
    RAISE EXCEPTION 'Order is not ready to complete' USING ERRCODE = '22023';
  END IF;
  -- A lost network response may cause the courier to retry after the first
  -- request already committed. Return the completed order instead of failing.
  IF v_order.status = 'DELIVERED' THEN
    IF v_order.delivery_proof_url IS NULL THEN
      UPDATE public.orders SET delivery_proof_url = p_proof_path,
        delivery_notes = COALESCE(NULLIF(trim(p_notes), ''), delivery_notes),
        updated_at = now()
      WHERE id = p_order_id RETURNING * INTO v_order;
    END IF;
    RETURN v_order;
  END IF;
  v_from_status := v_order.status;
  UPDATE public.orders SET status = 'DELIVERED', delivered_at = now(), delivery_proof_url = p_proof_path,
    delivery_notes = NULLIF(trim(p_notes), ''), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (p_order_id, v_from_status, 'DELIVERED', auth.uid(), 'Kurir menyelesaikan pengiriman', jsonb_build_object('proof_path', p_proof_path));
  RETURN v_order;
END; $$;

REVOKE ALL ON FUNCTION public.courier_pickup_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_start_delivery(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_complete_delivery(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.courier_pickup_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_start_delivery(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_complete_delivery(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
