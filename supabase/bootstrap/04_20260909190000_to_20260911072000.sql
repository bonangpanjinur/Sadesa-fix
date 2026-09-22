-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_8643cdb57e87$
BEGIN
  EXECUTE $bootstrap_sql_8643cdb57e87$-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 44_20260909190000_order_transition_and_courier_offers.sql .. 51_20260911072000_refund_settlement_hardening.sql

-- ===== BEGIN BUNDLE: 44_20260909190000_order_transition_and_courier_offers.sql =====
-- Order transition and courier offer contract
-- All order fulfillment mutations must pass through these functions.

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check$bootstrap_sql_8643cdb57e87$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8643cdb57e87$;

DO $bootstrap_do_7f32daf57666$
BEGIN
  EXECUTE $bootstrap_sql_7f32daf57666$ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT', 'PROCESSED', 'READY',
    'ASSIGNED', 'COURIER_ASSIGNED', 'COURIER_ACCEPTED', 'COURIER_REJECTED',
    'PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED', 'DONE', 'CANCELED',
    'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED'
  ))$bootstrap_sql_7f32daf57666$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f32daf57666$;

DO $bootstrap_do_0abee8b8bb4c$
BEGIN
  EXECUTE $bootstrap_sql_0abee8b8bb4c$CREATE TABLE IF NOT EXISTS public.order_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_0abee8b8bb4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0abee8b8bb4c$;

DO $bootstrap_do_d7ccf32d8395$
BEGIN
  EXECUTE $bootstrap_sql_d7ccf32d8395$CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON public.order_status_history(order_id, created_at DESC)$bootstrap_sql_d7ccf32d8395$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7ccf32d8395$;

DO $bootstrap_do_1e57c5595b45$
BEGIN
  EXECUTE $bootstrap_sql_1e57c5595b45$CREATE TABLE IF NOT EXISTS public.delivery_assignments (
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
)$bootstrap_sql_1e57c5595b45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e57c5595b45$;

DO $bootstrap_do_35c35a371e56$
BEGIN
  EXECUTE $bootstrap_sql_35c35a371e56$CREATE INDEX IF NOT EXISTS idx_delivery_assignments_courier_queue ON public.delivery_assignments(courier_id, status, offered_at DESC)$bootstrap_sql_35c35a371e56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_35c35a371e56$;

DO $bootstrap_do_68506db9b923$
BEGIN
  EXECUTE $bootstrap_sql_68506db9b923$CREATE INDEX IF NOT EXISTS idx_delivery_assignments_order ON public.delivery_assignments(order_id, created_at DESC)$bootstrap_sql_68506db9b923$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68506db9b923$;

DO $bootstrap_do_c0f560a5513f$
BEGIN
  EXECUTE $bootstrap_sql_c0f560a5513f$CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_assignments_active_order
  ON public.delivery_assignments(order_id)
  WHERE status IN ('OFFERED', 'ACCEPTED')$bootstrap_sql_c0f560a5513f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0f560a5513f$;

DO $bootstrap_do_b77e542ce1d0$
BEGIN
  EXECUTE $bootstrap_sql_b77e542ce1d0$ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY$bootstrap_sql_b77e542ce1d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b77e542ce1d0$;

DO $bootstrap_do_4a2afa83499d$
BEGIN
  EXECUTE $bootstrap_sql_4a2afa83499d$ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY$bootstrap_sql_4a2afa83499d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a2afa83499d$;

DO $bootstrap_do_709361eadd40$
BEGIN
  EXECUTE $bootstrap_sql_709361eadd40$DROP POLICY IF EXISTS "Order participants read status history" ON public.order_status_history$bootstrap_sql_709361eadd40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_709361eadd40$;

DO $bootstrap_do_6b21fb425adb$
BEGIN
  EXECUTE $bootstrap_sql_6b21fb425adb$CREATE POLICY "Order participants read status history" ON public.order_status_history FOR SELECT TO authenticated
USING (
  public.is_admin() OR
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_status_history.order_id AND (
    o.buyer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = o.merchant_id AND m.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.couriers c WHERE c.id = o.courier_id AND c.user_id = auth.uid())
  ))
)$bootstrap_sql_6b21fb425adb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b21fb425adb$;

DO $bootstrap_do_723eaa0a43f3$
BEGIN
  EXECUTE $bootstrap_sql_723eaa0a43f3$DROP POLICY IF EXISTS "Courier and merchant read delivery assignments" ON public.delivery_assignments$bootstrap_sql_723eaa0a43f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_723eaa0a43f3$;

DO $bootstrap_do_6f4ccfb7e1f0$
BEGIN
  EXECUTE $bootstrap_sql_6f4ccfb7e1f0$CREATE POLICY "Courier and merchant read delivery assignments" ON public.delivery_assignments FOR SELECT TO authenticated
USING (
  public.is_admin() OR
  EXISTS (SELECT 1 FROM public.couriers c WHERE c.id = delivery_assignments.courier_id AND c.user_id = auth.uid()) OR
  EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id WHERE o.id = delivery_assignments.order_id AND m.user_id = auth.uid())
)$bootstrap_sql_6f4ccfb7e1f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f4ccfb7e1f0$;

DO $bootstrap_do_0c236120a322$
BEGIN
  EXECUTE $bootstrap_sql_0c236120a322$CREATE OR REPLACE FUNCTION public.merchant_transition_order(
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
END; $$$bootstrap_sql_0c236120a322$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c236120a322$;

DO $bootstrap_do_741706a76e10$
BEGIN
  EXECUTE $bootstrap_sql_741706a76e10$CREATE OR REPLACE FUNCTION public.merchant_offer_order_to_courier(p_order_id uuid, p_courier_id uuid)
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
END; $$$bootstrap_sql_741706a76e10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_741706a76e10$;

DO $bootstrap_do_65aa695753e5$
BEGIN
  EXECUTE $bootstrap_sql_65aa695753e5$CREATE OR REPLACE FUNCTION public.courier_respond_to_order_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
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
END; $$$bootstrap_sql_65aa695753e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_65aa695753e5$;

DO $bootstrap_do_67a9e3d7772a$
BEGIN
  EXECUTE $bootstrap_sql_67a9e3d7772a$REVOKE ALL ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) FROM PUBLIC$bootstrap_sql_67a9e3d7772a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67a9e3d7772a$;

DO $bootstrap_do_27b51be57fcf$
BEGIN
  EXECUTE $bootstrap_sql_27b51be57fcf$REVOKE ALL ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) FROM PUBLIC$bootstrap_sql_27b51be57fcf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27b51be57fcf$;

DO $bootstrap_do_1ee0e444753c$
BEGIN
  EXECUTE $bootstrap_sql_1ee0e444753c$REVOKE ALL ON FUNCTION public.courier_respond_to_order_offer(uuid, boolean, text) FROM PUBLIC$bootstrap_sql_1ee0e444753c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ee0e444753c$;

DO $bootstrap_do_6e82fe765348$
BEGIN
  EXECUTE $bootstrap_sql_6e82fe765348$GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text, boolean) TO authenticated$bootstrap_sql_6e82fe765348$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e82fe765348$;

DO $bootstrap_do_518902cd9bfd$
BEGIN
  EXECUTE $bootstrap_sql_518902cd9bfd$GRANT EXECUTE ON FUNCTION public.merchant_offer_order_to_courier(uuid, uuid) TO authenticated$bootstrap_sql_518902cd9bfd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_518902cd9bfd$;

DO $bootstrap_do_3c64e50527ae$
BEGIN
  EXECUTE $bootstrap_sql_3c64e50527ae$GRANT EXECUTE ON FUNCTION public.courier_respond_to_order_offer(uuid, boolean, text) TO authenticated$bootstrap_sql_3c64e50527ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c64e50527ae$;

DO $bootstrap_do_e1ac7341fe4e$
BEGIN
  EXECUTE $bootstrap_sql_e1ac7341fe4e$-- ===== END BUNDLE: 44_20260909190000_order_transition_and_courier_offers.sql =====

-- ===== BEGIN BUNDLE: 44_20260909193000_order_workflow_rpc.sql =====
-- Order workflow hardening: canonical transitions, courier offers, and self-delivery fee ledger.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check$bootstrap_sql_e1ac7341fe4e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1ac7341fe4e$;

DO $bootstrap_do_f388fb01350a$
BEGIN
  EXECUTE $bootstrap_sql_f388fb01350a$ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW','PENDING_CONFIRMATION','PENDING_PAYMENT','PROCESSED','READY','ASSIGNED',
    'COURIER_ASSIGNED','COURIER_ACCEPTED','COURIER_REJECTED','PICKED_UP','SENT',
    'DELIVERING','DELIVERED','DONE','CANCELED','REJECTED','REJECTED_BY_BUYER','REFUNDED'
  ))$bootstrap_sql_f388fb01350a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f388fb01350a$;

DO $bootstrap_do_23acb941da44$
BEGIN
  EXECUTE $bootstrap_sql_23acb941da44$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status_updated_at timestamptz$bootstrap_sql_23acb941da44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23acb941da44$;

DO $bootstrap_do_bba214314fe1$
BEGIN
  EXECUTE $bootstrap_sql_bba214314fe1$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_attempt integer NOT NULL DEFAULT 0$bootstrap_sql_bba214314fe1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bba214314fe1$;

DO $bootstrap_do_ec6df79c7018$
BEGIN
  EXECUTE $bootstrap_sql_ec6df79c7018$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_fee_amount numeric NOT NULL DEFAULT 0$bootstrap_sql_ec6df79c7018$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec6df79c7018$;

DO $bootstrap_do_d75f6b277c2a$
BEGIN
  EXECUTE $bootstrap_sql_d75f6b277c2a$ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_fee_status text NOT NULL DEFAULT 'NOT_APPLICABLE'$bootstrap_sql_d75f6b277c2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d75f6b277c2a$;

DO $bootstrap_do_48edfae8a423$
BEGIN
  EXECUTE $bootstrap_sql_48edfae8a423$CREATE TABLE IF NOT EXISTS public.order_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_48edfae8a423$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_48edfae8a423$;

DO $bootstrap_do_6b5b13385d67$
BEGIN
  EXECUTE $bootstrap_sql_6b5b13385d67$CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON public.order_status_history(order_id, created_at DESC)$bootstrap_sql_6b5b13385d67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b5b13385d67$;

DO $bootstrap_do_68272c71531c$
BEGIN
  EXECUTE $bootstrap_sql_68272c71531c$CREATE TABLE IF NOT EXISTS public.delivery_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'OFFERED' CHECK (status IN ('OFFERED','ACCEPTED','REJECTED','EXPIRED','CANCELED')),
  offered_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '5 minutes'),
  responded_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id, courier_id)
)$bootstrap_sql_68272c71531c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68272c71531c$;

DO $bootstrap_do_3638b69788d6$
BEGIN
  EXECUTE $bootstrap_sql_3638b69788d6$CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_assignment_active_order ON public.delivery_assignments(order_id) WHERE status IN ('OFFERED','ACCEPTED')$bootstrap_sql_3638b69788d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3638b69788d6$;

DO $bootstrap_do_8ae084a741b7$
BEGIN
  EXECUTE $bootstrap_sql_8ae084a741b7$CREATE INDEX IF NOT EXISTS idx_delivery_assignment_courier ON public.delivery_assignments(courier_id, status, created_at DESC)$bootstrap_sql_8ae084a741b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ae084a741b7$;

DO $bootstrap_do_1086a9412eac$
BEGIN
  EXECUTE $bootstrap_sql_1086a9412eac$CREATE TABLE IF NOT EXISTS public.merchant_delivery_fee_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL,
  basis_amount numeric NOT NULL DEFAULT 0,
  percent_snapshot numeric NOT NULL DEFAULT 0,
  fee_amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'DUE' CHECK (status IN ('NOT_APPLICABLE','DUE','PAID','WAIVED','OVERDUE')),
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  UNIQUE(order_id)
)$bootstrap_sql_1086a9412eac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1086a9412eac$;

DO $bootstrap_do_49288203cbdf$
BEGIN
  EXECUTE $bootstrap_sql_49288203cbdf$ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY$bootstrap_sql_49288203cbdf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49288203cbdf$;

DO $bootstrap_do_fe8d2673d201$
BEGIN
  EXECUTE $bootstrap_sql_fe8d2673d201$ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY$bootstrap_sql_fe8d2673d201$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe8d2673d201$;

DO $bootstrap_do_e4fd832c3681$
BEGIN
  EXECUTE $bootstrap_sql_e4fd832c3681$ALTER TABLE public.merchant_delivery_fee_ledger ENABLE ROW LEVEL SECURITY$bootstrap_sql_e4fd832c3681$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4fd832c3681$;

DO $bootstrap_do_40769e40d767$
BEGIN
  EXECUTE $bootstrap_sql_40769e40d767$DROP POLICY IF EXISTS "Order parties view status history" ON public.order_status_history$bootstrap_sql_40769e40d767$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40769e40d767$;

DO $bootstrap_do_e11b01f1903a$
BEGIN
  EXECUTE $bootstrap_sql_e11b01f1903a$CREATE POLICY "Order parties view status history" ON public.order_status_history FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND (o.buyer_id = auth.uid() OR public.is_order_merchant(o.id) OR public.is_admin() OR public.is_order_courier(o.id)))
)$bootstrap_sql_e11b01f1903a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e11b01f1903a$;

DO $bootstrap_do_7933e10488e7$
BEGIN
  EXECUTE $bootstrap_sql_7933e10488e7$DROP POLICY IF EXISTS "Couriers view own assignments" ON public.delivery_assignments$bootstrap_sql_7933e10488e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7933e10488e7$;

DO $bootstrap_do_f8c54230023b$
BEGIN
  EXECUTE $bootstrap_sql_f8c54230023b$CREATE POLICY "Couriers view own assignments" ON public.delivery_assignments FOR SELECT TO authenticated USING (
  courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()) OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND (o.buyer_id = auth.uid() OR public.is_order_merchant(o.id) OR public.is_admin()))
)$bootstrap_sql_f8c54230023b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8c54230023b$;

DO $bootstrap_do_5c2b72874d8d$
BEGIN
  EXECUTE $bootstrap_sql_5c2b72874d8d$DROP POLICY IF EXISTS "Merchant view own delivery fees" ON public.merchant_delivery_fee_ledger$bootstrap_sql_5c2b72874d8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c2b72874d8d$;

DO $bootstrap_do_5ce276badefd$
BEGIN
  EXECUTE $bootstrap_sql_5ce276badefd$CREATE POLICY "Merchant view own delivery fees" ON public.merchant_delivery_fee_ledger FOR SELECT TO authenticated USING (public.is_order_merchant(order_id) OR public.is_admin())$bootstrap_sql_5ce276badefd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ce276badefd$;

DO $bootstrap_do_8d4a8e06a239$
BEGIN
  EXECUTE $bootstrap_sql_8d4a8e06a239$CREATE OR REPLACE FUNCTION public.merchant_transition_order(p_order_id uuid, p_to_status text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_allowed boolean := false; v_fee_percent numeric := 10; v_attempt integer;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE='42501'; END IF;
  IF p_to_status = ANY(ARRAY['PROCESSED','READY','ASSIGNED','DELIVERING','DELIVERED','DONE','CANCELED','REJECTED']) THEN
    v_allowed := CASE
      WHEN p_to_status='PROCESSED' THEN v_order.status IN ('NEW','PENDING_CONFIRMATION','PENDING_PAYMENT') AND (v_order.payment_method='COD' OR v_order.payment_status='PAID')
      WHEN p_to_status='READY' THEN v_order.status='PROCESSED'
      WHEN p_to_status='ASSIGNED' THEN v_order.status IN ('READY','ASSIGNED') AND NOT v_order.is_self_delivery
      WHEN p_to_status='DELIVERING' THEN v_order.status IN ('READY','PROCESSED') AND v_order.is_self_delivery
      WHEN p_to_status='DELIVERED' THEN v_order.status IN ('DELIVERING','PICKED_UP','SENT')
      WHEN p_to_status='DONE' THEN v_order.status='DELIVERED'
      WHEN p_to_status IN ('CANCELED','REJECTED') THEN v_order.status NOT IN ('DONE','DELIVERED','CANCELED','REFUNDED')
      ELSE false END;
  END IF;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition from % to %', v_order.status, p_to_status USING ERRCODE='22023'; END IF;
  IF p_to_status='DELIVERING' THEN
    v_attempt := v_order.self_delivery_attempt + 1;
    UPDATE public.orders SET is_self_delivery=true, self_delivery_attempt=v_attempt, status=p_to_status, status_updated_at=now(), delivered_at=NULL, updated_at=now() WHERE id=p_order_id;
    IF v_attempt > 2 THEN
      SELECT COALESCE((value->>'percent')::numeric, 10) INTO v_fee_percent FROM public.app_settings WHERE key='self_delivery_fee';
      INSERT INTO public.merchant_delivery_fee_ledger(merchant_id,order_id,attempt_number,basis_amount,percent_snapshot,fee_amount,status)
      VALUES(v_order.merchant_id,p_order_id,v_attempt,COALESCE(v_order.shipping_cost,0),v_fee_percent,ROUND(COALESCE(v_order.shipping_cost,0)*v_fee_percent/100,0),'DUE') ON CONFLICT (order_id) DO NOTHING;
      UPDATE public.orders SET self_delivery_fee_amount=ROUND(COALESCE(v_order.shipping_cost,0)*v_fee_percent/100,0), self_delivery_fee_status='DUE' WHERE id=p_order_id;
    END IF;
  ELSE
    UPDATE public.orders SET status=p_to_status, status_updated_at=now(), delivered_at=CASE WHEN p_to_status='DELIVERED' THEN now() ELSE delivered_at END, updated_at=now() WHERE id=p_order_id;
  END IF;
  INSERT INTO public.order_status_history(order_id,from_status,to_status,actor_id,reason) VALUES(p_order_id,v_order.status,p_to_status,auth.uid(),NULLIF(trim(p_reason),''));
  RETURN jsonb_build_object('order_id',p_order_id,'from_status',v_order.status,'to_status',p_to_status);
END; $$$bootstrap_sql_8d4a8e06a239$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d4a8e06a239$;

DO $bootstrap_do_2ee5e29fdb30$
BEGIN
  EXECUTE $bootstrap_sql_2ee5e29fdb30$GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid,text,text) TO authenticated$bootstrap_sql_2ee5e29fdb30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ee5e29fdb30$;

DO $bootstrap_do_896476e90178$
BEGIN
  EXECUTE $bootstrap_sql_896476e90178$CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.orders%ROWTYPE; v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE='42501'; END IF;
 IF v_order.status NOT IN ('PROCESSED','READY','ASSIGNED') OR v_order.is_self_delivery THEN RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.delivery_assignments WHERE order_id=p_order_id AND courier_id=p_courier_id AND status IN ('REJECTED','EXPIRED')) THEN RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE='22023'; END IF;
 INSERT INTO public.delivery_assignments(order_id,courier_id) VALUES(p_order_id,p_courier_id) RETURNING * INTO v_assignment;
 UPDATE public.orders SET status='ASSIGNED', status_updated_at=now(), updated_at=now() WHERE id=p_order_id;
 RETURN v_assignment;
END; $$$bootstrap_sql_896476e90178$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_896476e90178$;

DO $bootstrap_do_63b178b9ec9b$
BEGIN
  EXECUTE $bootstrap_sql_63b178b9ec9b$GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid,uuid) TO authenticated$bootstrap_sql_63b178b9ec9b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63b178b9ec9b$;

DO $bootstrap_do_8700ec73af82$
BEGIN
  EXECUTE $bootstrap_sql_8700ec73af82$CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.delivery_assignments%ROWTYPE; v_courier public.couriers%ROWTYPE;
BEGIN
 SELECT da.* INTO v FROM public.delivery_assignments da JOIN public.couriers c ON c.id=da.courier_id WHERE da.id=p_assignment_id AND c.user_id=auth.uid() FOR UPDATE;
 IF NOT FOUND OR v.status <> 'OFFERED' OR v.expires_at < now() THEN RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE='22023'; END IF;
 IF p_accept THEN
   UPDATE public.delivery_assignments SET status='ACCEPTED',responded_at=now() WHERE id=p_assignment_id;
   UPDATE public.orders SET courier_id=v.courier_id,status='COURIER_ACCEPTED',courier_accepted_at=now(),status_updated_at=now(),updated_at=now() WHERE id=v.order_id;
 ELSE
   UPDATE public.delivery_assignments SET status='REJECTED',responded_at=now(),rejection_reason=NULLIF(trim(p_reason),'') WHERE id=p_assignment_id;
   UPDATE public.orders SET courier_rejected_ids=array_append(courier_rejected_ids,v.courier_id),status='ASSIGNED',status_updated_at=now(),updated_at=now() WHERE id=v.order_id AND status='ASSIGNED';
 END IF;
 SELECT * INTO v FROM public.delivery_assignments WHERE id=p_assignment_id;
 RETURN v;
END; $$$bootstrap_sql_8700ec73af82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8700ec73af82$;

DO $bootstrap_do_05d6f2c19c88$
BEGIN
  EXECUTE $bootstrap_sql_05d6f2c19c88$GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid,boolean,text) TO authenticated$bootstrap_sql_05d6f2c19c88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05d6f2c19c88$;

DO $bootstrap_do_4bc34d1907eb$
BEGIN
  EXECUTE $bootstrap_sql_4bc34d1907eb$INSERT INTO public.app_settings(key,category,value,description) VALUES('self_delivery_fee','delivery','{"percent":10}'::jsonb,'Biaya platform antar sendiri setelah kuota gratis') ON CONFLICT(key) DO NOTHING$bootstrap_sql_4bc34d1907eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4bc34d1907eb$;

DO $bootstrap_do_47548bca8c89$
BEGIN
  EXECUTE $bootstrap_sql_47548bca8c89$UPDATE public.orders SET status_updated_at=COALESCE(status_updated_at,updated_at,created_at)$bootstrap_sql_47548bca8c89$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47548bca8c89$;

DO $bootstrap_do_9efda0a208c4$
BEGIN
  EXECUTE $bootstrap_sql_9efda0a208c4$NOTIFY pgrst, 'reload schema'$bootstrap_sql_9efda0a208c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9efda0a208c4$;

DO $bootstrap_do_44036373d09d$
BEGIN
  EXECUTE $bootstrap_sql_44036373d09d$-- ===== END BUNDLE: 44_20260909193000_order_workflow_rpc.sql =====

-- ===== BEGIN BUNDLE: 44_20260922120500_chat_sender_delete.sql =====
-- Allow a sender (including admin direct-chat senders) to retract their own message.
-- This is a soft-delete: the row remains for retention/audit and realtime update.
CREATE OR REPLACE FUNCTION public.delete_chat_message(p_message_id uuid)
RETURNS public.chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.chat_messages%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat delete request' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_message
  FROM public.chat_messages
  WHERE id = p_message_id
    AND sender_id = auth.uid()
    AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'message not found or not owned by current user' USING ERRCODE = '42501';
  END IF;

  UPDATE public.chat_messages
  SET deleted_at = now(),
      deleted_reason = 'sender_deleted'
  WHERE id = p_message_id
  RETURNING * INTO v_message;

  RETURN v_message;
END;
$$$bootstrap_sql_44036373d09d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44036373d09d$;

DO $bootstrap_do_e0342205ed0c$
BEGIN
  EXECUTE $bootstrap_sql_e0342205ed0c$REVOKE ALL ON FUNCTION public.delete_chat_message(uuid) FROM PUBLIC, anon$bootstrap_sql_e0342205ed0c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e0342205ed0c$;

DO $bootstrap_do_4319e1f9ae7c$
BEGIN
  EXECUTE $bootstrap_sql_4319e1f9ae7c$GRANT EXECUTE ON FUNCTION public.delete_chat_message(uuid) TO authenticated$bootstrap_sql_4319e1f9ae7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4319e1f9ae7c$;

DO $bootstrap_do_7d7d21112113$
BEGIN
  EXECUTE $bootstrap_sql_7d7d21112113$COMMENT ON FUNCTION public.delete_chat_message IS
  'Soft-deletes a chat message only when the authenticated user is its sender.'$bootstrap_sql_7d7d21112113$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d7d21112113$;

DO $bootstrap_do_1c75b07d1d72$
BEGIN
  EXECUTE $bootstrap_sql_1c75b07d1d72$NOTIFY pgrst, 'reload schema'$bootstrap_sql_1c75b07d1d72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c75b07d1d72$;

DO $bootstrap_do_5778338e895a$
BEGIN
  EXECUTE $bootstrap_sql_5778338e895a$-- ===== END BUNDLE: 44_20260922120500_chat_sender_delete.sql =====

-- ===== BEGIN BUNDLE: 45_20260909201500_fix_delivery_offer_rpc.sql =====
-- Fix Kurir Desa offer RPC compatibility after workflow hardening.
-- The merchant UI can offer a courier directly from PROCESSED; the courier must
-- then accept or reject before the order becomes COURIER_ACCEPTED.

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED') OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;
  IF p_courier_id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')) THEN
    RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.couriers c
    WHERE c.id = p_courier_id
      AND c.status = 'ACTIVE'
      AND c.registration_status = 'APPROVED'
      AND c.is_available = true
  ) THEN
    RAISE EXCEPTION 'Courier is not available' USING ERRCODE = '22023';
  END IF;

  UPDATE public.delivery_assignments
  SET status = 'CANCELED', updated_at = now()
  WHERE order_id = p_order_id AND status = 'OFFERED';

  INSERT INTO public.delivery_assignments(order_id, courier_id)
  VALUES (p_order_id, p_courier_id)
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED', courier_id = p_courier_id, assigned_at = now(), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, 'ASSIGNED', auth.uid(), 'Tawaran dikirim ke kurir desa');
  RETURN v_assignment;
END; $$$bootstrap_sql_5778338e895a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5778338e895a$;

DO $bootstrap_do_5eed57717e7d$
BEGIN
  EXECUTE $bootstrap_sql_5eed57717e7d$CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
RETURNS public.delivery_assignments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_assignment public.delivery_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid();
  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.id = p_assignment_id AND da.courier_id = v_courier_id
  FOR UPDATE;
  IF NOT FOUND OR v_assignment.status <> 'OFFERED' OR v_assignment.expires_at < now() THEN
    RAISE EXCEPTION 'Offer is no longer active' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_assignment.order_id FOR UPDATE;
  IF p_accept THEN
    UPDATE public.delivery_assignments
    SET status = 'ACCEPTED', responded_at = now(), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;
    UPDATE public.orders
    SET courier_id = v_courier_id, status = 'COURIER_ACCEPTED', courier_accepted_at = now(), status_updated_at = now(), updated_at = now()
    WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'COURIER_ACCEPTED', auth.uid(), 'Kurir menerima pesanan');
  ELSE
    UPDATE public.delivery_assignments
    SET status = 'REJECTED', responded_at = now(), rejection_reason = NULLIF(trim(p_reason), ''), updated_at = now()
    WHERE id = p_assignment_id
    RETURNING * INTO v_assignment;
    UPDATE public.orders
    SET courier_rejected_ids = array_append(COALESCE(courier_rejected_ids, '{}'), v_courier_id), status = 'ASSIGNED', status_updated_at = now(), updated_at = now()
    WHERE id = v_order.id;
    INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
    VALUES (v_order.id, v_order.status, 'ASSIGNED', auth.uid(), COALESCE(p_reason, 'Kurir menolak pesanan'));
  END IF;
  RETURN v_assignment;
END; $$$bootstrap_sql_5eed57717e7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5eed57717e7d$;

DO $bootstrap_do_463d2423bce3$
BEGIN
  EXECUTE $bootstrap_sql_463d2423bce3$GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid, uuid) TO authenticated$bootstrap_sql_463d2423bce3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_463d2423bce3$;

DO $bootstrap_do_496629991a1d$
BEGIN
  EXECUTE $bootstrap_sql_496629991a1d$GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid, boolean, text) TO authenticated$bootstrap_sql_496629991a1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_496629991a1d$;

DO $bootstrap_do_bff2421317b8$
BEGIN
  EXECUTE $bootstrap_sql_bff2421317b8$NOTIFY pgrst, 'reload schema'$bootstrap_sql_bff2421317b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bff2421317b8$;

DO $bootstrap_do_c5ed98d15365$
BEGIN
  EXECUTE $bootstrap_sql_c5ed98d15365$-- Couriers must advance their assigned orders through a server-side transition.
CREATE OR REPLACE FUNCTION public.courier_transition_order(p_order_id uuid, p_to_status text)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_allowed boolean := false;
  v_from_status text;
BEGIN
  SELECT c.id INTO v_courier_id FROM public.couriers c WHERE c.user_id = auth.uid();
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.courier_id IS DISTINCT FROM v_courier_id THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  v_allowed := (v_order.status = 'COURIER_ACCEPTED' AND p_to_status = 'PICKED_UP')
    OR (v_order.status = 'PICKED_UP' AND p_to_status = 'SENT')
    OR (v_order.status IN ('SENT', 'DELIVERING') AND p_to_status = 'DELIVERED');
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid courier transition: % -> %', v_order.status, p_to_status USING ERRCODE = '22023';
  END IF;
  v_from_status := v_order.status;
  UPDATE public.orders SET
    status = p_to_status,
    picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
    delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
    status_updated_at = now(),
    updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;
  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from_status, p_to_status, auth.uid(), 'Pembaruan status oleh kurir');
  RETURN v_order;
END; $$$bootstrap_sql_c5ed98d15365$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5ed98d15365$;

DO $bootstrap_do_8585f92aa4be$
BEGIN
  EXECUTE $bootstrap_sql_8585f92aa4be$GRANT EXECUTE ON FUNCTION public.courier_transition_order(uuid, text) TO authenticated$bootstrap_sql_8585f92aa4be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8585f92aa4be$;

DO $bootstrap_do_aafd529dfbb1$
BEGIN
  EXECUTE $bootstrap_sql_aafd529dfbb1$NOTIFY pgrst, 'reload schema'$bootstrap_sql_aafd529dfbb1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aafd529dfbb1$;

DO $bootstrap_do_f3d5da7d5fc3$
BEGIN
  EXECUTE $bootstrap_sql_f3d5da7d5fc3$-- ===== END BUNDLE: 45_20260909201500_fix_delivery_offer_rpc.sql =====

-- ===== BEGIN BUNDLE: 45_20260911001000_payment_notification_hardening.sql =====
-- Payment and notification worker hardening.
-- Recover abandoned reservations/jobs after a worker or edge function crash.

CREATE OR REPLACE FUNCTION public.reserve_payment_invoice_request(
  p_provider text,
  p_order_id uuid,
  p_request_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_invoice_requests%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF p_provider IS NULL OR p_provider = '' OR p_order_id IS NULL
     OR p_request_key IS NULL OR length(trim(p_request_key)) < 16
     OR length(p_request_key) > 128 THEN
    RAISE EXCEPTION 'Invalid payment invoice request' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.payment_invoice_requests(provider, order_id, request_key)
  VALUES (lower(trim(p_provider)), p_order_id, trim(p_request_key))
  ON CONFLICT (provider, order_id) DO NOTHING
  RETURNING true INTO v_inserted;

  SELECT * INTO v_row
  FROM public.payment_invoice_requests
  WHERE provider = lower(trim(p_provider)) AND order_id = p_order_id
  FOR UPDATE;

  -- A crashed edge function must not permanently block payment retries.
  IF NOT COALESCE(v_inserted, false)
     AND v_row.status = 'processing'
     AND v_row.updated_at < now() - interval '10 minutes' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'failed', invoice_id = NULL, invoice_url = NULL,
        last_error = 'reservation:lease_expired', updated_at = now()
    WHERE id = v_row.id AND status = 'processing';
    v_row.status := 'failed';
    v_row.invoice_id := NULL;
    v_row.invoice_url := NULL;
  END IF;

  IF NOT COALESCE(v_inserted, false) AND v_row.status = 'failed' THEN
    UPDATE public.payment_invoice_requests
    SET status = 'processing', request_key = trim(p_request_key),
        last_error = NULL, updated_at = now()
    WHERE id = v_row.id AND status = 'failed';
    v_inserted := true;
    SELECT * INTO v_row FROM public.payment_invoice_requests WHERE id = v_row.id;
  END IF;

  RETURN jsonb_build_object(
    'can_process', COALESCE(v_inserted, false),
    'status', v_row.status,
    'request_key', v_row.request_key,
    'invoice_id', v_row.invoice_id,
    'invoice_url', v_row.invoice_url,
    'last_error', v_row.last_error,
    'created_at', v_row.created_at
  );
END;
$$$bootstrap_sql_f3d5da7d5fc3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3d5da7d5fc3$;

DO $bootstrap_do_e1358a17809f$
BEGIN
  EXECUTE $bootstrap_sql_e1358a17809f$ALTER TABLE public.notification_delivery_jobs
  ADD COLUMN IF NOT EXISTS locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_by text$bootstrap_sql_e1358a17809f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1358a17809f$;

DO $bootstrap_do_1066980b45d4$
BEGIN
  EXECUTE $bootstrap_sql_1066980b45d4$CREATE OR REPLACE FUNCTION public.claim_notification_delivery_job(p_job_id uuid)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job claim requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notification_delivery_jobs
  SET status = 'processing', attempts = attempts + 1,
      locked_at = now(), locked_by = COALESCE(current_setting('request.jwt.claim.sub', true), 'worker')
  WHERE id = p_job_id
    AND attempts < max_attempts
    AND next_attempt_at <= now()
    AND (
      status IN ('queued', 'failed')
      OR (status = 'processing' AND COALESCE(locked_at, 'epoch'::timestamptz) < now() - interval '10 minutes')
    )
  RETURNING * INTO v_job;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification job is unavailable' USING ERRCODE = '55000'; END IF;
  RETURN v_job;
END; $$$bootstrap_sql_1066980b45d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1066980b45d4$;

DO $bootstrap_do_8997dc54989f$
BEGIN
  EXECUTE $bootstrap_sql_8997dc54989f$CREATE OR REPLACE FUNCTION public.complete_notification_delivery_job(
  p_job_id uuid, p_success boolean, p_provider_message_id text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS public.notification_delivery_jobs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.notification_delivery_jobs%ROWTYPE; v_status text; v_next timestamptz;
BEGIN
  IF (auth.jwt()->>'role') <> 'service_role' AND (auth.uid() IS NULL OR NOT public.is_admin()) THEN
    RAISE EXCEPTION 'Notification job completion requires worker or admin access' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_job FROM public.notification_delivery_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'processing' THEN RAISE EXCEPTION 'Notification job is not processing' USING ERRCODE = '55000'; END IF;
  IF p_success THEN v_status := 'sent'; ELSE v_status := CASE WHEN v_job.attempts >= v_job.max_attempts THEN 'dead_letter' ELSE 'failed' END; END IF;
  v_next := CASE WHEN v_status = 'failed' THEN now() + make_interval(secs => LEAST(3600, 30 * (2 ^ LEAST(v_job.attempts, 7)))) ELSE NULL END;
  UPDATE public.notification_delivery_jobs
  SET status = v_status,
      provider_message_id = COALESCE(p_provider_message_id, provider_message_id),
      last_error = NULLIF(trim(p_error), ''),
      next_attempt_at = COALESCE(v_next, next_attempt_at),
      sent_at = CASE WHEN p_success THEN now() ELSE sent_at END,
      dead_letter_at = CASE WHEN v_status = 'dead_letter' THEN now() ELSE dead_letter_at END,
      locked_at = NULL, locked_by = NULL
  WHERE id = p_job_id RETURNING * INTO v_job;
  RETURN v_job;
END; $$$bootstrap_sql_8997dc54989f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8997dc54989f$;

DO $bootstrap_do_ef7e22584c07$
BEGIN
  EXECUTE $bootstrap_sql_ef7e22584c07$-- ===== END BUNDLE: 45_20260911001000_payment_notification_hardening.sql =====

-- ===== BEGIN BUNDLE: 46_20260909203000_remove_merchant_transition_overload.sql =====
-- Remove the legacy 4-argument overload. PostgREST cannot reliably resolve
-- merchant_transition_order when both 3-arg and 4-arg (with defaults) exist.
DROP FUNCTION IF EXISTS public.merchant_transition_order(uuid, text, text, boolean)$bootstrap_sql_ef7e22584c07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef7e22584c07$;

DO $bootstrap_do_af925b970898$
BEGIN
  EXECUTE $bootstrap_sql_af925b970898$CREATE OR REPLACE FUNCTION public.merchant_transition_order(p_order_id uuid, p_to_status text, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_allowed boolean := false;
  v_fee_percent numeric := 10;
  v_attempt integer;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  v_allowed := CASE
    WHEN p_to_status = 'PROCESSED' THEN v_order.status IN ('NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT') AND (v_order.payment_method = 'COD' OR v_order.payment_status = 'PAID')
    WHEN p_to_status = 'READY' THEN v_order.status = 'PROCESSED'
    WHEN p_to_status = 'ASSIGNED' THEN v_order.status IN ('PROCESSED', 'READY', 'ASSIGNED') AND NOT COALESCE(v_order.is_self_delivery, false)
    WHEN p_to_status = 'DELIVERING' THEN v_order.status IN ('READY', 'PROCESSED')
    WHEN p_to_status = 'DELIVERED' THEN v_order.status IN ('DELIVERING', 'PICKED_UP', 'SENT')
    WHEN p_to_status = 'DONE' THEN v_order.status = 'DELIVERED'
    WHEN p_to_status IN ('CANCELED', 'REJECTED') THEN v_order.status NOT IN ('DONE', 'DELIVERED', 'CANCELED', 'REFUNDED')
    ELSE false
  END;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Invalid order transition from % to %', v_order.status, p_to_status USING ERRCODE = '22023';
  END IF;

  IF p_to_status = 'DELIVERING' THEN
    v_attempt := COALESCE(v_order.self_delivery_attempt, 0) + 1;
    UPDATE public.orders SET
      is_self_delivery = true,
      self_delivery_attempt = v_attempt,
      status = p_to_status,
      status_updated_at = now(),
      delivered_at = NULL,
      updated_at = now()
    WHERE id = p_order_id;
    IF v_attempt > 2 THEN
      SELECT COALESCE((value->>'percent')::numeric, 10) INTO v_fee_percent
      FROM public.app_settings WHERE key = 'self_delivery_fee';
      INSERT INTO public.merchant_delivery_fee_ledger(merchant_id, order_id, attempt_number, basis_amount, percent_snapshot, fee_amount, status)
      VALUES (v_order.merchant_id, p_order_id, v_attempt, COALESCE(v_order.shipping_cost, 0), v_fee_percent, ROUND(COALESCE(v_order.shipping_cost, 0) * v_fee_percent / 100, 0), 'DUE')
      ON CONFLICT (order_id) DO NOTHING;
      UPDATE public.orders SET self_delivery_fee_amount = ROUND(COALESCE(v_order.shipping_cost, 0) * v_fee_percent / 100, 0), self_delivery_fee_status = 'DUE' WHERE id = p_order_id;
    END IF;
  ELSE
    UPDATE public.orders SET
      status = p_to_status,
      status_updated_at = now(),
      confirmed_at = CASE WHEN p_to_status = 'PROCESSED' THEN now() ELSE confirmed_at END,
      delivered_at = CASE WHEN p_to_status = 'DELIVERED' THEN now() ELSE delivered_at END,
      updated_at = now()
    WHERE id = p_order_id;
  END IF;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_order.status, p_to_status, auth.uid(), NULLIF(trim(p_reason), ''));
  RETURN jsonb_build_object('order_id', p_order_id, 'from_status', v_order.status, 'to_status', p_to_status);
END; $$$bootstrap_sql_af925b970898$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_af925b970898$;

DO $bootstrap_do_a84e81716b93$
BEGIN
  EXECUTE $bootstrap_sql_a84e81716b93$GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid, text, text) TO authenticated$bootstrap_sql_a84e81716b93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a84e81716b93$;

DO $bootstrap_do_7855ea5c2b7d$
BEGIN
  EXECUTE $bootstrap_sql_7855ea5c2b7d$NOTIFY pgrst, 'reload schema'$bootstrap_sql_7855ea5c2b7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7855ea5c2b7d$;

DO $bootstrap_do_e433a7e3534e$
BEGIN
  EXECUTE $bootstrap_sql_e433a7e3534e$-- ===== END BUNDLE: 46_20260909203000_remove_merchant_transition_overload.sql =====

-- ===== BEGIN BUNDLE: 46_20260911002000_auth_role_security_hardening.sql =====
-- Auth and user-management hardening.
-- Replace roles atomically and prevent accidental removal of the last admin.

CREATE OR REPLACE FUNCTION public.admin_replace_user_roles(
  p_target_user_id uuid,
  p_roles public.app_role[]
)
RETURNS SETOF public.user_roles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_roles public.app_role[];
  v_target_is_admin boolean;
  v_admin_count bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'Target user not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(array_agg(role ORDER BY role), ARRAY['buyer']::public.app_role[])
    INTO v_roles
  FROM (SELECT DISTINCT unnest(COALESCE(p_roles, ARRAY[]::public.app_role[])) AS role) selected;

  IF cardinality(v_roles) = 0 THEN
    v_roles := ARRAY['buyer']::public.app_role[];
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = p_target_user_id AND role = 'admin'
  ) INTO v_target_is_admin;
  SELECT count(*) INTO v_admin_count FROM public.user_roles WHERE role = 'admin';

  IF v_target_is_admin AND NOT ('admin' = ANY(v_roles)) AND v_admin_count <= 1 THEN
    RAISE EXCEPTION 'Cannot remove the last admin' USING ERRCODE = '23514';
  END IF;
  IF p_target_user_id = auth.uid() AND v_target_is_admin AND NOT ('admin' = ANY(v_roles)) THEN
    RAISE EXCEPTION 'Cannot remove your own admin access' USING ERRCODE = '42501';
  END IF;

  PERFORM 1 FROM public.user_roles WHERE user_id = p_target_user_id FOR UPDATE;
  DELETE FROM public.user_roles WHERE user_id = p_target_user_id;
  INSERT INTO public.user_roles(user_id, role)
  SELECT p_target_user_id, role FROM unnest(v_roles) AS role;

  RETURN QUERY SELECT * FROM public.user_roles WHERE user_id = p_target_user_id ORDER BY role;
END;
$$$bootstrap_sql_e433a7e3534e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e433a7e3534e$;

DO $bootstrap_do_fed0aa021fee$
BEGIN
  EXECUTE $bootstrap_sql_fed0aa021fee$REVOKE ALL ON FUNCTION public.admin_replace_user_roles(uuid, public.app_role[]) FROM PUBLIC, anon$bootstrap_sql_fed0aa021fee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fed0aa021fee$;

DO $bootstrap_do_804e63f03ad0$
BEGIN
  EXECUTE $bootstrap_sql_804e63f03ad0$GRANT EXECUTE ON FUNCTION public.admin_replace_user_roles(uuid, public.app_role[]) TO authenticated, service_role$bootstrap_sql_804e63f03ad0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_804e63f03ad0$;

DO $bootstrap_do_411dd91829fc$
BEGIN
  EXECUTE $bootstrap_sql_411dd91829fc$-- The application uses Supabase Auth's resetPasswordForEmail flow. The legacy
-- plaintext token table must not be readable or writable through PostgREST.
DROP POLICY IF EXISTS "Users can verify their tokens" ON public.password_reset_tokens$bootstrap_sql_411dd91829fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_411dd91829fc$;

DO $bootstrap_do_f00ad377b612$
BEGIN
  EXECUTE $bootstrap_sql_f00ad377b612$DROP POLICY IF EXISTS "Password reset token insert" ON public.password_reset_tokens$bootstrap_sql_f00ad377b612$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f00ad377b612$;

DO $bootstrap_do_17bba1335fbc$
BEGIN
  EXECUTE $bootstrap_sql_17bba1335fbc$DROP POLICY IF EXISTS "Anyone can request password reset" ON public.password_reset_tokens$bootstrap_sql_17bba1335fbc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17bba1335fbc$;

DO $bootstrap_do_9086953f6c4f$
BEGIN
  EXECUTE $bootstrap_sql_9086953f6c4f$DROP POLICY IF EXISTS "Tokens can be marked as used" ON public.password_reset_tokens$bootstrap_sql_9086953f6c4f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9086953f6c4f$;

DO $bootstrap_do_c7382d1f74d8$
BEGIN
  EXECUTE $bootstrap_sql_c7382d1f74d8$REVOKE ALL ON TABLE public.password_reset_tokens FROM anon, authenticated$bootstrap_sql_c7382d1f74d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7382d1f74d8$;

DO $bootstrap_do_393bb37136f2$
BEGIN
  EXECUTE $bootstrap_sql_393bb37136f2$-- Align the UI password-reset minimum with registration policy. The actual
-- Supabase Auth password policy remains the server-side authority.
COMMENT ON TABLE public.password_reset_tokens IS
  'Legacy reset table disabled: password reset is handled by Supabase Auth; no public policies.'$bootstrap_sql_393bb37136f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_393bb37136f2$;

DO $bootstrap_do_8ab8b7f0e9d7$
BEGIN
  EXECUTE $bootstrap_sql_8ab8b7f0e9d7$-- ===== END BUNDLE: 46_20260911002000_auth_role_security_hardening.sql =====

-- ===== BEGIN BUNDLE: 47_20260909210000_delivery_method_restrictions.sql =====
-- Local ojek/kurir delivery is limited to 10 km and the merchant's
-- kecamatan/kabupaten. Orders outside that scope must use EXPEDITION.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_province_id text,
  ADD COLUMN IF NOT EXISTS delivery_province_name text,
  ADD COLUMN IF NOT EXISTS delivery_city_id text,
  ADD COLUMN IF NOT EXISTS delivery_city_name text,
  ADD COLUMN IF NOT EXISTS delivery_district_id text,
  ADD COLUMN IF NOT EXISTS delivery_district_name text$bootstrap_sql_8ab8b7f0e9d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ab8b7f0e9d7$;

DO $bootstrap_do_29c8184187e9$
BEGIN
  EXECUTE $bootstrap_sql_29c8184187e9$ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_delivery_type_check$bootstrap_sql_29c8184187e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_29c8184187e9$;

DO $bootstrap_do_679f7f8d8fb9$
BEGIN
  EXECUTE $bootstrap_sql_679f7f8d8fb9$ALTER TABLE public.orders
  ADD CONSTRAINT orders_delivery_type_check
  CHECK (delivery_type IN ('PICKUP', 'INTERNAL', 'EXPEDITION'))$bootstrap_sql_679f7f8d8fb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_679f7f8d8fb9$;

DO $bootstrap_do_4a19531368af$
BEGIN
  EXECUTE $bootstrap_sql_4a19531368af$CREATE OR REPLACE FUNCTION public.validate_delivery_method_restriction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_destination_city text;
  v_destination_district text;
  v_merchant_city text;
  v_merchant_district text;
BEGIN
  IF NEW.delivery_type <> 'INTERNAL' OR NEW.merchant_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_merchant
  FROM public.merchants
  WHERE id = NEW.merchant_id;

  IF NEW.buyer_distance_km > 10 THEN
    RAISE EXCEPTION 'Local delivery is limited to 10 km; use EXPEDITION'
      USING ERRCODE = '22023';
  END IF;

  -- Only compare administrative regions when both sides have a value. Older
  -- merchants may not have region metadata yet; distance remains authoritative.
  v_destination_city := regexp_replace(lower(coalesce(NEW.delivery_city_name, '')), '\m(kabupaten|kab\.?|kota)\M', '', 'g');
  v_destination_district := regexp_replace(lower(coalesce(NEW.delivery_district_name, '')), '\m(kecamatan|kec\.?)\M', '', 'g');
  v_merchant_city := regexp_replace(lower(coalesce(v_merchant.city, '')), '\m(kabupaten|kab\.?|kota)\M', '', 'g');
  v_merchant_district := regexp_replace(lower(coalesce(v_merchant.district, '')), '\m(kecamatan|kec\.?)\M', '', 'g');

  IF v_destination_city <> '' AND v_merchant_city <> ''
     AND regexp_replace(v_destination_city, '[^a-z0-9]+', '', 'g')
        <> regexp_replace(v_merchant_city, '[^a-z0-9]+', '', 'g') THEN
    RAISE EXCEPTION 'Different kabupaten/kota requires EXPEDITION'
      USING ERRCODE = '22023';
  END IF;

  IF v_destination_district <> '' AND v_merchant_district <> ''
     AND regexp_replace(v_destination_district, '[^a-z0-9]+', '', 'g')
        <> regexp_replace(v_merchant_district, '[^a-z0-9]+', '', 'g') THEN
    RAISE EXCEPTION 'Different kecamatan requires EXPEDITION'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_4a19531368af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a19531368af$;

DO $bootstrap_do_3c83d622d5a6$
BEGIN
  EXECUTE $bootstrap_sql_3c83d622d5a6$DROP TRIGGER IF EXISTS orders_validate_delivery_method ON public.orders$bootstrap_sql_3c83d622d5a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c83d622d5a6$;

DO $bootstrap_do_e15c00ff8895$
BEGIN
  EXECUTE $bootstrap_sql_e15c00ff8895$CREATE TRIGGER orders_validate_delivery_method
  BEFORE INSERT OR UPDATE OF delivery_type, merchant_id, buyer_distance_km,
    delivery_city_name, delivery_district_name
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_delivery_method_restriction()$bootstrap_sql_e15c00ff8895$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e15c00ff8895$;

DO $bootstrap_do_e4c4581c3379$
BEGIN
  EXECUTE $bootstrap_sql_e4c4581c3379$GRANT EXECUTE ON FUNCTION public.validate_delivery_method_restriction() TO authenticated$bootstrap_sql_e4c4581c3379$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4c4581c3379$;

DO $bootstrap_do_75d2c35fcb6e$
BEGIN
  EXECUTE $bootstrap_sql_75d2c35fcb6e$NOTIFY pgrst, 'reload schema'$bootstrap_sql_75d2c35fcb6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75d2c35fcb6e$;

DO $bootstrap_do_1414d8b44649$
BEGIN
  EXECUTE $bootstrap_sql_1414d8b44649$-- ===== END BUNDLE: 47_20260909210000_delivery_method_restrictions.sql =====

-- ===== BEGIN BUNDLE: 48_20260909230000_merchant_settings_schema_repair.sql =====
-- Keep the merchant settings form compatible with databases created from
-- older bootstrap bundles where classification_price was removed.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS classification_price text$bootstrap_sql_1414d8b44649$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1414d8b44649$;

DO $bootstrap_do_dc32c19bfcef$
BEGIN
  EXECUTE $bootstrap_sql_dc32c19bfcef$DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.merchants'::regclass
      AND conname = 'merchants_classification_price_check'
  ) THEN
    ALTER TABLE public.merchants
      ADD CONSTRAINT merchants_classification_price_check
      CHECK (
        classification_price IS NULL
        OR classification_price IN (
          'UNDER_5K',
          'FROM_5K_TO_10K',
          'FROM_10K_TO_20K',
          'ABOVE_20K'
        )
      );
  END IF;
END
$$$bootstrap_sql_dc32c19bfcef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc32c19bfcef$;

DO $bootstrap_do_1ee1518a64ce$
BEGIN
  EXECUTE $bootstrap_sql_1ee1518a64ce$NOTIFY pgrst, 'reload schema'$bootstrap_sql_1ee1518a64ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ee1518a64ce$;

DO $bootstrap_do_5535d9bb1727$
BEGIN
  EXECUTE $bootstrap_sql_5535d9bb1727$-- ===== END BUNDLE: 48_20260909230000_merchant_settings_schema_repair.sql =====

-- ===== BEGIN BUNDLE: 48_20260911003000_marketplace_checkout_authoritative.sql =====
-- Authoritative marketplace checkout.
-- The client submits only product IDs, quantities, delivery data, and payment choice.
-- Prices, flash-sale prices, voucher usage, order totals, and stock reservations
-- are calculated in one transaction on the server.

DELETE FROM public.voucher_usages a
USING public.voucher_usages b
WHERE a.voucher_id = b.voucher_id
  AND a.user_id = b.user_id
  AND a.id > b.id$bootstrap_sql_5535d9bb1727$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5535d9bb1727$;

DO $bootstrap_do_1fa5a20f1416$
BEGIN
  EXECUTE $bootstrap_sql_1fa5a20f1416$CREATE UNIQUE INDEX IF NOT EXISTS voucher_usages_voucher_user_unique
  ON public.voucher_usages(voucher_id, user_id)$bootstrap_sql_1fa5a20f1416$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1fa5a20f1416$;

DO $bootstrap_do_d6c9a32aa199$
BEGIN
  EXECUTE $bootstrap_sql_d6c9a32aa199$CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_product public.products%ROWTYPE;
  v_merchant_id uuid;
  v_order_id uuid;
  v_primary_order_id uuid;
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_quantity integer;
  v_subtotal integer;
  v_shipping integer;
  v_cod_fee integer := 0;
  v_discount integer := 0;
  v_total integer;
  v_voucher public.vouchers%ROWTYPE;
  v_voucher_merchant uuid;
  v_merchant_count integer;
  v_settings jsonb;
  v_cod_settings jsonb;
  v_unit_price integer;
  v_item_subtotal integer;
  v_status text;
  v_payment_status text;
  v_deadline timestamptz;
  v_merchant_item jsonb;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid checkout request' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type NOT IN ('PICKUP', 'INTERNAL', 'EXPEDITION') THEN
    RAISE EXCEPTION 'Invalid delivery type' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method NOT IN ('COD', 'TRANSFER', 'ONLINE') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'ONLINE' AND (
    SELECT count(DISTINCT p.merchant_id)
    FROM jsonb_array_elements(p_items) x
    JOIN public.products p ON p.id = NULLIF(x->>'product_id', '')::uuid
  ) > 1 THEN
    RAISE EXCEPTION 'Online checkout supports one merchant per invoice' USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE checkout_lines (
    product_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    product_name text NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    line_total integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF NULLIF(v_item->>'product_id', '') IS NULL THEN
      RAISE EXCEPTION 'Product is required' USING ERRCODE = '22023';
    END IF;
    v_quantity := (v_item->>'quantity')::integer;
    IF v_quantity IS NULL OR v_quantity <= 0 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Invalid product quantity' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid
    FOR UPDATE;
    IF NOT FOUND OR v_product.is_active IS NOT TRUE THEN
      RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.merchant_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = v_product.merchant_id
        AND m.registration_status = 'APPROVED'
        AND m.status = 'ACTIVE'
        AND m.is_open = true
    ) THEN
      RAISE EXCEPTION 'Merchant is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.stock < v_quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_product.name USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(fs.flash_price, v_product.price)
      INTO v_unit_price
    FROM (SELECT 1) base
    LEFT JOIN LATERAL (
      SELECT flash_price
      FROM public.flash_sales
      WHERE product_id = v_product.id
        AND merchant_id = v_product.merchant_id
        AND status = 'ACTIVE'
        AND start_time <= now()
        AND end_time > now()
        AND stock_available > stock_sold
      ORDER BY end_time ASC
      LIMIT 1
    ) fs ON true;
    v_item_subtotal := v_unit_price * v_quantity;
    INSERT INTO checkout_lines VALUES (
      v_product.id, v_product.merchant_id, v_product.name,
      v_quantity, v_unit_price, v_item_subtotal
    );
  END LOOP;

  SELECT count(DISTINCT merchant_id) INTO v_merchant_count FROM checkout_lines;
  IF p_voucher_id IS NOT NULL AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Voucher checkout must contain one merchant' USING ERRCODE = '22023';
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher FROM public.vouchers WHERE id = p_voucher_id FOR UPDATE;
    IF NOT FOUND OR v_voucher.is_active IS NOT TRUE
       OR v_voucher.start_date > now()
       OR (v_voucher.end_date IS NOT NULL AND v_voucher.end_date < now()) THEN
      RAISE EXCEPTION 'Voucher is invalid or expired' USING ERRCODE = '22023';
    END IF;
    SELECT merchant_id INTO v_voucher_merchant FROM checkout_lines LIMIT 1;
    IF v_voucher.merchant_id IS NOT NULL AND v_voucher.merchant_id <> v_voucher_merchant THEN
      RAISE EXCEPTION 'Voucher does not apply to this merchant' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.voucher_usages WHERE voucher_id = p_voucher_id AND user_id = auth.uid()) THEN
      RAISE EXCEPTION 'Voucher has already been used' USING ERRCODE = '23505';
    END IF;
    IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
      RAISE EXCEPTION 'Voucher usage limit reached' USING ERRCODE = '23505';
    END IF;
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines);
    IF v_subtotal < COALESCE(v_voucher.min_order_amount, 0) THEN
      RAISE EXCEPTION 'Minimum order for voucher is not met' USING ERRCODE = '22023';
    END IF;
    IF v_voucher.discount_type = 'percentage' THEN
      v_discount := floor(v_subtotal * v_voucher.discount_value / 100.0);
      IF v_voucher.max_discount IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_voucher.max_discount);
      END IF;
    ELSE
      v_discount := v_voucher.discount_value;
    END IF;
    v_discount := GREATEST(0, LEAST(v_discount, v_subtotal));
  END IF;

  SELECT value INTO v_settings FROM public.app_settings WHERE key = 'shipping_base_fee';
  IF p_delivery_type = 'PICKUP' THEN
    v_shipping := 0;
  ELSE
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines);
    IF v_subtotal >= COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000) THEN
      v_shipping := 0;
    ELSE
      v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
        + round(COALESCE(p_distance_km, 0) * COALESCE((v_settings->>'per_km_fee')::integer, 2000));
      v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
        GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
    END IF;
  END IF;

  SELECT value INTO v_cod_settings FROM public.app_settings WHERE key = 'cod_settings';
  IF p_payment_method = 'COD' THEN
    IF COALESCE((v_cod_settings->>'enabled')::boolean, true) IS NOT TRUE THEN
      RAISE EXCEPTION 'COD is currently unavailable' USING ERRCODE = '22023';
    END IF;
    -- COD remains available, but it is always free of charge.
    v_cod_fee := 0;
  END IF;

  IF p_payment_method = 'COD' THEN
    v_status := 'PENDING_CONFIRMATION';
    v_payment_status := 'COD';
    v_deadline := now() + make_interval(mins => COALESCE((v_cod_settings->>'confirmation_timeout_minutes')::integer, 15));
  ELSIF p_payment_method = 'TRANSFER' THEN
    v_status := 'PENDING_PAYMENT';
    v_payment_status := 'PENDING_TRANSFER';
    v_deadline := NULL;
  ELSE
    v_status := 'NEW';
    v_payment_status := 'UNPAID';
    v_deadline := NULL;
  END IF;

  FOR v_merchant_id IN SELECT DISTINCT merchant_id FROM checkout_lines ORDER BY merchant_id LOOP
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines WHERE merchant_id = v_merchant_id);
    v_total := GREATEST(0, v_subtotal + v_shipping + v_cod_fee - v_discount);
    INSERT INTO public.orders (
      buyer_id, merchant_id, status, handled_by, delivery_type,
      delivery_address, delivery_phone, delivery_name, shipping_cost,
      subtotal, total, notes, flash_sale_discount, payment_method,
      payment_status, confirmation_deadline, cod_service_fee, buyer_distance_km,
      delivery_lat, delivery_lng, delivery_province_id, delivery_province_name,
      delivery_city_id, delivery_city_name, delivery_district_id, delivery_district_name
    ) VALUES (
      auth.uid(), v_merchant_id, v_status, 'ADMIN', p_delivery_type,
      NULLIF(p_delivery->>'address', ''), NULLIF(p_delivery->>'phone', ''), NULLIF(p_delivery->>'name', ''),
      v_shipping, v_subtotal, v_total, NULLIF(p_delivery->>'notes', ''), v_discount,
      p_payment_method, v_payment_status, v_deadline, v_cod_fee, p_distance_km,
      (p_delivery->>'lat')::numeric, (p_delivery->>'lng')::numeric,
      NULLIF(p_delivery->>'province_id', ''), NULLIF(p_delivery->>'province_name', ''),
      NULLIF(p_delivery->>'city_id', ''), NULLIF(p_delivery->>'city_name', ''),
      NULLIF(p_delivery->>'district_id', ''), NULLIF(p_delivery->>'district_name', '')
    ) RETURNING id INTO v_order_id;
    v_order_ids := array_append(v_order_ids, v_order_id);
    IF v_primary_order_id IS NULL THEN v_primary_order_id := v_order_id; END IF;

    INSERT INTO public.order_items(order_id, product_id, product_name, product_price, quantity, subtotal)
    SELECT v_order_id, product_id, product_name, unit_price, quantity, line_total
    FROM checkout_lines WHERE merchant_id = v_merchant_id;

    PERFORM public.reserve_marketplace_stock(
      v_order_id,
      (SELECT jsonb_agg(jsonb_build_object('product_id', product_id, 'variant_id', NULL, 'quantity', quantity))
       FROM checkout_lines WHERE merchant_id = v_merchant_id),
      COALESCE(v_deadline, now() + interval '30 minutes')
    );

    IF p_voucher_id IS NOT NULL THEN
      INSERT INTO public.voucher_usages(voucher_id, user_id, order_id, discount_amount)
      VALUES (p_voucher_id, auth.uid(), v_order_id, v_discount);
      UPDATE public.vouchers SET used_count = used_count + 1, updated_at = now()
      WHERE id = p_voucher_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'order_ids', to_jsonb(v_order_ids),
    'primary_order_id', v_primary_order_id,
    'subtotal', (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines),
    'shipping_cost', v_shipping,
    'voucher_discount', v_discount,
    'cod_service_fee', v_cod_fee
  );
END;
$$$bootstrap_sql_d6c9a32aa199$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6c9a32aa199$;

DO $bootstrap_do_b6c67b697b71$
BEGIN
  EXECUTE $bootstrap_sql_b6c67b697b71$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric) FROM PUBLIC, anon$bootstrap_sql_b6c67b697b71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6c67b697b71$;

DO $bootstrap_do_8a26da6d2336$
BEGIN
  EXECUTE $bootstrap_sql_8a26da6d2336$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric) TO authenticated, service_role$bootstrap_sql_8a26da6d2336$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a26da6d2336$;

DO $bootstrap_do_e8b0f68871c2$
BEGIN
  EXECUTE $bootstrap_sql_e8b0f68871c2$-- Prevent buyer-side forged order/order-item rows. The security-definer checkout
-- function remains the supported write path.
DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_e8b0f68871c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8b0f68871c2$;

DO $bootstrap_do_99e65e6f890b$
BEGIN
  EXECUTE $bootstrap_sql_99e65e6f890b$DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items$bootstrap_sql_99e65e6f890b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99e65e6f890b$;

DO $bootstrap_do_c3a2d6b18fd3$
BEGIN
  EXECUTE $bootstrap_sql_c3a2d6b18fd3$REVOKE INSERT ON public.orders, public.order_items FROM authenticated, anon$bootstrap_sql_c3a2d6b18fd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3a2d6b18fd3$;

DO $bootstrap_do_7de89c952698$
BEGIN
  EXECUTE $bootstrap_sql_7de89c952698$-- ===== END BUNDLE: 48_20260911003000_marketplace_checkout_authoritative.sql =====

-- ===== BEGIN BUNDLE: 49_20260909240000_merchant_settings_hardening.sql =====
-- Harden merchant settings ownership and storage paths.
-- Merchants may edit operational/profile settings only. Approval, ownership,
-- verification and financial ledger fields remain admin/verifikator controlled.

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY$bootstrap_sql_7de89c952698$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7de89c952698$;

DO $bootstrap_do_4fe288021d37$
BEGIN
  EXECUTE $bootstrap_sql_4fe288021d37$DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants$bootstrap_sql_4fe288021d37$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fe288021d37$;

DO $bootstrap_do_8daf390686ad$
BEGIN
  EXECUTE $bootstrap_sql_8daf390686ad$CREATE POLICY "Merchants can update own data"
  ON public.merchants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid())$bootstrap_sql_8daf390686ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8daf390686ad$;

DO $bootstrap_do_8e0a9d6cd875$
BEGIN
  EXECUTE $bootstrap_sql_8e0a9d6cd875$CREATE OR REPLACE FUNCTION public.protect_merchant_control_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service-role operations and admin/verifikator workflows are allowed to
  -- change control-plane fields.
  IF auth.uid() IS NULL OR public.is_admin() OR public.is_verifikator() THEN
    RETURN NEW;
  END IF;

  IF OLD.user_id = auth.uid() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.user_id IS DISTINCT FROM OLD.user_id
      OR NEW.registration_status IS DISTINCT FROM OLD.registration_status
      OR NEW.status IS DISTINCT FROM OLD.status
      OR NEW.is_verified IS DISTINCT FROM OLD.is_verified
      OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
      OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
      OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
      OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
      OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
      OR NEW.verifikator_id IS DISTINCT FROM OLD.verifikator_id
      OR NEW.available_balance IS DISTINCT FROM OLD.available_balance
      OR NEW.pending_balance IS DISTINCT FROM OLD.pending_balance
      OR NEW.total_withdrawn IS DISTINCT FROM OLD.total_withdrawn
      OR NEW.current_subscription_id IS DISTINCT FROM OLD.current_subscription_id
      OR NEW.rating_avg IS DISTINCT FROM OLD.rating_avg
      OR NEW.rating_count IS DISTINCT FROM OLD.rating_count
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
      OR NEW.registered_at IS DISTINCT FROM OLD.registered_at
      OR NEW.village_id IS DISTINCT FROM OLD.village_id
      OR NEW.verifikator_code IS DISTINCT FROM OLD.verifikator_code THEN
      RAISE EXCEPTION 'merchant control fields can only be changed by admin or verifikator'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_8e0a9d6cd875$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e0a9d6cd875$;

DO $bootstrap_do_26d26fde1da8$
BEGIN
  EXECUTE $bootstrap_sql_26d26fde1da8$DROP TRIGGER IF EXISTS protect_merchant_control_fields ON public.merchants$bootstrap_sql_26d26fde1da8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26d26fde1da8$;

DO $bootstrap_do_39364bf762ec$
BEGIN
  EXECUTE $bootstrap_sql_39364bf762ec$CREATE TRIGGER protect_merchant_control_fields
  BEFORE UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_merchant_control_fields()$bootstrap_sql_39364bf762ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39364bf762ec$;

DO $bootstrap_do_a5f490d48512$
BEGIN
  EXECUTE $bootstrap_sql_a5f490d48512$INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'merchant-images',
  'merchant-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
SET public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']$bootstrap_sql_a5f490d48512$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5f490d48512$;

DO $bootstrap_do_ef51a3de040c$
BEGIN
  EXECUTE $bootstrap_sql_ef51a3de040c$DROP POLICY IF EXISTS "Merchants can upload merchant images" ON storage.objects$bootstrap_sql_ef51a3de040c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef51a3de040c$;

DO $bootstrap_do_b405e537291a$
BEGIN
  EXECUTE $bootstrap_sql_b405e537291a$CREATE POLICY "Merchants can upload merchant images"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  )$bootstrap_sql_b405e537291a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b405e537291a$;

DO $bootstrap_do_3b0a83af4487$
BEGIN
  EXECUTE $bootstrap_sql_3b0a83af4487$DROP POLICY IF EXISTS "Merchants can update own merchant images" ON storage.objects$bootstrap_sql_3b0a83af4487$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b0a83af4487$;

DO $bootstrap_do_070884bf320a$
BEGIN
  EXECUTE $bootstrap_sql_070884bf320a$CREATE POLICY "Merchants can update own merchant images"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  )
  WITH CHECK (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  )$bootstrap_sql_070884bf320a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_070884bf320a$;

DO $bootstrap_do_22fd949e4c01$
BEGIN
  EXECUTE $bootstrap_sql_22fd949e4c01$DROP POLICY IF EXISTS "Merchants can delete own merchant images" ON storage.objects$bootstrap_sql_22fd949e4c01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22fd949e4c01$;

DO $bootstrap_do_14d7ae1b2412$
BEGIN
  EXECUTE $bootstrap_sql_14d7ae1b2412$CREATE POLICY "Merchants can delete own merchant images"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'merchant-images'
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.user_id = auth.uid()
          AND (
            (storage.foldername(name))[1] = 'store'
            AND (storage.foldername(name))[2] = m.id::text
            OR (storage.foldername(name))[1] = 'qris'
            AND (storage.foldername(name))[2] = m.id::text
          )
      )
    )
  )$bootstrap_sql_14d7ae1b2412$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14d7ae1b2412$;

DO $bootstrap_do_95b35c5a8e09$
BEGIN
  EXECUTE $bootstrap_sql_95b35c5a8e09$NOTIFY pgrst, 'reload schema'$bootstrap_sql_95b35c5a8e09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95b35c5a8e09$;

DO $bootstrap_do_44f87e897ac4$
BEGIN
  EXECUTE $bootstrap_sql_44f87e897ac4$-- ===== END BUNDLE: 49_20260909240000_merchant_settings_hardening.sql =====

-- ===== BEGIN BUNDLE: 49_20260911005000_review_refund_rating_hardening.sql =====
-- Review, refund, and courier-rating hardening.
-- All buyer writes are moved behind ownership- and state-aware RPCs.

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS courier_rated boolean NOT NULL DEFAULT false$bootstrap_sql_44f87e897ac4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44f87e897ac4$;

DO $bootstrap_do_b00ca63ce573$
BEGIN
  EXECUTE $bootstrap_sql_b00ca63ce573$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS rating_avg numeric NOT NULL DEFAULT 0$bootstrap_sql_b00ca63ce573$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b00ca63ce573$;

DO $bootstrap_do_c18b2a69c303$
BEGIN
  EXECUTE $bootstrap_sql_c18b2a69c303$ALTER TABLE public.couriers ADD COLUMN IF NOT EXISTS rating_count integer NOT NULL DEFAULT 0$bootstrap_sql_c18b2a69c303$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c18b2a69c303$;

DO $bootstrap_do_6f9037d0c131$
BEGIN
  EXECUTE $bootstrap_sql_6f9037d0c131$DELETE FROM public.reviews a
USING public.reviews b
WHERE a.order_id = b.order_id
  AND a.product_id = b.product_id
  AND a.buyer_id = b.buyer_id
  AND a.id > b.id$bootstrap_sql_6f9037d0c131$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f9037d0c131$;

DO $bootstrap_do_959404c7c95b$
BEGIN
  EXECUTE $bootstrap_sql_959404c7c95b$CREATE UNIQUE INDEX IF NOT EXISTS reviews_one_per_order_product_buyer
  ON public.reviews(order_id, product_id, buyer_id)$bootstrap_sql_959404c7c95b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_959404c7c95b$;

DO $bootstrap_do_0121064518c2$
BEGIN
  EXECUTE $bootstrap_sql_0121064518c2$CREATE UNIQUE INDEX IF NOT EXISTS refund_requests_one_pending_per_order
  ON public.refund_requests(order_id)
  WHERE status IN ('PENDING', 'APPROVED')$bootstrap_sql_0121064518c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0121064518c2$;

DO $bootstrap_do_1b7c61673a03$
BEGIN
  EXECUTE $bootstrap_sql_1b7c61673a03$CREATE OR REPLACE FUNCTION public.prevent_review_identity_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() AND (
    NEW.buyer_id IS DISTINCT FROM OLD.buyer_id OR
    NEW.order_id IS DISTINCT FROM OLD.order_id OR
    NEW.product_id IS DISTINCT FROM OLD.product_id OR
    NEW.merchant_id IS DISTINCT FROM OLD.merchant_id OR
    NEW.rating IS DISTINCT FROM OLD.rating OR
    NEW.is_visible IS DISTINCT FROM OLD.is_visible OR
    NEW.comment IS DISTINCT FROM OLD.comment OR
    NEW.image_urls IS DISTINCT FROM OLD.image_urls OR
    NEW.created_at IS DISTINCT FROM OLD.created_at
  ) THEN
    RAISE EXCEPTION 'Review identity and rating are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_1b7c61673a03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b7c61673a03$;

DO $bootstrap_do_b7b331b8f593$
BEGIN
  EXECUTE $bootstrap_sql_b7b331b8f593$DROP TRIGGER IF EXISTS protect_review_identity ON public.reviews$bootstrap_sql_b7b331b8f593$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b7b331b8f593$;

DO $bootstrap_do_3a1785405626$
BEGIN
  EXECUTE $bootstrap_sql_3a1785405626$CREATE TRIGGER protect_review_identity
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.prevent_review_identity_mutation()$bootstrap_sql_3a1785405626$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a1785405626$;

DO $bootstrap_do_cb67bf5f4c64$
BEGIN
  EXECUTE $bootstrap_sql_cb67bf5f4c64$CREATE TABLE IF NOT EXISTS public.courier_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text,
  tags text[] DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id, courier_id, buyer_id)
)$bootstrap_sql_cb67bf5f4c64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb67bf5f4c64$;

DO $bootstrap_do_8981eb8ec8ad$
BEGIN
  EXECUTE $bootstrap_sql_8981eb8ec8ad$ALTER TABLE public.courier_ratings ENABLE ROW LEVEL SECURITY$bootstrap_sql_8981eb8ec8ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8981eb8ec8ad$;

DO $bootstrap_do_82c49b86b583$
BEGIN
  EXECUTE $bootstrap_sql_82c49b86b583$DROP POLICY IF EXISTS "Public can view courier ratings" ON public.courier_ratings$bootstrap_sql_82c49b86b583$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82c49b86b583$;

DO $bootstrap_do_81788fa23c46$
BEGIN
  EXECUTE $bootstrap_sql_81788fa23c46$CREATE POLICY "Public can view courier ratings" ON public.courier_ratings FOR SELECT USING (true)$bootstrap_sql_81788fa23c46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_81788fa23c46$;

DO $bootstrap_do_ff0a7cff988c$
BEGIN
  EXECUTE $bootstrap_sql_ff0a7cff988c$DROP POLICY IF EXISTS "Buyers can view own courier ratings" ON public.courier_ratings$bootstrap_sql_ff0a7cff988c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff0a7cff988c$;

DO $bootstrap_do_61d27712d8b3$
BEGIN
  EXECUTE $bootstrap_sql_61d27712d8b3$CREATE POLICY "Buyers can view own courier ratings" ON public.courier_ratings FOR SELECT USING (buyer_id = auth.uid())$bootstrap_sql_61d27712d8b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_61d27712d8b3$;

DO $bootstrap_do_295f53a02861$
BEGIN
  EXECUTE $bootstrap_sql_295f53a02861$GRANT SELECT ON public.courier_ratings TO anon, authenticated$bootstrap_sql_295f53a02861$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_295f53a02861$;

DO $bootstrap_do_15e80c76cdb9$
BEGIN
  EXECUTE $bootstrap_sql_15e80c76cdb9$REVOKE INSERT, UPDATE, DELETE ON public.courier_ratings FROM anon, authenticated$bootstrap_sql_15e80c76cdb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15e80c76cdb9$;

DO $bootstrap_do_eee5baec31df$
BEGIN
  EXECUTE $bootstrap_sql_eee5baec31df$CREATE OR REPLACE FUNCTION public.submit_order_reviews(p_order_id uuid, p_reviews jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_review jsonb;
  v_product_id uuid;
  v_rating integer;
  v_count integer := 0;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Only completed orders can be reviewed' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_reviews) <> 'array' OR jsonb_array_length(p_reviews) = 0 THEN
    RAISE EXCEPTION 'At least one review is required' USING ERRCODE = '22023';
  END IF;
  FOR v_review IN SELECT value FROM jsonb_array_elements(p_reviews) LOOP
    v_product_id := NULLIF(v_review->>'product_id', '')::uuid;
    v_rating := (v_review->>'rating')::integer;
    IF v_product_id IS NULL OR v_rating IS NULL OR v_rating NOT BETWEEN 1 AND 5 THEN
      RAISE EXCEPTION 'Invalid review payload' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.order_items WHERE order_id = p_order_id AND product_id = v_product_id) THEN
      RAISE EXCEPTION 'Product is not part of this order' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.reviews(product_id, order_id, buyer_id, merchant_id, rating, comment, image_urls)
    VALUES (
      v_product_id, p_order_id, auth.uid(), v_order.merchant_id, v_rating,
      NULLIF(left(COALESCE(v_review->>'comment', ''), 2000), ''),
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_review->'image_urls', '[]'::jsonb))), '{}')
    );
    v_count := v_count + 1;
  END LOOP;
  UPDATE public.orders SET has_review = true, updated_at = now() WHERE id = p_order_id;
  UPDATE public.merchants m SET
    rating_avg = COALESCE((SELECT round(avg(r.rating)::numeric, 2) FROM public.reviews r WHERE r.merchant_id = m.id AND r.is_visible = true), 0),
    rating_count = (SELECT count(*) FROM public.reviews r WHERE r.merchant_id = m.id AND r.is_visible = true)
  WHERE m.id = v_order.merchant_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'created', v_count);
END;
$$$bootstrap_sql_eee5baec31df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eee5baec31df$;

DO $bootstrap_do_fe58be045c26$
BEGIN
  EXECUTE $bootstrap_sql_fe58be045c26$CREATE OR REPLACE FUNCTION public.create_refund_request(
  p_order_id uuid, p_amount integer, p_reason text, p_evidence_urls text[] DEFAULT '{}',
  p_title text DEFAULT 'Komplain Pesanan', p_category text DEFAULT 'Lainnya'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_id uuid;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') THEN
    RAISE EXCEPTION 'Order is not eligible for refund' USING ERRCODE = '42501';
  END IF;
  IF upper(COALESCE(v_order.payment_status, '')) IN ('UNPAID', 'PENDING_TRANSFER', 'FAILED', 'EXPIRED') THEN
    RAISE EXCEPTION 'Unpaid orders cannot be refunded' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is outside the eligible range' USING ERRCODE = '22023';
  END IF;
  IF length(trim(COALESCE(p_reason, ''))) < 10 OR length(p_reason) > 4000 THEN
    RAISE EXCEPTION 'Refund reason is invalid' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.refund_requests WHERE order_id = p_order_id AND status IN ('PENDING', 'APPROVED')) THEN
    RAISE EXCEPTION 'An active refund request already exists' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.refund_requests(order_id, buyer_id, merchant_id, amount, reason, status, evidence_urls, refund_type, title, category, dispute_status)
  VALUES (p_order_id, auth.uid(), v_order.merchant_id, p_amount, trim(p_reason), 'PENDING',
    COALESCE(p_evidence_urls, '{}'), CASE WHEN p_amount = v_order.total THEN 'FULL' ELSE 'PARTIAL' END,
    left(COALESCE(NULLIF(trim(p_title), ''), 'Komplain Pesanan'), 200),
    left(COALESCE(NULLIF(trim(p_category), ''), 'Lainnya'), 80), 'OPEN')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'order_id', p_order_id, 'amount', p_amount);
END;
$$$bootstrap_sql_fe58be045c26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe58be045c26$;

DO $bootstrap_do_be97e3cfdf33$
BEGIN
  EXECUTE $bootstrap_sql_be97e3cfdf33$CREATE OR REPLACE FUNCTION public.process_refund_decision(p_refund_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_new_status text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_refund FROM public.refund_requests WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND OR v_refund.status <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund is no longer pending' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_refund.order_id FOR UPDATE;
  IF NOT FOUND OR v_refund.amount <= 0 OR v_refund.amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is invalid' USING ERRCODE = '22023';
  END IF;
  v_new_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  UPDATE public.refund_requests SET status = v_new_status, admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(), processed_at = now(), updated_at = now(), dispute_status = CASE WHEN p_approve THEN 'RESOLVED_REFUND' ELSE 'RESOLVED_REJECTED' END WHERE id = p_refund_id;
  IF p_approve THEN
    UPDATE public.orders SET status = 'REFUNDED', updated_at = now() WHERE id = v_order.id;
    UPDATE public.merchants SET available_balance = GREATEST(0, COALESCE(available_balance, 0) - v_refund.amount), updated_at = now() WHERE id = v_order.merchant_id;
  END IF;
  RETURN jsonb_build_object('id', p_refund_id, 'status', v_new_status);
END;
$$$bootstrap_sql_be97e3cfdf33$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be97e3cfdf33$;

DO $bootstrap_do_ee42ddf57e9b$
BEGIN
  EXECUTE $bootstrap_sql_ee42ddf57e9b$CREATE OR REPLACE FUNCTION public.respond_to_refund_request(p_refund_id uuid, p_response text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF length(trim(COALESCE(p_response, ''))) < 5 OR length(p_response) > 4000 THEN
    RAISE EXCEPTION 'Merchant response is invalid' USING ERRCODE = '22023';
  END IF;
  UPDATE public.refund_requests rr
  SET merchant_response = trim(p_response), merchant_responded_at = now(),
      dispute_status = 'MERCHANT_RESPONDED', updated_at = now()
  WHERE rr.id = p_refund_id
    AND rr.status = 'PENDING'
    AND EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = rr.merchant_id AND m.user_id = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund request is not available to this merchant' USING ERRCODE = '42501'; END IF;
  SELECT id INTO v_id FROM public.refund_requests WHERE id = p_refund_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'MERCHANT_RESPONDED');
END;
$$$bootstrap_sql_ee42ddf57e9b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee42ddf57e9b$;

DO $bootstrap_do_ee1a8832f797$
BEGIN
  EXECUTE $bootstrap_sql_ee1a8832f797$CREATE OR REPLACE FUNCTION public.submit_courier_rating(
  p_order_id uuid, p_courier_id uuid, p_rating integer, p_comment text DEFAULT NULL, p_tags text[] DEFAULT '{}'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR upper(v_order.status) NOT IN ('DONE', 'DELIVERED', 'COMPLETED') OR v_order.courier_id <> p_courier_id THEN
    RAISE EXCEPTION 'Order is not eligible for this courier rating' USING ERRCODE = '42501';
  END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '22023'; END IF;
  INSERT INTO public.courier_ratings(order_id, courier_id, buyer_id, rating, comment, tags)
  VALUES (p_order_id, p_courier_id, auth.uid(), p_rating, NULLIF(left(COALESCE(p_comment, ''), 500), ''), COALESCE(p_tags, '{}'))
  RETURNING id INTO v_id;
  UPDATE public.couriers c SET
    rating_avg = COALESCE((SELECT round(avg(r.rating)::numeric, 2) FROM public.courier_ratings r WHERE r.courier_id = c.id), 0),
    rating_count = (SELECT count(*) FROM public.courier_ratings r WHERE r.courier_id = c.id),
    updated_at = now()
  WHERE c.id = p_courier_id;
  UPDATE public.orders SET courier_rated = true, updated_at = now() WHERE id = p_order_id;
  RETURN jsonb_build_object('id', v_id);
END;
$$$bootstrap_sql_ee1a8832f797$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee1a8832f797$;

DO $bootstrap_do_f3b60c2bc756$
BEGIN
  EXECUTE $bootstrap_sql_f3b60c2bc756$REVOKE ALL ON FUNCTION public.submit_order_reviews(uuid, jsonb) FROM PUBLIC, anon$bootstrap_sql_f3b60c2bc756$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3b60c2bc756$;

DO $bootstrap_do_46c21ba0982f$
BEGIN
  EXECUTE $bootstrap_sql_46c21ba0982f$REVOKE ALL ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) FROM PUBLIC, anon$bootstrap_sql_46c21ba0982f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46c21ba0982f$;

DO $bootstrap_do_b98dcdfa00db$
BEGIN
  EXECUTE $bootstrap_sql_b98dcdfa00db$REVOKE ALL ON FUNCTION public.process_refund_decision(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_b98dcdfa00db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b98dcdfa00db$;

DO $bootstrap_do_6d55616bbc2d$
BEGIN
  EXECUTE $bootstrap_sql_6d55616bbc2d$REVOKE ALL ON FUNCTION public.submit_courier_rating(uuid, uuid, integer, text, text[]) FROM PUBLIC, anon$bootstrap_sql_6d55616bbc2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d55616bbc2d$;

DO $bootstrap_do_2dfbf0ccc478$
BEGIN
  EXECUTE $bootstrap_sql_2dfbf0ccc478$REVOKE ALL ON FUNCTION public.respond_to_refund_request(uuid, text) FROM PUBLIC, anon$bootstrap_sql_2dfbf0ccc478$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dfbf0ccc478$;

DO $bootstrap_do_f2e767b68c92$
BEGIN
  EXECUTE $bootstrap_sql_f2e767b68c92$GRANT EXECUTE ON FUNCTION public.submit_order_reviews(uuid, jsonb) TO authenticated$bootstrap_sql_f2e767b68c92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2e767b68c92$;

DO $bootstrap_do_09176b81b10e$
BEGIN
  EXECUTE $bootstrap_sql_09176b81b10e$GRANT EXECUTE ON FUNCTION public.create_refund_request(uuid, integer, text, text[], text, text) TO authenticated$bootstrap_sql_09176b81b10e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09176b81b10e$;

DO $bootstrap_do_aa48e2dec8b0$
BEGIN
  EXECUTE $bootstrap_sql_aa48e2dec8b0$GRANT EXECUTE ON FUNCTION public.process_refund_decision(uuid, boolean, text) TO authenticated$bootstrap_sql_aa48e2dec8b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa48e2dec8b0$;

DO $bootstrap_do_365c43bf4fb7$
BEGIN
  EXECUTE $bootstrap_sql_365c43bf4fb7$GRANT EXECUTE ON FUNCTION public.submit_courier_rating(uuid, uuid, integer, text, text[]) TO authenticated$bootstrap_sql_365c43bf4fb7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_365c43bf4fb7$;

DO $bootstrap_do_5c3afbb0057d$
BEGIN
  EXECUTE $bootstrap_sql_5c3afbb0057d$GRANT EXECUTE ON FUNCTION public.respond_to_refund_request(uuid, text) TO authenticated$bootstrap_sql_5c3afbb0057d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c3afbb0057d$;

DO $bootstrap_do_22b885edf5a2$
BEGIN
  EXECUTE $bootstrap_sql_22b885edf5a2$DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews$bootstrap_sql_22b885edf5a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22b885edf5a2$;

DO $bootstrap_do_a80cc36b5a63$
BEGIN
  EXECUTE $bootstrap_sql_a80cc36b5a63$DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests$bootstrap_sql_a80cc36b5a63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a80cc36b5a63$;

DO $bootstrap_do_cb9610af1fb6$
BEGIN
  EXECUTE $bootstrap_sql_cb9610af1fb6$REVOKE INSERT ON public.reviews, public.refund_requests FROM authenticated, anon$bootstrap_sql_cb9610af1fb6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb9610af1fb6$;

DO $bootstrap_do_5dd053769419$
BEGIN
  EXECUTE $bootstrap_sql_5dd053769419$-- ===== END BUNDLE: 49_20260911005000_review_refund_rating_hardening.sql =====

-- ===== BEGIN BUNDLE: 50_20260910000000_merchant_google_maps_url.sql =====
-- Store an optional public Google Maps link for the merchant profile.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS google_maps_url text$bootstrap_sql_5dd053769419$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5dd053769419$;

DO $bootstrap_do_09bc22ac2881$
BEGIN
  EXECUTE $bootstrap_sql_09bc22ac2881$COMMENT ON COLUMN public.merchants.google_maps_url IS
  'Optional public URL used to open the merchant location in Google Maps'$bootstrap_sql_09bc22ac2881$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09bc22ac2881$;

DO $bootstrap_do_39915c29f8b8$
BEGIN
  EXECUTE $bootstrap_sql_39915c29f8b8$NOTIFY pgrst, 'reload schema'$bootstrap_sql_39915c29f8b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39915c29f8b8$;

DO $bootstrap_do_8fc47d335b46$
BEGIN
  EXECUTE $bootstrap_sql_8fc47d335b46$-- ===== END BUNDLE: 50_20260910000000_merchant_google_maps_url.sql =====

-- ===== BEGIN BUNDLE: 50_20260911071000_transaction_critical_high_hardening.sql =====
-- Server-authoritative shipping, provider recovery, and settlement hardening.
-- This migration replaces the checkout function while retaining its signature.

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_product public.products%ROWTYPE;
  v_merchant_id uuid;
  v_order_id uuid;
  v_primary_order_id uuid;
  v_order_ids uuid[] := ARRAY[]::uuid[];
  v_quantity integer;
  v_subtotal integer;
  v_shipping integer;
  v_cod_fee integer := 0;
  v_discount integer := 0;
  v_total integer;
  v_voucher public.vouchers%ROWTYPE;
  v_voucher_merchant uuid;
  v_merchant_count integer;
  v_settings jsonb;
  v_cod_settings jsonb;
  v_unit_price integer;
  v_item_subtotal integer;
  v_status text;
  v_payment_status text;
  v_deadline timestamptz;
  v_merchant_item jsonb;
  v_delivery_lat numeric;
  v_delivery_lng numeric;
  v_merchant_lat numeric;
  v_merchant_lng numeric;
  v_server_distance numeric;
  v_shipping_total integer := 0;
BEGIN
  IF auth.uid() IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid checkout request' USING ERRCODE = '22023';
  END IF;
  IF p_delivery_type NOT IN ('PICKUP', 'INTERNAL', 'EXPEDITION') THEN
    RAISE EXCEPTION 'Invalid delivery type' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method NOT IN ('COD', 'TRANSFER', 'ONLINE') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'ONLINE' AND (
    SELECT count(DISTINCT p.merchant_id)
    FROM jsonb_array_elements(p_items) x
    JOIN public.products p ON p.id = NULLIF(x->>'product_id', '')::uuid
  ) > 1 THEN
    RAISE EXCEPTION 'Online checkout supports one merchant per invoice' USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE checkout_lines (
    product_id uuid NOT NULL,
    merchant_id uuid NOT NULL,
    product_name text NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    line_total integer NOT NULL
  ) ON COMMIT DROP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF NULLIF(v_item->>'product_id', '') IS NULL THEN
      RAISE EXCEPTION 'Product is required' USING ERRCODE = '22023';
    END IF;
    v_quantity := (v_item->>'quantity')::integer;
    IF v_quantity IS NULL OR v_quantity <= 0 OR v_quantity > 1000 THEN
      RAISE EXCEPTION 'Invalid product quantity' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = (v_item->>'product_id')::uuid
    FOR UPDATE;
    IF NOT FOUND OR v_product.is_active IS NOT TRUE THEN
      RAISE EXCEPTION 'Product is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.merchant_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = v_product.merchant_id
        AND m.registration_status = 'APPROVED'
        AND m.status = 'ACTIVE'
        AND m.is_open = true
    ) THEN
      RAISE EXCEPTION 'Merchant is unavailable' USING ERRCODE = '22023';
    END IF;
    IF v_product.stock < v_quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product %', v_product.name USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(fs.flash_price, v_product.price)
      INTO v_unit_price
    FROM (SELECT 1) base
    LEFT JOIN LATERAL (
      SELECT flash_price
      FROM public.flash_sales
      WHERE product_id = v_product.id
        AND merchant_id = v_product.merchant_id
        AND status = 'ACTIVE'
        AND start_time <= now()
        AND end_time > now()
        AND stock_available > stock_sold
      ORDER BY end_time ASC
      LIMIT 1
    ) fs ON true;
    v_item_subtotal := v_unit_price * v_quantity;
    INSERT INTO checkout_lines VALUES (
      v_product.id, v_product.merchant_id, v_product.name,
      v_quantity, v_unit_price, v_item_subtotal
    );
  END LOOP;

  SELECT count(DISTINCT merchant_id) INTO v_merchant_count FROM checkout_lines;
  IF p_voucher_id IS NOT NULL AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Voucher checkout must contain one merchant' USING ERRCODE = '22023';
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    SELECT * INTO v_voucher FROM public.vouchers WHERE id = p_voucher_id FOR UPDATE;
    IF NOT FOUND OR v_voucher.is_active IS NOT TRUE
       OR v_voucher.start_date > now()
       OR (v_voucher.end_date IS NOT NULL AND v_voucher.end_date < now()) THEN
      RAISE EXCEPTION 'Voucher is invalid or expired' USING ERRCODE = '22023';
    END IF;
    SELECT merchant_id INTO v_voucher_merchant FROM checkout_lines LIMIT 1;
    IF v_voucher.merchant_id IS NOT NULL AND v_voucher.merchant_id <> v_voucher_merchant THEN
      RAISE EXCEPTION 'Voucher does not apply to this merchant' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.voucher_usages WHERE voucher_id = p_voucher_id AND user_id = auth.uid()) THEN
      RAISE EXCEPTION 'Voucher has already been used' USING ERRCODE = '23505';
    END IF;
    IF v_voucher.usage_limit IS NOT NULL AND v_voucher.used_count >= v_voucher.usage_limit THEN
      RAISE EXCEPTION 'Voucher usage limit reached' USING ERRCODE = '23505';
    END IF;
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines);
    IF v_subtotal < COALESCE(v_voucher.min_order_amount, 0) THEN
      RAISE EXCEPTION 'Minimum order for voucher is not met' USING ERRCODE = '22023';
    END IF;
    IF v_voucher.discount_type = 'percentage' THEN
      v_discount := floor(v_subtotal * v_voucher.discount_value / 100.0);
      IF v_voucher.max_discount IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_voucher.max_discount);
      END IF;
    ELSE
      v_discount := v_voucher.discount_value;
    END IF;
    v_discount := GREATEST(0, LEAST(v_discount, v_subtotal));
  END IF;

  SELECT value INTO v_cod_settings FROM public.app_settings WHERE key = 'cod_settings';
  IF p_payment_method = 'COD' THEN
    IF COALESCE((v_cod_settings->>'enabled')::boolean, true) IS NOT TRUE THEN
      RAISE EXCEPTION 'COD is currently unavailable' USING ERRCODE = '22023';
    END IF;
    -- COD remains available, but it is always free of charge.
    v_cod_fee := 0;
  END IF;

  IF p_payment_method = 'COD' THEN
    v_status := 'PENDING_CONFIRMATION';
    v_payment_status := 'COD';
    v_deadline := now() + make_interval(mins => COALESCE((v_cod_settings->>'confirmation_timeout_minutes')::integer, 15));
  ELSIF p_payment_method = 'TRANSFER' THEN
    v_status := 'PENDING_PAYMENT';
    v_payment_status := 'PENDING_TRANSFER';
    v_deadline := NULL;
  ELSE
    v_status := 'NEW';
    v_payment_status := 'UNPAID';
    v_deadline := NULL;
  END IF;

  FOR v_merchant_id IN SELECT DISTINCT merchant_id FROM checkout_lines ORDER BY merchant_id LOOP
    v_subtotal := (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines WHERE merchant_id = v_merchant_id);
    SELECT location_lat, location_lng INTO v_merchant_lat, v_merchant_lng
    FROM public.merchants WHERE id = v_merchant_id FOR SHARE;
    v_delivery_lat := NULLIF(p_delivery->>'lat', '')::numeric;
    v_delivery_lng := NULLIF(p_delivery->>'lng', '')::numeric;
    IF p_delivery_type = 'PICKUP' THEN
      v_shipping := 0;
      v_server_distance := 0;
    ELSIF v_delivery_lat IS NULL OR v_delivery_lng IS NULL
       OR v_merchant_lat IS NULL OR v_merchant_lng IS NULL THEN
      RAISE EXCEPTION 'Valid delivery and merchant coordinates are required' USING ERRCODE = '22023';
    ELSE
      v_server_distance := 6371 * 2 * asin(sqrt(
        power(sin(radians(v_delivery_lat - v_merchant_lat) / 2), 2)
        + cos(radians(v_merchant_lat)) * cos(radians(v_delivery_lat))
        * power(sin(radians(v_delivery_lng - v_merchant_lng) / 2), 2)
      ));
      SELECT value INTO v_settings FROM public.app_settings WHERE key = 'shipping_base_fee';
      IF v_subtotal >= COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000) THEN
        v_shipping := 0;
      ELSE
        v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
          + round(v_server_distance * COALESCE((v_settings->>'per_km_fee')::integer, 2000));
        v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
          GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
      END IF;
    END IF;
    v_shipping_total := v_shipping_total + v_shipping;
    v_total := GREATEST(0, v_subtotal + v_shipping + v_cod_fee - v_discount);
    INSERT INTO public.orders (
      buyer_id, merchant_id, status, handled_by, delivery_type,
      delivery_address, delivery_phone, delivery_name, shipping_cost,
      subtotal, total, notes, flash_sale_discount, payment_method,
      payment_status, confirmation_deadline, cod_service_fee, buyer_distance_km,
      delivery_lat, delivery_lng, delivery_province_id, delivery_province_name,
      delivery_city_id, delivery_city_name, delivery_district_id, delivery_district_name
    ) VALUES (
      auth.uid(), v_merchant_id, v_status, 'ADMIN', p_delivery_type,
      NULLIF(p_delivery->>'address', ''), NULLIF(p_delivery->>'phone', ''), NULLIF(p_delivery->>'name', ''),
      v_shipping, v_subtotal, v_total, NULLIF(p_delivery->>'notes', ''), v_discount,
      p_payment_method, v_payment_status, v_deadline, v_cod_fee, v_server_distance,
      (p_delivery->>'lat')::numeric, (p_delivery->>'lng')::numeric,
      NULLIF(p_delivery->>'province_id', ''), NULLIF(p_delivery->>'province_name', ''),
      NULLIF(p_delivery->>'city_id', ''), NULLIF(p_delivery->>'city_name', ''),
      NULLIF(p_delivery->>'district_id', ''), NULLIF(p_delivery->>'district_name', '')
    ) RETURNING id INTO v_order_id;
    v_order_ids := array_append(v_order_ids, v_order_id);
    IF v_primary_order_id IS NULL THEN v_primary_order_id := v_order_id; END IF;

    INSERT INTO public.order_items(order_id, product_id, product_name, product_price, quantity, subtotal)
    SELECT v_order_id, product_id, product_name, unit_price, quantity, line_total
    FROM checkout_lines WHERE merchant_id = v_merchant_id;

    PERFORM public.reserve_marketplace_stock(
      v_order_id,
      (SELECT jsonb_agg(jsonb_build_object('product_id', product_id, 'variant_id', NULL, 'quantity', quantity))
       FROM checkout_lines WHERE merchant_id = v_merchant_id),
      COALESCE(v_deadline, now() + interval '30 minutes')
    );

    IF p_voucher_id IS NOT NULL THEN
      INSERT INTO public.voucher_usages(voucher_id, user_id, order_id, discount_amount)
      VALUES (p_voucher_id, auth.uid(), v_order_id, v_discount);
      UPDATE public.vouchers SET used_count = used_count + 1, updated_at = now()
      WHERE id = p_voucher_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'order_ids', to_jsonb(v_order_ids),
    'primary_order_id', v_primary_order_id,
    'subtotal', (SELECT COALESCE(sum(line_total), 0) FROM checkout_lines),
    'shipping_cost', v_shipping_total,
    'voucher_discount', v_discount,
    'cod_service_fee', v_cod_fee
  );
END;
$$$bootstrap_sql_8fc47d335b46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8fc47d335b46$;

DO $bootstrap_do_ee08c8a781d5$
BEGIN
  EXECUTE $bootstrap_sql_ee08c8a781d5$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric) FROM PUBLIC, anon$bootstrap_sql_ee08c8a781d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee08c8a781d5$;

DO $bootstrap_do_aaf945825b42$
BEGIN
  EXECUTE $bootstrap_sql_aaf945825b42$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric) TO authenticated, service_role$bootstrap_sql_aaf945825b42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aaf945825b42$;

DO $bootstrap_do_ae4a6e7a6c47$
BEGIN
  EXECUTE $bootstrap_sql_ae4a6e7a6c47$REVOKE INSERT ON public.orders, public.order_items FROM anon, authenticated$bootstrap_sql_ae4a6e7a6c47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae4a6e7a6c47$;

DO $bootstrap_do_dc44f3450f49$
BEGIN
  EXECUTE $bootstrap_sql_dc44f3450f49$-- ===== END BUNDLE: 50_20260911071000_transaction_critical_high_hardening.sql =====

-- ===== BEGIN BUNDLE: 51_20260911072000_refund_settlement_hardening.sql =====
-- Refund settlement hardening.
-- Approval creates a durable settlement intent; money and balances change only
-- after a trusted provider completion callback.

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS settlement_status text NOT NULL DEFAULT 'NOT_REQUIRED',
  ADD COLUMN IF NOT EXISTS settlement_id uuid$bootstrap_sql_dc44f3450f49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc44f3450f49$;

DO $bootstrap_do_23c513466a6b$
BEGIN
  EXECUTE $bootstrap_sql_23c513466a6b$REVOKE INSERT ON public.refund_requests FROM anon, authenticated$bootstrap_sql_23c513466a6b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23c513466a6b$;

DO $bootstrap_do_08414d5a4b36$
BEGIN
  EXECUTE $bootstrap_sql_08414d5a4b36$CREATE TABLE IF NOT EXISTS public.refund_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_request_id uuid NOT NULL UNIQUE REFERENCES public.refund_requests(id) ON DELETE RESTRICT,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE RESTRICT,
  amount integer NOT NULL CHECK (amount > 0),
  provider text NOT NULL DEFAULT 'xendit',
  idempotency_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED')),
  provider_reference text,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
)$bootstrap_sql_08414d5a4b36$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08414d5a4b36$;

DO $bootstrap_do_bbf97c1bd7f6$
BEGIN
  EXECUTE $bootstrap_sql_bbf97c1bd7f6$ALTER TABLE public.refund_settlements ENABLE ROW LEVEL SECURITY$bootstrap_sql_bbf97c1bd7f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbf97c1bd7f6$;

DO $bootstrap_do_2a0847eab622$
BEGIN
  EXECUTE $bootstrap_sql_2a0847eab622$DROP POLICY IF EXISTS "Buyers can view own refund settlements" ON public.refund_settlements$bootstrap_sql_2a0847eab622$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a0847eab622$;

DO $bootstrap_do_aa21bb5d462c$
BEGIN
  EXECUTE $bootstrap_sql_aa21bb5d462c$CREATE POLICY "Buyers can view own refund settlements" ON public.refund_settlements
  FOR SELECT USING (buyer_id = auth.uid())$bootstrap_sql_aa21bb5d462c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa21bb5d462c$;

DO $bootstrap_do_b8d720f4f627$
BEGIN
  EXECUTE $bootstrap_sql_b8d720f4f627$DROP POLICY IF EXISTS "Admins can manage refund settlements" ON public.refund_settlements$bootstrap_sql_b8d720f4f627$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b8d720f4f627$;

DO $bootstrap_do_d8329e66144b$
BEGIN
  EXECUTE $bootstrap_sql_d8329e66144b$CREATE POLICY "Admins can manage refund settlements" ON public.refund_settlements
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_d8329e66144b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8329e66144b$;

DO $bootstrap_do_75ce4cb3393a$
BEGIN
  EXECUTE $bootstrap_sql_75ce4cb3393a$REVOKE ALL ON public.refund_settlements FROM anon, authenticated$bootstrap_sql_75ce4cb3393a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75ce4cb3393a$;

DO $bootstrap_do_8711afa57ba0$
BEGIN
  EXECUTE $bootstrap_sql_8711afa57ba0$GRANT SELECT ON public.refund_settlements TO authenticated$bootstrap_sql_8711afa57ba0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8711afa57ba0$;

DO $bootstrap_do_0583fd830594$
BEGIN
  EXECUTE $bootstrap_sql_0583fd830594$CREATE OR REPLACE FUNCTION public.process_refund_decision(p_refund_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_settlement_id uuid;
  v_new_status text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_refund FROM public.refund_requests WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND OR v_refund.status <> 'PENDING' THEN
    RAISE EXCEPTION 'Refund is no longer pending' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = v_refund.order_id FOR UPDATE;
  IF NOT FOUND OR v_refund.amount <= 0 OR v_refund.amount > v_order.total THEN
    RAISE EXCEPTION 'Refund amount is invalid' USING ERRCODE = '22023';
  END IF;
  v_new_status := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
  IF p_approve THEN
    INSERT INTO public.refund_settlements(refund_request_id, order_id, buyer_id, merchant_id, amount, idempotency_key)
    VALUES (v_refund.id, v_refund.order_id, v_refund.buyer_id, v_refund.merchant_id, v_refund.amount, 'refund:' || v_refund.id::text)
    ON CONFLICT (refund_request_id) DO UPDATE SET updated_at = now()
    RETURNING id INTO v_settlement_id;
    UPDATE public.refund_requests
    SET status = 'APPROVED', settlement_status = 'PENDING', settlement_id = v_settlement_id,
        admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(),
        processed_at = now(), updated_at = now(), dispute_status = 'RESOLVED_REFUND'
    WHERE id = p_refund_id;
  ELSE
    UPDATE public.refund_requests
    SET status = 'REJECTED', settlement_status = 'NOT_REQUIRED',
        admin_notes = NULLIF(left(COALESCE(p_notes, ''), 2000), ''), processed_by = auth.uid(),
        processed_at = now(), updated_at = now(), dispute_status = 'RESOLVED_REJECTED'
    WHERE id = p_refund_id;
  END IF;
  RETURN jsonb_build_object('id', p_refund_id, 'status', v_new_status,
    'settlement_status', CASE WHEN p_approve THEN 'PENDING' ELSE 'NOT_REQUIRED' END,
    'settlement_id', v_settlement_id);
END;
$$$bootstrap_sql_0583fd830594$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0583fd830594$;

DO $bootstrap_do_571fe616b8d5$
BEGIN
  EXECUTE $bootstrap_sql_571fe616b8d5$CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text DEFAULT NULL, p_error text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
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
    UPDATE public.refund_settlements SET status = 'FAILED', last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now() WHERE id = p_settlement_id;
    UPDATE public.refund_requests SET settlement_status = 'FAILED', updated_at = now() WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;
  UPDATE public.refund_settlements SET status = 'COMPLETED', provider_reference = left(p_provider_reference, 200), updated_at = now(), completed_at = now() WHERE id = p_settlement_id;
  UPDATE public.refund_requests SET settlement_status = 'COMPLETED', updated_at = now() WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now() WHERE id = v_settlement.order_id;
  UPDATE public.merchants SET available_balance = GREATEST(0, COALESCE(available_balance, 0) - v_settlement.amount), updated_at = now() WHERE id = v_settlement.merchant_id;
  RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED');
END;
$$$bootstrap_sql_571fe616b8d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_571fe616b8d5$;

DO $bootstrap_do_d1869ed6ce49$
BEGIN
  EXECUTE $bootstrap_sql_d1869ed6ce49$-- PAID is terminal except for the trusted, completed refund transition.
CREATE OR REPLACE FUNCTION public.prevent_paid_payment_downgrade()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.payment_status = 'PAID' AND NEW.payment_status IS DISTINCT FROM 'PAID'
     AND NEW.payment_status IS DISTINCT FROM 'REFUNDED' THEN
    RAISE EXCEPTION 'Paid order payment status is terminal' USING ERRCODE = '27000';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_d1869ed6ce49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d1869ed6ce49$;

DO $bootstrap_do_723a5ca4d416$
BEGIN
  EXECUTE $bootstrap_sql_723a5ca4d416$REVOKE ALL ON FUNCTION public.process_refund_decision(uuid, boolean, text) FROM PUBLIC, anon$bootstrap_sql_723a5ca4d416$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_723a5ca4d416$;

DO $bootstrap_do_3032d30198f8$
BEGIN
  EXECUTE $bootstrap_sql_3032d30198f8$GRANT EXECUTE ON FUNCTION public.process_refund_decision(uuid, boolean, text) TO authenticated$bootstrap_sql_3032d30198f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3032d30198f8$;

DO $bootstrap_do_ca55ef090b5d$
BEGIN
  EXECUTE $bootstrap_sql_ca55ef090b5d$REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated$bootstrap_sql_ca55ef090b5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ca55ef090b5d$;

DO $bootstrap_do_589ecac23658$
BEGIN
  EXECUTE $bootstrap_sql_589ecac23658$GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) TO service_role$bootstrap_sql_589ecac23658$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_589ecac23658$;

DO $bootstrap_do_9e3d12ed3805$
BEGIN
  EXECUTE $bootstrap_sql_9e3d12ed3805$-- ===== END BUNDLE: 51_20260911072000_refund_settlement_hardening.sql =====$bootstrap_sql_9e3d12ed3805$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e3d12ed3805$;
