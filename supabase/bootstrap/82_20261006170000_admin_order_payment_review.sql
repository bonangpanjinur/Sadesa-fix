-- DesaMart repeatable canonical bootstrap bundle.
-- Admin payment-proof review and safe resubmission after a rejected proof.

DO $bootstrap_do_admin_order_payment_review$
BEGIN
  EXECUTE $bootstrap_sql_admin_reject_order_payment$
CREATE OR REPLACE FUNCTION public.admin_reject_order_payment(
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
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_order_id IS NULL OR v_reason IS NULL
     OR char_length(v_reason) < 3 OR char_length(v_reason) > 1000 THEN
    RAISE EXCEPTION 'A rejection reason between 3 and 1000 characters is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.payment_method IS DISTINCT FROM 'TRANSFER'
     OR v_order.status NOT IN ('PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'NEW')
     OR v_order.payment_status IN ('PAID', 'FAILED', 'REFUNDED', 'EXPIRED') THEN
    RAISE EXCEPTION 'Order payment is not awaiting review' USING ERRCODE = '55000';
  END IF;

  IF NULLIF(trim(COALESCE(v_order.payment_proof_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Payment proof is required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET payment_status = 'FAILED', updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_security_audit_log (
    order_id, actor_id, event_type, old_status, new_status,
    old_payment_status, new_payment_status, metadata
  ) VALUES (
    p_order_id, auth.uid(), 'payment_proof_rejected', v_order.status, v_order.status,
    v_order.payment_status, 'FAILED', jsonb_build_object('reason', v_reason)
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'payment_status', 'FAILED',
    'status', v_order.status
  );
END;
$$;
$bootstrap_sql_admin_reject_order_payment$;

  EXECUTE $bootstrap_sql_admin_order_payment_review_verify$
CREATE OR REPLACE FUNCTION public.merchant_verify_order_payment(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT id, merchant_id, status, payment_status, payment_proof_url
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.is_admin()
     AND NOT EXISTS (
       SELECT 1 FROM public.merchants m
       WHERE m.id = v_order.merchant_id AND m.user_id = auth.uid()
     ) THEN
    RAISE EXCEPTION 'Order verification access denied' USING ERRCODE = '42501';
  END IF;

  IF v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'already_paid', true, 'order_id', v_order.id);
  END IF;

  IF v_order.payment_status = 'FAILED' THEN
    RAISE EXCEPTION 'Payment proof was rejected; a new proof is required' USING ERRCODE = '22023';
  END IF;

  IF v_order.payment_proof_url IS NULL OR length(trim(v_order.payment_proof_url)) = 0 THEN
    RAISE EXCEPTION 'Payment proof is required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET payment_status = 'PAID',
      payment_paid_at = v_now,
      status = CASE WHEN status IN ('PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'NEW') THEN 'PROCESSED' ELSE status END,
      confirmed_at = COALESCE(confirmed_at, v_now),
      updated_at = v_now
  WHERE id = v_order.id;

  RETURN jsonb_build_object('success', true, 'already_paid', false, 'order_id', v_order.id, 'payment_status', 'PAID');
END;
$$;
REVOKE ALL ON FUNCTION public.merchant_verify_order_payment(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.merchant_verify_order_payment(uuid) TO authenticated;
$bootstrap_sql_admin_order_payment_review_verify$;

  EXECUTE $bootstrap_sql_admin_order_payment_review_buyer_submit$
CREATE OR REPLACE FUNCTION public.buyer_submit_payment_proof(
  p_order_id uuid,
  p_payment_proof_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_next_payment_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR length(trim(COALESCE(p_payment_proof_url, ''))) < 1
     OR length(p_payment_proof_url) > 2000 THEN
    RAISE EXCEPTION 'Payment proof is invalid' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = '42501';
  END IF;
  IF v_order.payment_method <> 'TRANSFER'
     OR v_order.payment_status IN ('PAID', 'REFUNDED', 'EXPIRED')
     OR v_order.status IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED') THEN
    RAISE EXCEPTION 'Order is not accepting transfer proof' USING ERRCODE = '22023';
  END IF;

  v_next_payment_status := CASE WHEN v_order.payment_status = 'FAILED' THEN 'PENDING_TRANSFER' ELSE v_order.payment_status END;
  UPDATE public.orders
  SET payment_proof_url = trim(p_payment_proof_url), payment_status = v_next_payment_status, updated_at = now()
  WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', trim(p_payment_proof_url), 'payment_status', v_next_payment_status);
END;
$$;
REVOKE ALL ON FUNCTION public.buyer_submit_payment_proof(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_submit_payment_proof(uuid, text) TO authenticated;
$bootstrap_sql_admin_order_payment_review_buyer_submit$;

  EXECUTE $bootstrap_sql_admin_order_payment_review_guest_submit$
CREATE OR REPLACE FUNCTION public.guest_submit_payment_proof(p_order_id uuid, p_guest_access_token text, p_payment_proof_url text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_next_payment_status text;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex')
    AND guest_token_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501';
  END IF;
  IF v_order.payment_method <> 'TRANSFER'
     OR v_order.payment_status IN ('PAID', 'REFUNDED', 'EXPIRED')
     OR v_order.status IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED')
     OR length(trim(COALESCE(p_payment_proof_url, ''))) < 1
     OR length(p_payment_proof_url) > 2000 THEN
    RAISE EXCEPTION 'Order is not accepting transfer proof' USING ERRCODE = '22023';
  END IF;

  v_next_payment_status := CASE WHEN v_order.payment_status = 'FAILED' THEN 'PENDING_TRANSFER' ELSE v_order.payment_status END;
  UPDATE public.orders
  SET payment_proof_url = trim(p_payment_proof_url), payment_status = v_next_payment_status, updated_at = now()
  WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', trim(p_payment_proof_url), 'payment_status', v_next_payment_status);
END;
$$;
REVOKE ALL ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) TO anon;
$bootstrap_sql_admin_order_payment_review_guest_submit$;

  EXECUTE $bootstrap_sql_admin_order_payment_review_notify$
NOTIFY pgrst, 'reload schema';
$bootstrap_sql_admin_order_payment_review_notify$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_admin_order_payment_review$;
