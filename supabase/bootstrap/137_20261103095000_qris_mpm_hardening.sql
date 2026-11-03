-- QRIS MPM hardening: bind checkout intent to the order before any provider call.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_intent text;

UPDATE public.orders
SET payment_intent = CASE
  WHEN payment_method = 'TRANSFER' AND payment_channel = 'QRIS_MPM_GDC' THEN 'GDC_MPM'
  WHEN payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL'
  ELSE payment_method
END
WHERE payment_intent IS NULL;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_payment_intent_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_payment_intent_check
  CHECK (payment_intent IS NULL OR payment_intent IN ('ADMIN_MANUAL', 'GDC_MPM', 'ONLINE', 'COD'));

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
      NEW.payment_intent := NEW.payment_method;
      IF NEW.payment_channel IS NULL THEN NEW.payment_channel := NEW.payment_method; END IF;
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
DROP TRIGGER IF EXISTS assign_order_payment_intent_trigger ON public.orders;
CREATE TRIGGER assign_order_payment_intent_trigger
BEFORE INSERT OR UPDATE OF payment_channel, payment_intent ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.assign_order_payment_intent();

-- Existing checkout RPCs remain source-compatible; these overloads bind the selected intent
-- in the same transaction as the order INSERT. The trigger above rejects unbound/invalid channels.
CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL, p_payment_channel text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF p_payment_method = 'TRANSFER' AND COALESCE(p_payment_channel, 'ADMIN_MANUAL') NOT IN ('ADMIN_MANUAL','QRIS_MPM_GDC') THEN
    RAISE EXCEPTION 'Payment channel transfer tidak valid' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('sadesa.checkout_payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END), true);
  v_result := public.create_marketplace_checkout(p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km, p_checkout_key);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_guest_marketplace_checkout(
  p_items jsonb, p_delivery jsonb, p_delivery_type text, p_payment_method text,
  p_voucher_id uuid DEFAULT NULL, p_distance_km numeric DEFAULT NULL,
  p_guest_checkout_key text DEFAULT NULL, p_checkout_key text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_result jsonb;
BEGIN
  IF p_payment_method = 'TRANSFER' AND COALESCE(p_payment_channel, 'ADMIN_MANUAL') <> 'ADMIN_MANUAL' THEN
    RAISE EXCEPTION 'Guest checkout hanya mendukung pembayaran manual Admin Sadesa' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('sadesa.checkout_payment_channel', COALESCE(p_payment_channel, CASE WHEN p_payment_method = 'TRANSFER' THEN 'ADMIN_MANUAL' ELSE p_payment_method END), true);
  v_result := public.create_guest_marketplace_checkout(p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km, p_guest_checkout_key, p_checkout_key);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_guest_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric,text,text,text) TO anon, authenticated, service_role;

-- Prefer GDC only for an explicit GDC intent; manual orders always snapshot Admin.
CREATE OR REPLACE FUNCTION public.snapshot_order_payment_and_delivery_contract()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_merchant public.merchants%ROWTYPE; v_admin jsonb; v_admin_ready boolean := false; v_mpm_ready boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.courier_delivery_fee_snapshot := GREATEST(COALESCE(NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost, 0), 0);
    IF NEW.payment_method = 'TRANSFER' AND NEW.confirmation_deadline IS NULL THEN NEW.confirmation_deadline := now() + interval '30 minutes'; END IF;
    IF NEW.payment_method = 'TRANSFER' AND NEW.payment_destination_snapshot IS NULL THEN
      IF NEW.merchant_id IS NOT NULL THEN SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id; END IF;
      SELECT value INTO v_admin FROM public.app_settings WHERE key = 'admin_payment_info';
      v_admin_ready := (NULLIF(btrim(COALESCE(v_admin->>'bank_name','')), '') IS NOT NULL AND NULLIF(btrim(COALESCE(v_admin->>'bank_account_number','')), '') IS NOT NULL) OR NULLIF(btrim(COALESCE(v_admin->>'qris_image_url','')), '') IS NOT NULL;
      IF NEW.payment_channel = 'QRIS_MPM_GDC' THEN
        SELECT (NULLIF(btrim(COALESCE(a.gdc_merchant_id,'')), '') IS NOT NULL AND NULLIF(btrim(COALESCE(a.gdc_account_number,'')), '') IS NOT NULL) INTO v_mpm_ready
        FROM public.qris_applications a WHERE a.merchant_id = NEW.merchant_id AND a.status = 'ACTIVE' ORDER BY a.activated_at DESC LIMIT 1;
        IF NOT COALESCE(v_mpm_ready, false) AND NOT v_admin_ready THEN RAISE EXCEPTION 'QRIS MPM merchant dan fallback Admin belum tersedia' USING ERRCODE = '22023'; END IF;
        NEW.payment_destination_snapshot := jsonb_build_object('source','GDC_MPM','merchant_name',v_merchant.name,'fallback_source',CASE WHEN v_admin_ready THEN 'ADMIN' ELSE NULL END,'bank_name',CASE WHEN v_admin_ready THEN v_admin->>'bank_name' ELSE NULL END,'bank_account_number',CASE WHEN v_admin_ready THEN v_admin->>'bank_account_number' ELSE NULL END,'bank_account_name',CASE WHEN v_admin_ready THEN v_admin->>'bank_account_name' ELSE NULL END,'qris_image_url',CASE WHEN v_admin_ready THEN v_admin->>'qris_image_url' ELSE NULL END,'version',4);
      ELSIF v_admin_ready THEN
        NEW.payment_destination_snapshot := jsonb_build_object('source','ADMIN','merchant_name',v_merchant.name,'bank_name',v_admin->>'bank_name','bank_account_number',v_admin->>'bank_account_number','bank_account_name',v_admin->>'bank_account_name','qris_image_url',v_admin->>'qris_image_url','version',4);
      ELSE
        RAISE EXCEPTION 'QR atau rekening Admin Sadesa belum dikonfigurasi' USING ERRCODE = '22023';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.shipping_cost IS DISTINCT FROM OLD.shipping_cost OR NEW.shipping_pricing_contract IS DISTINCT FROM OLD.shipping_pricing_contract OR NEW.payment_destination_snapshot IS DISTINCT FROM OLD.payment_destination_snapshot OR NEW.courier_delivery_fee_snapshot IS DISTINCT FROM OLD.courier_delivery_fee_snapshot THEN
    RAISE EXCEPTION 'Order pricing/payment destination snapshots are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

ALTER TABLE public.gdc_qris_mpm_payments ADD COLUMN IF NOT EXISTS creating_started_at timestamptz, ADD COLUMN IF NOT EXISTS attempt_number integer NOT NULL DEFAULT 1, ADD COLUMN IF NOT EXISTS last_error text, ADD COLUMN IF NOT EXISTS provider_external_id uuid;
ALTER TABLE public.gdc_qris_mpm_payments DROP CONSTRAINT IF EXISTS gdc_qris_mpm_payments_status_check;
ALTER TABLE public.gdc_qris_mpm_payments ADD CONSTRAINT gdc_qris_mpm_payments_status_check CHECK (status IN ('CREATING','PENDING','PAID','FAILED','UNKNOWN','EXPIRED','MANUAL_FALLBACK_PENDING'));
UPDATE public.gdc_qris_mpm_payments SET provider_external_id = external_id WHERE provider_external_id IS NULL;

-- Settlement must not rewrite a fulfillment lifecycle that has already advanced.
CREATE OR REPLACE FUNCTION public.settle_gdc_qris_mpm_payment(p_order_id uuid,p_partner_reference_no uuid,p_reference_no text,p_paid_amount numeric,p_paid_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_payment public.gdc_qris_mpm_payments%ROWTYPE; v_order public.orders%ROWTYPE;
BEGIN
  IF COALESCE(auth.role(),'') <> 'service_role' AND session_user NOT IN ('postgres','supabase_admin') THEN RAISE EXCEPTION 'GDC payment settlement requires service role' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_payment FROM public.gdc_qris_mpm_payments WHERE order_id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_payment.partner_reference_no<>p_partner_reference_no OR v_payment.reference_no<>p_reference_no OR v_payment.amount<>p_paid_amount THEN RAISE EXCEPTION 'GDC payment reference or amount mismatch' USING ERRCODE='23P01'; END IF;
  SELECT * INTO v_order FROM public.orders WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.payment_channel <> 'QRIS_MPM_GDC' OR v_order.payment_intent <> 'GDC_MPM' THEN RAISE EXCEPTION 'Order is not bound to GDC QR MPM' USING ERRCODE='22023'; END IF;
  IF v_payment.status='PAID' OR v_order.payment_status='PAID' THEN RETURN jsonb_build_object('success',true,'duplicate',true,'status','PAID'); END IF;
  IF v_order.payment_status NOT IN ('PENDING_TRANSFER','UNPAID','FAILED') OR v_order.status NOT IN ('PENDING_PAYMENT','NEW') THEN RAISE EXCEPTION 'Order is not eligible for GDC payment settlement' USING ERRCODE='22023'; END IF;
  UPDATE public.orders SET payment_status='PAID', payment_paid_at=COALESCE(p_paid_at,now()), status=CASE WHEN status='NEW' THEN status ELSE 'CONFIRMED' END, updated_at=now() WHERE id=p_order_id;
  UPDATE public.gdc_qris_mpm_payments SET status='PAID', paid_at=COALESCE(p_paid_at,now()), provider_response_code='00', updated_at=now() WHERE order_id=p_order_id;
  RETURN jsonb_build_object('success',true,'status','PAID','order_id',p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,numeric,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.settle_gdc_qris_mpm_payment(uuid,uuid,text,numeric,timestamptz) TO service_role;

-- Merchant resubmission is a whitelist, not a generic row update.
CREATE OR REPLACE FUNCTION public.protect_qris_application_merchant_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_admin() THEN
    IF NEW.assigned_admin_id IS DISTINCT FROM OLD.assigned_admin_id OR NEW.decision_by_admin_id IS DISTINCT FROM OLD.decision_by_admin_id OR NEW.decision_note IS DISTINCT FROM OLD.decision_note OR NEW.issued_at IS DISTINCT FROM OLD.issued_at OR NEW.activated_at IS DISTINCT FROM OLD.activated_at OR NEW.issued_by_admin_id IS DISTINCT FROM OLD.issued_by_admin_id OR NEW.activated_by_admin_id IS DISTINCT FROM OLD.activated_by_admin_id OR NEW.revision_number < OLD.revision_number THEN
      RAISE EXCEPTION 'Metadata administratif QRIS hanya dapat diubah admin' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protect_qris_application_merchant_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS protect_qris_application_merchant_update_trigger ON public.qris_applications;
CREATE TRIGGER protect_qris_application_merchant_update_trigger BEFORE UPDATE ON public.qris_applications FOR EACH ROW EXECUTE FUNCTION public.protect_qris_application_merchant_update();
NOTIFY pgrst, 'reload schema';
