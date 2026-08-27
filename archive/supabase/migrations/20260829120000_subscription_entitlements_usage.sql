-- Subscription plans, entitlements, invoices, and usage ledger.
-- Safe to replay: all schema objects and policies are guarded.

CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  price numeric(15,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  billing_interval text NOT NULL DEFAULT 'monthly' CHECK (billing_interval IN ('monthly', 'quarterly', 'yearly')),
  trial_days integer NOT NULL DEFAULT 0 CHECK (trial_days >= 0 AND trial_days <= 365),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.subscription_plans(id),
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_plan ON public.merchant_subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_active_merchant
  ON public.merchant_subscriptions(merchant_id, status, expired_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_plan_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES public.subscription_plans(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  entitlement_type text NOT NULL DEFAULT 'limit' CHECK (entitlement_type IN ('boolean', 'limit', 'metered')),
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plan_id, feature_key)
);

CREATE TABLE IF NOT EXISTS public.merchant_subscription_entitlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  unit text,
  source text NOT NULL DEFAULT 'override' CHECK (source IN ('override', 'support', 'migration')),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key),
  CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_merchant_entitlements_active
  ON public.merchant_subscription_entitlements(subscription_id, feature_key, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS public.subscription_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text,
  provider_invoice_id text,
  invoice_number text,
  amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'IDR' CHECK (char_length(currency) = 3),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'paid', 'void', 'uncollectible', 'failed')),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  due_at timestamptz,
  paid_at timestamptz,
  hosted_invoice_url text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_invoice_id),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_subscription_invoices_subscription
  ON public.subscription_invoices(subscription_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.subscription_usage_counters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  used_quantity numeric(20,4) NOT NULL DEFAULT 0 CHECK (used_quantity >= 0),
  limit_value bigint CHECK (limit_value IS NULL OR limit_value >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, period_start, period_end),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_counters_merchant_period
  ON public.subscription_usage_counters(merchant_id, feature_key, period_start, period_end);

CREATE TABLE IF NOT EXISTS public.subscription_usage_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  feature_key text NOT NULL,
  quantity numeric(20,4) NOT NULL CHECK (quantity > 0),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  idempotency_key text NOT NULL,
  source_type text NOT NULL DEFAULT 'application',
  source_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, feature_key, idempotency_key),
  CHECK (period_end > period_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_ledger_merchant_created
  ON public.subscription_usage_ledger(merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_feature_period
  ON public.subscription_usage_ledger(subscription_id, feature_key, period_start, period_end, created_at DESC);

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plan_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_subscription_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_usage_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users view active subscription plans" ON public.subscription_plans;
CREATE POLICY "Authenticated users view active subscription plans"
  ON public.subscription_plans FOR SELECT TO authenticated
  USING (is_active OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription plans" ON public.subscription_plans;
CREATE POLICY "Admins manage subscription plans"
  ON public.subscription_plans FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Authenticated users view plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Authenticated users view plan entitlements"
  ON public.subscription_plan_entitlements FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.subscription_plans p WHERE p.id = plan_id AND (p.is_active OR public.is_admin())));
DROP POLICY IF EXISTS "Admins manage plan entitlements" ON public.subscription_plan_entitlements;
CREATE POLICY "Admins manage plan entitlements"
  ON public.subscription_plan_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Merchants view own subscription entitlements"
  ON public.merchant_subscription_entitlements FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage merchant subscription entitlements" ON public.merchant_subscription_entitlements;
CREATE POLICY "Admins manage merchant subscription entitlements"
  ON public.merchant_subscription_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Merchants view own subscription invoices"
  ON public.subscription_invoices FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage subscription invoices" ON public.subscription_invoices;
CREATE POLICY "Admins manage subscription invoices"
  ON public.subscription_invoices FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Merchants view own usage counters"
  ON public.subscription_usage_counters FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage counters" ON public.subscription_usage_counters;
CREATE POLICY "Admins manage usage counters"
  ON public.subscription_usage_counters FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Merchants view own usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Merchants view own usage ledger"
  ON public.subscription_usage_ledger FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage usage ledger" ON public.subscription_usage_ledger;
CREATE POLICY "Admins manage usage ledger"
  ON public.subscription_usage_ledger FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.consume_subscription_usage(
  p_merchant_id uuid,
  p_feature_key text,
  p_quantity numeric,
  p_idempotency_key text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_source_type text DEFAULT 'application',
  p_source_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.merchant_subscriptions%ROWTYPE;
  v_plan_limit bigint;
  v_override_limit bigint;
  v_enabled boolean;
  v_used numeric(20,4);
  v_counter public.subscription_usage_counters%ROWTYPE;
  v_ledger_id uuid;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(trim(p_feature_key), '') IS NULL OR p_quantity IS NULL OR p_quantity <= 0 OR NULLIF(trim(p_idempotency_key), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid subscription usage request' USING ERRCODE = '22023';
  END IF;
  IF p_period_end <= p_period_start THEN
    RAISE EXCEPTION 'Usage period is invalid' USING ERRCODE = '22023';
  END IF;
  IF NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Subscription usage access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.merchant_subscriptions ms
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status IN ('ACTIVE', 'PAST_DUE')
    AND (ms.status = 'ACTIVE' OR ms.grace_period_until IS NULL OR ms.grace_period_until > now())
    AND (ms.expired_at IS NULL OR ms.expired_at > now())
  ORDER BY ms.current_period_end DESC NULLS LAST, ms.expired_at DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active subscription found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_subscription.id::text || ':' || p_feature_key || ':' || p_idempotency_key, 0));
  SELECT id, quantity INTO v_ledger_id, v_used
  FROM public.subscription_usage_ledger
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND idempotency_key = p_idempotency_key;
  IF v_ledger_id IS NOT NULL THEN
    RETURN jsonb_build_object('accepted', true, 'idempotent', true, 'ledger_id', v_ledger_id, 'quantity', v_used);
  END IF;

  SELECT spe.enabled, spe.limit_value INTO v_enabled, v_override_limit
  FROM public.merchant_subscription_entitlements spe
  WHERE spe.subscription_id = v_subscription.id
    AND spe.feature_key = p_feature_key
    AND spe.starts_at <= now()
    AND (spe.ends_at IS NULL OR spe.ends_at > now());
  IF NOT FOUND THEN
    SELECT spe.enabled, spe.limit_value INTO v_enabled, v_plan_limit
    FROM public.subscription_plan_entitlements spe
    WHERE spe.plan_id = v_subscription.plan_id AND spe.feature_key = p_feature_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Feature is not included in subscription' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF COALESCE(v_enabled, false) = false THEN
    RAISE EXCEPTION 'Feature is disabled for subscription' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.subscription_usage_counters(subscription_id, merchant_id, feature_key, period_start, period_end, limit_value)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_period_start, p_period_end, COALESCE(v_override_limit, v_plan_limit))
  ON CONFLICT (subscription_id, feature_key, period_start, period_end) DO NOTHING;
  SELECT * INTO v_counter
  FROM public.subscription_usage_counters
  WHERE subscription_id = v_subscription.id AND feature_key = p_feature_key AND period_start = p_period_start AND period_end = p_period_end
  FOR UPDATE;

  IF v_counter.limit_value IS NOT NULL AND v_counter.used_quantity + p_quantity > v_counter.limit_value THEN
    RAISE EXCEPTION 'Subscription usage limit exceeded' USING ERRCODE = '54000';
  END IF;

  UPDATE public.subscription_usage_counters
  SET used_quantity = used_quantity + p_quantity, updated_at = now()
  WHERE id = v_counter.id;
  INSERT INTO public.subscription_usage_ledger(subscription_id, merchant_id, feature_key, quantity, period_start, period_end, idempotency_key, source_type, source_id, metadata)
  VALUES (v_subscription.id, p_merchant_id, p_feature_key, p_quantity, p_period_start, p_period_end, p_idempotency_key, COALESCE(NULLIF(trim(p_source_type), ''), 'application'), p_source_id, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_ledger_id;

  RETURN jsonb_build_object('accepted', true, 'idempotent', false, 'ledger_id', v_ledger_id, 'used_quantity', v_counter.used_quantity + p_quantity, 'limit_value', v_counter.limit_value);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) TO authenticated, service_role;

-- Seed only the plan catalog; entitlements are intentionally explicit and can be managed by admin UI.
INSERT INTO public.subscription_plans (code, name, description, price, billing_interval, trial_days, sort_order)
VALUES
  ('free', 'Free', 'Operasi marketplace dasar', 0, 'monthly', 0, 10),
  ('starter', 'Starter', 'POS dan laporan operasional', 49000, 'monthly', 14, 20),
  ('growth', 'Growth', 'Inventaris, CRM, dan automation', 149000, 'monthly', 14, 30),
  ('pro', 'Pro', 'Multi-outlet, API, dan analytics lanjutan', 399000, 'monthly', 14, 40)
ON CONFLICT (code) DO NOTHING;

DROP TRIGGER IF EXISTS set_subscription_plans_updated_at ON public.subscription_plans;
CREATE TRIGGER set_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_plan_entitlements_updated_at ON public.subscription_plan_entitlements;
CREATE TRIGGER set_subscription_plan_entitlements_updated_at BEFORE UPDATE ON public.subscription_plan_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_merchant_subscription_entitlements_updated_at ON public.merchant_subscription_entitlements;
CREATE TRIGGER set_merchant_subscription_entitlements_updated_at BEFORE UPDATE ON public.merchant_subscription_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_invoices_updated_at ON public.subscription_invoices;
CREATE TRIGGER set_subscription_invoices_updated_at BEFORE UPDATE ON public.subscription_invoices
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS set_subscription_usage_counters_updated_at ON public.subscription_usage_counters;
CREATE TRIGGER set_subscription_usage_counters_updated_at BEFORE UPDATE ON public.subscription_usage_counters
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
