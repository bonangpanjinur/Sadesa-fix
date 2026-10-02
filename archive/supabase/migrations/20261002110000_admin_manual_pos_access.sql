-- Allow admins to grant POS access directly to a selected merchant account.
-- This is intentionally separate from payment approval so an admin can provision
-- a merchant without requiring a subscription request or payment proof.

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
  v_old jsonb;
  v_started_at timestamptz := now();
  v_expired_at timestamptz;
  v_duration integer;
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can grant POS access' USING ERRCODE = '42501';
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
        status = 'ACTIVE',
        payment_amount = 0,
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        grace_ends_at = NULL,
        approved_by = auth.uid(),
        approved_at = v_started_at,
        rejection_reason = NULL,
        is_trial = true,
        updated_at = v_started_at
    WHERE id = v_subscription.id
    RETURNING * INTO v_subscription;
  END IF;

  UPDATE public.pos_tenants
  SET status = CASE WHEN status = 'suspended' THEN 'active' ELSE status END,
      is_active = true,
      activated_at = COALESCE(activated_at, v_started_at),
      suspended_at = NULL,
      updated_at = v_started_at
  WHERE merchant_id = p_merchant_id;

  INSERT INTO public.admin_audit_logs (admin_id, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    auth.uid(),
    'POS_ACCESS_MANUAL_GRANT',
    'merchant',
    p_merchant_id,
    v_old,
    jsonb_build_object(
      'subscription', to_jsonb(v_subscription),
      'package_id', p_package_id,
      'duration_months', v_duration,
      'reason', v_reason
    )
  );

  RETURN jsonb_build_object(
    'merchant_id', p_merchant_id,
    'subscription_id', v_subscription.id,
    'status', v_subscription.status,
    'started_at', v_subscription.started_at,
    'expired_at', v_subscription.expired_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_grant_pos_access(uuid, uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_pos_access(uuid, uuid, integer, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
