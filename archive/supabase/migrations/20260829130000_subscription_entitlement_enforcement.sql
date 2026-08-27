-- Subscription entitlement catalog and server-side resolution.
-- Idempotent and safe to replay. Existing merchant overrides always win.

INSERT INTO public.subscription_plan_entitlements (plan_id, feature_key, entitlement_type, enabled, limit_value, unit)
SELECT p.id, v.feature_key, v.entitlement_type, v.enabled, v.limit_value, v.unit
FROM public.subscription_plans p
JOIN (VALUES
  ('free', 'active_products', 'limit', true, 50::bigint, 'items'),
  ('free', 'pos_devices', 'limit', true, 1::bigint, 'devices'),
  ('free', 'whatsapp_messages', 'metered', true, 0::bigint, 'messages/month'),
  ('free', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('free', 'customer_segments', 'limit', true, 0::bigint, 'segments'),
  ('free', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('free', 'offline_queue', 'limit', true, 20::bigint, 'transactions'),
  ('free', 'reports_history_days', 'limit', true, 30::bigint, 'days'),
  ('free', 'loyalty_rules', 'limit', true, 1::bigint, 'rules'),
  ('starter', 'active_products', 'limit', true, 300::bigint, 'items'),
  ('starter', 'pos_devices', 'limit', true, 2::bigint, 'devices'),
  ('starter', 'whatsapp_messages', 'metered', true, 500::bigint, 'messages/month'),
  ('starter', 'warehouses', 'limit', true, 1::bigint, 'warehouses'),
  ('starter', 'customer_segments', 'limit', true, 1::bigint, 'segments'),
  ('starter', 'api_requests', 'metered', true, 0::bigint, 'requests/month'),
  ('starter', 'offline_queue', 'limit', true, 100::bigint, 'transactions'),
  ('starter', 'reports_history_days', 'limit', true, 365::bigint, 'days'),
  ('starter', 'loyalty_rules', 'limit', true, 3::bigint, 'rules'),
  ('growth', 'active_products', 'limit', true, 2000::bigint, 'items'),
  ('growth', 'pos_devices', 'limit', true, 5::bigint, 'devices'),
  ('growth', 'whatsapp_messages', 'metered', true, 3000::bigint, 'messages/month'),
  ('growth', 'warehouses', 'limit', true, 2::bigint, 'warehouses'),
  ('growth', 'customer_segments', 'limit', true, 10::bigint, 'segments'),
  ('growth', 'api_requests', 'metered', true, 10000::bigint, 'requests/month'),
  ('growth', 'offline_queue', 'limit', true, 500::bigint, 'transactions'),
  ('growth', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('growth', 'loyalty_rules', 'limit', true, 10::bigint, 'rules'),
  ('pro', 'active_products', 'limit', true, NULL::bigint, 'items'),
  ('pro', 'pos_devices', 'limit', true, NULL::bigint, 'devices'),
  ('pro', 'whatsapp_messages', 'metered', true, 15000::bigint, 'messages/month'),
  ('pro', 'warehouses', 'limit', true, NULL::bigint, 'warehouses'),
  ('pro', 'customer_segments', 'limit', true, NULL::bigint, 'segments'),
  ('pro', 'api_requests', 'metered', true, 100000::bigint, 'requests/month'),
  ('pro', 'offline_queue', 'limit', true, 2000::bigint, 'transactions'),
  ('pro', 'reports_history_days', 'limit', true, NULL::bigint, 'days'),
  ('pro', 'loyalty_rules', 'limit', true, NULL::bigint, 'rules')
) AS v(plan_code, feature_key, entitlement_type, enabled, limit_value, unit) ON v.plan_code = p.code
ON CONFLICT (plan_id, feature_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_subscription_entitlement(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_enabled boolean;
  v_limit bigint;
  v_unit text;
  v_source text;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid entitlement request' USING ERRCODE = '22023';
  END IF;
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Entitlement access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('enabled', false, 'limit_value', 0, 'source', 'none');
  END IF;

  SELECT mse.enabled, mse.limit_value, mse.unit, 'override'
  INTO v_enabled, v_limit, v_unit, v_source
  FROM public.merchant_subscription_entitlements mse
  WHERE mse.subscription_id = v_subscription.id
    AND mse.feature_key = p_feature_key
    AND mse.starts_at <= now()
    AND (mse.ends_at IS NULL OR mse.ends_at > now());

  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value, spe.unit, 'plan'
    INTO v_enabled, v_limit, v_unit, v_source
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id
      AND spe.feature_key = p_feature_key;
  END IF;

  RETURN jsonb_build_object(
    'enabled', COALESCE(v_enabled, false),
    'limit_value', v_limit,
    'unit', v_unit,
    'source', COALESCE(v_source, 'none'),
    'subscription_id', v_subscription.id,
    'plan_id', v_subscription.plan_id,
    'status', v_subscription.status,
    'grace_period_until', v_subscription.grace_period_until
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_subscription_entitlement(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_subscription_entitlement(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.require_subscription_feature(
  p_merchant_id uuid,
  p_feature_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entitlement jsonb;
BEGIN
  v_entitlement := public.get_subscription_entitlement(p_merchant_id, p_feature_key);
  IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
    RAISE EXCEPTION 'Feature is not included in active subscription' USING ERRCODE = '42501';
  END IF;
  RETURN v_entitlement;
END;
$$;

REVOKE ALL ON FUNCTION public.require_subscription_feature(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_subscription_feature(uuid, text) TO authenticated, service_role;
