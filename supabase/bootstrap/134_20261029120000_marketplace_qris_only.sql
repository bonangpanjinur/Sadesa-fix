-- Marketplace checkout is QRIS-only. QRIS becomes visible to buyers only after
-- an admin activates it; merchant bank details remain available for admin payout.

-- Legacy/manual QRIS values not backed by an active application must not be used
-- as buyer payment instructions.
UPDATE public.merchants m
SET qris_image_url = NULL,
    updated_at = now()
WHERE NULLIF(btrim(COALESCE(m.qris_image_url, '')), '') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.qris_applications a
    WHERE a.merchant_id = m.id
      AND a.status = 'ACTIVE'
      AND a.qris_asset_key = m.qris_image_url
  );

-- Issuance records the asset on the application only. It does not replace the
-- currently active QRIS before the admin completes the final activation step.
CREATE OR REPLACE FUNCTION public.admin_issue_qris(p_application_id uuid, p_qris_reference text, p_qris_asset_key text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_qris_reference), '') IS NULL OR NULLIF(trim(p_qris_asset_key), '') IS NULL THEN
    RAISE EXCEPTION 'Referensi dan gambar QRIS wajib diisi' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'APPROVED_PENDING_ISSUANCE' THEN
    RAISE EXCEPTION 'Pengajuan belum berada pada tahap penerbitan' USING ERRCODE = '23514';
  END IF;
  UPDATE public.qris_applications
  SET status = 'ISSUED_PENDING_ACTIVATION',
      qris_reference = trim(p_qris_reference),
      qris_asset_key = trim(p_qris_asset_key),
      issued_by_admin_id = auth.uid(),
      issued_at = now(),
      updated_at = now()
  WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_issue_qris(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_qris(uuid, text, text) TO authenticated;

-- Activate the QRIS and expose it on the merchant profile atomically.
CREATE OR REPLACE FUNCTION public.admin_activate_qris(p_application_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_application public.qris_applications%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Akses admin diperlukan' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO STRICT v_application
  FROM public.qris_applications
  WHERE id = p_application_id
  FOR UPDATE;
  IF v_application.status <> 'ISSUED_PENDING_ACTIVATION'
     OR NULLIF(v_application.qris_reference, '') IS NULL
     OR NULLIF(v_application.qris_asset_key, '') IS NULL THEN
    RAISE EXCEPTION 'QRIS belum diterbitkan lengkap dan belum dapat diaktifkan' USING ERRCODE = '23514';
  END IF;
  UPDATE public.merchants
  SET qris_image_url = v_application.qris_asset_key,
      updated_at = now()
  WHERE id = v_application.merchant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Merchant untuk pengajuan QRIS tidak ditemukan' USING ERRCODE = '23503';
  END IF;
  UPDATE public.qris_applications
  SET status = 'ACTIVE',
      activated_by_admin_id = auth.uid(),
      activated_at = now(),
      updated_at = now()
  WHERE id = p_application_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_activate_qris(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_qris(uuid) TO authenticated;

-- Snapshot the active merchant QRIS for marketplace orders only. Never copy a
-- merchant or platform bank account into a buyer-visible order snapshot.
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
    IF NEW.payment_method = 'TRANSFER' AND NEW.confirmation_deadline IS NULL THEN
      NEW.confirmation_deadline := now() + interval '30 minutes';
    END IF;
    IF NEW.payment_method = 'TRANSFER' AND NEW.payment_destination_snapshot IS NULL THEN
      IF NEW.merchant_id IS NOT NULL THEN
        SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
      END IF;
      IF NEW.service_type = 'MARKETPLACE' THEN
        IF NULLIF(btrim(COALESCE(v_merchant.qris_image_url, '')), '') IS NULL THEN
          RAISE EXCEPTION 'QRIS merchant belum aktif untuk checkout' USING ERRCODE = '22023';
        END IF;
        NEW.payment_destination_snapshot := jsonb_build_object(
          'source', 'MERCHANT',
          'merchant_name', v_merchant.name,
          'qris_image_url', v_merchant.qris_image_url,
          'version', 2
        );
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

-- Guest payment instructions expose only the immutable QRIS snapshot.
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
    'qris_image_url', v_order.payment_destination_snapshot->>'qris_image_url',
    'payment_destination_source', v_order.payment_destination_snapshot->>'source'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_guest_order_payment_context(uuid, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.get_guest_order_payment_context(uuid, text) TO anon;
