-- Audit fix: pickup completion and authoritative status history.
CREATE OR REPLACE FUNCTION public.merchant_transition_order(p_order_id uuid, p_to_status text, p_reason text DEFAULT NULL, p_is_self_delivery boolean DEFAULT NULL)
RETURNS public.orders LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.orders%ROWTYPE; v_merchant_id uuid; v_allowed boolean := false; v_from text; v_payload jsonb := CASE WHEN left(trim(coalesce(p_reason, '')), 1) = '{' THEN p_reason::jsonb ELSE '{}'::jsonb END;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id=auth.uid() LIMIT 1;
 SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
 IF NOT FOUND OR (NOT public.is_admin() AND v_order.merchant_id IS DISTINCT FROM v_merchant_id) THEN RAISE EXCEPTION 'Order access denied' USING ERRCODE='42501'; END IF;
 v_from:=v_order.status;
 v_allowed := CASE
  WHEN v_from IN ('NEW','PENDING_CONFIRMATION') AND p_to_status IN ('PROCESSED','CANCELED','REJECTED') THEN true
  WHEN v_from='PENDING_PAYMENT' AND p_to_status IN ('CANCELED','REJECTED') THEN true
  WHEN v_from='PROCESSED' AND p_to_status IN ('READY','DELIVERING','ASSIGNED','CANCELED') THEN true
  WHEN v_from='PROCESSED' AND p_to_status='SENT' AND v_order.delivery_type='EXPEDITION' THEN true
  WHEN v_from='READY' AND p_to_status IN ('ASSIGNED','DELIVERING','CANCELED') THEN true
  WHEN v_from='READY' AND p_to_status='DONE' AND v_order.delivery_type='PICKUP' THEN true
  WHEN v_from='ASSIGNED' AND p_to_status IN ('COURIER_ACCEPTED','CANCELED') THEN true
  WHEN v_from='COURIER_ACCEPTED' AND p_to_status IN ('PICKED_UP','CANCELED') THEN true
  WHEN v_from='PICKED_UP' AND p_to_status='DELIVERING' THEN true
  WHEN v_from='DELIVERING' AND p_to_status='DELIVERED' THEN true
  WHEN v_from IN ('DELIVERED','SENT') AND p_to_status='DONE' THEN true
  WHEN public.is_admin() AND p_to_status IN ('CANCELED','REFUNDED','DONE') THEN true ELSE false END;
 IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid order transition: % -> %',v_from,p_to_status USING ERRCODE='55000'; END IF;
 UPDATE public.orders SET status=p_to_status,is_self_delivery=COALESCE(p_is_self_delivery,is_self_delivery),confirmed_at=CASE WHEN p_to_status='PROCESSED' THEN now() ELSE confirmed_at END,ready_at=CASE WHEN p_to_status='READY' THEN now() ELSE ready_at END,picked_up_at=CASE WHEN p_to_status='PICKED_UP' THEN now() ELSE picked_up_at END,delivered_at=CASE WHEN p_to_status IN ('DELIVERED','DONE') THEN COALESCE(delivered_at,now()) ELSE delivered_at END,updated_at=now() WHERE id=p_order_id RETURNING * INTO v_order;
 INSERT INTO public.order_status_history(order_id,from_status,to_status,actor_id,reason) VALUES(p_order_id,v_from,p_to_status,auth.uid(),COALESCE(NULLIF(trim(v_payload->>'reason'),''),NULLIF(trim(p_reason),''),CASE WHEN p_to_status='DONE' AND v_order.delivery_type='PICKUP' THEN 'Pesanan pickup diselesaikan oleh merchant/admin' END));
 RETURN v_order;
END; $$;
GRANT EXECUTE ON FUNCTION public.merchant_transition_order(uuid,text,text,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
