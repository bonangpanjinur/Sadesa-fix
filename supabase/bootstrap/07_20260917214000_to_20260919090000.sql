-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 78_20260917214000_courier_earning_columns_compatibility.sql .. 91_20260919090000_merchant_ads_storage.sql

-- ===== BEGIN BUNDLE: 78_20260917214000_courier_earning_columns_compatibility.sql =====
-- Compatibility repair for projects where courier payout columns were not applied.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_earning_estimate integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee integer NOT NULL DEFAULT 0;

UPDATE public.orders
SET courier_earning_estimate = COALESCE(shipping_cost, 0),
    courier_platform_fee = 0
WHERE courier_earning_estimate = 0
  AND COALESCE(shipping_cost, 0) > 0;

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 78_20260917214000_courier_earning_columns_compatibility.sql =====

-- ===== BEGIN BUNDLE: 79_20260918020000_merchant_courier_dispatch_repair.sql =====
-- Repair merchant-originated courier dispatch. The previous frontend called
-- /api/assign-courier, but no such API exists in this application.
CREATE OR REPLACE FUNCTION public.dispatch_merchant_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_merchant_id uuid;
BEGIN
  SELECT m.id INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = auth.uid()
  LIMIT 1;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (public.is_admin() OR merchant_id = v_merchant_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;
  IF v_order.delivery_type <> 'INTERNAL' OR COALESCE(v_order.is_self_delivery, false) THEN
    RAISE EXCEPTION 'Order is not an internal courier order' USING ERRCODE = '22023';
  END IF;
  IF v_order.status NOT IN ('PROCESSED', 'READY', 'ASSIGNED') THEN
    RAISE EXCEPTION 'Order is not ready for courier assignment' USING ERRCODE = '22023';
  END IF;
  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RAISE EXCEPTION 'Merchant pickup location is required' USING ERRCODE = '22023';
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
    AND da.expires_at > now()
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'order_id', p_order_id,
      'assignment_id', v_assignment.id,
      'courier_id', v_assignment.courier_id,
      'dispatch_status', 'OFFERED'
    );
  END IF;

  SELECT c.* INTO v_courier
  FROM public.couriers c
  WHERE c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available = true
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}')))
  ORDER BY (
    6371 * 2 * asin(sqrt(
      power(sin(radians(c.current_lat - v_order.pickup_lat) / 2), 2)
      + cos(radians(v_order.pickup_lat)) * cos(radians(c.current_lat))
      * power(sin(radians(c.current_lng - v_order.pickup_lng) / 2), 2)
    ))
  ) ASC
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  INSERT INTO public.delivery_assignments(order_id, courier_id, created_by, offered_at, expires_at)
  VALUES (p_order_id, v_courier.id, auth.uid(), now(), now() + interval '5 minutes')
  RETURNING * INTO v_assignment;

  UPDATE public.orders
  SET status = 'ASSIGNED', courier_id = NULL, assigned_at = NULL,
      status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (p_order_id, v_order.status, 'ASSIGNED', auth.uid(),
    'Tawaran courier dibuat dari order toko',
    jsonb_build_object('courier_id', v_courier.id, 'assignment_id', v_assignment.id));

  PERFORM public.send_notification(
    v_courier.user_id,
    'Tawaran Pengiriman Baru',
    'Ada pesanan toko baru. Silakan pilih Terima atau Tolak.',
    'order',
    '/courier/deliveries'
  );

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'assignment_id', v_assignment.id,
    'courier_id', v_courier.id,
    'dispatch_status', 'OFFERED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_merchant_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_merchant_order(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 79_20260918020000_merchant_courier_dispatch_repair.sql =====

-- ===== BEGIN BUNDLE: 80_20260918152000_courier_active_delivery_feed_fix.sql =====
-- Include merchant-originated internal deliveries in the courier active feed.
-- The previous feed only allowed COURIER_DELIVERY, which hid marketplace orders
-- after a courier accepted them even though they were not completed yet.

CREATE OR REPLACE FUNCTION public.get_courier_active_deliveries()
RETURNS SETOF public.orders
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id uuid;
BEGIN
  SELECT c.id INTO v_courier_id
  FROM public.couriers c
  WHERE c.user_id = auth.uid()
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT o.*
  FROM public.orders o
  WHERE o.courier_id = v_courier_id
    -- Include direct courier and merchant marketplace deliveries, but never
    -- passenger ride records if legacy rows share the orders table.
    AND (o.service_type IN ('COURIER_DELIVERY', 'MARKETPLACE') OR o.service_type IS NULL)
    AND o.status IN ('COURIER_ACCEPTED', 'PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING')
  ORDER BY o.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_courier_active_deliveries() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_active_deliveries() TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 80_20260918152000_courier_active_delivery_feed_fix.sql =====

-- ===== BEGIN BUNDLE: 81_20260918152300_courier_internal_order_state_machine_fix.sql =====
-- Allow couriers to process merchant marketplace orders as well as direct
-- courier bookings. The active feed includes both kinds, so their state
-- transition RPCs must apply the same service-type rule.

CREATE OR REPLACE FUNCTION public.courier_pickup_order(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR (v_order.service_type NOT IN ('COURIER_DELIVERY', 'MARKETPLACE') AND v_order.service_type IS NOT NULL)
     OR v_order.courier_id <> v_courier_id
     OR v_order.status <> 'COURIER_ACCEPTED' THEN
    RAISE EXCEPTION 'Order is not ready for pickup' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders
  SET status = 'PICKED_UP', picked_up_at = now(), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, 'COURIER_ACCEPTED', 'PICKED_UP', auth.uid(), 'Kurir mengambil barang');

  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_start_delivery(p_order_id uuid)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_from_status text;
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR (v_order.service_type NOT IN ('COURIER_DELIVERY', 'MARKETPLACE') AND v_order.service_type IS NOT NULL)
     OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT') THEN
    RAISE EXCEPTION 'Order is not ready for delivery' USING ERRCODE = '22023';
  END IF;

  v_from_status := v_order.status;
  UPDATE public.orders
  SET status = 'DELIVERING', status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
  VALUES (p_order_id, v_from_status, 'DELIVERING', auth.uid(), 'Kurir memulai pengantaran');

  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.courier_complete_delivery(p_order_id uuid, p_proof_path text, p_notes text DEFAULT NULL)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier_id uuid;
  v_from_status text;
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid() AND status = 'ACTIVE' AND registration_status = 'APPROVED';

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Courier is not authorized' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(trim(p_proof_path), '') IS NULL THEN
    RAISE EXCEPTION 'Proof of delivery is required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR (v_order.service_type NOT IN ('COURIER_DELIVERY', 'MARKETPLACE') AND v_order.service_type IS NOT NULL)
     OR v_order.courier_id <> v_courier_id
     OR v_order.status NOT IN ('PICKED_UP', 'SENT', 'ON_DELIVERY', 'DELIVERING', 'DELIVERED') THEN
    RAISE EXCEPTION 'Order is not ready to complete' USING ERRCODE = '22023';
  END IF;

  -- A lost network response may cause the courier to retry after the first
  -- request already committed. Return the completed order instead of failing.
  IF v_order.status = 'DELIVERED' THEN
    IF v_order.delivery_proof_url IS NULL THEN
      UPDATE public.orders
      SET delivery_proof_url = p_proof_path,
          delivery_notes = COALESCE(NULLIF(trim(p_notes), ''), delivery_notes),
          updated_at = now()
      WHERE id = p_order_id
      RETURNING * INTO v_order;
    END IF;
    RETURN v_order;
  END IF;

  v_from_status := v_order.status;
  UPDATE public.orders
  SET status = 'DELIVERED', delivered_at = now(), delivery_proof_url = p_proof_path,
      delivery_notes = NULLIF(trim(p_notes), ''), status_updated_at = now(), updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason, metadata)
  VALUES (p_order_id, v_from_status, 'DELIVERED', auth.uid(), 'Kurir menyelesaikan pengiriman', jsonb_build_object('proof_path', p_proof_path));

  RETURN v_order;
END; $$;

REVOKE ALL ON FUNCTION public.courier_pickup_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_start_delivery(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.courier_complete_delivery(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.courier_pickup_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_start_delivery(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.courier_complete_delivery(uuid, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 81_20260918152300_courier_internal_order_state_machine_fix.sql =====

-- ===== BEGIN BUNDLE: 82_20260918170000_refund_dispute_state_guard.sql =====
-- Guard the refund dispute state machine.
-- Admin mediation updates must go through this RPC so terminal refund decisions
-- cannot be overwritten by a direct table update from the UI.

CREATE OR REPLACE FUNCTION public.update_refund_dispute_status(
  p_refund_id uuid,
  p_dispute_status text,
  p_admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_refund public.refund_requests%ROWTYPE;
  v_next_status text := upper(trim(COALESCE(p_dispute_status, '')));
  v_notes text := NULLIF(left(trim(COALESCE(p_admin_notes, '')), 2000), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF v_next_status NOT IN ('OPEN', 'IN_MEDIATION', 'CLOSED') THEN
    RAISE EXCEPTION 'Invalid dispute status transition' USING ERRCODE = '22023';
  END IF;
  IF v_next_status = 'CLOSED' AND v_notes IS NULL THEN
    RAISE EXCEPTION 'Closing a dispute requires admin notes' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_refund
  FROM public.refund_requests
  WHERE id = p_refund_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Refund request not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_next_status = 'CLOSED' AND v_refund.status = 'APPROVED'
     AND v_refund.settlement_status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'Refund dispute cannot be closed before settlement completes' USING ERRCODE = '55000';
  END IF;
  IF v_next_status = 'CLOSED'
     AND v_refund.status NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Only a decided refund dispute can be closed' USING ERRCODE = '55000';
  END IF;
  IF v_next_status <> 'CLOSED'
     AND (v_refund.status IN ('APPROVED', 'REJECTED')
       OR v_refund.dispute_status IN ('RESOLVED_REFUND', 'RESOLVED_REJECTED', 'CLOSED')) THEN
    RAISE EXCEPTION 'Resolved refund dispute cannot be reopened' USING ERRCODE = '55000';
  END IF;
  IF v_refund.dispute_status = 'CLOSED' AND v_next_status = 'CLOSED' THEN
    RETURN jsonb_build_object('id', v_refund.id, 'dispute_status', 'CLOSED');
  END IF;

  UPDATE public.refund_requests
  SET dispute_status = v_next_status,
      admin_notes = COALESCE(v_notes, admin_notes),
      updated_at = now()
  WHERE id = v_refund.id;

  RETURN jsonb_build_object('id', v_refund.id, 'dispute_status', v_next_status);
END;
$$;

REVOKE ALL ON FUNCTION public.update_refund_dispute_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_refund_dispute_status(uuid, text, text) TO authenticated;
-- ===== END BUNDLE: 82_20260918170000_refund_dispute_state_guard.sql =====

-- ===== BEGIN BUNDLE: 83_20260918190000_refund_notifications.sql =====
-- Refund notification coverage.
-- Every persisted refund lifecycle transition produces an in-app notification
-- for the parties that need to act or be informed.

CREATE OR REPLACE FUNCTION public.notify_refund_request_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_user_id uuid;
  v_order_link text := '/orders/' || COALESCE(NEW.order_id, OLD.order_id)::text || '/dispute';
  v_admin_link text := '/admin/disputes';
  v_merchant_link text := '/merchant/refunds';
  v_title text;
  v_message text;
  v_type text := 'refund';
BEGIN
  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = COALESCE(NEW.merchant_id, OLD.merchant_id);

  -- A new request needs action from the merchant and admin team.
  IF TG_OP = 'INSERT' THEN
    v_title := 'Pengajuan Refund Baru';
    v_message := 'Pembeli mengajukan refund untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '. Silakan tinjau pengajuan ini.';
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    INSERT INTO public.notifications (user_id, title, message, type, link)
    SELECT ur.user_id, v_title, v_message, v_type, v_admin_link
    FROM public.user_roles ur
    WHERE ur.role::text = 'admin';
    RETURN NEW;
  END IF;

  -- Merchant response is a distinct event and must reach the buyer and admins.
  IF OLD.merchant_response IS DISTINCT FROM NEW.merchant_response
     AND NEW.merchant_response IS NOT NULL THEN
    v_title := 'Respons Merchant atas Refund';
    v_message := 'Merchant telah memberikan respons untuk refund pesanan #' || LEFT(NEW.order_id::text, 8) || '. Silakan lihat detailnya.';
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    INSERT INTO public.notifications (user_id, title, message, type, link)
    SELECT ur.user_id, v_title, v_message, v_type, v_admin_link
    FROM public.user_roles ur
    WHERE ur.role::text = 'admin' AND ur.user_id <> NEW.buyer_id;
    RETURN NEW;
  END IF;

  -- A decision notification includes the initial settlement state so the buyer
  -- does not mistake approval for completed payout.
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.status = 'APPROVED' THEN
      v_title := 'Refund Disetujui';
      v_message := 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' disetujui dan sedang menunggu pencairan.';
    ELSIF NEW.status = 'REJECTED' THEN
      v_title := 'Refund Ditolak';
      v_message := 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' ditolak. Silakan buka detail untuk melihat catatan admin.';
    ELSE
      v_title := 'Status Refund Diperbarui';
      v_message := 'Status refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.status || '.';
    END IF;
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  -- Mediation and closure transitions are informative even when the refund
  -- decision itself has not changed.
  IF OLD.dispute_status IS DISTINCT FROM NEW.dispute_status THEN
    v_title := 'Status Penanganan Refund Diperbarui';
    v_message := 'Penanganan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.dispute_status || '.';
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  -- Settlement status can change independently through the provider callback.
  IF OLD.settlement_status IS DISTINCT FROM NEW.settlement_status THEN
    v_title := 'Status Pencairan Refund Diperbarui';
    v_message := CASE NEW.settlement_status
      WHEN 'PROCESSING' THEN 'Pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' sedang diproses.'
      WHEN 'COMPLETED' THEN 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berhasil dicairkan.'
      WHEN 'FAILED' THEN 'Pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' gagal dan perlu ditindaklanjuti.'
      ELSE 'Status pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || COALESCE(NEW.settlement_status, 'UNKNOWN') || '.'
    END;
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_request_notification_trigger ON public.refund_requests;
CREATE TRIGGER refund_request_notification_trigger
AFTER INSERT OR UPDATE OF status, dispute_status, merchant_response, settlement_status
ON public.refund_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_request_change();

CREATE OR REPLACE FUNCTION public.notify_refund_settlement_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_user_id uuid;
  v_title text;
  v_message text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = NEW.merchant_id;

  v_title := 'Status Pencairan Refund Diperbarui';
  v_message := CASE NEW.status
    WHEN 'PROCESSING' THEN 'Pencairan refund sedang diproses untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '.'
    WHEN 'COMPLETED' THEN 'Refund berhasil dicairkan untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '.'
    WHEN 'FAILED' THEN 'Pencairan refund gagal untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '; perlu ditindaklanjuti.'
    ELSE 'Status pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.status || '.'
  END;
  PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, 'refund', '/orders/' || NEW.order_id::text || '/dispute');
  IF v_merchant_user_id IS NOT NULL THEN
    PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, 'refund', '/merchant/refunds');
  END IF;
  INSERT INTO public.notifications (user_id, title, message, type, link)
  SELECT ur.user_id, v_title, v_message, 'refund', '/admin/disputes'
  FROM public.user_roles ur
  WHERE ur.role::text = 'admin' AND ur.user_id <> NEW.buyer_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_settlement_notification_trigger ON public.refund_settlements;
CREATE TRIGGER refund_settlement_notification_trigger
AFTER UPDATE OF status ON public.refund_settlements
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_settlement_change();

REVOKE ALL ON FUNCTION public.notify_refund_request_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_refund_settlement_change() FROM PUBLIC, anon, authenticated;
-- ===== END BUNDLE: 83_20260918190000_refund_notifications.sql =====

-- ===== BEGIN BUNDLE: 84_20260918200000_cashback_promo_program.sql =====
-- Cashback and promotion program hardening.
-- Adds merchant-owned cashback rules and an authoritative ledger lifecycle.

ALTER TABLE public.cashback_rules
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE;

ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'earn',
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cashback_balance numeric(14,2) NOT NULL DEFAULT 0;

ALTER TABLE public.cashback_transactions
  DROP CONSTRAINT IF EXISTS cashback_transactions_status_valid;
ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_status_valid
  CHECK (status IN ('pending', 'confirmed', 'cancelled', 'reversed', 'expired', 'redeemed'));
ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_type_valid
  CHECK (type IN ('earn', 'redeem', 'expire'));

CREATE INDEX IF NOT EXISTS cashback_rules_merchant_period_idx
  ON public.cashback_rules (merchant_id, is_active, valid_from, valid_until);

DROP POLICY IF EXISTS "Merchants manage own cashback rules" ON public.cashback_rules;
CREATE POLICY "Merchants manage own cashback rules"
  ON public.cashback_rules FOR ALL TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Merchants view own cashback rules" ON public.cashback_rules;
CREATE POLICY "Merchants view own cashback rules"
  ON public.cashback_rules FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.award_cashback_for_order(p_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_rule public.cashback_rules%ROWTYPE;
  v_amount numeric(14,2);
  v_awarded integer := 0;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status NOT IN ('DONE', 'DELIVERED') THEN
    RETURN 0;
  END IF;

  FOR v_rule IN
    SELECT r.*
    FROM public.cashback_rules r
    WHERE r.is_active
      AND r.valid_from <= now()
      AND (r.valid_until IS NULL OR r.valid_until >= now())
      AND (r.merchant_id IS NULL OR r.merchant_id = v_order.merchant_id)
      AND v_order.subtotal >= r.min_order_amount
      AND (r.category IS NULL OR EXISTS (
        SELECT 1
        FROM public.order_items oi
        JOIN public.products p ON p.id = oi.product_id
        WHERE oi.order_id = v_order.id AND lower(p.category) = lower(r.category)
      ))
    ORDER BY (r.merchant_id IS NOT NULL) DESC, r.cashback_percent DESC, r.created_at ASC
  LOOP
    v_amount := round((v_order.subtotal * v_rule.cashback_percent / 100)::numeric, 2);
    IF v_rule.max_cashback IS NOT NULL THEN
      v_amount := LEAST(v_amount, v_rule.max_cashback);
    END IF;
    IF v_amount <= 0 THEN CONTINUE; END IF;

    INSERT INTO public.cashback_transactions
      (user_id, order_id, rule_id, amount, type, status, expires_at)
    VALUES
      (v_order.buyer_id, v_order.id, v_rule.id, v_amount, 'earn', 'pending', now() + interval '90 days')
    ON CONFLICT (order_id, rule_id) WHERE order_id IS NOT NULL AND rule_id IS NOT NULL AND status <> 'reversed'
    DO NOTHING;

    IF FOUND THEN v_awarded := v_awarded + 1; END IF;
  END LOOP;
  RETURN v_awarded;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_due_cashback()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admin or service role may confirm cashback' USING ERRCODE = '42501';
  END IF;
  WITH confirmed AS (
    UPDATE public.cashback_transactions t
    SET status = 'confirmed', confirmed_at = now()
    WHERE t.type = 'earn' AND t.status = 'pending'
      AND t.created_at <= now() - interval '3 days'
      AND (t.expires_at IS NULL OR t.expires_at > now())
    RETURNING t.user_id, t.amount
  )
  UPDATE public.profiles p
  SET cashback_balance = p.cashback_balance + c.amount, updated_at = now()
  FROM (SELECT user_id, sum(amount) AS amount FROM confirmed GROUP BY user_id) c
  WHERE p.user_id = c.user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_order_done_award_cashback()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.award_cashback_for_order(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_cashback_award_trigger ON public.orders;
CREATE TRIGGER orders_cashback_award_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_done_award_cashback();

REVOKE ALL ON FUNCTION public.award_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.award_cashback_for_order(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.confirm_due_cashback() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_due_cashback() TO authenticated, service_role;
COMMENT ON FUNCTION public.award_cashback_for_order(uuid) IS 'Authoritative, idempotent cashback award invoked when an order is delivered or done.';
COMMENT ON FUNCTION public.confirm_due_cashback() IS 'Confirms cashback after the three-day dispute window and updates buyer balance.';
-- ===== END BUNDLE: 84_20260918200000_cashback_promo_program.sql =====

-- ===== BEGIN BUNDLE: 85_20260918201000_cashback_reversal_redemption.sql =====
-- Cashback redemption and refund reversal hardening.
-- The checkout integration should call redeem_cashback inside the same authoritative
-- checkout transaction once the checkout contract accepts a cashback amount.

ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS reversal_of uuid REFERENCES public.cashback_transactions(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS cashback_reversal_once_idx
  ON public.cashback_transactions (reversal_of)
  WHERE reversal_of IS NOT NULL;

CREATE OR REPLACE FUNCTION public.redeem_cashback(
  p_amount numeric,
  p_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_balance numeric(14,2);
  v_tx_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN
    RAISE EXCEPTION 'Redeem amount is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT cashback_balance INTO v_balance
  FROM public.profiles
  WHERE user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_balance, 0) < p_amount THEN
    RAISE EXCEPTION 'Insufficient cashback balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.cashback_transactions
    (user_id, amount, type, status, confirmed_at)
  VALUES
    (v_user_id, p_amount, 'redeem', 'confirmed', now())
  RETURNING id INTO v_tx_id;

  UPDATE public.profiles
  SET cashback_balance = cashback_balance - p_amount, updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('id', v_tx_id, 'amount', p_amount, 'reference', p_reference);
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_cashback_for_order(p_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.cashback_transactions%ROWTYPE;
  v_count integer := 0;
BEGIN
  FOR v_tx IN
    SELECT * FROM public.cashback_transactions
    WHERE order_id = p_order_id AND type = 'earn' AND status IN ('pending', 'confirmed')
    FOR UPDATE
  LOOP
    IF v_tx.status = 'pending' THEN
      UPDATE public.cashback_transactions
      SET status = 'cancelled'
      WHERE id = v_tx.id;
    ELSE
      INSERT INTO public.cashback_transactions
        (user_id, order_id, amount, type, status, confirmed_at, reversal_of)
      VALUES
        (v_tx.user_id, v_tx.order_id, v_tx.amount, 'expire', 'confirmed', now(), v_tx.id)
      ON CONFLICT (reversal_of) WHERE reversal_of IS NOT NULL DO NOTHING;

      IF FOUND THEN
        UPDATE public.profiles
        SET cashback_balance = GREATEST(0, cashback_balance - v_tx.amount), updated_at = now()
        WHERE user_id = v_tx.user_id;
      END IF;
      UPDATE public.cashback_transactions SET status = 'reversed' WHERE id = v_tx.id;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_order_refunded_reverse_cashback()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'REFUNDED' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.reverse_cashback_for_order(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_cashback_reversal_trigger ON public.orders;
CREATE TRIGGER orders_cashback_reversal_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_refunded_reverse_cashback();

REVOKE ALL ON FUNCTION public.redeem_cashback(numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_cashback(numeric, text) TO authenticated;
REVOKE ALL ON FUNCTION public.reverse_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_cashback_for_order(uuid) TO service_role;
COMMENT ON FUNCTION public.redeem_cashback(numeric, text) IS 'Atomically consumes confirmed buyer cashback; checkout should call this inside its transaction.';
COMMENT ON FUNCTION public.reverse_cashback_for_order(uuid) IS 'Creates an auditable reversal or cancels pending cashback when an order is refunded.';
-- ===== END BUNDLE: 85_20260918201000_cashback_reversal_redemption.sql =====

-- ===== BEGIN BUNDLE: 86_20260918220000_checkout_idempotency_and_payment_guard.sql =====
-- Checkout hardening: serialize retries by buyer/key and reject unsupported
-- multi-merchant payment methods before the authoritative order function runs.

CREATE TABLE IF NOT EXISTS public.marketplace_checkout_idempotency (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_key text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, checkout_key)
);

ALTER TABLE public.marketplace_checkout_idempotency ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_checkout_idempotency FROM PUBLIC, anon, authenticated;

-- Keep the legacy six-argument implementation private and unambiguous. The
-- seven-argument idempotent wrapper below has defaults, so leaving both names
-- active makes a six-argument call resolve ambiguously in PostgreSQL.
ALTER FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  RENAME TO create_marketplace_checkout_legacy;

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
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;

  -- This advisory transaction lock makes a timeout/retry wait for the first
  -- attempt, then return its committed result instead of creating duplicates.
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
  IF p_payment_method IN ('ONLINE', 'TRANSFER') AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Pembayaran online dan transfer hanya tersedia untuk checkout satu toko' USING ERRCODE = '22023';
  END IF;

  v_result := public.create_marketplace_checkout_legacy(
    p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
COMMENT ON TABLE public.marketplace_checkout_idempotency IS 'Authoritative checkout results keyed per buyer to make retries safe.';
-- ===== END BUNDLE: 86_20260918220000_checkout_idempotency_and_payment_guard.sql =====

-- ===== BEGIN BUNDLE: 87_20260918230000_checkout_p1_hardening.sql =====
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
-- ===== END BUNDLE: 87_20260918230000_checkout_p1_hardening.sql =====

-- ===== BEGIN BUNDLE: 88_20260918240000_secure_payment_proof_storage.sql =====
-- Secure marketplace transfer proofs.
-- Payment proof images contain financial and personal information and must not
-- be publicly readable or mutable by arbitrary authenticated users.

UPDATE storage.buckets
SET public = false
WHERE id = 'payment-proofs';

CREATE OR REPLACE FUNCTION public.can_access_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
BEGIN
  IF auth.uid() IS NULL OR split_part(p_object_name, '/', 1) <> 'orders' THEN
    RETURN false;
  END IF;

  BEGIN
    v_order_id := split_part(p_object_name, '/', 2)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;

  RETURN EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = v_order_id
      AND (
        o.buyer_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.merchants m
          WHERE m.id = o.merchant_id
            AND m.user_id = auth.uid()
        )
        OR public.is_admin()
      )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
BEGIN
  IF auth.uid() IS NULL OR split_part(p_object_name, '/', 1) <> 'orders' THEN
    RETURN false;
  END IF;

  BEGIN
    v_order_id := split_part(p_object_name, '/', 2)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;

  RETURN EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = v_order_id
      AND o.buyer_id = auth.uid()
      AND o.payment_method = 'TRANSFER'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_payment_proof(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_payment_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_payment_proof(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_payment_proof(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can update own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer or admin can delete payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Payment proof owner or merchant can read" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can upload payment proof for own transfer order" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can replace own payment proof" ON storage.objects;
DROP POLICY IF EXISTS "Buyer can delete own payment proof" ON storage.objects;

CREATE POLICY "Payment proof owner or merchant can read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_access_payment_proof(name)
);

CREATE POLICY "Buyer can upload payment proof for own transfer order"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

CREATE POLICY "Buyer can replace own payment proof"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

CREATE POLICY "Buyer can delete own payment proof"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
);

COMMENT ON FUNCTION public.can_access_payment_proof(text)
IS 'Allows only the buyer, owning merchant, or admin to read a marketplace payment proof object.';
COMMENT ON FUNCTION public.can_manage_payment_proof(text)
IS 'Allows only the buyer who owns a TRANSFER order to create, replace, or delete its proof object.';
-- ===== END BUNDLE: 88_20260918240000_secure_payment_proof_storage.sql =====

-- ===== BEGIN BUNDLE: 89_20260918235900_merchant_banner_ads.sql =====
-- Merchant paid advertising workflow
-- Merchants submit paid placements; admins approve them before public display.

CREATE TABLE IF NOT EXISTS public.ad_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  description TEXT,
  price_per_day NUMERIC(12, 0) NOT NULL CHECK (price_per_day > 0),
  max_days INTEGER NOT NULL DEFAULT 30 CHECK (max_days BETWEEN 1 AND 365),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.merchant_ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID REFERENCES public.ad_packages(id) ON DELETE SET NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  description TEXT,
  image_url TEXT,
  link_url TEXT,
  duration_days INTEGER NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'expired', 'rejected')),
  payment_amount NUMERIC(12, 0) NOT NULL CHECK (payment_amount >= 0),
  payment_proof_url TEXT,
  rejection_reason TEXT,
  view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  click_count INTEGER NOT NULL DEFAULT 0 CHECK (click_count >= 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT merchant_ads_dates_valid CHECK (end_date IS NULL OR start_date IS NULL OR end_date > start_date)
);

CREATE INDEX IF NOT EXISTS merchant_ads_public_banner_idx
  ON public.merchant_ads (placement_type, status, start_date, end_date, sort_order);
CREATE INDEX IF NOT EXISTS merchant_ads_merchant_idx
  ON public.merchant_ads (merchant_id, created_at DESC);

ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.ad_packages TO anon, authenticated;
GRANT SELECT ON public.merchant_ads TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.ad_packages TO authenticated;
GRANT INSERT, UPDATE ON public.merchant_ads TO authenticated;

DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages;
CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS "Admins manage ad packages" ON public.ad_packages;
CREATE POLICY "Admins manage ad packages" ON public.ad_packages
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active merchant ads" ON public.merchant_ads;
CREATE POLICY "Anyone can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    (status = 'active' AND start_date <= now() AND (end_date IS NULL OR end_date >= now()))
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Merchants submit own ads" ON public.merchant_ads;
CREATE POLICY "Merchants submit own ads" ON public.merchant_ads
  FOR INSERT WITH CHECK (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id
        AND m.user_id = auth.uid()
        AND m.registration_status = 'APPROVED'
    )
  );

DROP POLICY IF EXISTS "Merchants update own pending ads" ON public.merchant_ads;
CREATE POLICY "Merchants update own pending ads" ON public.merchant_ads
  FOR UPDATE USING (
    public.is_admin() OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
    )
  ) WITH CHECK (
    public.is_admin() OR (
      status = 'pending' AND EXISTS (
        SELECT 1 FROM public.merchants m
        WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
      )
    )
  );

DROP TRIGGER IF EXISTS update_ad_packages_updated_at ON public.ad_packages;
CREATE TRIGGER update_ad_packages_updated_at
  BEFORE UPDATE ON public.ad_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_merchant_ads_updated_at ON public.merchant_ads;
CREATE TRIGGER update_merchant_ads_updated_at
  BEFORE UPDATE ON public.merchant_ads
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days, is_active)
VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000, 30, true),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000, 30, true),
  ('Banner di Atas Menu', 'home_banner', 'Banner besar di atas menu layanan halaman utama', 50000, 14, true),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi rekomendasi produk', 10000, 30, true)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.merchant_ads IS 'Paid merchant advertising submissions, approved by admin before publication.';
COMMENT ON COLUMN public.merchant_ads.placement_type IS 'home_banner renders above the main service menu on the homepage.';

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 89_20260918235900_merchant_banner_ads.sql =====

-- ===== BEGIN BUNDLE: 90_20260919004500_merchant_ad_targeting.sql =====
-- Optional targeting metadata for merchant ad planning and reporting.
ALTER TABLE public.merchant_ads
  ADD COLUMN IF NOT EXISTS target_area TEXT,
  ADD COLUMN IF NOT EXISTS target_category TEXT,
  ADD COLUMN IF NOT EXISTS target_start_hour SMALLINT CHECK (target_start_hour IS NULL OR target_start_hour BETWEEN 0 AND 23),
  ADD COLUMN IF NOT EXISTS target_end_hour SMALLINT CHECK (target_end_hour IS NULL OR target_end_hour BETWEEN 0 AND 23);

COMMENT ON COLUMN public.merchant_ads.target_area IS 'Optional village, district, or service area requested by the merchant.';
COMMENT ON COLUMN public.merchant_ads.target_category IS 'Optional category targeting requested by the merchant.';
COMMENT ON COLUMN public.merchant_ads.target_start_hour IS 'Optional local hour window start for future delivery targeting.';
COMMENT ON COLUMN public.merchant_ads.target_end_hour IS 'Optional local hour window end for future delivery targeting.';

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 90_20260919004500_merchant_ad_targeting.sql =====

-- ===== BEGIN BUNDLE: 91_20260919005000_ad_performance_counters.sql =====
-- Public-safe counters for ad performance reporting.
CREATE OR REPLACE FUNCTION public.increment_merchant_ad_view(p_ad_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.merchant_ads
  SET view_count = view_count + 1
  WHERE id = p_ad_id
    AND status = 'active'
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());
$$;

CREATE OR REPLACE FUNCTION public.increment_merchant_ad_click(p_ad_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.merchant_ads
  SET click_count = click_count + 1
  WHERE id = p_ad_id
    AND status = 'active'
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());
$$;

CREATE OR REPLACE FUNCTION public.increment_promotion_view(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET view_count = view_count + 1 WHERE id = p_promotion_id;
$$;

CREATE OR REPLACE FUNCTION public.increment_promotion_click(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET click_count = click_count + 1 WHERE id = p_promotion_id;
$$;

GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_view(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_click(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_promotion_view(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_promotion_click(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 91_20260919005000_ad_performance_counters.sql =====

-- ===== BEGIN BUNDLE: 91_20260919090000_merchant_ads_storage.sql =====
-- Storage for merchant paid-ad creatives.
-- Kept separate from payment proofs so public campaign assets and private
-- financial evidence can be governed independently.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects;
CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads');

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 91_20260919090000_merchant_ads_storage.sql =====

