-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- Source: 20261002110000_admin_manual_pos_access.sql

DO $bootstrap_do_manual_pos_access$
BEGIN
  EXECUTE $bootstrap_sql_manual_pos_access$-- Admin-only manual POS access grant.
-- A grant must provision the merchant POS workspace as well as its entitlement,
-- so the merchant can use POS immediately without repeating setup manually.

CREATE OR REPLACE FUNCTION public.admin_grant_pos_access(
  p_merchant_id uuid,
  p_package_id uuid DEFAULT NULL,
  p_duration_months integer DEFAULT 1,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant public.merchants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_tenant public.pos_tenants%ROWTYPE;
  v_outlet public.pos_outlets%ROWTYPE;
  v_old jsonb;
  v_started_at timestamptz := now();
  v_expired_at timestamptz;
  v_duration integer;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
  v_synced_products integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can grant POS access' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required for manual POS access grants' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_merchant
  FROM public.merchants
  WHERE id = p_merchant_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Merchant account not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_merchant.user_id IS NULL THEN
    RAISE EXCEPTION 'Merchant has no linked user account' USING ERRCODE = '23503';
  END IF;
  IF COALESCE(v_merchant.status, '') <> 'ACTIVE'
     AND COALESCE(v_merchant.registration_status, '') <> 'APPROVED' THEN
    RAISE EXCEPTION 'Merchant must be approved and active before POS access is granted' USING ERRCODE = '42501';
  END IF;

  IF p_package_id IS NOT NULL THEN
    SELECT * INTO v_package
    FROM public.pos_packages
    WHERE id = p_package_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selected POS package is not active' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_duration := GREATEST(1, COALESCE(NULLIF(p_duration_months, 0), v_package.duration_months, 1));
  v_expired_at := v_started_at + make_interval(months => v_duration);

  SELECT * INTO v_subscription
  FROM public.pos_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status NOT IN ('CANCELLED', 'REJECTED')
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_subscription.id IS NULL THEN
    INSERT INTO public.pos_subscriptions (
      merchant_id, package_id, status, payment_amount, payment_status,
      started_at, expired_at, approved_by, approved_at, is_trial
    ) VALUES (
      p_merchant_id, p_package_id, 'ACTIVE', 0, 'PAID',
      v_started_at, v_expired_at, auth.uid(), v_started_at, true
    )
    RETURNING * INTO v_subscription;
  ELSE
    v_old := to_jsonb(v_subscription);
    UPDATE public.pos_subscriptions
    SET package_id = COALESCE(p_package_id, package_id),
        status = 'ACTIVE', payment_amount = 0, payment_status = 'PAID',
        started_at = v_started_at, expired_at = v_expired_at,
        grace_ends_at = NULL, approved_by = auth.uid(), approved_at = v_started_at,
        rejection_reason = NULL, is_trial = true, updated_at = v_started_at
    WHERE id = v_subscription.id
    RETURNING * INTO v_subscription;
  END IF;

  -- Provision or repair the merchant-owned POS workspace in this same transaction.
  SELECT * INTO v_tenant
  FROM public.pos_tenants
  WHERE merchant_id = p_merchant_id OR user_id = v_merchant.user_id
  ORDER BY (merchant_id = p_merchant_id) DESC, created_at
  LIMIT 1
  FOR UPDATE;

  IF v_tenant.id IS NULL THEN
    INSERT INTO public.pos_tenants (
      user_id, name, phone, address, timezone, currency, merchant_id,
      is_active, status, enabled_modules, activated_at
    ) VALUES (
      v_merchant.user_id,
      COALESCE(NULLIF(trim(v_merchant.name), ''), 'Toko Merchant'),
      NULLIF(trim(v_merchant.phone), ''), NULLIF(trim(v_merchant.address), ''),
      'Asia/Jakarta', 'IDR', p_merchant_id,
      true, 'trial', '["cashier"]'::jsonb, v_started_at
    )
    RETURNING * INTO v_tenant;
  ELSE
    UPDATE public.pos_tenants
    SET merchant_id = COALESCE(merchant_id, p_merchant_id), user_id = v_merchant.user_id,
        name = COALESCE(NULLIF(trim(name), ''), NULLIF(trim(v_merchant.name), ''), 'Toko Merchant'),
        phone = COALESCE(phone, NULLIF(trim(v_merchant.phone), '')),
        address = COALESCE(address, NULLIF(trim(v_merchant.address), '')),
        is_active = true, status = 'trial',
        enabled_modules = CASE
          WHEN jsonb_typeof(enabled_modules) = 'array' AND jsonb_array_length(enabled_modules) > 0
            THEN enabled_modules ELSE '["cashier"]'::jsonb END,
        activated_at = COALESCE(activated_at, v_started_at), suspended_at = NULL,
        updated_at = v_started_at
    WHERE id = v_tenant.id
    RETURNING * INTO v_tenant;
  END IF;

  IF v_tenant.merchant_id IS DISTINCT FROM p_merchant_id THEN
    RAISE EXCEPTION 'POS tenant is mapped to another merchant' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_outlet
  FROM public.pos_outlets
  WHERE tenant_id = v_tenant.id AND is_active = true
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
    VALUES (
      v_tenant.id,
      COALESCE(NULLIF(trim(v_merchant.name), ''), 'Toko Merchant') || ' - Outlet Utama',
      NULLIF(trim(v_merchant.address), ''), NULLIF(trim(v_merchant.phone), ''), true
    )
    RETURNING * INTO v_outlet;
  END IF;

  IF to_regprocedure('public.sync_pos_tenant_catalog(uuid)') IS NOT NULL THEN
    v_synced_products := COALESCE(public.sync_pos_tenant_catalog(v_tenant.id), 0);
  END IF;

  INSERT INTO public.admin_audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    auth.uid(), 'POS_ACCESS_MANUAL_GRANT', 'merchant', p_merchant_id, v_old,
    jsonb_build_object('subscription', to_jsonb(v_subscription), 'tenant', to_jsonb(v_tenant),
      'outlet', to_jsonb(v_outlet), 'package_id', p_package_id, 'duration_months', v_duration,
      'reason', v_reason, 'synced_products', v_synced_products)
  );

  RETURN jsonb_build_object('merchant_id', p_merchant_id, 'subscription_id', v_subscription.id,
    'tenant_id', v_tenant.id, 'outlet_id', v_outlet.id, 'status', v_subscription.status,
    'started_at', v_subscription.started_at, 'expired_at', v_subscription.expired_at,
    'synced_products', v_synced_products);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_grant_pos_access(uuid, uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_pos_access(uuid, uuid, integer, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
$bootstrap_sql_manual_pos_access$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_manual_pos_access$;
