-- Admin-only login activity and active-device registry.
CREATE TABLE IF NOT EXISTS public.admin_login_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT 'Browser',
  device_type text NOT NULL DEFAULT 'browser' CHECK (device_type IN ('browser', 'pwa')),
  platform text,
  user_agent text,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  login_count integer NOT NULL DEFAULT 1 CHECK (login_count > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_admin_login_activity_last_seen
  ON public.admin_login_activity(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_login_activity_user
  ON public.admin_login_activity(user_id, last_seen_at DESC);
ALTER TABLE public.admin_login_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins view login activity" ON public.admin_login_activity;
CREATE POLICY "Admins view login activity" ON public.admin_login_activity
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.record_admin_login_activity(
  p_device_id text,
  p_device_name text DEFAULT 'Browser',
  p_device_type text DEFAULT 'browser',
  p_platform text DEFAULT NULL,
  p_user_agent text DEFAULT NULL
)
RETURNS public.admin_login_activity
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_activity public.admin_login_activity%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN NULL;
  END IF;
  IF NULLIF(trim(p_device_id), '') IS NULL OR p_device_type NOT IN ('browser', 'pwa') THEN
    RAISE EXCEPTION 'Invalid admin login activity payload' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.admin_login_activity(user_id, device_id, device_name, device_type, platform, user_agent)
  VALUES (
    auth.uid(), trim(p_device_id), COALESCE(NULLIF(left(trim(p_device_name), 120), ''), 'Browser'),
    p_device_type, NULLIF(left(trim(p_platform), 120), ''), NULLIF(left(p_user_agent, 500), '')
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    device_name = EXCLUDED.device_name,
    device_type = EXCLUDED.device_type,
    platform = EXCLUDED.platform,
    user_agent = EXCLUDED.user_agent,
    last_seen_at = now(),
    login_count = public.admin_login_activity.login_count + 1,
    updated_at = now()
  RETURNING * INTO v_activity;
  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_admin_login_activity(p_device_id text)
RETURNS public.admin_login_activity
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_activity public.admin_login_activity%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RETURN NULL; END IF;
  UPDATE public.admin_login_activity
    SET last_seen_at = now(), updated_at = now()
    WHERE user_id = auth.uid() AND device_id = trim(p_device_id)
    RETURNING * INTO v_activity;
  RETURN v_activity;
END;
$$;

REVOKE ALL ON FUNCTION public.record_admin_login_activity(text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.touch_admin_login_activity(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_admin_login_activity(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_admin_login_activity(text) TO authenticated;
