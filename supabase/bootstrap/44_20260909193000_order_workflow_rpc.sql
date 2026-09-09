-- Order workflow hardening: canonical transitions, courier offers, and self-delivery fee ledger.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW','PENDING_CONFIRMATION','PENDING_PAYMENT','PROCESSED','READY','ASSIGNED',
    'COURIER_ASSIGNED','COURIER_ACCEPTED','COURIER_REJECTED','PICKED_UP','SENT',
    'DELIVERING','DELIVERED','DONE','CANCELED','REJECTED','REJECTED_BY_BUYER','REFUNDED'
  ));

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status_updated_at timestamptz;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_attempt integer NOT NULL DEFAULT 0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_fee_amount numeric NOT NULL DEFAULT 0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS self_delivery_fee_status text NOT NULL DEFAULT 'NOT_APPLICABLE';

CREATE TABLE IF NOT EXISTS public.order_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  from_status text,
  to_status text NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON public.order_status_history(order_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.delivery_assignments (
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
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_assignment_active_order ON public.delivery_assignments(order_id) WHERE status IN ('OFFERED','ACCEPTED');
CREATE INDEX IF NOT EXISTS idx_delivery_assignment_courier ON public.delivery_assignments(courier_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.merchant_delivery_fee_ledger (
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
);

ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_delivery_fee_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Order parties view status history" ON public.order_status_history;
CREATE POLICY "Order parties view status history" ON public.order_status_history FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND (o.buyer_id = auth.uid() OR public.is_order_merchant(o.id) OR public.is_admin() OR public.is_order_courier(o.id)))
);
DROP POLICY IF EXISTS "Couriers view own assignments" ON public.delivery_assignments;
CREATE POLICY "Couriers view own assignments" ON public.delivery_assignments FOR SELECT TO authenticated USING (
  courier_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()) OR EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND (o.buyer_id = auth.uid() OR public.is_order_merchant(o.id) OR public.is_admin()))
);
DROP POLICY IF EXISTS "Merchant view own delivery fees" ON public.merchant_delivery_fee_ledger;
CREATE POLICY "Merchant view own delivery fees" ON public.merchant_delivery_fee_ledger FOR SELECT TO authenticated USING (public.is_order_merchant(order_id) OR public.is_admin());

CREATE OR REPLACE FUNCTION public.merchant_transition_order(p_order_id uuid, p_to_status text, p_reason text DEFAULT NULL)
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
END; $$;
GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_delivery_offer(p_order_id uuid, p_courier_id uuid)
RETURNS public.delivery_assignments LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.orders%ROWTYPE; v_assignment public.delivery_assignments%ROWTYPE;
BEGIN
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR NOT public.is_order_merchant(p_order_id) THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE='42501'; END IF;
 IF v_order.status NOT IN ('READY','ASSIGNED') OR v_order.is_self_delivery THEN RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.delivery_assignments WHERE order_id=p_order_id AND courier_id=p_courier_id AND status IN ('REJECTED','EXPIRED')) THEN RAISE EXCEPTION 'Courier already declined this order' USING ERRCODE='22023'; END IF;
 INSERT INTO public.delivery_assignments(order_id,courier_id) VALUES(p_order_id,p_courier_id) RETURNING * INTO v_assignment;
 UPDATE public.orders SET status='ASSIGNED', status_updated_at=now(), updated_at=now() WHERE id=p_order_id;
 RETURN v_assignment;
END; $$;
GRANT EXECUTE ON FUNCTION public.create_delivery_offer(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_delivery_offer(p_assignment_id uuid, p_accept boolean, p_reason text DEFAULT NULL)
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
END; $$;
GRANT EXECUTE ON FUNCTION public.respond_delivery_offer(uuid,boolean,text) TO authenticated;

INSERT INTO public.app_settings(key,category,value,description) VALUES('self_delivery_fee','delivery','{"percent":10}'::jsonb,'Biaya platform antar sendiri setelah kuota gratis') ON CONFLICT(key) DO NOTHING;
UPDATE public.orders SET status_updated_at=COALESCE(status_updated_at,updated_at,created_at);
NOTIFY pgrst, 'reload schema';
