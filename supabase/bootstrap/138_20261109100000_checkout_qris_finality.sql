-- Single-merchant checkout and final QR MPM state transitions.
-- Forward-only migration; do not run against production from this task workspace.

CREATE OR REPLACE FUNCTION public.assign_order_payment_intent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_channel text := NULLIF(current_setting('sadesa.checkout_payment_channel', true), '');
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.payment_method = 'TRANSFER' THEN
      NEW.payment_channel := COALESCE(v_channel, 'ADMIN_MANUAL');
      IF NEW.payment_channel NOT IN ('ADMIN_MANUAL', 'QRIS_MPM_GDC') THEN
        RAISE EXCEPTION 'Payment channel transfer tidak valid' USING ERRCODE = '22023';
      END IF;
      NEW.payment_intent := CASE WHEN NEW.payment_channel = 'QRIS_MPM_GDC' THEN 'GDC_MPM' ELSE 'ADMIN_MANUAL' END;
    ELSE
      IF (v_channel IS NOT NULL AND v_channel IS DISTINCT FROM NEW.payment_method)
         OR (NEW.payment_channel IS NOT NULL AND NEW.payment_channel IS DISTINCT FROM NEW.payment_method) THEN
        RAISE EXCEPTION 'Payment channel tidak sesuai dengan metode pembayaran' USING ERRCODE = '22023';
      END IF;
      NEW.payment_intent := NEW.payment_method;
      NEW.payment_channel := NEW.payment_method;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.payment_channel IS DISTINCT FROM OLD.payment_channel
     OR NEW.payment_intent IS DISTINCT FROM OLD.payment_intent THEN
    RAISE EXCEPTION 'Payment intent/channel immutable setelah order dibuat' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.assign_order_payment_intent() FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.marketplace_checkout_request_fingerprints (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_key text NOT NULL,
  payload_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, checkout_key)
);
ALTER TABLE public.marketplace_checkout_request_fingerprints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_checkout_request_fingerprints FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.marketplace_guest_checkout_request_fingerprints (
  guest_session_key_hash text NOT NULL,
  checkout_key text NOT NULL,
  payload_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (guest_session_key_hash, checkout_key)
);
ALTER TABLE public.marketplace_guest_checkout_request_fingerprints ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_guest_checkout_request_fingerprints FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF to_regprocedure('public.create_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text)') IS NULL THEN
    ALTER FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text)
      RENAME TO create_marketplace_checkout_core;
  END IF;
END;
$$;

-- Preserve the current payment-intent binding while rejecting cross-merchant calls
-- and binding every authenticated idempotency key to its first exact payload.
CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid, p_distance_km numeric,
  p_checkout_key text, p_payment_channel text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_user_id uuid := auth.uid();
  v_merchant_count integer;
  v_fingerprint text;
  v_existing_fingerprint text;
  v_has_legacy_result boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated checkout is required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one checkout item is required' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(public.normalize_marketplace_checkout_items(p_items)) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya dapat berisi produk dari satu pedagang' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method = 'TRANSFER' THEN
    IF COALESCE(p_payment_channel, 'ADMIN_MANUAL') NOT IN ('ADMIN_MANUAL', 'QRIS_MPM_GDC') THEN
      RAISE EXCEPTION 'Payment channel transfer tidak valid' USING ERRCODE = '22023';
    END IF;
  ELSIF p_payment_channel IS NOT NULL AND p_payment_channel <> p_payment_method THEN
    RAISE EXCEPTION 'Payment channel tidak sesuai dengan metode pembayaran' USING ERRCODE = '22023';
  END IF;

  v_fingerprint := encode(digest(jsonb_build_object(
    'items', public.normalize_marketplace_checkout_items(p_items),
    'delivery', COALESCE(p_delivery, '{}'::jsonb),
    'delivery_type', p_delivery_type,
    'payment_method', p_payment_method,
    'payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END),
    'voucher_id', p_voucher_id,
    'distance_km', p_distance_km
  )::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':' || trim(p_checkout_key), 0));

  SELECT payload_fingerprint INTO v_existing_fingerprint
  FROM public.marketplace_checkout_request_fingerprints
  WHERE user_id = v_user_id AND checkout_key = trim(p_checkout_key)
  FOR UPDATE;
  IF v_existing_fingerprint IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.marketplace_checkout_idempotency
      WHERE user_id = v_user_id AND checkout_key = trim(p_checkout_key)
    ) INTO v_has_legacy_result;
    IF v_has_legacy_result THEN
      RAISE EXCEPTION 'Checkout key lama tidak dapat digunakan ulang; pulihkan pesanan yang sudah dibuat' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.marketplace_checkout_request_fingerprints(user_id, checkout_key, payload_fingerprint)
    VALUES (v_user_id, trim(p_checkout_key), v_fingerprint);
  ELSIF v_existing_fingerprint <> v_fingerprint THEN
    RAISE EXCEPTION 'Checkout key sudah terikat pada payload lain' USING ERRCODE = '23505';
  END IF;

  PERFORM set_config('sadesa.checkout_payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END), true);
  v_result := public.create_marketplace_checkout_core(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_checkout_key
  );
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.create_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_checkout_key, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text) TO authenticated, service_role;

-- The client supplies one 256-bit guest access token and retains it with the
-- checkout key. The database stores only its hash and restores that token on retry.
DO $$
BEGIN
  IF to_regprocedure('public.create_guest_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text,text)') IS NULL THEN
    ALTER FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text)
      RENAME TO create_guest_marketplace_checkout_core;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_guest_access_token text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL, p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_session_hash text;
  v_checkout_key text;
  v_fingerprint text;
  v_existing_fingerprint text;
  v_merchant_count integer;
  v_order_id uuid;
  v_order_ids jsonb;
  v_access_token text;
  v_has_legacy_result boolean;
  v_updated integer;
BEGIN
  IF p_guest_checkout_key IS NULL OR length(trim(p_guest_checkout_key)) < 16 OR length(trim(p_guest_checkout_key)) > 128
     OR p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128
     OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid guest checkout request' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method <> 'TRANSFER' OR COALESCE(p_payment_channel, 'ADMIN_MANUAL') <> 'ADMIN_MANUAL' THEN
    RAISE EXCEPTION 'Guest checkout hanya mendukung pembayaran manual Admin Sadesa' USING ERRCODE = '22023';
  END IF;
  IF p_voucher_id IS NOT NULL THEN
    RAISE EXCEPTION 'Account vouchers are not available for guest checkout' USING ERRCODE = '22023';
  END IF;
  IF p_guest_access_token IS NULL OR p_guest_access_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Guest access token tidak valid' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(public.normalize_marketplace_checkout_items(p_items)) AS i(product_id uuid, variant_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count <> 1 THEN
    RAISE EXCEPTION 'Checkout hanya dapat berisi produk dari satu pedagang' USING ERRCODE = '22023';
  END IF;

  v_session_hash := encode(digest(trim(p_guest_checkout_key), 'sha256'), 'hex');
  v_checkout_key := trim(p_checkout_key);
  v_fingerprint := encode(digest(jsonb_build_object(
    'items', public.normalize_marketplace_checkout_items(p_items),
    'delivery', COALESCE(p_delivery, '{}'::jsonb),
    'delivery_type', p_delivery_type,
    'payment_method', p_payment_method,
    'payment_channel', 'ADMIN_MANUAL',
    'voucher_id', p_voucher_id,
    'distance_km', p_distance_km
  )::text, 'sha256'), 'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_session_hash || ':' || v_checkout_key, 0));

  SELECT payload_fingerprint INTO v_existing_fingerprint
  FROM public.marketplace_guest_checkout_request_fingerprints
  WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_checkout_key
  FOR UPDATE;
  IF v_existing_fingerprint IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.marketplace_guest_checkout_idempotency
      WHERE guest_session_key_hash = v_session_hash AND checkout_key = v_checkout_key
    ) INTO v_has_legacy_result;
    IF v_has_legacy_result THEN
      RAISE EXCEPTION 'Checkout key lama tidak dapat digunakan ulang; pulihkan pesanan yang sudah dibuat' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.marketplace_guest_checkout_request_fingerprints(guest_session_key_hash, checkout_key, payload_fingerprint)
    VALUES (v_session_hash, v_checkout_key, v_fingerprint);
  ELSIF v_existing_fingerprint <> v_fingerprint THEN
    RAISE EXCEPTION 'Checkout key sudah terikat pada payload lain' USING ERRCODE = '23505';
  END IF;

  PERFORM set_config('sadesa.checkout_payment_channel', 'ADMIN_MANUAL', true);
  v_result := public.create_guest_marketplace_checkout_core(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    p_voucher_id, p_distance_km, p_guest_checkout_key, p_checkout_key
  );
  v_access_token := p_guest_access_token;
  IF v_access_token IS NULL OR v_access_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Guest access token tidak tersedia; pesanan perlu dipulihkan' USING ERRCODE = '22023';
  END IF;

  v_order_ids := COALESCE(v_result->'order_ids', jsonb_build_array(v_result->>'primary_order_id'));
  FOR v_order_id IN SELECT value::uuid FROM jsonb_array_elements_text(v_order_ids) AS id(value)
  LOOP
    UPDATE public.orders
    SET guest_access_token_hash = encode(digest(v_access_token, 'sha256'), 'hex')
    WHERE id = v_order_id AND buyer_id IS NULL;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated <> 1 THEN
      RAISE EXCEPTION 'Guest order access could not be bound to checkout attempt' USING ERRCODE = '42501';
    END IF;
  END LOOP;
  RETURN (v_result - 'guest_access_token') || jsonb_build_object('guest_access_token', v_access_token);
END;
$$;
-- Keep the old RPC signature usable during rollout, but route it through the
-- same fingerprinted function with a deterministic per-attempt access token.
CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL, p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_access_token text;
BEGIN
  IF p_guest_checkout_key IS NULL OR p_checkout_key IS NULL THEN
    RAISE EXCEPTION 'Guest checkout attempt key is required' USING ERRCODE = '22023';
  END IF;
  v_access_token := encode(digest(trim(p_guest_checkout_key) || ':' || trim(p_checkout_key), 'sha256'), 'hex');
  RETURN public.create_guest_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method,
    v_access_token, p_voucher_id, p_distance_km,
    p_guest_checkout_key, p_checkout_key, p_payment_channel
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,text,uuid,numeric,text,text,text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,text,uuid,numeric,text,text,text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout_core(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon, authenticated;

-- Payment callbacks must be bound to the provider's per-attempt external ID,
-- immutable merchant/order intent, exact amount and currency, and a live pending row.
DROP FUNCTION IF EXISTS public.settle_gdc_qris_mpm_payment(uuid,uuid,text,numeric,timestamptz);
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
SET search_path = public, pg_temp
AS $$
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
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no IS DISTINCT FROM p_partner_reference_no
     OR (v_payment.reference_no IS NOT NULL AND v_payment.reference_no IS DISTINCT FROM p_reference_no)
     OR v_payment.provider_external_id IS DISTINCT FROM p_external_id
     OR p_currency <> 'IDR'
     OR v_payment.currency IS DISTINCT FROM p_currency
     OR v_payment.amount IS DISTINCT FROM p_paid_amount
     OR p_reference_no IS NULL OR length(trim(p_reference_no)) = 0 THEN
    RAISE EXCEPTION 'GDC payment identity or amount mismatch' USING ERRCODE = '23P01';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
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
  SET payment_status = 'PAID', payment_paid_at = v_paid_at,
      status = CASE WHEN status = 'NEW' THEN status ELSE 'CONFIRMED' END,
      updated_at = now()
  WHERE id = p_order_id;
  UPDATE public.gdc_qris_mpm_payments
  SET reference_no = COALESCE(reference_no, p_reference_no), status = 'PAID', paid_at = v_paid_at,
      provider_response_code = '00', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('PENDING', 'CREATING', 'UNKNOWN');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN RAISE EXCEPTION 'GDC payment status changed during settlement' USING ERRCODE = '40001'; END IF;
  RETURN jsonb_build_object('success', true, 'status', 'PAID', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,uuid,text,numeric,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,uuid,text,numeric,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.record_gdc_qris_mpm_failure(
  p_order_id uuid,
  p_partner_reference_no uuid,
  p_reference_no text,
  p_external_id uuid,
  p_currency text,
  p_paid_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC failure recording requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no IS DISTINCT FROM p_partner_reference_no
     OR (v_payment.reference_no IS NOT NULL AND v_payment.reference_no IS DISTINCT FROM p_reference_no)
     OR v_payment.provider_external_id IS DISTINCT FROM p_external_id
     OR p_currency <> 'IDR'
     OR v_payment.currency IS DISTINCT FROM p_currency
     OR v_payment.amount IS DISTINCT FROM p_paid_amount THEN
    RAISE EXCEPTION 'GDC failure identity or amount mismatch' USING ERRCODE = '23P01';
  END IF;
  IF v_payment.status IN ('FAILED', 'EXPIRED') THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', v_payment.status);
  END IF;
  IF v_payment.status NOT IN ('PENDING', 'CREATING', 'UNKNOWN') THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', v_payment.status);
  END IF;
  UPDATE public.gdc_qris_mpm_payments
  SET reference_no = COALESCE(reference_no, p_reference_no), status = 'FAILED',
      provider_response_code = '06', last_error = 'Provider reported a failed QR transaction', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('PENDING', 'CREATING', 'UNKNOWN');
  RETURN jsonb_build_object('success', true, 'status', 'FAILED', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.record_gdc_qris_mpm_failure(uuid,uuid,text,uuid,text,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_gdc_qris_mpm_failure(uuid,uuid,text,uuid,text,numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.request_gdc_qris_mpm_manual_fallback(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.gdc_qris_mpm_payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_destination jsonb;
  v_has_admin_destination boolean;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'GDC manual fallback requires service role' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GDC payment record not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.payment_channel <> 'QRIS_MPM_GDC' OR v_order.payment_intent <> 'GDC_MPM' THEN
    RAISE EXCEPTION 'Order is not bound to GDC QR MPM' USING ERRCODE = '22023';
  END IF;
  IF v_payment.status NOT IN ('FAILED', 'EXPIRED', 'MANUAL_FALLBACK_PENDING') THEN
    RAISE EXCEPTION 'Manual fallback is allowed only after a final provider failure' USING ERRCODE = '22023';
  END IF;
  IF v_order.payment_status NOT IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
     OR v_order.status NOT IN ('PENDING_PAYMENT', 'NEW') THEN
    RAISE EXCEPTION 'Order is no longer eligible for manual fallback' USING ERRCODE = '22023';
  END IF;
  IF v_order.confirmation_deadline IS NULL OR v_order.confirmation_deadline <= now() THEN
    RAISE EXCEPTION 'Order payment deadline has passed' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id AND status = 'active' AND expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Marketplace stock reservation is no longer active' USING ERRCODE = '22023'; END IF;
  v_destination := COALESCE(v_order.payment_destination_snapshot, '{}'::jsonb);
  v_has_admin_destination := v_destination->>'fallback_source' = 'ADMIN'
    AND ((NULLIF(btrim(COALESCE(v_destination->>'bank_name', '')), '') IS NOT NULL
          AND NULLIF(btrim(COALESCE(v_destination->>'bank_account_number', '')), '') IS NOT NULL)
      OR NULLIF(btrim(COALESCE(v_destination->>'qris_image_url', '')), '') IS NOT NULL);
  IF NOT v_has_admin_destination THEN
    RAISE EXCEPTION 'Admin payment instructions were not snapshotted for this order' USING ERRCODE = '22023';
  END IF;
  IF v_payment.status = 'MANUAL_FALLBACK_PENDING' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'MANUAL_FALLBACK_PENDING');
  END IF;
  UPDATE public.gdc_qris_mpm_payments
  SET status = 'MANUAL_FALLBACK_PENDING', qr_content = NULL,
      last_error = 'Manual Admin fallback locked after provider final failure', updated_at = now()
  WHERE order_id = p_order_id AND status IN ('FAILED', 'EXPIRED');
  RETURN jsonb_build_object('success', true, 'status', 'MANUAL_FALLBACK_PENDING', 'order_id', p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.request_gdc_qris_mpm_manual_fallback(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_gdc_qris_mpm_manual_fallback(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
