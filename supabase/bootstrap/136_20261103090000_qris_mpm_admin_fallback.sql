-- Keep dynamic QRIS MPM independent from a merchant static QR upload.
-- When platform admin payment details are configured, snapshot them on the
-- order so buyers can use the approved manual fallback if GDC cannot generate.
CREATE OR REPLACE FUNCTION public.snapshot_order_payment_and_delivery_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_admin jsonb;
  v_admin_ready boolean := false;
  v_mpm_ready boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.courier_delivery_fee_snapshot := GREATEST(
      COALESCE(NULLIF(NEW.courier_earning_estimate, 0), NEW.shipping_cost, 0), 0
    );
    IF NEW.payment_method = 'TRANSFER' AND NEW.confirmation_deadline IS NULL THEN
      NEW.confirmation_deadline := now() + interval '30 minutes';
    END IF;
    IF NEW.payment_method = 'TRANSFER' AND NEW.payment_destination_snapshot IS NULL THEN
      IF NEW.merchant_id IS NOT NULL THEN
        SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
      END IF;

      IF NEW.service_type = 'MARKETPLACE' THEN
        SELECT value INTO v_admin FROM public.app_settings WHERE key = 'admin_payment_info';
        v_admin_ready := (
          NULLIF(btrim(COALESCE(v_admin->>'bank_name', '')), '') IS NOT NULL
          AND NULLIF(btrim(COALESCE(v_admin->>'bank_account_number', '')), '') IS NOT NULL
        ) OR NULLIF(btrim(COALESCE(v_admin->>'qris_image_url', '')), '') IS NOT NULL;

        IF v_admin_ready THEN
          NEW.payment_destination_snapshot := jsonb_build_object(
            'source', 'ADMIN',
            'merchant_name', v_merchant.name,
            'bank_name', v_admin->>'bank_name',
            'bank_account_number', v_admin->>'bank_account_number',
            'bank_account_name', v_admin->>'bank_account_name',
            'qris_image_url', v_admin->>'qris_image_url',
            'version', 3
          );
        ELSE
          SELECT (
            NULLIF(btrim(COALESCE(application.gdc_merchant_id, '')), '') IS NOT NULL
            AND NULLIF(btrim(COALESCE(application.gdc_account_number, '')), '') IS NOT NULL
          ) INTO v_mpm_ready
          FROM public.qris_applications AS application
          WHERE application.merchant_id = NEW.merchant_id
            AND application.status = 'ACTIVE'
          ORDER BY application.activated_at DESC
          LIMIT 1;
          v_mpm_ready := COALESCE(v_mpm_ready, false);

          IF v_mpm_ready THEN
            NEW.payment_destination_snapshot := jsonb_build_object(
              'source', 'GDC_MPM',
              'merchant_name', v_merchant.name,
              'version', 3
            );
          ELSE
            RAISE EXCEPTION 'Pembayaran MPM merchant atau QR/rekening Admin Sadesa belum dikonfigurasi' USING ERRCODE = '22023';
          END IF;
        END IF;
      ELSIF (NULLIF(btrim(COALESCE(v_merchant.bank_name, '')), '') IS NOT NULL
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

-- Expose only the payment instructions already snapshotted for this guest order.
CREATE OR REPLACE FUNCTION public.get_guest_order_payment_context(p_order_id uuid, p_guest_access_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = encode(digest(p_guest_access_token, 'sha256'), 'hex')
    AND guest_token_expires_at > now();
  IF NOT FOUND OR v_order.payment_method <> 'TRANSFER' THEN
    RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'id', v_order.id,
    'total', v_order.total,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'merchant_id', v_order.merchant_id,
    'merchant_name', COALESCE(v_order.payment_destination_snapshot->>'merchant_name', 'Merchant'),
    'created_at', v_order.created_at,
    'payment_proof_url', v_order.payment_proof_url,
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
NOTIFY pgrst, 'reload schema';
