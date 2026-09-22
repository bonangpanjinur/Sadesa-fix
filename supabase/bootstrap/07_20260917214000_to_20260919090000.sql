-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_8e6fb7689117$
BEGIN
  EXECUTE $bootstrap_sql_8e6fb7689117$-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 78_20260917214000_courier_earning_columns_compatibility.sql .. 91_20260919090000_merchant_ads_storage.sql

-- ===== BEGIN BUNDLE: 78_20260917214000_courier_earning_columns_compatibility.sql =====
-- Compatibility repair for projects where courier payout columns were not applied.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS courier_earning_estimate integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee integer NOT NULL DEFAULT 0$bootstrap_sql_8e6fb7689117$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e6fb7689117$;

DO $bootstrap_do_f67be06c3955$
BEGIN
  EXECUTE $bootstrap_sql_f67be06c3955$UPDATE public.orders
SET courier_earning_estimate = COALESCE(shipping_cost, 0),
    courier_platform_fee = 0
WHERE courier_earning_estimate = 0
  AND COALESCE(shipping_cost, 0) > 0$bootstrap_sql_f67be06c3955$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f67be06c3955$;

DO $bootstrap_do_2cf6c209b3ea$
BEGIN
  EXECUTE $bootstrap_sql_2cf6c209b3ea$NOTIFY pgrst, 'reload schema'$bootstrap_sql_2cf6c209b3ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2cf6c209b3ea$;

DO $bootstrap_do_6ca0348b57a0$
BEGIN
  EXECUTE $bootstrap_sql_6ca0348b57a0$-- ===== END BUNDLE: 78_20260917214000_courier_earning_columns_compatibility.sql =====

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
$$$bootstrap_sql_6ca0348b57a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ca0348b57a0$;

DO $bootstrap_do_33a62f332176$
BEGIN
  EXECUTE $bootstrap_sql_33a62f332176$REVOKE ALL ON FUNCTION public.dispatch_merchant_order(uuid) FROM PUBLIC, anon$bootstrap_sql_33a62f332176$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33a62f332176$;

DO $bootstrap_do_688276351580$
BEGIN
  EXECUTE $bootstrap_sql_688276351580$GRANT EXECUTE ON FUNCTION public.dispatch_merchant_order(uuid) TO authenticated$bootstrap_sql_688276351580$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_688276351580$;

DO $bootstrap_do_ce27d3ba194f$
BEGIN
  EXECUTE $bootstrap_sql_ce27d3ba194f$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ce27d3ba194f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce27d3ba194f$;

DO $bootstrap_do_5dc1efb25cad$
BEGIN
  EXECUTE $bootstrap_sql_5dc1efb25cad$-- ===== END BUNDLE: 79_20260918020000_merchant_courier_dispatch_repair.sql =====

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
$$$bootstrap_sql_5dc1efb25cad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5dc1efb25cad$;

DO $bootstrap_do_28620ef79dee$
BEGIN
  EXECUTE $bootstrap_sql_28620ef79dee$REVOKE ALL ON FUNCTION public.get_courier_active_deliveries() FROM PUBLIC, anon$bootstrap_sql_28620ef79dee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_28620ef79dee$;

DO $bootstrap_do_30ea8572fbbc$
BEGIN
  EXECUTE $bootstrap_sql_30ea8572fbbc$GRANT EXECUTE ON FUNCTION public.get_courier_active_deliveries() TO authenticated$bootstrap_sql_30ea8572fbbc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_30ea8572fbbc$;

DO $bootstrap_do_eb5c55fc82f1$
BEGIN
  EXECUTE $bootstrap_sql_eb5c55fc82f1$NOTIFY pgrst, 'reload schema'$bootstrap_sql_eb5c55fc82f1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb5c55fc82f1$;

DO $bootstrap_do_e46257bbacca$
BEGIN
  EXECUTE $bootstrap_sql_e46257bbacca$-- ===== END BUNDLE: 80_20260918152000_courier_active_delivery_feed_fix.sql =====

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
END; $$$bootstrap_sql_e46257bbacca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e46257bbacca$;

DO $bootstrap_do_07885cd8497e$
BEGIN
  EXECUTE $bootstrap_sql_07885cd8497e$CREATE OR REPLACE FUNCTION public.courier_start_delivery(p_order_id uuid)
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
END; $$$bootstrap_sql_07885cd8497e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07885cd8497e$;

DO $bootstrap_do_e8d60c34e611$
BEGIN
  EXECUTE $bootstrap_sql_e8d60c34e611$CREATE OR REPLACE FUNCTION public.courier_complete_delivery(p_order_id uuid, p_proof_path text, p_notes text DEFAULT NULL)
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
END; $$$bootstrap_sql_e8d60c34e611$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8d60c34e611$;

DO $bootstrap_do_b96dbe59b38e$
BEGIN
  EXECUTE $bootstrap_sql_b96dbe59b38e$REVOKE ALL ON FUNCTION public.courier_pickup_order(uuid) FROM PUBLIC, anon$bootstrap_sql_b96dbe59b38e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b96dbe59b38e$;

DO $bootstrap_do_a8ad1bb89cc4$
BEGIN
  EXECUTE $bootstrap_sql_a8ad1bb89cc4$REVOKE ALL ON FUNCTION public.courier_start_delivery(uuid) FROM PUBLIC, anon$bootstrap_sql_a8ad1bb89cc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a8ad1bb89cc4$;

DO $bootstrap_do_3a52c0061ff9$
BEGIN
  EXECUTE $bootstrap_sql_3a52c0061ff9$REVOKE ALL ON FUNCTION public.courier_complete_delivery(uuid, text, text) FROM PUBLIC, anon$bootstrap_sql_3a52c0061ff9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a52c0061ff9$;

DO $bootstrap_do_945381c23bcf$
BEGIN
  EXECUTE $bootstrap_sql_945381c23bcf$GRANT EXECUTE ON FUNCTION public.courier_pickup_order(uuid) TO authenticated$bootstrap_sql_945381c23bcf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_945381c23bcf$;

DO $bootstrap_do_90e56c9df929$
BEGIN
  EXECUTE $bootstrap_sql_90e56c9df929$GRANT EXECUTE ON FUNCTION public.courier_start_delivery(uuid) TO authenticated$bootstrap_sql_90e56c9df929$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90e56c9df929$;

DO $bootstrap_do_f51479b5dcd2$
BEGIN
  EXECUTE $bootstrap_sql_f51479b5dcd2$GRANT EXECUTE ON FUNCTION public.courier_complete_delivery(uuid, text, text) TO authenticated$bootstrap_sql_f51479b5dcd2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f51479b5dcd2$;

DO $bootstrap_do_06110510e322$
BEGIN
  EXECUTE $bootstrap_sql_06110510e322$NOTIFY pgrst, 'reload schema'$bootstrap_sql_06110510e322$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06110510e322$;

DO $bootstrap_do_3461934f47ef$
BEGIN
  EXECUTE $bootstrap_sql_3461934f47ef$-- ===== END BUNDLE: 81_20260918152300_courier_internal_order_state_machine_fix.sql =====

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
$$$bootstrap_sql_3461934f47ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3461934f47ef$;

DO $bootstrap_do_4aa1a301ebf9$
BEGIN
  EXECUTE $bootstrap_sql_4aa1a301ebf9$REVOKE ALL ON FUNCTION public.update_refund_dispute_status(uuid, text, text) FROM PUBLIC, anon$bootstrap_sql_4aa1a301ebf9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4aa1a301ebf9$;

DO $bootstrap_do_d5b7e1cdecca$
BEGIN
  EXECUTE $bootstrap_sql_d5b7e1cdecca$GRANT EXECUTE ON FUNCTION public.update_refund_dispute_status(uuid, text, text) TO authenticated$bootstrap_sql_d5b7e1cdecca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5b7e1cdecca$;

DO $bootstrap_do_553491ae67d0$
BEGIN
  EXECUTE $bootstrap_sql_553491ae67d0$-- ===== END BUNDLE: 82_20260918170000_refund_dispute_state_guard.sql =====

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
$$$bootstrap_sql_553491ae67d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_553491ae67d0$;

DO $bootstrap_do_e6d8836b4a8c$
BEGIN
  EXECUTE $bootstrap_sql_e6d8836b4a8c$DROP TRIGGER IF EXISTS refund_request_notification_trigger ON public.refund_requests$bootstrap_sql_e6d8836b4a8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6d8836b4a8c$;

DO $bootstrap_do_9ef8aae5dee7$
BEGIN
  EXECUTE $bootstrap_sql_9ef8aae5dee7$CREATE TRIGGER refund_request_notification_trigger
AFTER INSERT OR UPDATE OF status, dispute_status, merchant_response, settlement_status
ON public.refund_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_request_change()$bootstrap_sql_9ef8aae5dee7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ef8aae5dee7$;

DO $bootstrap_do_34b5fc10e5e6$
BEGIN
  EXECUTE $bootstrap_sql_34b5fc10e5e6$CREATE OR REPLACE FUNCTION public.notify_refund_settlement_change()
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
$$$bootstrap_sql_34b5fc10e5e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34b5fc10e5e6$;

DO $bootstrap_do_a6391a826cf9$
BEGIN
  EXECUTE $bootstrap_sql_a6391a826cf9$DROP TRIGGER IF EXISTS refund_settlement_notification_trigger ON public.refund_settlements$bootstrap_sql_a6391a826cf9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6391a826cf9$;

DO $bootstrap_do_60488b406ed5$
BEGIN
  EXECUTE $bootstrap_sql_60488b406ed5$CREATE TRIGGER refund_settlement_notification_trigger
AFTER UPDATE OF status ON public.refund_settlements
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_settlement_change()$bootstrap_sql_60488b406ed5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_60488b406ed5$;

DO $bootstrap_do_03b2a298cd08$
BEGIN
  EXECUTE $bootstrap_sql_03b2a298cd08$REVOKE ALL ON FUNCTION public.notify_refund_request_change() FROM PUBLIC, anon, authenticated$bootstrap_sql_03b2a298cd08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03b2a298cd08$;

DO $bootstrap_do_3788f62f3a35$
BEGIN
  EXECUTE $bootstrap_sql_3788f62f3a35$REVOKE ALL ON FUNCTION public.notify_refund_settlement_change() FROM PUBLIC, anon, authenticated$bootstrap_sql_3788f62f3a35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3788f62f3a35$;

DO $bootstrap_do_f157dbcc1292$
BEGIN
  EXECUTE $bootstrap_sql_f157dbcc1292$-- ===== END BUNDLE: 83_20260918190000_refund_notifications.sql =====

-- ===== BEGIN BUNDLE: 84_20260918200000_cashback_promo_program.sql =====
-- Cashback and promotion program hardening.
-- Adds merchant-owned cashback rules and an authoritative ledger lifecycle.

ALTER TABLE public.cashback_rules
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE$bootstrap_sql_f157dbcc1292$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f157dbcc1292$;

DO $bootstrap_do_f31b3fa7bbe7$
BEGIN
  EXECUTE $bootstrap_sql_f31b3fa7bbe7$ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'earn',
  ADD COLUMN IF NOT EXISTS expires_at timestamptz$bootstrap_sql_f31b3fa7bbe7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f31b3fa7bbe7$;

DO $bootstrap_do_f959089a70a2$
BEGIN
  EXECUTE $bootstrap_sql_f959089a70a2$ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cashback_balance numeric(14,2) NOT NULL DEFAULT 0$bootstrap_sql_f959089a70a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f959089a70a2$;

DO $bootstrap_do_9c19fb9fbcc8$
BEGIN
  EXECUTE $bootstrap_sql_9c19fb9fbcc8$ALTER TABLE public.cashback_transactions
  DROP CONSTRAINT IF EXISTS cashback_transactions_status_valid$bootstrap_sql_9c19fb9fbcc8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c19fb9fbcc8$;

DO $bootstrap_do_fd1282a8bfe0$
BEGIN
  EXECUTE $bootstrap_sql_fd1282a8bfe0$ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_status_valid
  CHECK (status IN ('pending', 'confirmed', 'cancelled', 'reversed', 'expired', 'redeemed'))$bootstrap_sql_fd1282a8bfe0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd1282a8bfe0$;

DO $bootstrap_do_b207c42db896$
BEGIN
  EXECUTE $bootstrap_sql_b207c42db896$ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_type_valid
  CHECK (type IN ('earn', 'redeem', 'expire'))$bootstrap_sql_b207c42db896$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b207c42db896$;

DO $bootstrap_do_20ff5f4d294c$
BEGIN
  EXECUTE $bootstrap_sql_20ff5f4d294c$CREATE INDEX IF NOT EXISTS cashback_rules_merchant_period_idx
  ON public.cashback_rules (merchant_id, is_active, valid_from, valid_until)$bootstrap_sql_20ff5f4d294c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20ff5f4d294c$;

DO $bootstrap_do_a593dd2cc9f0$
BEGIN
  EXECUTE $bootstrap_sql_a593dd2cc9f0$DROP POLICY IF EXISTS "Merchants manage own cashback rules" ON public.cashback_rules$bootstrap_sql_a593dd2cc9f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a593dd2cc9f0$;

DO $bootstrap_do_408d9ca0e60e$
BEGIN
  EXECUTE $bootstrap_sql_408d9ca0e60e$CREATE POLICY "Merchants manage own cashback rules"
  ON public.cashback_rules FOR ALL TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_408d9ca0e60e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_408d9ca0e60e$;

DO $bootstrap_do_06b782b8d4ce$
BEGIN
  EXECUTE $bootstrap_sql_06b782b8d4ce$DROP POLICY IF EXISTS "Merchants view own cashback rules" ON public.cashback_rules$bootstrap_sql_06b782b8d4ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06b782b8d4ce$;

DO $bootstrap_do_96f26825bc1e$
BEGIN
  EXECUTE $bootstrap_sql_96f26825bc1e$CREATE POLICY "Merchants view own cashback rules"
  ON public.cashback_rules FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_96f26825bc1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_96f26825bc1e$;

DO $bootstrap_do_ba754b7a26ca$
BEGIN
  EXECUTE $bootstrap_sql_ba754b7a26ca$CREATE OR REPLACE FUNCTION public.award_cashback_for_order(p_order_id uuid)
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
$$$bootstrap_sql_ba754b7a26ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba754b7a26ca$;

DO $bootstrap_do_6838f2222dba$
BEGIN
  EXECUTE $bootstrap_sql_6838f2222dba$CREATE OR REPLACE FUNCTION public.confirm_due_cashback()
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
$$$bootstrap_sql_6838f2222dba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6838f2222dba$;

DO $bootstrap_do_3fabaa046ef3$
BEGIN
  EXECUTE $bootstrap_sql_3fabaa046ef3$CREATE OR REPLACE FUNCTION public.on_order_done_award_cashback()
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
$$$bootstrap_sql_3fabaa046ef3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3fabaa046ef3$;

DO $bootstrap_do_66840018b20a$
BEGIN
  EXECUTE $bootstrap_sql_66840018b20a$DROP TRIGGER IF EXISTS orders_cashback_award_trigger ON public.orders$bootstrap_sql_66840018b20a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66840018b20a$;

DO $bootstrap_do_dfee74e2cb32$
BEGIN
  EXECUTE $bootstrap_sql_dfee74e2cb32$CREATE TRIGGER orders_cashback_award_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_done_award_cashback()$bootstrap_sql_dfee74e2cb32$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dfee74e2cb32$;

DO $bootstrap_do_e811bb6e3252$
BEGIN
  EXECUTE $bootstrap_sql_e811bb6e3252$REVOKE ALL ON FUNCTION public.award_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated$bootstrap_sql_e811bb6e3252$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e811bb6e3252$;

DO $bootstrap_do_22bc8d752d51$
BEGIN
  EXECUTE $bootstrap_sql_22bc8d752d51$GRANT EXECUTE ON FUNCTION public.award_cashback_for_order(uuid) TO service_role$bootstrap_sql_22bc8d752d51$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22bc8d752d51$;

DO $bootstrap_do_41e7986dc203$
BEGIN
  EXECUTE $bootstrap_sql_41e7986dc203$REVOKE ALL ON FUNCTION public.confirm_due_cashback() FROM PUBLIC, anon$bootstrap_sql_41e7986dc203$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41e7986dc203$;

DO $bootstrap_do_85d67d203349$
BEGIN
  EXECUTE $bootstrap_sql_85d67d203349$GRANT EXECUTE ON FUNCTION public.confirm_due_cashback() TO authenticated, service_role$bootstrap_sql_85d67d203349$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_85d67d203349$;

DO $bootstrap_do_a9b136159c8d$
BEGIN
  EXECUTE $bootstrap_sql_a9b136159c8d$COMMENT ON FUNCTION public.award_cashback_for_order(uuid) IS 'Authoritative, idempotent cashback award invoked when an order is delivered or done.'$bootstrap_sql_a9b136159c8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a9b136159c8d$;

DO $bootstrap_do_975a228859f3$
BEGIN
  EXECUTE $bootstrap_sql_975a228859f3$COMMENT ON FUNCTION public.confirm_due_cashback() IS 'Confirms cashback after the three-day dispute window and updates buyer balance.'$bootstrap_sql_975a228859f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_975a228859f3$;

DO $bootstrap_do_c95e2ac47351$
BEGIN
  EXECUTE $bootstrap_sql_c95e2ac47351$-- ===== END BUNDLE: 84_20260918200000_cashback_promo_program.sql =====

-- ===== BEGIN BUNDLE: 85_20260918201000_cashback_reversal_redemption.sql =====
-- Cashback redemption and refund reversal hardening.
-- The checkout integration should call redeem_cashback inside the same authoritative
-- checkout transaction once the checkout contract accepts a cashback amount.

ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS reversal_of uuid REFERENCES public.cashback_transactions(id) ON DELETE RESTRICT$bootstrap_sql_c95e2ac47351$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c95e2ac47351$;

DO $bootstrap_do_35f82148787d$
BEGIN
  EXECUTE $bootstrap_sql_35f82148787d$CREATE UNIQUE INDEX IF NOT EXISTS cashback_reversal_once_idx
  ON public.cashback_transactions (reversal_of)
  WHERE reversal_of IS NOT NULL$bootstrap_sql_35f82148787d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_35f82148787d$;

DO $bootstrap_do_d4af88befd54$
BEGIN
  EXECUTE $bootstrap_sql_d4af88befd54$CREATE OR REPLACE FUNCTION public.redeem_cashback(
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
$$$bootstrap_sql_d4af88befd54$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4af88befd54$;

DO $bootstrap_do_3579d43918fd$
BEGIN
  EXECUTE $bootstrap_sql_3579d43918fd$CREATE OR REPLACE FUNCTION public.reverse_cashback_for_order(p_order_id uuid)
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
$$$bootstrap_sql_3579d43918fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3579d43918fd$;

DO $bootstrap_do_3026d5ec1933$
BEGIN
  EXECUTE $bootstrap_sql_3026d5ec1933$CREATE OR REPLACE FUNCTION public.on_order_refunded_reverse_cashback()
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
$$$bootstrap_sql_3026d5ec1933$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3026d5ec1933$;

DO $bootstrap_do_0640a35f53ec$
BEGIN
  EXECUTE $bootstrap_sql_0640a35f53ec$DROP TRIGGER IF EXISTS orders_cashback_reversal_trigger ON public.orders$bootstrap_sql_0640a35f53ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0640a35f53ec$;

DO $bootstrap_do_1df203cef065$
BEGIN
  EXECUTE $bootstrap_sql_1df203cef065$CREATE TRIGGER orders_cashback_reversal_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_refunded_reverse_cashback()$bootstrap_sql_1df203cef065$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1df203cef065$;

DO $bootstrap_do_8e575dd081ad$
BEGIN
  EXECUTE $bootstrap_sql_8e575dd081ad$REVOKE ALL ON FUNCTION public.redeem_cashback(numeric, text) FROM PUBLIC, anon$bootstrap_sql_8e575dd081ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e575dd081ad$;

DO $bootstrap_do_44878c1384f2$
BEGIN
  EXECUTE $bootstrap_sql_44878c1384f2$GRANT EXECUTE ON FUNCTION public.redeem_cashback(numeric, text) TO authenticated$bootstrap_sql_44878c1384f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44878c1384f2$;

DO $bootstrap_do_9c53b9175a47$
BEGIN
  EXECUTE $bootstrap_sql_9c53b9175a47$REVOKE ALL ON FUNCTION public.reverse_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated$bootstrap_sql_9c53b9175a47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c53b9175a47$;

DO $bootstrap_do_f99c8832cd56$
BEGIN
  EXECUTE $bootstrap_sql_f99c8832cd56$GRANT EXECUTE ON FUNCTION public.reverse_cashback_for_order(uuid) TO service_role$bootstrap_sql_f99c8832cd56$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f99c8832cd56$;

DO $bootstrap_do_41d33557a89a$
BEGIN
  EXECUTE $bootstrap_sql_41d33557a89a$COMMENT ON FUNCTION public.redeem_cashback(numeric, text) IS 'Atomically consumes confirmed buyer cashback; checkout should call this inside its transaction.'$bootstrap_sql_41d33557a89a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41d33557a89a$;

DO $bootstrap_do_68d808b4e010$
BEGIN
  EXECUTE $bootstrap_sql_68d808b4e010$COMMENT ON FUNCTION public.reverse_cashback_for_order(uuid) IS 'Creates an auditable reversal or cancels pending cashback when an order is refunded.'$bootstrap_sql_68d808b4e010$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68d808b4e010$;

DO $bootstrap_do_3a82b15bae0e$
BEGIN
  EXECUTE $bootstrap_sql_3a82b15bae0e$-- ===== END BUNDLE: 85_20260918201000_cashback_reversal_redemption.sql =====

-- ===== BEGIN BUNDLE: 86_20260918220000_checkout_idempotency_and_payment_guard.sql =====
-- Checkout hardening: serialize retries by buyer/key and reject unsupported
-- multi-merchant payment methods before the authoritative order function runs.

CREATE TABLE IF NOT EXISTS public.marketplace_checkout_idempotency (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_key text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, checkout_key)
)$bootstrap_sql_3a82b15bae0e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a82b15bae0e$;

DO $bootstrap_do_739402397d7f$
BEGIN
  EXECUTE $bootstrap_sql_739402397d7f$ALTER TABLE public.marketplace_checkout_idempotency ENABLE ROW LEVEL SECURITY$bootstrap_sql_739402397d7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_739402397d7f$;

DO $bootstrap_do_96d0f5dab2af$
BEGIN
  EXECUTE $bootstrap_sql_96d0f5dab2af$REVOKE ALL ON public.marketplace_checkout_idempotency FROM PUBLIC, anon, authenticated$bootstrap_sql_96d0f5dab2af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_96d0f5dab2af$;

DO $bootstrap_do_6baa93717975$
BEGIN
  EXECUTE $bootstrap_sql_6baa93717975$-- Keep the legacy six-argument implementation private and unambiguous. The
-- seven-argument idempotent wrapper below has defaults, so leaving both names
-- active makes a six-argument call resolve ambiguously in PostgreSQL.
ALTER FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  RENAME TO create_marketplace_checkout_legacy$bootstrap_sql_6baa93717975$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6baa93717975$;

DO $bootstrap_do_5a1c999b44fe$
BEGIN
  EXECUTE $bootstrap_sql_5a1c999b44fe$CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
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
$$$bootstrap_sql_5a1c999b44fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a1c999b44fe$;

DO $bootstrap_do_765b2a7f3ef9$
BEGIN
  EXECUTE $bootstrap_sql_765b2a7f3ef9$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon$bootstrap_sql_765b2a7f3ef9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_765b2a7f3ef9$;

DO $bootstrap_do_1abea9a7313d$
BEGIN
  EXECUTE $bootstrap_sql_1abea9a7313d$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role$bootstrap_sql_1abea9a7313d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1abea9a7313d$;

DO $bootstrap_do_15e0bf1f9250$
BEGIN
  EXECUTE $bootstrap_sql_15e0bf1f9250$COMMENT ON TABLE public.marketplace_checkout_idempotency IS 'Authoritative checkout results keyed per buyer to make retries safe.'$bootstrap_sql_15e0bf1f9250$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15e0bf1f9250$;

DO $bootstrap_do_6f585aee9e2b$
BEGIN
  EXECUTE $bootstrap_sql_6f585aee9e2b$-- ===== END BUNDLE: 86_20260918220000_checkout_idempotency_and_payment_guard.sql =====

-- ===== BEGIN BUNDLE: 87_20260918230000_checkout_p1_hardening.sql =====
-- Checkout P1 hardening:
-- 1) close the legacy buyer-callable checkout overload;
-- 2) reject every multi-merchant checkout in the authoritative wrapper;
-- 3) consume stock when payment becomes PAID and never expire paid reservations;
-- 4) reject online checkout while the provider is disabled;
-- 5) provide a scoped buyer RPC for transfer proof updates.

REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  FROM PUBLIC, anon, authenticated$bootstrap_sql_6f585aee9e2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f585aee9e2b$;

DO $bootstrap_do_70844ae32875$
BEGIN
  EXECUTE $bootstrap_sql_70844ae32875$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
  TO service_role$bootstrap_sql_70844ae32875$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70844ae32875$;

DO $bootstrap_do_d58873a25f69$
BEGIN
  EXECUTE $bootstrap_sql_d58873a25f69$CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
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
$$$bootstrap_sql_d58873a25f69$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d58873a25f69$;

DO $bootstrap_do_b6935d6fcf84$
BEGIN
  EXECUTE $bootstrap_sql_b6935d6fcf84$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)
  FROM PUBLIC, anon$bootstrap_sql_b6935d6fcf84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6935d6fcf84$;

DO $bootstrap_do_70704b5bbcb8$
BEGIN
  EXECUTE $bootstrap_sql_70704b5bbcb8$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text)
  TO authenticated, service_role$bootstrap_sql_70704b5bbcb8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70704b5bbcb8$;

DO $bootstrap_do_4abcdf6ee753$
BEGIN
  EXECUTE $bootstrap_sql_4abcdf6ee753$-- Consume marketplace stock once when any trusted payment path marks an order PAID.
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
$$$bootstrap_sql_4abcdf6ee753$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4abcdf6ee753$;

DO $bootstrap_do_d7295e0ef3d5$
BEGIN
  EXECUTE $bootstrap_sql_d7295e0ef3d5$DROP TRIGGER IF EXISTS trg_consume_marketplace_stock_on_payment ON public.orders$bootstrap_sql_d7295e0ef3d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7295e0ef3d5$;

DO $bootstrap_do_6a0012d375b9$
BEGIN
  EXECUTE $bootstrap_sql_6a0012d375b9$CREATE TRIGGER trg_consume_marketplace_stock_on_payment
AFTER UPDATE OF payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.consume_marketplace_stock_on_payment()$bootstrap_sql_6a0012d375b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a0012d375b9$;

DO $bootstrap_do_b6160c2824c5$
BEGIN
  EXECUTE $bootstrap_sql_b6160c2824c5$-- Expiry workers may release only unpaid reservations. Paid stock was consumed
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
$$$bootstrap_sql_b6160c2824c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6160c2824c5$;

DO $bootstrap_do_677514c49c65$
BEGIN
  EXECUTE $bootstrap_sql_677514c49c65$REVOKE ALL ON FUNCTION public.expire_marketplace_stock_reservations(integer) FROM PUBLIC, anon, authenticated$bootstrap_sql_677514c49c65$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_677514c49c65$;

DO $bootstrap_do_78d8a9860f16$
BEGIN
  EXECUTE $bootstrap_sql_78d8a9860f16$GRANT EXECUTE ON FUNCTION public.expire_marketplace_stock_reservations(integer) TO service_role$bootstrap_sql_78d8a9860f16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78d8a9860f16$;

DO $bootstrap_do_6956d5f3b943$
BEGIN
  EXECUTE $bootstrap_sql_6956d5f3b943$-- Buyer-scoped transfer proof mutation. Direct UPDATE on orders remains revoked.
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
$$$bootstrap_sql_6956d5f3b943$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6956d5f3b943$;

DO $bootstrap_do_00d071b1189b$
BEGIN
  EXECUTE $bootstrap_sql_00d071b1189b$REVOKE ALL ON FUNCTION public.buyer_submit_payment_proof(uuid, text) FROM PUBLIC, anon$bootstrap_sql_00d071b1189b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00d071b1189b$;

DO $bootstrap_do_cc3c3b2e2473$
BEGIN
  EXECUTE $bootstrap_sql_cc3c3b2e2473$GRANT EXECUTE ON FUNCTION public.buyer_submit_payment_proof(uuid, text) TO authenticated$bootstrap_sql_cc3c3b2e2473$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc3c3b2e2473$;

DO $bootstrap_do_a0383a15c57a$
BEGIN
  EXECUTE $bootstrap_sql_a0383a15c57a$-- ===== END BUNDLE: 87_20260918230000_checkout_p1_hardening.sql =====

-- ===== BEGIN BUNDLE: 88_20260918240000_secure_payment_proof_storage.sql =====
-- Secure marketplace transfer proofs.
-- Payment proof images contain financial and personal information and must not
-- be publicly readable or mutable by arbitrary authenticated users.

UPDATE storage.buckets
SET public = false
WHERE id = 'payment-proofs'$bootstrap_sql_a0383a15c57a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0383a15c57a$;

DO $bootstrap_do_a7eef0fbbab5$
BEGIN
  EXECUTE $bootstrap_sql_a7eef0fbbab5$CREATE OR REPLACE FUNCTION public.can_access_payment_proof(p_object_name text)
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
$$$bootstrap_sql_a7eef0fbbab5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7eef0fbbab5$;

DO $bootstrap_do_50309c89c9f5$
BEGIN
  EXECUTE $bootstrap_sql_50309c89c9f5$CREATE OR REPLACE FUNCTION public.can_manage_payment_proof(p_object_name text)
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
$$$bootstrap_sql_50309c89c9f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50309c89c9f5$;

DO $bootstrap_do_47fef2856e03$
BEGIN
  EXECUTE $bootstrap_sql_47fef2856e03$REVOKE ALL ON FUNCTION public.can_access_payment_proof(text) FROM PUBLIC, anon$bootstrap_sql_47fef2856e03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47fef2856e03$;

DO $bootstrap_do_fa9260fe4f46$
BEGIN
  EXECUTE $bootstrap_sql_fa9260fe4f46$REVOKE ALL ON FUNCTION public.can_manage_payment_proof(text) FROM PUBLIC, anon$bootstrap_sql_fa9260fe4f46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa9260fe4f46$;

DO $bootstrap_do_fcca37c377f2$
BEGIN
  EXECUTE $bootstrap_sql_fcca37c377f2$GRANT EXECUTE ON FUNCTION public.can_access_payment_proof(text) TO authenticated, service_role$bootstrap_sql_fcca37c377f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fcca37c377f2$;

DO $bootstrap_do_f65b83e48c39$
BEGIN
  EXECUTE $bootstrap_sql_f65b83e48c39$GRANT EXECUTE ON FUNCTION public.can_manage_payment_proof(text) TO authenticated, service_role$bootstrap_sql_f65b83e48c39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f65b83e48c39$;

DO $bootstrap_do_1d60851150ad$
BEGIN
  EXECUTE $bootstrap_sql_1d60851150ad$DROP POLICY IF EXISTS "Payment proofs are publicly viewable" ON storage.objects$bootstrap_sql_1d60851150ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d60851150ad$;

DO $bootstrap_do_234d86e13474$
BEGIN
  EXECUTE $bootstrap_sql_234d86e13474$DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects$bootstrap_sql_234d86e13474$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_234d86e13474$;

DO $bootstrap_do_8da86bc8a698$
BEGIN
  EXECUTE $bootstrap_sql_8da86bc8a698$DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects$bootstrap_sql_8da86bc8a698$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8da86bc8a698$;

DO $bootstrap_do_6cda9de2d337$
BEGIN
  EXECUTE $bootstrap_sql_6cda9de2d337$DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects$bootstrap_sql_6cda9de2d337$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6cda9de2d337$;

DO $bootstrap_do_9c55972cb00b$
BEGIN
  EXECUTE $bootstrap_sql_9c55972cb00b$DROP POLICY IF EXISTS "Buyer/merchant/admin can view payment proofs" ON storage.objects$bootstrap_sql_9c55972cb00b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c55972cb00b$;

DO $bootstrap_do_6a21aacc5f5a$
BEGIN
  EXECUTE $bootstrap_sql_6a21aacc5f5a$DROP POLICY IF EXISTS "Buyer can update own payment proofs" ON storage.objects$bootstrap_sql_6a21aacc5f5a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a21aacc5f5a$;

DO $bootstrap_do_0d76f8e15eaf$
BEGIN
  EXECUTE $bootstrap_sql_0d76f8e15eaf$DROP POLICY IF EXISTS "Buyer or admin can delete payment proofs" ON storage.objects$bootstrap_sql_0d76f8e15eaf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d76f8e15eaf$;

DO $bootstrap_do_d14ea9ef83ea$
BEGIN
  EXECUTE $bootstrap_sql_d14ea9ef83ea$DROP POLICY IF EXISTS "Buyer merchant admin can upload payment proofs" ON storage.objects$bootstrap_sql_d14ea9ef83ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d14ea9ef83ea$;

DO $bootstrap_do_53bc8ef2ea74$
BEGIN
  EXECUTE $bootstrap_sql_53bc8ef2ea74$DROP POLICY IF EXISTS "Payment proof owner or merchant can read" ON storage.objects$bootstrap_sql_53bc8ef2ea74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_53bc8ef2ea74$;

DO $bootstrap_do_5ad04179453c$
BEGIN
  EXECUTE $bootstrap_sql_5ad04179453c$DROP POLICY IF EXISTS "Buyer can upload payment proof for own transfer order" ON storage.objects$bootstrap_sql_5ad04179453c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ad04179453c$;

DO $bootstrap_do_a5c4a0c5dec6$
BEGIN
  EXECUTE $bootstrap_sql_a5c4a0c5dec6$DROP POLICY IF EXISTS "Buyer can replace own payment proof" ON storage.objects$bootstrap_sql_a5c4a0c5dec6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5c4a0c5dec6$;

DO $bootstrap_do_77ca3426954b$
BEGIN
  EXECUTE $bootstrap_sql_77ca3426954b$DROP POLICY IF EXISTS "Buyer can delete own payment proof" ON storage.objects$bootstrap_sql_77ca3426954b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77ca3426954b$;

DO $bootstrap_do_c04749409637$
BEGIN
  EXECUTE $bootstrap_sql_c04749409637$CREATE POLICY "Payment proof owner or merchant can read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_access_payment_proof(name)
)$bootstrap_sql_c04749409637$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c04749409637$;

DO $bootstrap_do_c29b65c51aa6$
BEGIN
  EXECUTE $bootstrap_sql_c29b65c51aa6$CREATE POLICY "Buyer can upload payment proof for own transfer order"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)$bootstrap_sql_c29b65c51aa6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c29b65c51aa6$;

DO $bootstrap_do_4930bbf47ddc$
BEGIN
  EXECUTE $bootstrap_sql_4930bbf47ddc$CREATE POLICY "Buyer can replace own payment proof"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)$bootstrap_sql_4930bbf47ddc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4930bbf47ddc$;

DO $bootstrap_do_3e864355ad42$
BEGIN
  EXECUTE $bootstrap_sql_3e864355ad42$CREATE POLICY "Buyer can delete own payment proof"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND public.can_manage_payment_proof(name)
)$bootstrap_sql_3e864355ad42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e864355ad42$;

DO $bootstrap_do_e035e937f234$
BEGIN
  EXECUTE $bootstrap_sql_e035e937f234$COMMENT ON FUNCTION public.can_access_payment_proof(text)
IS 'Allows only the buyer, owning merchant, or admin to read a marketplace payment proof object.'$bootstrap_sql_e035e937f234$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e035e937f234$;

DO $bootstrap_do_8cddca97e01c$
BEGIN
  EXECUTE $bootstrap_sql_8cddca97e01c$COMMENT ON FUNCTION public.can_manage_payment_proof(text)
IS 'Allows only the buyer who owns a TRANSFER order to create, replace, or delete its proof object.'$bootstrap_sql_8cddca97e01c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cddca97e01c$;

DO $bootstrap_do_0c1d8119c77c$
BEGIN
  EXECUTE $bootstrap_sql_0c1d8119c77c$-- ===== END BUNDLE: 88_20260918240000_secure_payment_proof_storage.sql =====

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
)$bootstrap_sql_0c1d8119c77c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c1d8119c77c$;

DO $bootstrap_do_0526d53c9b9d$
BEGIN
  EXECUTE $bootstrap_sql_0526d53c9b9d$CREATE TABLE IF NOT EXISTS public.merchant_ads (
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
)$bootstrap_sql_0526d53c9b9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0526d53c9b9d$;

DO $bootstrap_do_18f3b6a8af97$
BEGIN
  EXECUTE $bootstrap_sql_18f3b6a8af97$CREATE INDEX IF NOT EXISTS merchant_ads_public_banner_idx
  ON public.merchant_ads (placement_type, status, start_date, end_date, sort_order)$bootstrap_sql_18f3b6a8af97$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18f3b6a8af97$;

DO $bootstrap_do_03d206a10310$
BEGIN
  EXECUTE $bootstrap_sql_03d206a10310$CREATE INDEX IF NOT EXISTS merchant_ads_merchant_idx
  ON public.merchant_ads (merchant_id, created_at DESC)$bootstrap_sql_03d206a10310$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03d206a10310$;

DO $bootstrap_do_7b968333b97d$
BEGIN
  EXECUTE $bootstrap_sql_7b968333b97d$ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_7b968333b97d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b968333b97d$;

DO $bootstrap_do_2662a8845e48$
BEGIN
  EXECUTE $bootstrap_sql_2662a8845e48$ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY$bootstrap_sql_2662a8845e48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2662a8845e48$;

DO $bootstrap_do_1947103a4735$
BEGIN
  EXECUTE $bootstrap_sql_1947103a4735$GRANT SELECT ON public.ad_packages TO anon, authenticated$bootstrap_sql_1947103a4735$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1947103a4735$;

DO $bootstrap_do_d67e8b1ef6c2$
BEGIN
  EXECUTE $bootstrap_sql_d67e8b1ef6c2$GRANT SELECT ON public.merchant_ads TO anon, authenticated$bootstrap_sql_d67e8b1ef6c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d67e8b1ef6c2$;

DO $bootstrap_do_a01b492ca410$
BEGIN
  EXECUTE $bootstrap_sql_a01b492ca410$GRANT INSERT, UPDATE, DELETE ON public.ad_packages TO authenticated$bootstrap_sql_a01b492ca410$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a01b492ca410$;

DO $bootstrap_do_12fb553fe5dc$
BEGIN
  EXECUTE $bootstrap_sql_12fb553fe5dc$GRANT INSERT, UPDATE ON public.merchant_ads TO authenticated$bootstrap_sql_12fb553fe5dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12fb553fe5dc$;

DO $bootstrap_do_e4511da5e92e$
BEGIN
  EXECUTE $bootstrap_sql_e4511da5e92e$DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages$bootstrap_sql_e4511da5e92e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4511da5e92e$;

DO $bootstrap_do_aed71e9cb75a$
BEGIN
  EXECUTE $bootstrap_sql_aed71e9cb75a$CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.is_admin())$bootstrap_sql_aed71e9cb75a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aed71e9cb75a$;

DO $bootstrap_do_0c9cedc2b6d6$
BEGIN
  EXECUTE $bootstrap_sql_0c9cedc2b6d6$DROP POLICY IF EXISTS "Admins manage ad packages" ON public.ad_packages$bootstrap_sql_0c9cedc2b6d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c9cedc2b6d6$;

DO $bootstrap_do_6f3944696241$
BEGIN
  EXECUTE $bootstrap_sql_6f3944696241$CREATE POLICY "Admins manage ad packages" ON public.ad_packages
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_6f3944696241$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f3944696241$;

DO $bootstrap_do_d6f09574dee9$
BEGIN
  EXECUTE $bootstrap_sql_d6f09574dee9$DROP POLICY IF EXISTS "Anyone can view active merchant ads" ON public.merchant_ads$bootstrap_sql_d6f09574dee9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6f09574dee9$;

DO $bootstrap_do_77a4fdb0b812$
BEGIN
  EXECUTE $bootstrap_sql_77a4fdb0b812$CREATE POLICY "Anyone can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    (status = 'active' AND start_date <= now() AND (end_date IS NULL OR end_date >= now()))
    OR public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id AND m.user_id = auth.uid()
    )
  )$bootstrap_sql_77a4fdb0b812$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77a4fdb0b812$;

DO $bootstrap_do_9ce25d9b7dad$
BEGIN
  EXECUTE $bootstrap_sql_9ce25d9b7dad$DROP POLICY IF EXISTS "Merchants submit own ads" ON public.merchant_ads$bootstrap_sql_9ce25d9b7dad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ce25d9b7dad$;

DO $bootstrap_do_5bd886c335f7$
BEGIN
  EXECUTE $bootstrap_sql_5bd886c335f7$CREATE POLICY "Merchants submit own ads" ON public.merchant_ads
  FOR INSERT WITH CHECK (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_ads.merchant_id
        AND m.user_id = auth.uid()
        AND m.registration_status = 'APPROVED'
    )
  )$bootstrap_sql_5bd886c335f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5bd886c335f7$;

DO $bootstrap_do_19ad8b11678f$
BEGIN
  EXECUTE $bootstrap_sql_19ad8b11678f$DROP POLICY IF EXISTS "Merchants update own pending ads" ON public.merchant_ads$bootstrap_sql_19ad8b11678f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19ad8b11678f$;

DO $bootstrap_do_141a3b83ab39$
BEGIN
  EXECUTE $bootstrap_sql_141a3b83ab39$CREATE POLICY "Merchants update own pending ads" ON public.merchant_ads
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
  )$bootstrap_sql_141a3b83ab39$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_141a3b83ab39$;

DO $bootstrap_do_703acf7fb619$
BEGIN
  EXECUTE $bootstrap_sql_703acf7fb619$DROP TRIGGER IF EXISTS update_ad_packages_updated_at ON public.ad_packages$bootstrap_sql_703acf7fb619$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_703acf7fb619$;

DO $bootstrap_do_080687aca929$
BEGIN
  EXECUTE $bootstrap_sql_080687aca929$CREATE TRIGGER update_ad_packages_updated_at
  BEFORE UPDATE ON public.ad_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_080687aca929$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_080687aca929$;

DO $bootstrap_do_3f04c7312c09$
BEGIN
  EXECUTE $bootstrap_sql_3f04c7312c09$DROP TRIGGER IF EXISTS update_merchant_ads_updated_at ON public.merchant_ads$bootstrap_sql_3f04c7312c09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f04c7312c09$;

DO $bootstrap_do_b910c5e15125$
BEGIN
  EXECUTE $bootstrap_sql_b910c5e15125$CREATE TRIGGER update_merchant_ads_updated_at
  BEFORE UPDATE ON public.merchant_ads
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_b910c5e15125$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b910c5e15125$;

DO $bootstrap_do_8759a039877d$
BEGIN
  EXECUTE $bootstrap_sql_8759a039877d$INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days, is_active)
VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000, 30, true),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000, 30, true),
  ('Banner di Atas Menu', 'home_banner', 'Banner besar di atas menu layanan halaman utama', 50000, 14, true),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi rekomendasi produk', 10000, 30, true)
ON CONFLICT DO NOTHING$bootstrap_sql_8759a039877d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8759a039877d$;

DO $bootstrap_do_d3678a0957ea$
BEGIN
  EXECUTE $bootstrap_sql_d3678a0957ea$COMMENT ON TABLE public.merchant_ads IS 'Paid merchant advertising submissions, approved by admin before publication.'$bootstrap_sql_d3678a0957ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3678a0957ea$;

DO $bootstrap_do_618208eea29d$
BEGIN
  EXECUTE $bootstrap_sql_618208eea29d$COMMENT ON COLUMN public.merchant_ads.placement_type IS 'home_banner renders above the main service menu on the homepage.'$bootstrap_sql_618208eea29d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_618208eea29d$;

DO $bootstrap_do_a4e16188b3a4$
BEGIN
  EXECUTE $bootstrap_sql_a4e16188b3a4$NOTIFY pgrst, 'reload schema'$bootstrap_sql_a4e16188b3a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4e16188b3a4$;

DO $bootstrap_do_78c8fab976ca$
BEGIN
  EXECUTE $bootstrap_sql_78c8fab976ca$-- ===== END BUNDLE: 89_20260918235900_merchant_banner_ads.sql =====

-- ===== BEGIN BUNDLE: 90_20260919004500_merchant_ad_targeting.sql =====
-- Optional targeting metadata for merchant ad planning and reporting.
ALTER TABLE public.merchant_ads
  ADD COLUMN IF NOT EXISTS target_area TEXT,
  ADD COLUMN IF NOT EXISTS target_category TEXT,
  ADD COLUMN IF NOT EXISTS target_start_hour SMALLINT CHECK (target_start_hour IS NULL OR target_start_hour BETWEEN 0 AND 23),
  ADD COLUMN IF NOT EXISTS target_end_hour SMALLINT CHECK (target_end_hour IS NULL OR target_end_hour BETWEEN 0 AND 23)$bootstrap_sql_78c8fab976ca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78c8fab976ca$;

DO $bootstrap_do_2b46a8b25aed$
BEGIN
  EXECUTE $bootstrap_sql_2b46a8b25aed$COMMENT ON COLUMN public.merchant_ads.target_area IS 'Optional village, district, or service area requested by the merchant.'$bootstrap_sql_2b46a8b25aed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b46a8b25aed$;

DO $bootstrap_do_5b070fba6dce$
BEGIN
  EXECUTE $bootstrap_sql_5b070fba6dce$COMMENT ON COLUMN public.merchant_ads.target_category IS 'Optional category targeting requested by the merchant.'$bootstrap_sql_5b070fba6dce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b070fba6dce$;

DO $bootstrap_do_05c14c5b7f83$
BEGIN
  EXECUTE $bootstrap_sql_05c14c5b7f83$COMMENT ON COLUMN public.merchant_ads.target_start_hour IS 'Optional local hour window start for future delivery targeting.'$bootstrap_sql_05c14c5b7f83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05c14c5b7f83$;

DO $bootstrap_do_13dc881d2ec5$
BEGIN
  EXECUTE $bootstrap_sql_13dc881d2ec5$COMMENT ON COLUMN public.merchant_ads.target_end_hour IS 'Optional local hour window end for future delivery targeting.'$bootstrap_sql_13dc881d2ec5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_13dc881d2ec5$;

DO $bootstrap_do_1538472d0c04$
BEGIN
  EXECUTE $bootstrap_sql_1538472d0c04$NOTIFY pgrst, 'reload schema'$bootstrap_sql_1538472d0c04$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1538472d0c04$;

DO $bootstrap_do_f6c61d4049cf$
BEGIN
  EXECUTE $bootstrap_sql_f6c61d4049cf$-- ===== END BUNDLE: 90_20260919004500_merchant_ad_targeting.sql =====

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
$$$bootstrap_sql_f6c61d4049cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f6c61d4049cf$;

DO $bootstrap_do_bf4c17d0c463$
BEGIN
  EXECUTE $bootstrap_sql_bf4c17d0c463$CREATE OR REPLACE FUNCTION public.increment_merchant_ad_click(p_ad_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.merchant_ads
  SET click_count = click_count + 1
  WHERE id = p_ad_id
    AND status = 'active'
    AND start_date <= now()
    AND (end_date IS NULL OR end_date >= now());
$$$bootstrap_sql_bf4c17d0c463$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf4c17d0c463$;

DO $bootstrap_do_71f68afc7072$
BEGIN
  EXECUTE $bootstrap_sql_71f68afc7072$CREATE OR REPLACE FUNCTION public.increment_promotion_view(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET view_count = view_count + 1 WHERE id = p_promotion_id;
$$$bootstrap_sql_71f68afc7072$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71f68afc7072$;

DO $bootstrap_do_539c5ee74981$
BEGIN
  EXECUTE $bootstrap_sql_539c5ee74981$CREATE OR REPLACE FUNCTION public.increment_promotion_click(p_promotion_id UUID)
RETURNS VOID LANGUAGE SQL SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.promotions SET click_count = click_count + 1 WHERE id = p_promotion_id;
$$$bootstrap_sql_539c5ee74981$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_539c5ee74981$;

DO $bootstrap_do_ea83296ae6f5$
BEGIN
  EXECUTE $bootstrap_sql_ea83296ae6f5$GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_view(UUID) TO anon, authenticated$bootstrap_sql_ea83296ae6f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea83296ae6f5$;

DO $bootstrap_do_2c1babe7db12$
BEGIN
  EXECUTE $bootstrap_sql_2c1babe7db12$GRANT EXECUTE ON FUNCTION public.increment_merchant_ad_click(UUID) TO anon, authenticated$bootstrap_sql_2c1babe7db12$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c1babe7db12$;

DO $bootstrap_do_a4a4446036bc$
BEGIN
  EXECUTE $bootstrap_sql_a4a4446036bc$GRANT EXECUTE ON FUNCTION public.increment_promotion_view(UUID) TO anon, authenticated$bootstrap_sql_a4a4446036bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4a4446036bc$;

DO $bootstrap_do_18d4c07f76ad$
BEGIN
  EXECUTE $bootstrap_sql_18d4c07f76ad$GRANT EXECUTE ON FUNCTION public.increment_promotion_click(UUID) TO anon, authenticated$bootstrap_sql_18d4c07f76ad$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18d4c07f76ad$;

DO $bootstrap_do_b16a6cba4ced$
BEGIN
  EXECUTE $bootstrap_sql_b16a6cba4ced$NOTIFY pgrst, 'reload schema'$bootstrap_sql_b16a6cba4ced$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b16a6cba4ced$;

DO $bootstrap_do_fc9e0f727e73$
BEGIN
  EXECUTE $bootstrap_sql_fc9e0f727e73$-- ===== END BUNDLE: 91_20260919005000_ad_performance_counters.sql =====

-- ===== BEGIN BUNDLE: 91_20260919090000_merchant_ads_storage.sql =====
-- Storage for merchant paid-ad creatives.
-- Kept separate from payment proofs so public campaign assets and private
-- financial evidence can be governed independently.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_fc9e0f727e73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc9e0f727e73$;

DO $bootstrap_do_93dd2cee10fb$
BEGIN
  EXECUTE $bootstrap_sql_93dd2cee10fb$DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects$bootstrap_sql_93dd2cee10fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93dd2cee10fb$;

DO $bootstrap_do_9f3418132581$
BEGIN
  EXECUTE $bootstrap_sql_9f3418132581$CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads')$bootstrap_sql_9f3418132581$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f3418132581$;

DO $bootstrap_do_64df672245b0$
BEGIN
  EXECUTE $bootstrap_sql_64df672245b0$DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects$bootstrap_sql_64df672245b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64df672245b0$;

DO $bootstrap_do_5950ce8d0c4b$
BEGIN
  EXECUTE $bootstrap_sql_5950ce8d0c4b$CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads')$bootstrap_sql_5950ce8d0c4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5950ce8d0c4b$;

DO $bootstrap_do_fcba27e59386$
BEGIN
  EXECUTE $bootstrap_sql_fcba27e59386$DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects$bootstrap_sql_fcba27e59386$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fcba27e59386$;

DO $bootstrap_do_2c165a66f584$
BEGIN
  EXECUTE $bootstrap_sql_2c165a66f584$CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_2c165a66f584$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c165a66f584$;

DO $bootstrap_do_865f5be5d75e$
BEGIN
  EXECUTE $bootstrap_sql_865f5be5d75e$DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects$bootstrap_sql_865f5be5d75e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_865f5be5d75e$;

DO $bootstrap_do_f24b9cba2ad9$
BEGIN
  EXECUTE $bootstrap_sql_f24b9cba2ad9$CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_f24b9cba2ad9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f24b9cba2ad9$;

DO $bootstrap_do_ec113170e76c$
BEGIN
  EXECUTE $bootstrap_sql_ec113170e76c$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ec113170e76c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec113170e76c$;

DO $bootstrap_do_11de1f42854a$
BEGIN
  EXECUTE $bootstrap_sql_11de1f42854a$-- ===== END BUNDLE: 91_20260919090000_merchant_ads_storage.sql =====$bootstrap_sql_11de1f42854a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11de1f42854a$;
