-- Phase 1: make POS entitlement time-aware and preserve a readable grace period.
-- Marketplace merchant access is intentionally not coupled to this lifecycle.

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS grace_ends_at timestamptz;

ALTER TABLE public.pos_tenants
  DROP CONSTRAINT IF EXISTS pos_tenants_status_check;

ALTER TABLE public.pos_tenants
  ADD CONSTRAINT pos_tenants_status_check
  CHECK (status IN ('inactive', 'setup_required', 'trial', 'active', 'grace', 'suspended', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_entitlement_lookup
  ON public.pos_subscriptions(merchant_id, status, expired_at, grace_ends_at);

-- This is the single read model for the current POS entitlement. It is safe
-- for the merchant subscription screen and keeps expiry/grace logic out of
-- browser-only checks.
CREATE OR REPLACE FUNCTION public.get_pos_entitlement(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_state text := 'none';
  v_operational boolean := false;
BEGIN
  IF auth.uid() IS NULL OR (
    NOT public.is_admin()
    AND NOT EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id = p_merchant_id
        AND m.user_id = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'Merchant entitlement access denied' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status IN ('ACTIVE', 'SUSPENDED', 'CANCELLED')
  ORDER BY
    CASE status WHEN 'ACTIVE' THEN 1 WHEN 'SUSPENDED' THEN 2 ELSE 3 END,
    created_at DESC
  LIMIT 1;

  IF v_subscription.id IS NULL THEN
    RETURN jsonb_build_object('state', v_state, 'operational', false);
  END IF;

  IF v_subscription.status = 'SUSPENDED' THEN
    v_state := 'suspended';
  ELSIF v_subscription.status = 'CANCELLED' THEN
    v_state := 'cancelled';
  ELSIF v_subscription.started_at IS NULL OR v_subscription.started_at > now() THEN
    v_state := 'pending';
  ELSIF v_subscription.expired_at > now() THEN
    v_state := CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END;
    v_operational := true;
  ELSIF v_subscription.grace_ends_at IS NOT NULL
    AND v_subscription.grace_ends_at > now() THEN
    v_state := 'grace';
    v_operational := true;
  ELSE
    v_state := 'expired';
  END IF;

  RETURN jsonb_build_object(
    'state', v_state,
    'operational', v_operational,
    'subscription_id', v_subscription.id,
    'package_id', v_subscription.package_id,
    'is_trial', v_subscription.is_trial,
    'started_at', v_subscription.started_at,
    'expired_at', v_subscription.expired_at,
    'grace_ends_at', v_subscription.grace_ends_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_entitlement(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_entitlement(uuid) TO authenticated;

-- Every operational mutation, including the atomic checkout trigger path,
-- must consult the subscription clock rather than trusting the tenant row.
CREATE OR REPLACE FUNCTION public.is_pos_tenant_active(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    JOIN public.pos_subscriptions s ON s.merchant_id = t.merchant_id
    WHERE t.id = p_tenant_id
      AND t.is_active = true
      AND t.status IN ('trial', 'active', 'grace')
      AND s.status = 'ACTIVE'
      AND s.started_at IS NOT NULL
      AND s.started_at <= now()
      AND (
        s.expired_at > now()
        OR s.grace_ends_at > now()
      )
      AND (
        s.is_trial = true
        OR s.payment_status = 'PAID'
      )
  );
$$;

REVOKE ALL ON FUNCTION public.is_pos_tenant_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pos_tenant_active(uuid) TO authenticated;

-- Admin approval/reactivation clears a previous grace window. A later
-- suspend/cancel remains explicit and does not delete merchant data.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_duration_months integer;
  v_started_at timestamptz;
  v_expired_at timestamptz;
  v_action text := upper(trim(p_action));
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;
  v_duration_months := COALESCE(v_duration_months, 1);

  IF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at
        + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
    ELSE
      v_started_at := now();
      v_expired_at := v_started_at + make_interval(months => CASE
        WHEN v_action = 'EXTEND' THEN GREATEST(1, COALESCE(p_extension_months, 1))
        ELSE v_duration_months
      END);
    END IF;

    UPDATE public.pos_subscriptions
    SET status = 'ACTIVE',
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        grace_ends_at = NULL,
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END,
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED', payment_status = 'UNPAID', updated_at = now()
    WHERE id = v_subscription.id;
    UPDATE public.pos_tenants
    SET status = 'suspended', is_active = false, suspended_at = now(), updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED', payment_status = 'CANCELLED', updated_at = now()
    WHERE id = v_subscription.id;
    UPDATE public.pos_tenants
    SET status = 'cancelled', is_active = false, updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(NULLIF(trim(p_rejection_reason), ''), 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object('subscription', to_jsonb(s), 'tenant', to_jsonb(t))
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;