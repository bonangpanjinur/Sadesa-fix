-- Phase 1 completion slice:
-- package price history, subscription export, idempotent reactivation,
-- and auditable admin lifecycle actions.

CREATE TABLE IF NOT EXISTS public.pos_package_price_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid REFERENCES public.pos_packages(id) ON DELETE SET NULL,
  package_name text NOT NULL,
  description text,
  duration_months integer NOT NULL,
  price integer NOT NULL,
  is_active boolean NOT NULL,
  sort_order integer NOT NULL,
  change_type text NOT NULL CHECK (change_type IN ('INITIAL', 'UPDATE')),
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  change_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pos_package_price_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view POS package history" ON public.pos_package_price_history;
CREATE POLICY "Admins can view POS package history"
  ON public.pos_package_price_history FOR SELECT
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_pos_package_price_history_package
  ON public.pos_package_price_history(package_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.record_pos_package_price_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR OLD.name IS DISTINCT FROM NEW.name
     OR OLD.description IS DISTINCT FROM NEW.description
     OR OLD.duration_months IS DISTINCT FROM NEW.duration_months
     OR OLD.price IS DISTINCT FROM NEW.price
     OR OLD.is_active IS DISTINCT FROM NEW.is_active
     OR OLD.sort_order IS DISTINCT FROM NEW.sort_order THEN
    INSERT INTO public.pos_package_price_history (
      package_id,
      package_name,
      description,
      duration_months,
      price,
      is_active,
      sort_order,
      change_type,
       changed_by,
       change_reason
    )
    VALUES (
      NEW.id,
      NEW.name,
      NEW.description,
      NEW.duration_months,
      NEW.price,
      NEW.is_active,
      NEW.sort_order,
       CASE WHEN TG_OP = 'INSERT' THEN 'INITIAL' ELSE 'UPDATE' END,
       auth.uid(),
       NULLIF(current_setting('app.pos_package_change_reason', true), '')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_pos_package_price_history ON public.pos_packages;
CREATE TRIGGER trg_record_pos_package_price_history
AFTER INSERT OR UPDATE ON public.pos_packages
FOR EACH ROW
EXECUTE FUNCTION public.record_pos_package_price_history();

-- Backfill the current package state once for packages created before this
-- history table existed. The NOT EXISTS guard keeps the migration rerunnable.
INSERT INTO public.pos_package_price_history (
  package_id,
  package_name,
  description,
  duration_months,
  price,
  is_active,
  sort_order,
  change_type
)
SELECT p.id, p.name, p.description, p.duration_months, p.price, p.is_active, p.sort_order, 'INITIAL'
FROM public.pos_packages p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.pos_package_price_history h
  WHERE h.package_id = p.id
);

CREATE OR REPLACE FUNCTION public.get_pos_package_history(p_limit integer DEFAULT 200)
RETURNS TABLE (
  id uuid,
  package_id uuid,
  package_name text,
  description text,
  duration_months integer,
  price integer,
  is_active boolean,
  sort_order integer,
  change_type text,
  changed_by uuid,
  change_reason text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    h.id,
    h.package_id,
    h.package_name,
    h.description,
    h.duration_months,
    h.price,
    h.is_active,
    h.sort_order,
    h.change_type,
    h.changed_by,
    h.change_reason,
    h.created_at
  FROM public.pos_package_price_history h
  WHERE public.is_admin()
  ORDER BY h.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500);
$$;

REVOKE ALL ON FUNCTION public.get_pos_package_history(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_package_history(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_pos_package(
  p_package_id uuid,
  p_name text,
  p_description text,
  p_duration_months integer,
  p_price integer,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before public.pos_packages%ROWTYPE;
  v_after public.pos_packages%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can update POS packages' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION 'Package name and change reason are required' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_duration_months, 0) < 1 OR COALESCE(p_price, -1) < 0 THEN
    RAISE EXCEPTION 'Package duration and price are invalid' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_before
  FROM public.pos_packages
  WHERE id = p_package_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS package not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.pos_package_change_reason', v_reason, true);
  UPDATE public.pos_packages
  SET name = trim(p_name),
      description = NULLIF(trim(COALESCE(p_description, '')), ''),
      duration_months = p_duration_months,
      price = p_price
  WHERE id = p_package_id;

  SELECT * INTO v_after
  FROM public.pos_packages
  WHERE id = p_package_id;

  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  )
  VALUES (
    auth.uid(),
    'UPDATE_POS_PACKAGE',
    'pos_package',
    p_package_id,
    to_jsonb(v_before),
    to_jsonb(v_after) || jsonb_build_object('reason', v_reason)
  );

  RETURN to_jsonb(v_after);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_pos_package(uuid, text, text, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_pos_package(uuid, text, text, integer, integer, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.export_pos_subscription_data(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_owner boolean;
  v_is_admin boolean;
  v_subscriptions jsonb;
BEGIN
  v_is_owner := EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.id = p_merchant_id
      AND m.user_id = auth.uid()
  );
  v_is_admin := public.is_admin();

  IF auth.uid() IS NULL OR (NOT v_is_owner AND NOT v_is_admin) THEN
    RAISE EXCEPTION 'Subscription export access denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      to_jsonb(s) || jsonb_build_object(
        'package',
        CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'description', p.description,
          'duration_months', p.duration_months,
          'price', p.price
        ) END
      )
      ORDER BY s.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_subscriptions
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_packages p ON p.id = s.package_id
  WHERE s.merchant_id = p_merchant_id;

  RETURN jsonb_build_object(
    'export_version', 1,
    'exported_at', now(),
    'merchant_id', p_merchant_id,
    'subscriptions', v_subscriptions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.export_pos_subscription_data(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_pos_subscription_data(uuid) TO authenticated;

-- Extend the existing lifecycle RPC without changing its call contract:
-- the new reason parameter is optional for existing clients.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_current public.pos_subscriptions%ROWTYPE;
  v_duration_months integer;
  v_started_at timestamptz;
  v_expired_at timestamptz;
  v_action text := upper(trim(p_action));
  v_reason text := NULLIF(trim(COALESCE(p_reason, p_rejection_reason)), '');
  v_result jsonb;
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

  -- Repeating approval/reactivation on an already operational subscription
  -- must not reset its clock or create a second workspace.
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
    admin_id,
    action,
    entity_type,
    entity_id,
    old_value,
    new_value
  )
  VALUES (
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

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text, text) TO authenticated;

-- Preserve the four-argument RPC used by older clients while routing it
-- through the audited implementation above.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
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

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;