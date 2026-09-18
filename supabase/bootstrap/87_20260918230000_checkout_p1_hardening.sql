-- Checkout P1 hardening:
-- 1) close the legacy buyer-callable checkout overload;
-- 2) reject every multi-merchant checkout in the authoritative wrapper;
-- 3) consume stock when payment becomes PAID and never expire paid reservations;
-- 4) reject online checkout while the provider is disabled;
-- 5) provide a scoped buyer RPC for transfer proof updates.

REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  TO service_role;

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing jsonb;
  v_result jsonb;
  v_merchant_count integer;
  v_online_enabled boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing
  FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS i(product_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count = 0 THEN
    RAISE EXCEPTION 'Cart is empty or contains invalid products' USING ERRCODE = '22023';
  END IF;
  IF v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Checkout hanya tersedia untuk satu toko dalam satu transaksi' USING ERRCODE = '22023';
  END IF;

  IF p_payment_method = 'ONLINE' THEN
    SELECT COALESCE((value->>'enabled')::boolean, false)
    INTO v_online_enabled
    FROM public.app_settings
    WHERE key = 'payment_xendit';
    IF COALESCE(v_online_enabled, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Pembayaran online sedang tidak tersedia' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_result := public.create_marketplace_checkout(
    p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)
  TO authenticated, service_role;

-- Consume marketplace stock once when any trusted payment path marks an order PAID.
CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_on_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation_status text;
BEGIN
  IF NEW.payment_status = 'PAID' AND OLD.payment_status IS DISTINCT FROM 'PAID' THEN
    SELECT status INTO v_reservation_status
    FROM public.marketplace_stock_reservations
    WHERE order_id = NEW.id
    FOR UPDATE;
    IF v_reservation_status IN ('expired', 'released') THEN
      RAISE EXCEPTION 'Payment cannot complete after stock reservation expiry' USING ERRCODE = '55000';
    END IF;
    PERFORM public.consume_marketplace_stock_reservation(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_consume_marketplace_stock_on_payment ON public.orders;
CREATE TRIGGER trg_consume_marketplace_stock_on_payment
AFTER UPDATE OF payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.consume_marketplace_stock_on_payment();

-- Expiry workers may release only unpaid reservations. Paid stock was consumed
-- by the trigger above and must never be released by the unpaid cleanup path.
CREATE OR REPLACE FUNCTION public.expire_marketplace_stock_reservations(p_limit integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
  v_count integer := 0;
BEGIN
  FOR v_order_id IN
    SELECT r.order_id
    FROM public.marketplace_stock_reservations r
    JOIN public.orders o ON o.id = r.order_id
    WHERE r.status = 'active'
      AND r.expires_at <= now()
      AND COALESCE(o.payment_status, '') <> 'PAID'
    ORDER BY r.expires_at
    FOR UPDATE OF r SKIP LOCKED
    LIMIT GREATEST(1, LEAST(p_limit, 1000))
  LOOP
    PERFORM public.release_marketplace_stock_reservation(v_order_id, 'expired');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role;

-- Buyer-scoped transfer proof mutation. Direct UPDATE on orders remains revoked.
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
  UPDATE public.orders
  SET payment_proof_url = trim(p_payment_proof_url), updated_at = now()
  WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', trim(p_payment_proof_url));
END;
$$;
REVOKE ALL ON FUNCTION public.buyer_submit_payment_proof(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_submit_payment_proof(uuid, text) TO authenticated;
