-- Order transition and courier offer contract
-- All order fulfillment mutations must pass through these functions.

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT', 'PROCESSED', 'READY',
    'ASSIGNED', 'COURIER_ASSIGNED', 'COURIER_ACCEPTED', 'COURIER_REJECTED',
    'PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED', 'DONE', 'CANCELED',
    'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED'
  ));

CREATE TABLE IF NOT EXISTS public.order_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON public.order_status_history(order_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.delivery_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'OFFERED' CHECK (status IN ('OFFERED', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'CANCELED')),
  offered_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '5 minutes'),
  responded_at timestamptz,
  rejection_reason text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_courier_queue ON public.delivery_assignments(courier_id, status, offered_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_order ON public.delivery_assignments(order_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_assignments_active_order
  ON public.delivery_assignments(order_id)
  WHERE status IN ('OFFERED', 'ACCEPTED');

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Order participants read status history" ON public.order_status_history;
CREATE POLICY "Order participants read status history" ON public.order_status_history FOR SELECT TO authenticated
USING (
  public.is_admin() OR
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_status_history.order_id AND (
    o.buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = o.merchant_id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.couriers c WHERE c.id = o.courier_id AND c.user_id = auth.uid())
  ))
);
DROP POLICY IF EXISTS "Courier and merchant read delivery assignments" ON public.delivery_assignments;
CREATE POLICY "Courier and merchant read delivery assignments" ON public.delivery_assignments FOR SELECT TO authenticated
USING (
  public.is_admin() OR
  EXISTS (SELECT 1 FROM public.couriers c WHERE c.id = delivery_assignments.courier_id AND c.user_id = auth.uid()) OR
  EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = delivery_assignments.order_id AND m.user_id = auth.uid())
);

CREATE OR REPLACE FUNCTION public.merchant_transition_order(
  p_order_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL,
  p_is_self_delivery boolean DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_merchant_id uuid;
  v_allowed boolean := false;
  v_from text;
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
    WHEN v_from = 'READY' AND p_to_status IN ('ASSIGNED', 'DELIVERING', 'CANCELED') THEN true
    WHEN v_from = 'ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED', 'CANCELED') THEN true
    WHEN v_from = 'COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP', 'CANCELED') THEN true
    WHEN v_from = 'PICKED_UP' AND p_to_status = 'DELIVERING' THEN true
    WHEN v_from = 'DELIVERING' AND p_to_status = 'DELIVERED' THEN true
    WHEN v_from IN ('DELIVERED', 'SENT') AND p_to_status = 'DONE' THEN true
    WHEN public.is_admin() AND p_to_status IN ('CANCELED', 'REFUNDED', 'DONE') THEN true
    ELSE false END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition: % -> %', v_from, p_to_status USING ERRCODE = '55000'; END IF;

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
END; $$;

CREATE OR REPLACE FUNCTION public.merchant_offer_order_to_courier(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_assignment public.delivery_assignments%ROWTYPE; v_merchant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501'; END IF;
  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED') OR v_order.delivery_type <> 'INTERNAL' THEN RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '55000'; END IF;
  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN RAISE EXCEPTION 'Courier already rejected this order' USING ERRCODE = '55000'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.couriers c WHERE c.id = p_courier_id AND c.status = 'ACTIVE' AND c.registration_status = 'APPROVED' AND c.is_available = true) THEN RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '55000'; END IF;
  UPDATE public.delivery_assignments SET status = 'CANCELED', updated_at = now() WHERE order_id = p_order_id AND status = 'OFFERED';
  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by)
  VALUES (p_order_id, p_courier_id, auth.uid()) RETURNING * INTO v_assignment;
  UPDATE public.orders SET status = 'ASSIGNED', courier_id = p_courier_id, assigned_at = now(), updated_at = now() WHERE id = p_order_id;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, metadata)
  VALUES (p_order_id, v_order.status, 'ASSIGNED', auth.uid(), jsonb_build_object('courier_id', p_courier_id));
  RETURN v_assignment;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_respond_to_order_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_assignment public.delivery_assignments%ROWTYPE; v_order public.orders%ROWTYPE; v_courier_id uuid; v_to text;
BEGIN
  SELECT c.id INTO v_courier_id FROM public.couriers c WHERE c.user_id = auth.uid() LIMIT 1;
  SELECT * INTO v_assignment FROM public.delivery_assignments WHERE id = p_assignment_id FOR UPDATE;
  IF NOT FOUND OR v_assignment.courier_id IS DISTINCT FROM v_courier_id THEN RAISE EXCEPTION 'Assignment access denied' USING ERRCODE = '42501'; END IF;
  IF v_assignment.status <> 'OFFERED' OR v_assignment.expires_at < now() THEN RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE = '55000'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_assignment.order_id FOR UPDATE;
  IF p_accept THEN
    v_to := 'COURIER_ACCEPTED';
    UPDATE public.delivery_assignments SET status = 'ACCEPTED', responded_at = now(), updated_at = now() WHERE id = p_assignment_id RETURNING * INTO v_assignment;
    UPDATE public.orders SET status = v_to, courier_accepted_at = now(), updated_at = now() WHERE id = v_order.id;
  ELSE
    UPDATE public.delivery_assignments SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now() WHERE id = p_assignment_id RETURNING * INTO v_assignment;
    UPDATE public.orders SET status = 'ASSIGNED', courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id), updated_at = now() WHERE id = v_order.id;
    v_to := 'ASSIGNED';
  END IF;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (v_order.id, v_order.status, v_to, auth.uid(), p_reason, jsonb_build_object('assignment_id', p_assignment_id, 'courier_id', v_courier_id));
  RETURN v_assignment;
END; $$;

REVOKE ALL ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.courier_respond_to_order_offer(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_respond_to_order_offer(uuid, boolean, text) TO authenticated;
