-- Manual payment verification must be an authorized, auditable business action.
-- It is intentionally separate from provider webhooks: merchant verification
-- requires ownership and an uploaded proof, while provider callbacks require
-- the provider secret and matching invoice.

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
$$$bootstrap_sql_20b1c5f31e70$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20b1c5f31e70$;

DO $bootstrap_do_8281f04815bf$
BEGIN
  EXECUTE $bootstrap_sql_8281f04815bf$REVOKE ALL ON FUNCTION public.merchant_verify_order_payment(uuid) FROM PUBLIC$bootstrap_sql_8281f04815bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8281f04815bf$;

DO $bootstrap_do_6c93622a9356$
BEGIN
  EXECUTE $bootstrap_sql_6c93622a9356$GRANT EXECUTE ON FUNCTION public.merchant_verify_order_payment(uuid) TO authenticated$bootstrap_sql_6c93622a9356$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c93622a9356$;

DO $bootstrap_do_e12ca8e87ff0$
BEGIN
  EXECUTE $bootstrap_sql_e12ca8e87ff0$
