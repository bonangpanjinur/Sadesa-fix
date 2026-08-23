-- Payment security hardening:
-- do not expose provider credentials through the generic app_settings read path.

DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings;

CREATE POLICY "Public can view non-sensitive settings"
  ON public.app_settings
  FOR SELECT
  USING (
    key !~* '(secret|token|credential|api[_-]?key|private|password)'
    AND key NOT IN (
      'payment_xendit',
      'payment_midtrans',
      'whatsapp_settings',
      'push_notification_settings'
    )
  );

CREATE OR REPLACE FUNCTION public.is_payment_provider_enabled(p_provider text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE lower(trim(p_provider))
    WHEN 'xendit' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_xendit'
    ), false)
    WHEN 'midtrans' THEN COALESCE((
      SELECT (value->>'enabled')::boolean
      FROM public.app_settings
      WHERE key = 'payment_midtrans'
    ), false)
    ELSE false
  END;
$$;

REVOKE ALL ON FUNCTION public.is_payment_provider_enabled(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_payment_provider_enabled(text) TO anon, authenticated;
