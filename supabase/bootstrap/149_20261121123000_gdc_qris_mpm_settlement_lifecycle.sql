-- Align GDC QRIS MPM settlement with the existing marketplace payment lifecycle.
-- Paid orders transition to PROCESSED; the current orders_status_check remains unchanged.
CREATE OR REPLACE FUNCTION public.settle_gdc_qris_mpm_payment(
  p_order_id uuid,
  p_partner_reference_no uuid,
  p_reference_no text,
  p_external_id uuid,
  p_currency text,
  p_paid_amount numeric,
  p_paid_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_reservation public.marketplace_stock_reservations%ROWTYPE;
  v_paid_at timestamptz := COALESCE(p_paid_at, now());
  v_updated integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC payment settlement requires service role' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_payment
  FROM public.gdc_qris_mpm_payments
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_payment.partner_reference_no IS DISTINCT FROM p_partner_reference_no
     OR (v_payment.reference_no IS NOT NULL AND v_payment.reference_no IS DISTINCT FROM p_reference_no)
     OR v_payment.provider_external_id IS DISTINCT FROM p_external_id
     OR p_currency <> 'IDR'
     OR v_payment.currency IS DISTINCT FROM p_currency
     OR v_payment.amount IS DISTINCT FROM p_paid_amount
     OR p_reference_no IS NULL
     OR length(trim(p_reference_no)) = 0 THEN
    RAISE EXCEPTION 'GDC payment identity or amount mismatch' USING ERRCODE = '23P01';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND OR v_order.payment_channel <> 'QRIS_MPM_GDC' OR v_order.payment_intent <> 'GDC_MPM' THEN
    RAISE EXCEPTION 'Order is not bound to GDC QR MPM' USING ERRCODE = '22023';
  END IF;

  IF v_order.total IS DISTINCT FROM p_paid_amount THEN
    RAISE EXCEPTION 'GDC payment does not match order total' USING ERRCODE = '23P01';
  END IF;

  IF v_payment.status = 'PAID' AND v_order.payment_status = 'PAID' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'PAID');
  END IF;

  IF v_payment.status = 'PAID' OR v_order.payment_status = 'PAID' THEN
    RAISE EXCEPTION 'GDC order and payment ledger state do not match' USING ERRCODE = '23P01';
  END IF;

  IF v_order.confirmation_deadline IS NULL
     OR v_paid_at > v_order.confirmation_deadline
     OR v_paid_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'GDC payment arrived outside the order payment window' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_reservation
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id AND status = 'active' AND expires_at > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Marketplace stock reservation is no longer active' USING ERRCODE = '22023';
  END IF;

  IF v_payment.status NOT IN ('PENDING', 'CREATING', 'UNKNOWN')
     OR v_order.payment_status NOT IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
     OR v_order.status NOT IN ('PENDING_PAYMENT', 'NEW') THEN
    RAISE EXCEPTION 'GDC payment is no longer eligible for settlement' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET payment_status = 'PAID',
      payment_paid_at = v_paid_at,
      status = CASE
        WHEN status IN ('PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'NEW') THEN 'PROCESSED'
        ELSE status
      END,
      updated_at = now()
  WHERE id = p_order_id;

  UPDATE public.gdc_qris_mpm_payments
  SET reference_no = COALESCE(reference_no, p_reference_no),
      status = 'PAID',
      paid_at = v_paid_at,
      provider_response_code = '00',
      updated_at = now()
  WHERE order_id = p_order_id AND status IN ('PENDING', 'CREATING', 'UNKNOWN');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RAISE EXCEPTION 'GDC payment status changed during settlement' USING ERRCODE = '40001';
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'PAID', 'order_id', p_order_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid, uuid, text, uuid, text, numeric, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid, uuid, text, uuid, text, numeric, timestamptz) TO service_role;

NOTIFY pgrst, 'reload schema';
