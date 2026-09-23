-- Record the public IP observed during authenticated PWA device registration.
-- This is an audit signal, not a permanent identity or precise location.
ALTER TABLE public.pwa_device_sessions
  ADD COLUMN IF NOT EXISTS ip_address inet;

CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_ip_last_seen
  ON public.pwa_device_sessions(ip_address, last_seen_at DESC)
  WHERE ip_address IS NOT NULL;

COMMENT ON COLUMN public.pwa_device_sessions.ip_address IS
  'Public IP observed by the application during device registration; may change and must not be treated as a unique identity.';

-- Keep the original six-argument RPC compatible while adding a seven-argument
-- version for clients that can provide the observed public IP.
CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_ip_address inet DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_device public.pwa_device_sessions%ROWTYPE;
  v_merchant_id uuid;
  v_entitlement jsonb;
  v_limit bigint;
  v_active_devices bigint;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true)
    OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pwa-device:' || auth.uid()::text, 0));
  SELECT * INTO v_device
  FROM public.pwa_device_sessions
  WHERE user_id = auth.uid() AND device_id = trim(p_device_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    SELECT m.id INTO v_merchant_id FROM public.merchants m WHERE m.user_id = auth.uid() LIMIT 1;
    SELECT count(*) INTO v_active_devices
    FROM public.pwa_device_sessions
    WHERE user_id = auth.uid() AND status <> 'revoked';
    v_limit := 1;
    IF v_merchant_id IS NOT NULL THEN
      v_entitlement := public.get_subscription_entitlement(v_merchant_id, 'pos_devices');
      IF COALESCE((v_entitlement->>'subscription_id') IS NOT NULL, false) THEN
        IF COALESCE((v_entitlement->>'enabled')::boolean, false) = false THEN
          RAISE EXCEPTION 'POS device feature is not included in active subscription' USING ERRCODE = '42501';
        END IF;
        v_limit := NULLIF((v_entitlement->>'limit_value')::bigint, 0);
      END IF;
    END IF;
    IF v_limit IS NOT NULL AND v_active_devices >= v_limit THEN
      RAISE EXCEPTION 'POS device limit exceeded' USING ERRCODE = '54000';
    END IF;
  END IF;

  INSERT INTO public.pwa_device_sessions(
    user_id, tenant_id, device_id, device_name, device_type, platform,
    user_agent, ip_address, status, last_seen_at, revoked_at, revoked_by
  )
  VALUES (
    auth.uid(), p_tenant_id, trim(p_device_id),
    COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'),
    p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''),
    p_ip_address, 'active', now(), NULL, NULL
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    tenant_id = EXCLUDED.tenant_id,
    device_name = EXCLUDED.device_name,
    device_type = EXCLUDED.device_type,
    platform = EXCLUDED.platform,
    user_agent = EXCLUDED.user_agent,
    ip_address = COALESCE(EXCLUDED.ip_address, public.pwa_device_sessions.ip_address),
    status = 'active',
    last_seen_at = now(),
    revoked_at = NULL,
    revoked_by = NULL,
    updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END;
$$;

REVOKE ALL ON FUNCTION public.register_pwa_device(text, text, text, text, text, inet, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_pwa_device(text, text, text, text, text, inet, uuid) TO authenticated;
COMMENT ON FUNCTION public.register_pwa_device(text, text, text, text, text, inet, uuid) IS
  'Register an authenticated PWA device and record the observed public IP for security audit signals.';
