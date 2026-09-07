-- Fase 5: pertumbuhan dan monetisasi lanjutan.
-- Paket tetap menjadi sumber konfigurasi limit POS; transaksi tetap
-- divalidasi oleh guard server-side, bukan hanya oleh UI.

ALTER TABLE public.pos_packages
  ADD COLUMN IF NOT EXISTS max_outlets INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_users INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS add_on_user_price INTEGER NOT NULL DEFAULT 25000,
  ADD COLUMN IF NOT EXISTS priority_support BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_discount_percent INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS onboarding_discount_expires_at TIMESTAMPTZ;

ALTER TABLE public.pos_packages
  DROP CONSTRAINT IF EXISTS pos_packages_limits_check;
ALTER TABLE public.pos_packages
  ADD CONSTRAINT pos_packages_limits_check CHECK (
    max_outlets > 0
    AND max_users > 0
    AND add_on_user_price >= 0
    AND onboarding_discount_percent BETWEEN 0 AND 100
  );

UPDATE public.pos_packages
SET
  max_outlets = CASE
    WHEN lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%' THEN 99
    WHEN lower(name) LIKE '%pro%' OR lower(name) LIKE '%growth%' THEN 3
    ELSE 1
  END,
  max_users = CASE
    WHEN lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%' THEN 20
    WHEN lower(name) LIKE '%pro%' OR lower(name) LIKE '%growth%' THEN 5
    ELSE 2
  END,
  priority_support = lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%';

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  partner_type TEXT,
  discount_percent INTEGER NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  max_redemptions INTEGER,
  redeemed_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pos_onboarding_promotions_discount_check CHECK (discount_percent BETWEEN 0 AND 100),
  CONSTRAINT pos_onboarding_promotions_redemption_check CHECK (
    max_redemptions IS NULL OR max_redemptions > 0
  )
);

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotion_redemptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  promotion_id UUID NOT NULL REFERENCES public.pos_onboarding_promotions(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, merchant_id)
);

ALTER TABLE public.pos_onboarding_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_onboarding_promotion_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Anyone can view active onboarding promotions"
  ON public.pos_onboarding_promotions FOR SELECT TO authenticated
  USING (is_active AND starts_at <= now() AND expires_at > now());

DROP POLICY IF EXISTS "Admins manage onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Admins manage onboarding promotions"
  ON public.pos_onboarding_promotions FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Merchants view own promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Merchants view own promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = merchant_id AND m.user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Admins view promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Admins view promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (is_admin());

CREATE OR REPLACE FUNCTION public.get_pos_commercial_entitlement(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_outlet_count INTEGER;
  v_user_count INTEGER;
BEGIN
  SELECT * INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id;

  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'POS tenant tidak ditemukan';
  END IF;

  IF v_tenant.user_id <> auth.uid() AND NOT is_admin() THEN
    RAISE EXCEPTION 'Tidak berwenang melihat entitlement tenant ini';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status IN ('ACTIVE', 'PENDING')
  ORDER BY ps.created_at DESC
  LIMIT 1;

  IF v_subscription.package_id IS NOT NULL THEN
    SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  END IF;

  SELECT count(*)::INTEGER INTO v_outlet_count
  FROM public.pos_outlets WHERE tenant_id = p_tenant_id AND is_active;

  SELECT count(*)::INTEGER INTO v_user_count
  FROM public.pos_users WHERE tenant_id = p_tenant_id AND is_active;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'subscription_status', COALESCE(v_subscription.status, 'NONE'),
    'package_id', v_package.id,
    'package_name', COALESCE(v_package.name, 'Trial / legacy'),
    'max_outlets', COALESCE(v_package.max_outlets, 1),
    'max_users', COALESCE(v_package.max_users, 2),
    'add_on_user_price', COALESCE(v_package.add_on_user_price, 25000),
    'priority_support', COALESCE(v_package.priority_support, false),
    'active_outlets', v_outlet_count,
    'active_users', v_user_count,
    'outlets_remaining', GREATEST(COALESCE(v_package.max_outlets, 1) - v_outlet_count, 0),
    'users_remaining', GREATEST(COALESCE(v_package.max_users, 2) - v_user_count, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pos_outlet_with_entitlement_guard(
  p_tenant_id UUID,
  p_name TEXT,
  p_address TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
)
RETURNS public.pos_outlets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_outlet_count INTEGER;
  v_outlet public.pos_outlets%ROWTYPE;
BEGIN
  SELECT * INTO v_tenant FROM public.pos_tenants
  WHERE id = p_tenant_id AND user_id = auth.uid();
  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'Tidak berwenang menambah outlet pada tenant ini';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;
  IF v_subscription.id IS NULL THEN
    RAISE EXCEPTION 'Subscription POS aktif diperlukan untuk menambah outlet';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  SELECT count(*)::INTEGER INTO v_outlet_count
  FROM public.pos_outlets WHERE tenant_id = p_tenant_id AND is_active;
  IF v_outlet_count >= COALESCE(v_package.max_outlets, 1) THEN
    RAISE EXCEPTION 'Batas outlet paket % tercapai (% outlet)', COALESCE(v_package.name, 'POS'), COALESCE(v_package.max_outlets, 1);
  END IF;

  INSERT INTO public.pos_outlets (tenant_id, name, address, phone)
  VALUES (p_tenant_id, NULLIF(trim(p_name), ''), NULLIF(trim(p_address), ''), NULLIF(trim(p_phone), ''))
  RETURNING * INTO v_outlet;
  RETURN v_outlet;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pos_commercial_entitlement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pos_outlet_with_entitlement_guard(UUID, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_pos_package(
  p_package_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_duration_months INTEGER,
  p_price INTEGER,
  p_max_outlets INTEGER,
  p_max_users INTEGER,
  p_add_on_user_price INTEGER,
  p_priority_support BOOLEAN,
  p_onboarding_discount_percent INTEGER,
  p_onboarding_discount_expires_at TIMESTAMPTZ,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before public.pos_packages%ROWTYPE;
  v_after public.pos_packages%ROWTYPE;
  v_reason TEXT := NULLIF(trim(p_reason), '');
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can update POS packages' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR v_reason IS NULL
    OR COALESCE(p_duration_months, 0) < 1 OR COALESCE(p_price, -1) < 0
    OR COALESCE(p_max_outlets, 0) < 1 OR COALESCE(p_max_users, 0) < 1
    OR COALESCE(p_add_on_user_price, -1) < 0
    OR COALESCE(p_onboarding_discount_percent, -1) NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'Data paket atau alasan perubahan tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.pos_packages WHERE id = p_package_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS package not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.pos_packages
  SET name = trim(p_name),
      description = NULLIF(trim(COALESCE(p_description, '')), ''),
      duration_months = p_duration_months,
      price = p_price,
      max_outlets = p_max_outlets,
      max_users = p_max_users,
      add_on_user_price = p_add_on_user_price,
      priority_support = COALESCE(p_priority_support, false),
      onboarding_discount_percent = p_onboarding_discount_percent,
      onboarding_discount_expires_at = p_onboarding_discount_expires_at
  WHERE id = p_package_id;

  SELECT * INTO v_after FROM public.pos_packages WHERE id = p_package_id;
  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  ) VALUES (
    auth.uid(), 'UPDATE_POS_PACKAGE_LIMITS', 'pos_package', p_package_id,
    to_jsonb(v_before), to_jsonb(v_after) || jsonb_build_object('reason', v_reason)
  );
  RETURN to_jsonb(v_after);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_pos_package(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, BOOLEAN, INTEGER, TIMESTAMPTZ, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_pos_package(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, BOOLEAN, INTEGER, TIMESTAMPTZ, TEXT
) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pos_user_with_entitlement_guard(
  p_tenant_id UUID,
  p_name TEXT,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'kasir',
  p_outlet_id UUID DEFAULT NULL,
  p_pin TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true
)
RETURNS public.pos_users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_user_count INTEGER;
  v_user public.pos_users%ROWTYPE;
BEGIN
  SELECT * INTO v_tenant FROM public.pos_tenants
  WHERE id = p_tenant_id AND user_id = auth.uid();
  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'Tidak berwenang menambah pengguna pada tenant ini';
  END IF;
  IF p_role NOT IN ('owner', 'manager', 'kasir', 'staff_gudang', 'purchasing', 'finance', 'auditor') THEN
    RAISE EXCEPTION 'Role pengguna tidak valid';
  END IF;
  IF p_outlet_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = p_outlet_id AND tenant_id = p_tenant_id AND is_active
  ) THEN
    RAISE EXCEPTION 'Outlet pengguna tidak valid';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;
  IF v_subscription.id IS NULL THEN
    RAISE EXCEPTION 'Subscription POS aktif diperlukan untuk menambah pengguna';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  SELECT count(*)::INTEGER INTO v_user_count
  FROM public.pos_users WHERE tenant_id = p_tenant_id AND is_active;
  IF v_user_count >= COALESCE(v_package.max_users, 2) THEN
    RAISE EXCEPTION 'Batas pengguna paket % tercapai (% pengguna)', COALESCE(v_package.name, 'POS'), COALESCE(v_package.max_users, 2);
  END IF;

  INSERT INTO public.pos_users (tenant_id, name, email, phone, role, outlet_id, pin, is_active)
  VALUES (p_tenant_id, NULLIF(trim(p_name), ''), NULLIF(trim(p_email), ''), NULLIF(trim(p_phone), ''), p_role, p_outlet_id, NULLIF(trim(p_pin), ''), COALESCE(p_is_active, true))
  RETURNING * INTO v_user;
  RETURN v_user;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pos_user_with_entitlement_guard(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_user_with_entitlement_guard(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN) TO authenticated;