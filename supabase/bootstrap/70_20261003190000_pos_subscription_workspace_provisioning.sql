-- DesaMart canonical bootstrap bundle; generated from the POS entitlement repair migration.
-- Active subscription approval must always have a merchant POS workspace.

DO $bootstrap_do_pos_subscription_workspace_provisioning$
BEGIN
  EXECUTE $bootstrap_sql_pos_subscription_workspace_provisioning$
CREATE OR REPLACE FUNCTION public.provision_pos_workspace_for_subscription(
  p_subscription_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_merchant public.merchants%ROWTYPE;
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  SELECT * INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id;
  IF NOT FOUND
     OR v_subscription.status <> 'ACTIVE'
     OR v_subscription.started_at IS NULL
     OR v_subscription.expired_at IS NULL
     OR v_subscription.expired_at <= now()
     OR (NOT COALESCE(v_subscription.is_trial, false) AND v_subscription.payment_status <> 'PAID') THEN
    RETURN;
  END IF;

  SELECT * INTO v_merchant
  FROM public.merchants
  WHERE id = v_subscription.merchant_id
    AND user_id IS NOT NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.pos_tenants (
    user_id, name, phone, address, timezone, currency, merchant_id,
    is_active, status, enabled_modules, activated_at
  ) VALUES (
    v_merchant.user_id,
    COALESCE(NULLIF(trim(v_merchant.name), ''), 'Toko Merchant'),
    NULLIF(trim(v_merchant.phone), ''),
    NULLIF(trim(v_merchant.address), ''),
    'Asia/Jakarta', 'IDR', v_merchant.id,
    true,
    CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END,
    '["cashier"]'::jsonb,
    COALESCE(v_subscription.started_at, now())
  )
  ON CONFLICT (user_id) DO UPDATE SET
    merchant_id = COALESCE(public.pos_tenants.merchant_id, EXCLUDED.merchant_id),
    name = COALESCE(public.pos_tenants.name, EXCLUDED.name),
    phone = COALESCE(public.pos_tenants.phone, EXCLUDED.phone),
    address = COALESCE(public.pos_tenants.address, EXCLUDED.address),
    is_active = true,
    status = EXCLUDED.status,
    enabled_modules = CASE
      WHEN jsonb_typeof(public.pos_tenants.enabled_modules) = 'array'
        AND jsonb_array_length(public.pos_tenants.enabled_modules) > 0
        THEN public.pos_tenants.enabled_modules
      ELSE EXCLUDED.enabled_modules
    END,
    activated_at = COALESCE(public.pos_tenants.activated_at, EXCLUDED.activated_at),
    suspended_at = NULL,
    updated_at = now()
  RETURNING * INTO v_tenant;

  IF v_tenant.merchant_id IS DISTINCT FROM v_merchant.id THEN
    RAISE EXCEPTION 'POS tenant is mapped to another merchant' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
  SELECT
    v_tenant.id,
    COALESCE(NULLIF(trim(v_merchant.name), ''), 'Toko Merchant') || ' - Outlet Utama',
    NULLIF(trim(v_merchant.address), ''),
    NULLIF(trim(v_merchant.phone), ''),
    true
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE tenant_id = v_tenant.id AND is_active = true
  );

  IF to_regprocedure('public.sync_pos_tenant_catalog(uuid)') IS NOT NULL THEN
    PERFORM public.sync_pos_tenant_catalog(v_tenant.id);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.provision_pos_workspace_for_subscription_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.provision_pos_workspace_for_subscription(NEW.id);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.provision_pos_workspace_for_subscription(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provision_pos_workspace_for_subscription_trigger() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS provision_pos_workspace_after_subscription_change ON public.pos_subscriptions;
CREATE TRIGGER provision_pos_workspace_after_subscription_change
AFTER INSERT OR UPDATE OF status, started_at, expired_at, payment_status, is_trial
ON public.pos_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.provision_pos_workspace_for_subscription_trigger();
$bootstrap_sql_pos_subscription_workspace_provisioning$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_pos_subscription_workspace_provisioning$;

-- Reconcile existing active subscriptions created before this repair.
DO $bootstrap_do_pos_subscription_workspace_backfill$
DECLARE
  v_subscription record;
BEGIN
  FOR v_subscription IN
    SELECT s.id
    FROM public.pos_subscriptions s
    WHERE s.status = 'ACTIVE'
      AND s.started_at IS NOT NULL
      AND s.expired_at > now()
      AND (s.is_trial = true OR s.payment_status = 'PAID')
  LOOP
    PERFORM public.provision_pos_workspace_for_subscription(v_subscription.id);
  END LOOP;
END $bootstrap_do_pos_subscription_workspace_backfill$;
