ALTER TABLE public.merchant_subscriptions
  ADD COLUMN IF NOT EXISTS billing_period text NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly','quarterly','yearly')),
  ADD COLUMN IF NOT EXISTS current_period_start timestamptz,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz,
  ADD COLUMN IF NOT EXISTS grace_period_until timestamptz,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS provider_subscription_id text$bootstrap_sql_dd9742a378da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd9742a378da$;

DO $bootstrap_do_33771a5a55fe$
BEGIN
  EXECUTE $bootstrap_sql_33771a5a55fe$CREATE TABLE IF NOT EXISTS public.subscription_billing_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL,
  amount numeric(15,2),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'received' CHECK (status IN ('received','processed','ignored','failed')),
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE(provider, provider_event_id)
)$bootstrap_sql_33771a5a55fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33771a5a55fe$;

DO $bootstrap_do_98402b295abd$
BEGIN
  EXECUTE $bootstrap_sql_98402b295abd$CREATE INDEX IF NOT EXISTS idx_subscription_events_subscription ON public.subscription_billing_events(subscription_id, created_at DESC)$bootstrap_sql_98402b295abd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_98402b295abd$;

DO $bootstrap_do_865547fc3131$
BEGIN
  EXECUTE $bootstrap_sql_865547fc3131$ALTER TABLE public.subscription_billing_events ENABLE ROW LEVEL SECURITY$bootstrap_sql_865547fc3131$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_865547fc3131$;

DO $bootstrap_do_e4acd2ba9fee$
BEGIN
  EXECUTE $bootstrap_sql_e4acd2ba9fee$DROP POLICY IF EXISTS "Merchant views own subscription events" ON public.subscription_billing_events$bootstrap_sql_e4acd2ba9fee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4acd2ba9fee$;

DO $bootstrap_do_8d30679f8342$
BEGIN
  EXECUTE $bootstrap_sql_8d30679f8342$CREATE POLICY "Merchant views own subscription events" ON public.subscription_billing_events FOR SELECT TO authenticated
  USING (subscription_id IN (SELECT ms.id FROM public.merchant_subscriptions ms JOIN public.merchants m ON m.id = ms.merchant_id WHERE m.user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_8d30679f8342$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d30679f8342$;

DO $bootstrap_do_de84acf8b889$
BEGIN
  EXECUTE $bootstrap_sql_de84acf8b889$DROP POLICY IF EXISTS "Admins manage subscription events" ON public.subscription_billing_events$bootstrap_sql_de84acf8b889$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de84acf8b889$;

DO $bootstrap_do_4691ec4e55b0$
BEGIN
  EXECUTE $bootstrap_sql_4691ec4e55b0$CREATE POLICY "Admins manage subscription events" ON public.subscription_billing_events FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_4691ec4e55b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4691ec4e55b0$;

DO $bootstrap_do_98ca7a416ae7$
BEGIN
  EXECUTE $bootstrap_sql_98ca7a416ae7$CREATE OR REPLACE FUNCTION public.record_subscription_billing_event(
  p_subscription_id uuid, p_provider text, p_provider_event_id text, p_event_type text, p_amount numeric, p_payload jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_merchant_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Billing event ingestion requires admin access' USING ERRCODE = '42501'; END IF;
  SELECT merchant_id INTO v_merchant_id FROM public.merchant_subscriptions WHERE id = p_subscription_id;
  IF v_merchant_id IS NULL THEN RAISE EXCEPTION 'Subscription not found' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO public.subscription_billing_events(subscription_id, provider, provider_event_id, event_type, amount, payload)
  VALUES (p_subscription_id, p_provider, p_provider_event_id, p_event_type, p_amount, COALESCE(p_payload, '{}'::jsonb))
  ON CONFLICT (provider, provider_event_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN jsonb_build_object('duplicate', true, 'provider_event_id', p_provider_event_id); END IF;
  RETURN jsonb_build_object('duplicate', false, 'event_id', v_id);
END; $$$bootstrap_sql_98ca7a416ae7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_98ca7a416ae7$;

DO $bootstrap_do_e21ceb7e9255$
BEGIN
  EXECUTE $bootstrap_sql_e21ceb7e9255$REVOKE ALL ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) FROM PUBLIC, anon, authenticated$bootstrap_sql_e21ceb7e9255$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e21ceb7e9255$;

DO $bootstrap_do_ba3cc98087b7$
BEGIN
  EXECUTE $bootstrap_sql_ba3cc98087b7$GRANT EXECUTE ON FUNCTION public.record_subscription_billing_event(uuid, text, text, text, numeric, jsonb) TO service_role$bootstrap_sql_ba3cc98087b7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba3cc98087b7$;

DO $bootstrap_do_cadb7947d606$
BEGIN
  EXECUTE $bootstrap_sql_cadb7947d606$
