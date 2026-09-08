-- Safe repair bundle for the Admin POS subscription and partner-promotion flows.
-- Apply after the base POS bootstrap (bundles 13-19). Every statement is
-- idempotent so this file can be pasted into the Supabase SQL editor again.

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
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
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
    SELECT 1
    FROM public.merchants m
    WHERE m.id = merchant_id AND m.user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Admins view promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Admins view promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (is_admin());

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS original_amount INTEGER,
  ADD COLUMN IF NOT EXISTS discount_amount INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promotion_id UUID,
  ADD COLUMN IF NOT EXISTS promotion_code TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.pos_subscriptions'::regclass
      AND conname = 'pos_subscriptions_promotion_id_fkey'
  ) THEN
    ALTER TABLE public.pos_subscriptions
      ADD CONSTRAINT pos_subscriptions_promotion_id_fkey
      FOREIGN KEY (promotion_id)
      REFERENCES public.pos_onboarding_promotions(id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_promotion_id
  ON public.pos_subscriptions(promotion_id);

CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id UUID,
  p_action TEXT,
  p_extension_months INTEGER DEFAULT 1,
  p_rejection_reason TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_current public.pos_subscriptions%ROWTYPE;
  v_duration_months INTEGER;
  v_started_at TIMESTAMPTZ;
  v_expired_at TIMESTAMPTZ;
  v_action TEXT := upper(trim(p_action));
  v_reason TEXT := NULLIF(trim(COALESCE(p_reason, p_rejection_reason)), '');
  v_result JSONB;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
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

  IF v_action IN ('APPROVE', 'REACTIVATE')
     AND v_subscription.status = 'ACTIVE'
     AND v_subscription.started_at IS NOT NULL
     AND v_subscription.expired_at > now()
     AND (v_subscription.grace_ends_at IS NULL OR v_subscription.grace_ends_at > now()) THEN
    NULL;
  ELSIF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
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
        rejection_reason = COALESCE(v_reason, 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_current
  FROM public.pos_subscriptions
  WHERE id = v_subscription.id;

  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  ) VALUES (
    auth.uid(),
    'POS_SUBSCRIPTION_' || v_action,
    'pos_subscription',
    v_subscription.id,
    to_jsonb(v_subscription),
    to_jsonb(v_current) || jsonb_build_object('reason', v_reason)
  );

  SELECT jsonb_build_object('subscription', to_jsonb(s), 'tenant', to_jsonb(t))
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id UUID,
  p_action TEXT,
  p_extension_months INTEGER DEFAULT 1,
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.admin_manage_pos_subscription(
    p_subscription_id,
    p_action,
    p_extension_months,
    p_rejection_reason,
    NULL
  );
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT)
  TO authenticated;

-- Supabase/PostgREST normally reloads after DDL; this makes the refresh
-- explicit so the new table and RPC are immediately visible to the SPA.
NOTIFY pgrst, 'reload schema';