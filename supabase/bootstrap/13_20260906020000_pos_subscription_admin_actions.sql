-- Atomic admin actions for POS subscriptions and the merchant POS feature gate.

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
    RAISE EXCEPTION 'Only admins can manage POS subscriptions'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;

  v_duration_months := COALESCE(v_duration_months, 1);

  IF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at IS NOT NULL
       AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
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
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'active',
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED',
        payment_status = 'UNPAID',
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'suspended',
        is_active = false,
        suspended_at = now(),
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED',
        payment_status = 'CANCELLED',
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'cancelled',
        is_active = false,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(NULLIF(trim(p_rejection_reason), ''), 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action
      USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object(
    'subscription', to_jsonb(s),
    'tenant', to_jsonb(t)
  )
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;