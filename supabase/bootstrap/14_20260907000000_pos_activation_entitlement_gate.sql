-- POS activation must be backed by an approved merchant entitlement.
-- Existing operational tenants remain usable through the normal POS routes,
-- but the setup/activation RPC cannot be used to re-activate without one.

CREATE OR REPLACE FUNCTION public.ensure_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_merchant_id uuid;
  v_tenant public.pos_tenants%ROWTYPE;
  v_outlet public.pos_outlets%ROWTYPE;
  v_source_count integer;
  v_has_active_entitlement boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id
  INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = v_user_id
    AND m.registration_status = 'APPROVED'
    AND m.status = 'ACTIVE'
  ORDER BY m.updated_at DESC NULLS LAST, m.created_at DESC
  LIMIT 1;

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'An approved and active merchant profile is required before enabling POS'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.pos_subscriptions s
    WHERE s.merchant_id = v_merchant_id
      AND s.status = 'ACTIVE'
      AND s.started_at IS NOT NULL
      AND s.expired_at > now()
      AND (
        s.is_trial = true
        OR s.payment_status = 'PAID'
      )
  )
  INTO v_has_active_entitlement;

  IF NOT v_has_active_entitlement THEN
    RAISE EXCEPTION 'An active POS trial or subscription is required before enabling POS'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.pos_tenants (
    user_id, name, phone, address, timezone, currency, merchant_id, is_active
  )
  VALUES (
    v_user_id,
    NULLIF(trim(p_name), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_address), ''),
    COALESCE(NULLIF(trim(p_timezone), ''), 'Asia/Jakarta'),
    COALESCE(NULLIF(trim(p_currency), ''), 'IDR'),
    v_merchant_id,
    true
  )
  ON CONFLICT (user_id) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.pos_tenants.name),
    phone = COALESCE(EXCLUDED.phone, public.pos_tenants.phone),
    address = COALESCE(EXCLUDED.address, public.pos_tenants.address),
    timezone = COALESCE(EXCLUDED.timezone, public.pos_tenants.timezone),
    currency = COALESCE(EXCLUDED.currency, public.pos_tenants.currency),
    merchant_id = COALESCE(public.pos_tenants.merchant_id, EXCLUDED.merchant_id),
    is_active = true,
    status = CASE
      WHEN public.pos_tenants.status IN ('suspended', 'cancelled') THEN 'active'
      ELSE public.pos_tenants.status
    END,
    updated_at = now()
  RETURNING * INTO v_tenant;

  IF v_tenant.merchant_id IS NULL THEN
    RAISE EXCEPTION 'POS tenant is not mapped to a merchant' USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO v_outlet
  FROM public.pos_outlets
  WHERE tenant_id = v_tenant.id AND is_active = true
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
    VALUES (
      v_tenant.id,
      COALESCE(NULLIF(trim(p_outlet_name), ''), v_tenant.name || ' - Outlet Utama'),
      NULLIF(trim(COALESCE(p_outlet_address, p_address)), ''),
      NULLIF(trim(COALESCE(p_outlet_phone, p_phone)), ''),
      true
    )
    RETURNING * INTO v_outlet;
  END IF;

  v_source_count := public.sync_pos_tenant_catalog(v_tenant.id);

  RETURN jsonb_build_object(
    'tenant', to_jsonb(v_tenant),
    'outlet', to_jsonb(v_outlet),
    'merchant_id', v_tenant.merchant_id,
    'source_products_synced', v_source_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) TO authenticated;