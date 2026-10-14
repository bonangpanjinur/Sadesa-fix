-- Payment/fare hardening based on the 2026-10-14 audit.
-- Forward-only manual canonical bootstrap bundle; do not apply to an existing
-- production database outside the authorized migration/deployment workflow.

-- P0: all authenticated order writes go through validated SECURITY DEFINER RPCs.
-- Existing permissive policies are intentionally removed (policies OR together).
DO $hardening_order_policies$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders'
      AND cmd IN ('INSERT', 'UPDATE')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.orders', p.policyname);
  END LOOP;
END;
$hardening_order_policies$;
REVOKE INSERT, UPDATE ON public.orders FROM PUBLIC, anon, authenticated;

-- Immutable at creation: courier fee basis and payment destination shown later.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_delivery_fee_snapshot integer,
  ADD COLUMN IF NOT EXISTS payment_destination_snapshot jsonb;

CREATE OR REPLACE FUNCTION public.snapshot_order_payment_and_delivery_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_admin jsonb;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.courier_delivery_fee_snapshot := GREATEST(
      COALESCE(NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost, 0), 0
    );
    -- Checkout transfer RPCs historically left this nullable; ensure newly
    -- created orders actually enter the enforced expiry lifecycle.
    IF NEW.payment_method = 'TRANSFER' AND NEW.confirmation_deadline IS NULL THEN
      NEW.confirmation_deadline := now() + interval '30 minutes';
    END IF;
    IF NEW.payment_method = 'TRANSFER' AND NEW.payment_destination_snapshot IS NULL THEN
      IF NEW.merchant_id IS NOT NULL THEN
        SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
      END IF;
      IF (NULLIF(btrim(COALESCE(v_merchant.bank_name, '')), '') IS NOT NULL
          AND NULLIF(btrim(COALESCE(v_merchant.bank_account_number, '')), '') IS NOT NULL)
         OR NULLIF(btrim(COALESCE(v_merchant.qris_image_url, '')), '') IS NOT NULL THEN
        NEW.payment_destination_snapshot := jsonb_build_object(
          'source', 'MERCHANT', 'merchant_name', v_merchant.name,
          'bank_name', v_merchant.bank_name,
          'bank_account_number', v_merchant.bank_account_number,
          'bank_account_name', v_merchant.bank_account_name,
          'qris_image_url', v_merchant.qris_image_url,
          'version', 1
        );
      ELSE
        SELECT value INTO v_admin FROM public.app_settings WHERE key = 'admin_payment_info';
        IF (NULLIF(btrim(COALESCE(v_admin->>'bank_name', '')), '') IS NOT NULL
            AND NULLIF(btrim(COALESCE(v_admin->>'bank_account_number', '')), '') IS NOT NULL)
           OR NULLIF(btrim(COALESCE(v_admin->>'qris_image_url', '')), '') IS NOT NULL THEN
          NEW.payment_destination_snapshot := jsonb_build_object(
            'source', 'ADMIN', 'merchant_name', v_merchant.name,
            'bank_name', v_admin->>'bank_name',
            'bank_account_number', v_admin->>'bank_account_number',
            'bank_account_name', v_admin->>'bank_account_name',
            'qris_image_url', v_admin->>'qris_image_url',
            'version', 1
          );
        END IF;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.shipping_cost IS DISTINCT FROM OLD.shipping_cost
     OR NEW.shipping_pricing_contract IS DISTINCT FROM OLD.shipping_pricing_contract
     OR NEW.payment_destination_snapshot IS DISTINCT FROM OLD.payment_destination_snapshot
     OR NEW.courier_delivery_fee_snapshot IS DISTINCT FROM OLD.courier_delivery_fee_snapshot THEN
    RAISE EXCEPTION 'Order pricing/payment destination snapshots are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.snapshot_order_payment_and_delivery_contract() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS orders_snapshot_payment_and_delivery_contract ON public.orders;
CREATE TRIGGER orders_snapshot_payment_and_delivery_contract
BEFORE INSERT OR UPDATE OF shipping_cost, shipping_pricing_contract, payment_destination_snapshot, courier_delivery_fee_snapshot
ON public.orders FOR EACH ROW
EXECUTE FUNCTION public.snapshot_order_payment_and_delivery_contract();

-- Existing pending transfers receive a finite, predictable grace window.
UPDATE public.orders
SET confirmation_deadline = now() + interval '30 minutes'
WHERE payment_method = 'TRANSFER'
  AND payment_status IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
  AND confirmation_deadline IS NULL
  AND status NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED');

-- Reject late proof attachment or a late approval even when invoked through an RPC.
CREATE OR REPLACE FUNCTION public.guard_marketplace_payment_deadline()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.payment_method = 'TRANSFER'
     AND (OLD.payment_status = 'EXPIRED'
          OR (OLD.confirmation_deadline IS NOT NULL
              AND OLD.confirmation_deadline <= clock_timestamp()))
     AND (NEW.payment_proof_url IS DISTINCT FROM OLD.payment_proof_url
          OR (NEW.payment_status IN ('PAID', 'FAILED', 'PENDING_TRANSFER', 'UNPAID')
              AND NEW.payment_status IS DISTINCT FROM OLD.payment_status)) THEN
    RAISE EXCEPTION 'Payment confirmation deadline has expired' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_marketplace_payment_deadline() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS orders_guard_marketplace_payment_deadline ON public.orders;
CREATE TRIGGER orders_guard_marketplace_payment_deadline
BEFORE UPDATE OF payment_proof_url, payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_marketplace_payment_deadline();

-- Atomically expire pending transfers, transition their lifecycle and release stock.
CREATE OR REPLACE FUNCTION public.expire_pending_marketplace_payments(p_limit integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order record;
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_count integer := 0;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Payment expiry worker access required' USING ERRCODE = '42501';
  END IF;
  FOR v_order IN
    SELECT id FROM public.orders
    WHERE payment_method = 'TRANSFER'
      AND payment_status IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
      AND confirmation_deadline IS NOT NULL
      AND confirmation_deadline <= clock_timestamp()
      AND status NOT IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED')
    ORDER BY confirmation_deadline, id
    FOR UPDATE SKIP LOCKED
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 1000))
  LOOP
    SELECT * INTO v_res FROM public.marketplace_stock_reservations
      WHERE order_id = v_order.id FOR UPDATE;
    IF FOUND AND v_res.status = 'active' THEN
      FOR v_item IN SELECT product_id, quantity
        FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id
      LOOP
        UPDATE public.products
        SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
        WHERE id = v_item.product_id;
      END LOOP;
      UPDATE public.marketplace_stock_reservations
      SET status = 'expired', released_at = now() WHERE id = v_res.id;
    END IF;
    UPDATE public.orders
    SET status = 'CANCELED', payment_status = 'EXPIRED',
        cancellation_reason = COALESCE(cancellation_reason, 'Batas pembayaran telah berakhir'),
        cancelled_at = COALESCE(cancelled_at, now()), updated_at = now()
    WHERE id = v_order.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_pending_marketplace_payments(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_pending_marketplace_payments(integer) TO service_role;

-- The existing scheduled reservation worker becomes the scheduled payment-expiry
-- entry point. Explicitly preserve non-payment reservation expiry for legacy jobs.
CREATE OR REPLACE FUNCTION public.expire_marketplace_stock_reservations(p_limit integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
  v_total integer;
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Reservation expiry worker access required' USING ERRCODE = '42501';
  END IF;
  v_count := public.expire_pending_marketplace_payments(p_limit);
  v_total := v_count;
  -- Continue expiring any legacy/non-transfer reservations through the same
  -- worker, without changing their order lifecycle.
  FOR v_res IN
    SELECT r.* FROM public.marketplace_stock_reservations r
    WHERE r.status = 'active' AND r.expires_at <= clock_timestamp()
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o WHERE o.id = r.order_id
          AND o.payment_method = 'TRANSFER'
          AND o.payment_status IN ('PENDING_TRANSFER', 'UNPAID', 'FAILED')
          AND o.confirmation_deadline <= clock_timestamp()
      )
    ORDER BY r.expires_at, r.id
    FOR UPDATE SKIP LOCKED
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 1000))
  LOOP
    FOR v_item IN SELECT product_id, quantity
      FROM public.marketplace_stock_reservation_items WHERE reservation_id = v_res.id
    LOOP
      UPDATE public.products
      SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
      WHERE id = v_item.product_id;
    END LOOP;
    UPDATE public.marketplace_stock_reservations
    SET status = 'expired', released_at = now() WHERE id = v_res.id;
    v_total := v_total + 1;
  END LOOP;
  RETURN v_total;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role;
SELECT cron.schedule(
  'expire-pending-marketplace-payments',
  '* * * * *',
  'SELECT public.expire_marketplace_stock_reservations(100)'
);

-- Avoid a second release attempt when the expiry worker has already released
-- the reservation inside the same transaction as the order transition.
CREATE OR REPLACE FUNCTION public.marketplace_reservation_order_status_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF lower(COALESCE(NEW.status, '')) IN ('cancelled', 'canceled', 'rejected', 'refunded')
     AND lower(COALESCE(OLD.status, '')) <> lower(COALESCE(NEW.status, ''))
     AND EXISTS (SELECT 1 FROM public.marketplace_stock_reservations
                 WHERE order_id = NEW.id AND status = 'active') THEN
    PERFORM public.release_marketplace_stock_reservation(NEW.id, 'released');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.marketplace_reservation_order_status_trigger() FROM PUBLIC, anon, authenticated;

-- Snapshot-only settlement basis; fail closed for legacy rows without a snapshot.
DO $commission_source$
DECLARE
  v_function text;
BEGIN
  SELECT pg_get_functiondef('public.apply_transaction_commission(text,uuid,text)'::regprocedure)
    INTO v_function;
  IF v_function IS NULL THEN RAISE EXCEPTION 'Commission function is missing'; END IF;
  v_function := replace(v_function,
    'COALESCE(o.courier_earning_estimate, o.shipping_cost, 0)::bigint',
    'o.courier_delivery_fee_snapshot::bigint');
  v_function := replace(v_function,
    $search$WHERE o.id = p_source_id AND o.courier_id IS NOT NULL$search$,
    $replace$WHERE o.id = p_source_id AND o.courier_id IS NOT NULL
      AND o.courier_delivery_fee_snapshot IS NOT NULL$replace$);
  IF v_function NOT LIKE '%courier_delivery_fee_snapshot::bigint%' THEN
    RAISE EXCEPTION 'Could not install immutable courier settlement basis';
  END IF;
  IF v_function NOT LIKE '%courier_delivery_fee_snapshot IS NOT NULL%' THEN
    RAISE EXCEPTION 'Could not enforce courier settlement snapshot validation';
  END IF;
  EXECUTE v_function;
END;
$commission_source$;

-- Payment destination context for guest orders now returns only checkout snapshot.
CREATE OR REPLACE FUNCTION public.get_guest_order_payment_context(p_order_id uuid, p_guest_access_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex')
    AND guest_token_expires_at > now();
  IF NOT FOUND OR v_order.payment_method <> 'TRANSFER' THEN
    RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'id', v_order.id, 'total', v_order.total, 'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status, 'merchant_id', v_order.merchant_id,
    'merchant_name', COALESCE(v_order.payment_destination_snapshot->>'merchant_name', 'Merchant'),
    'created_at', v_order.created_at, 'payment_proof_url', v_order.payment_proof_url,
    'confirmation_deadline', v_order.confirmation_deadline,
    'bank_name', v_order.payment_destination_snapshot->>'bank_name',
    'bank_account_number', v_order.payment_destination_snapshot->>'bank_account_number',
    'bank_account_name', v_order.payment_destination_snapshot->>'bank_account_name',
    'qris_image_url', v_order.payment_destination_snapshot->>'qris_image_url',
    'payment_destination_source', v_order.payment_destination_snapshot->>'source'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_guest_order_payment_context(uuid, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.get_guest_order_payment_context(uuid, text) TO anon;

-- Provider evidence is required and auditable for refund completion.
ALTER TABLE public.refund_settlements
  ADD COLUMN IF NOT EXISTS provider_status text,
  ADD COLUMN IF NOT EXISTS provider_amount integer;
CREATE UNIQUE INDEX IF NOT EXISTS refund_settlements_provider_reference_unique
  ON public.refund_settlements(btrim(provider_reference))
  WHERE provider_reference IS NOT NULL AND btrim(provider_reference) <> '';

CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text,
  p_provider_amount integer, p_provider_status text, p_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_balance numeric := 0;
  v_deducted numeric := 0;
  v_shortfall numeric := 0;
  v_commission_reversed bigint := 0;
  v_reference text := NULLIF(btrim(p_provider_reference), '');
  v_status text := upper(COALESCE(NULLIF(btrim(p_provider_status), ''), ''));
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Settlement worker access required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_settlement FROM public.refund_settlements WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Settlement not found' USING ERRCODE = 'P0002'; END IF;
  IF v_settlement.status = 'COMPLETED' THEN
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED', 'duplicate', true);
  END IF;
  IF v_settlement.status NOT IN ('PENDING', 'FAILED', 'PROCESSING') THEN
    RAISE EXCEPTION 'Refund settlement state does not allow provider result' USING ERRCODE = '55000';
  END IF;
  IF v_reference IS NOT NULL AND length(v_reference) > 200 THEN
    RAISE EXCEPTION 'Provider reference exceeds the supported length' USING ERRCODE = '22023';
  END IF;
  IF p_success IS TRUE THEN
    IF v_reference IS NULL OR length(v_reference) > 200 OR v_status <> 'SUCCEEDED'
       OR p_provider_amount IS NULL OR p_provider_amount <> v_settlement.amount THEN
      RAISE EXCEPTION 'Successful refund requires a unique provider reference, SUCCEEDED status, and exact amount' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.refund_settlements
               WHERE provider_reference = v_reference AND id <> p_settlement_id) THEN
      RAISE EXCEPTION 'Provider reference has already been used' USING ERRCODE = '23505';
    END IF;
  ELSIF v_status NOT IN ('FAILED', 'REJECTED') THEN
    RAISE EXCEPTION 'Failed refund requires a FAILED or REJECTED provider status' USING ERRCODE = '22023';
  END IF;
  IF NOT p_success THEN
    UPDATE public.refund_settlements
    SET status = 'FAILED', provider_reference = v_reference,
          provider_status = v_status, provider_amount = p_provider_amount,
          last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now()
      WHERE id = p_settlement_id;
    UPDATE public.refund_requests SET settlement_status = 'FAILED', updated_at = now()
      WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;
  SELECT COALESCE(m.available_balance, 0) INTO v_balance
    FROM public.merchants m WHERE m.id = v_settlement.merchant_id FOR UPDATE;
  v_deducted := LEAST(GREATEST(v_balance, 0), v_settlement.amount);
  v_shortfall := GREATEST(v_settlement.amount - v_deducted, 0);
  UPDATE public.refund_settlements
    SET status = 'COMPLETED', provider_reference = v_reference,
        provider_status = v_status, provider_amount = p_provider_amount,
        updated_at = now(), completed_at = now()
    WHERE id = p_settlement_id;
  UPDATE public.refund_requests SET settlement_status = 'COMPLETED', updated_at = now()
    WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now()
    WHERE id = v_settlement.order_id;
  UPDATE public.merchants SET available_balance = COALESCE(available_balance, 0) - v_deducted, updated_at = now()
    WHERE id = v_settlement.merchant_id;
  IF v_shortfall > 0 THEN
    INSERT INTO public.merchant_refund_shortfalls(
      settlement_id, merchant_id, order_id, refund_request_id, amount,
      deducted_amount, outstanding_amount, status
    ) VALUES (
      v_settlement.id, v_settlement.merchant_id, v_settlement.order_id,
      v_settlement.refund_request_id, v_settlement.amount, v_deducted, v_shortfall, 'OPEN'
    ) ON CONFLICT (settlement_id) DO NOTHING;
  END IF;
  v_commission_reversed := public.reverse_commission_for_refund(
    v_settlement.refund_request_id, v_settlement.order_id, v_settlement.amount
  );
  RETURN jsonb_build_object(
    'id', p_settlement_id, 'status', 'COMPLETED', 'provider_reference', v_reference,
    'provider_amount', p_provider_amount, 'provider_status', v_status,
    'deducted_amount', v_deducted, 'shortfall_amount', v_shortfall,
    'shortfall_status', CASE WHEN v_shortfall > 0 THEN 'OPEN' ELSE 'NONE' END,
    'commission_reversed_rupiah', v_commission_reversed
  );
END;
$$;
REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, integer, text, text) TO service_role;

NOTIFY pgrst, 'reload schema';
