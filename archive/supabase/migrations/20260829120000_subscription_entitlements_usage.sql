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
)$bootstrap_sql_59da677d0c06$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59da677d0c06$;

DO $bootstrap_do_a1a515a4efd5$
BEGIN
  EXECUTE $bootstrap_sql_a1a515a4efd5$ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.subscription_plans(id),
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz$bootstrap_sql_a1a515a4efd5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1a515a4efd5$;

DO $bootstrap_do_1bf1d084ce58$
BEGIN
  EXECUTE $bootstrap_sql_1bf1d084ce58$CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_plan ON public.merchant_subscriptions(plan_id)$bootstrap_sql_1bf1d084ce58$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1bf1d084ce58$;

DO $bootstrap_do_05f233577cec$
BEGIN
  EXECUTE $bootstrap_sql_05f233577cec$CREATE INDEX IF NOT EXISTS idx_merchant_subscriptions_active_merchant
  ON public.merchant_subscriptions(merchant_id, status, expired_at DESC)$bootstrap_sql_05f233577cec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05f233577cec$;

DO $bootstrap_do_f184f4f3a377$
BEGIN
  EXECUTE $bootstrap_sql_f184f4f3a377$CREATE TABLE IF NOT EXISTS public.subscription_plan_entitlements (
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
)$bootstrap_sql_f184f4f3a377$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f184f4f3a377$;

DO $bootstrap_do_e3760f366675$
BEGIN
  EXECUTE $bootstrap_sql_e3760f366675$CREATE TABLE IF NOT EXISTS public.merchant_subscription_entitlements (
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
)$bootstrap_sql_e3760f366675$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e3760f366675$;

DO $bootstrap_do_5d4b05428d7e$
BEGIN
  EXECUTE $bootstrap_sql_5d4b05428d7e$CREATE INDEX IF NOT EXISTS idx_merchant_entitlements_active
  ON public.merchant_subscription_entitlements(subscription_id, feature_key, starts_at, ends_at)$bootstrap_sql_5d4b05428d7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d4b05428d7e$;

DO $bootstrap_do_8f19e23b6760$
BEGIN
  EXECUTE $bootstrap_sql_8f19e23b6760$CREATE TABLE IF NOT EXISTS public.subscription_invoices (
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
)$bootstrap_sql_8f19e23b6760$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8f19e23b6760$;

DO $bootstrap_do_67f141283f02$
BEGIN
  EXECUTE $bootstrap_sql_67f141283f02$CREATE INDEX IF NOT EXISTS idx_subscription_invoices_subscription
  ON public.subscription_invoices(subscription_id, created_at DESC)$bootstrap_sql_67f141283f02$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67f141283f02$;

DO $bootstrap_do_d0ff4a518fa4$
BEGIN
  EXECUTE $bootstrap_sql_d0ff4a518fa4$CREATE TABLE IF NOT EXISTS public.subscription_usage_counters (
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
)$bootstrap_sql_d0ff4a518fa4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d0ff4a518fa4$;

DO $bootstrap_do_39af6abd040e$
BEGIN
  EXECUTE $bootstrap_sql_39af6abd040e$CREATE INDEX IF NOT EXISTS idx_usage_counters_merchant_period
  ON public.subscription_usage_counters(merchant_id, feature_key, period_start, period_end)$bootstrap_sql_39af6abd040e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39af6abd040e$;

DO $bootstrap_do_d0344ac2c09a$
BEGIN
  EXECUTE $bootstrap_sql_d0344ac2c09a$CREATE TABLE IF NOT EXISTS public.subscription_usage_ledger (
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
)$bootstrap_sql_d0344ac2c09a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d0344ac2c09a$;

DO $bootstrap_do_44d5a1e8d9f7$
BEGIN
  EXECUTE $bootstrap_sql_44d5a1e8d9f7$CREATE INDEX IF NOT EXISTS idx_usage_ledger_merchant_created
  ON public.subscription_usage_ledger(merchant_id, created_at DESC)$bootstrap_sql_44d5a1e8d9f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44d5a1e8d9f7$;

DO $bootstrap_do_2c0d9d9325e3$
BEGIN
  EXECUTE $bootstrap_sql_2c0d9d9325e3$CREATE INDEX IF NOT EXISTS idx_usage_ledger_feature_period
  ON public.subscription_usage_ledger(subscription_id, feature_key, period_start, period_end, created_at DESC)$bootstrap_sql_2c0d9d9325e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c0d9d9325e3$;

DO $bootstrap_do_d19a242f9f38$
BEGIN
  EXECUTE $bootstrap_sql_d19a242f9f38$ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY$bootstrap_sql_d19a242f9f38$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d19a242f9f38$;

DO $bootstrap_do_f3465dc0a9c9$
BEGIN
  EXECUTE $bootstrap_sql_f3465dc0a9c9$ALTER TABLE public.subscription_plan_entitlements ENABLE ROW LEVEL SECURITY$bootstrap_sql_f3465dc0a9c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3465dc0a9c9$;

DO $bootstrap_do_a207f62b384d$
BEGIN
  EXECUTE $bootstrap_sql_a207f62b384d$ALTER TABLE public.merchant_subscription_entitlements ENABLE ROW LEVEL SECURITY$bootstrap_sql_a207f62b384d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a207f62b384d$;

DO $bootstrap_do_90a087b20b13$
BEGIN
  EXECUTE $bootstrap_sql_90a087b20b13$ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY$bootstrap_sql_90a087b20b13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90a087b20b13$;

DO $bootstrap_do_a8451c01f9a6$
BEGIN
  EXECUTE $bootstrap_sql_a8451c01f9a6$ALTER TABLE public.subscription_usage_counters ENABLE ROW LEVEL SECURITY$bootstrap_sql_a8451c01f9a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a8451c01f9a6$;

DO $bootstrap_do_e8c0755c146e$
BEGIN
  EXECUTE $bootstrap_sql_e8c0755c146e$ALTER TABLE public.subscription_usage_ledger ENABLE ROW LEVEL SECURITY$bootstrap_sql_e8c0755c146e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8c0755c146e$;

DO $bootstrap_do_75eb74bf440b$
BEGIN
  EXECUTE $bootstrap_sql_75eb74bf440b$DROP POLICY IF EXISTS "Authenticated users view active subscription plans" ON public.subscription_plans$bootstrap_sql_75eb74bf440b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75eb74bf440b$;

DO $bootstrap_do_ae15a7e88370$
BEGIN
  EXECUTE $bootstrap_sql_ae15a7e88370$CREATE POLICY "Authenticated users view active subscription plans"
  ON public.subscription_plans FOR SELECT TO authenticated
  USING (is_active OR public.is_admin())$bootstrap_sql_ae15a7e88370$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae15a7e88370$;

DO $bootstrap_do_b54f209a6091$
BEGIN
  EXECUTE $bootstrap_sql_b54f209a6091$DROP POLICY IF EXISTS "Admins manage subscription plans" ON public.subscription_plans$bootstrap_sql_b54f209a6091$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b54f209a6091$;

DO $bootstrap_do_9c48b0736dcf$
BEGIN
  EXECUTE $bootstrap_sql_9c48b0736dcf$CREATE POLICY "Admins manage subscription plans"
  ON public.subscription_plans FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_9c48b0736dcf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9c48b0736dcf$;

DO $bootstrap_do_17c524123c71$
BEGIN
  EXECUTE $bootstrap_sql_17c524123c71$DROP POLICY IF EXISTS "Authenticated users view plan entitlements" ON public.subscription_plan_entitlements$bootstrap_sql_17c524123c71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17c524123c71$;

DO $bootstrap_do_52c04a3512f0$
BEGIN
  EXECUTE $bootstrap_sql_52c04a3512f0$CREATE POLICY "Authenticated users view plan entitlements"
  ON public.subscription_plan_entitlements FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.subscription_plans p WHERE p.id = plan_id AND (p.is_active OR public.is_admin())))$bootstrap_sql_52c04a3512f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52c04a3512f0$;

DO $bootstrap_do_6287bb8546e6$
BEGIN
  EXECUTE $bootstrap_sql_6287bb8546e6$DROP POLICY IF EXISTS "Admins manage plan entitlements" ON public.subscription_plan_entitlements$bootstrap_sql_6287bb8546e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6287bb8546e6$;

DO $bootstrap_do_5e72b6f53f45$
BEGIN
  EXECUTE $bootstrap_sql_5e72b6f53f45$CREATE POLICY "Admins manage plan entitlements"
  ON public.subscription_plan_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_5e72b6f53f45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e72b6f53f45$;

DO $bootstrap_do_422215616f2a$
BEGIN
  EXECUTE $bootstrap_sql_422215616f2a$DROP POLICY IF EXISTS "Merchants view own subscription entitlements" ON public.merchant_subscription_entitlements$bootstrap_sql_422215616f2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_422215616f2a$;

DO $bootstrap_do_9183e8b5cec4$
BEGIN
  EXECUTE $bootstrap_sql_9183e8b5cec4$CREATE POLICY "Merchants view own subscription entitlements"
  ON public.merchant_subscription_entitlements FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_9183e8b5cec4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9183e8b5cec4$;

DO $bootstrap_do_62b1a49ff7ab$
BEGIN
  EXECUTE $bootstrap_sql_62b1a49ff7ab$DROP POLICY IF EXISTS "Admins manage merchant subscription entitlements" ON public.merchant_subscription_entitlements$bootstrap_sql_62b1a49ff7ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_62b1a49ff7ab$;

DO $bootstrap_do_9a28d9e9cec3$
BEGIN
  EXECUTE $bootstrap_sql_9a28d9e9cec3$CREATE POLICY "Admins manage merchant subscription entitlements"
  ON public.merchant_subscription_entitlements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_9a28d9e9cec3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a28d9e9cec3$;

DO $bootstrap_do_8a3d75f056af$
BEGIN
  EXECUTE $bootstrap_sql_8a3d75f056af$DROP POLICY IF EXISTS "Merchants view own subscription invoices" ON public.subscription_invoices$bootstrap_sql_8a3d75f056af$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a3d75f056af$;

DO $bootstrap_do_70fc19e77281$
BEGIN
  EXECUTE $bootstrap_sql_70fc19e77281$CREATE POLICY "Merchants view own subscription invoices"
  ON public.subscription_invoices FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_70fc19e77281$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70fc19e77281$;

DO $bootstrap_do_7adbb9466b41$
BEGIN
  EXECUTE $bootstrap_sql_7adbb9466b41$DROP POLICY IF EXISTS "Admins manage subscription invoices" ON public.subscription_invoices$bootstrap_sql_7adbb9466b41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7adbb9466b41$;

DO $bootstrap_do_5fa514ef616a$
BEGIN
  EXECUTE $bootstrap_sql_5fa514ef616a$CREATE POLICY "Admins manage subscription invoices"
  ON public.subscription_invoices FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_5fa514ef616a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fa514ef616a$;

DO $bootstrap_do_a40e2dc28396$
BEGIN
  EXECUTE $bootstrap_sql_a40e2dc28396$DROP POLICY IF EXISTS "Merchants view own usage counters" ON public.subscription_usage_counters$bootstrap_sql_a40e2dc28396$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a40e2dc28396$;

DO $bootstrap_do_45755f774ea2$
BEGIN
  EXECUTE $bootstrap_sql_45755f774ea2$CREATE POLICY "Merchants view own usage counters"
  ON public.subscription_usage_counters FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_45755f774ea2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45755f774ea2$;

DO $bootstrap_do_fd7c21cdf858$
BEGIN
  EXECUTE $bootstrap_sql_fd7c21cdf858$DROP POLICY IF EXISTS "Admins manage usage counters" ON public.subscription_usage_counters$bootstrap_sql_fd7c21cdf858$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd7c21cdf858$;

DO $bootstrap_do_aa9e7cec2e19$
BEGIN
  EXECUTE $bootstrap_sql_aa9e7cec2e19$CREATE POLICY "Admins manage usage counters"
  ON public.subscription_usage_counters FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_aa9e7cec2e19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa9e7cec2e19$;

DO $bootstrap_do_ff1631ef79e3$
BEGIN
  EXECUTE $bootstrap_sql_ff1631ef79e3$DROP POLICY IF EXISTS "Merchants view own usage ledger" ON public.subscription_usage_ledger$bootstrap_sql_ff1631ef79e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff1631ef79e3$;

DO $bootstrap_do_c85c11ccf107$
BEGIN
  EXECUTE $bootstrap_sql_c85c11ccf107$CREATE POLICY "Merchants view own usage ledger"
  ON public.subscription_usage_ledger FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_c85c11ccf107$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c85c11ccf107$;

DO $bootstrap_do_966389d8cf2f$
BEGIN
  EXECUTE $bootstrap_sql_966389d8cf2f$DROP POLICY IF EXISTS "Admins manage usage ledger" ON public.subscription_usage_ledger$bootstrap_sql_966389d8cf2f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_966389d8cf2f$;

DO $bootstrap_do_30c2830a3563$
BEGIN
  EXECUTE $bootstrap_sql_30c2830a3563$CREATE POLICY "Admins manage usage ledger"
  ON public.subscription_usage_ledger FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_30c2830a3563$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_30c2830a3563$;

DO $bootstrap_do_92bf8d407902$
BEGIN
  EXECUTE $bootstrap_sql_92bf8d407902$CREATE OR REPLACE FUNCTION public.consume_subscription_usage(
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
  IF auth.role() <> 'service_role' AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid())) THEN
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
$$$bootstrap_sql_92bf8d407902$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92bf8d407902$;

DO $bootstrap_do_c0bbc2bff381$
BEGIN
  EXECUTE $bootstrap_sql_c0bbc2bff381$REVOKE ALL ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) FROM PUBLIC, anon, authenticated$bootstrap_sql_c0bbc2bff381$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0bbc2bff381$;

DO $bootstrap_do_6b39d9fd9c2a$
BEGIN
  EXECUTE $bootstrap_sql_6b39d9fd9c2a$GRANT EXECUTE ON FUNCTION public.consume_subscription_usage(uuid, text, numeric, text, timestamptz, timestamptz, text, text, jsonb) TO authenticated, service_role$bootstrap_sql_6b39d9fd9c2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b39d9fd9c2a$;

DO $bootstrap_do_9e874c3e3a2e$
BEGIN
  EXECUTE $bootstrap_sql_9e874c3e3a2e$-- Seed only the plan catalog; entitlements are intentionally explicit and can be managed by admin UI.
INSERT INTO public.subscription_plans (code, name, description, price, billing_interval, trial_days, sort_order)
VALUES
  ('free', 'Free', 'Operasi marketplace dasar', 0, 'monthly', 0, 10),
  ('starter', 'Starter', 'POS dan laporan operasional', 49000, 'monthly', 14, 20),
  ('growth', 'Growth', 'Inventaris, CRM, dan automation', 149000, 'monthly', 14, 30),
  ('pro', 'Pro', 'Multi-outlet, API, dan analytics lanjutan', 399000, 'monthly', 14, 40)
ON CONFLICT (code) DO NOTHING$bootstrap_sql_9e874c3e3a2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e874c3e3a2e$;

DO $bootstrap_do_e323abb508e9$
BEGIN
  EXECUTE $bootstrap_sql_e323abb508e9$DROP TRIGGER IF EXISTS set_subscription_plans_updated_at ON public.subscription_plans$bootstrap_sql_e323abb508e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e323abb508e9$;

DO $bootstrap_do_33d6d4dfdb74$
BEGIN
  EXECUTE $bootstrap_sql_33d6d4dfdb74$CREATE TRIGGER set_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_33d6d4dfdb74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33d6d4dfdb74$;

DO $bootstrap_do_ed89af96cd62$
BEGIN
  EXECUTE $bootstrap_sql_ed89af96cd62$DROP TRIGGER IF EXISTS set_subscription_plan_entitlements_updated_at ON public.subscription_plan_entitlements$bootstrap_sql_ed89af96cd62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed89af96cd62$;

DO $bootstrap_do_fa270e3ab3b6$
BEGIN
  EXECUTE $bootstrap_sql_fa270e3ab3b6$CREATE TRIGGER set_subscription_plan_entitlements_updated_at BEFORE UPDATE ON public.subscription_plan_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_fa270e3ab3b6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa270e3ab3b6$;

DO $bootstrap_do_7cfc8acbf916$
BEGIN
  EXECUTE $bootstrap_sql_7cfc8acbf916$DROP TRIGGER IF EXISTS set_merchant_subscription_entitlements_updated_at ON public.merchant_subscription_entitlements$bootstrap_sql_7cfc8acbf916$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cfc8acbf916$;

DO $bootstrap_do_c2f8605882db$
BEGIN
  EXECUTE $bootstrap_sql_c2f8605882db$CREATE TRIGGER set_merchant_subscription_entitlements_updated_at BEFORE UPDATE ON public.merchant_subscription_entitlements
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_c2f8605882db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2f8605882db$;

DO $bootstrap_do_8139a82146a3$
BEGIN
  EXECUTE $bootstrap_sql_8139a82146a3$DROP TRIGGER IF EXISTS set_subscription_invoices_updated_at ON public.subscription_invoices$bootstrap_sql_8139a82146a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8139a82146a3$;

DO $bootstrap_do_b276ccda1c23$
BEGIN
  EXECUTE $bootstrap_sql_b276ccda1c23$CREATE TRIGGER set_subscription_invoices_updated_at BEFORE UPDATE ON public.subscription_invoices
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_b276ccda1c23$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b276ccda1c23$;

DO $bootstrap_do_5ef46bf38f20$
BEGIN
  EXECUTE $bootstrap_sql_5ef46bf38f20$DROP TRIGGER IF EXISTS set_subscription_usage_counters_updated_at ON public.subscription_usage_counters$bootstrap_sql_5ef46bf38f20$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ef46bf38f20$;

DO $bootstrap_do_3e51ab9660fa$
BEGIN
  EXECUTE $bootstrap_sql_3e51ab9660fa$CREATE TRIGGER set_subscription_usage_counters_updated_at BEFORE UPDATE ON public.subscription_usage_counters
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_3e51ab9660fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e51ab9660fa$;

DO $bootstrap_do_bdfbd81df3d6$
BEGIN
  EXECUTE $bootstrap_sql_bdfbd81df3d6$
