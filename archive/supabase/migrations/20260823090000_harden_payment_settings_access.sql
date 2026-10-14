-- Payment security hardening:
-- do not expose provider credentials through the generic app_settings read path.

DROP POLICY IF EXISTS "Anyone can view settings" ON public.app_settings$bootstrap_sql_1f9a0ad229bb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f9a0ad229bb$;

DO $bootstrap_do_7b9800bab41c$
BEGIN
  EXECUTE $bootstrap_sql_7b9800bab41c$DROP POLICY IF EXISTS "Public can view non-sensitive settings" ON public.app_settings$bootstrap_sql_7b9800bab41c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b9800bab41c$;

DO $bootstrap_do_6e3cfce68152$
BEGIN
  EXECUTE $bootstrap_sql_6e3cfce68152$CREATE POLICY "Public can view non-sensitive settings"
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
  )$bootstrap_sql_6e3cfce68152$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e3cfce68152$;

DO $bootstrap_do_1bc78c050788$
BEGIN
  EXECUTE $bootstrap_sql_1bc78c050788$CREATE OR REPLACE FUNCTION public.is_payment_provider_enabled(p_provider text)
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
$$$bootstrap_sql_1bc78c050788$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1bc78c050788$;

DO $bootstrap_do_cb8477e0b390$
BEGIN
  EXECUTE $bootstrap_sql_cb8477e0b390$REVOKE ALL ON FUNCTION public.is_payment_provider_enabled(text) FROM PUBLIC$bootstrap_sql_cb8477e0b390$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb8477e0b390$;

DO $bootstrap_do_a7c9d1a30309$
BEGIN
  EXECUTE $bootstrap_sql_a7c9d1a30309$GRANT EXECUTE ON FUNCTION public.is_payment_provider_enabled(text) TO anon, authenticated$bootstrap_sql_a7c9d1a30309$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7c9d1a30309$;

DO $bootstrap_do_950b52f9699e$
BEGIN
  EXECUTE $bootstrap_sql_950b52f9699e$
