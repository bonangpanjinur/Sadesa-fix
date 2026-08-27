CREATE TABLE IF NOT EXISTS public.pwa_device_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT 'Perangkat PWA',
  device_type text NOT NULL DEFAULT 'browser' CHECK (device_type IN ('browser','pwa','kiosk')),
  platform text,
  user_agent text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','idle','revoked')),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  last_sync_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_user ON public.pwa_device_sessions(user_id, status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_pwa_device_sessions_tenant ON public.pwa_device_sessions(tenant_id, status, last_seen_at DESC);
ALTER TABLE public.pwa_device_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Users view own PWA devices" ON public.pwa_device_sessions FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Admins manage PWA devices" ON public.pwa_device_sessions;
CREATE POLICY "Admins manage PWA devices" ON public.pwa_device_sessions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.register_pwa_device(
  p_device_id text,
  p_device_name text DEFAULT 'Perangkat PWA',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser','pwa','kiosk') THEN
    RAISE EXCEPTION 'Invalid PWA device registration' USING ERRCODE = '22023';
  END IF;
  IF p_tenant_id IS NOT NULL AND NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.pos_users pu WHERE pu.tenant_id = p_tenant_id AND pu.user_id = auth.uid() AND pu.is_active = true) OR EXISTS (SELECT 1 FROM public.pos_tenants t WHERE t.id = p_tenant_id AND t.user_id = auth.uid())) THEN
    RAISE EXCEPTION 'Device tenant access denied' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pwa_device_sessions(user_id, tenant_id, device_id, device_name, device_type, platform, user_agent, status, last_seen_at, revoked_at, revoked_by)
  VALUES (auth.uid(), p_tenant_id, trim(p_device_id), COALESCE(NULLIF(trim(p_device_name), ''), 'Perangkat PWA'), p_device_type, NULLIF(trim(p_platform), ''), NULLIF(left(p_user_agent, 500), ''), 'active', now(), NULL, NULL)
  ON CONFLICT (user_id, device_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, platform = EXCLUDED.platform, user_agent = EXCLUDED.user_agent, status = 'active', last_seen_at = now(), revoked_at = NULL, revoked_by = NULL, updated_at = now()
  RETURNING * INTO v_device;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.heartbeat_pwa_device(p_device_id text, p_sync_at timestamptz DEFAULT NULL)
RETURNS public.pwa_device_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_device public.pwa_device_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_device FROM public.pwa_device_sessions WHERE user_id = auth.uid() AND device_id = trim(p_device_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'PWA device is not registered' USING ERRCODE = 'P0002'; END IF;
  IF v_device.status <> 'revoked' THEN
    UPDATE public.pwa_device_sessions SET status = 'active', last_seen_at = now(), last_sync_at = COALESCE(p_sync_at, last_sync_at), updated_at = now() WHERE id = v_device.id RETURNING * INTO v_device;
  END IF;
  RETURN v_device;
END; $$;

CREATE OR REPLACE FUNCTION public.revoke_pwa_device(p_device_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Device revoke requires admin access' USING ERRCODE = '42501'; END IF;
  UPDATE public.pwa_device_sessions SET status = 'revoked', revoked_at = now(), revoked_by = auth.uid(), updated_at = now() WHERE id = p_device_session_id AND status <> 'revoked';
  IF NOT FOUND THEN RAISE EXCEPTION 'Device not found or already revoked' USING ERRCODE = 'P0002'; END IF;
  RETURN jsonb_build_object('device_id', p_device_session_id, 'status', 'revoked');
END; $$;

REVOKE ALL ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_pwa_device(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_pwa_device(text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.heartbeat_pwa_device(text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_pwa_device(uuid) TO authenticated;
