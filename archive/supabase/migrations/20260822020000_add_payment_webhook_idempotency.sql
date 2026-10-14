-- Idempotency ledger for payment provider callbacks.
CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_key text NOT NULL,
  invoice_id text NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, event_key)
)$bootstrap_sql_64fe9011088f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64fe9011088f$;

DO $bootstrap_do_9dd5f3461400$
BEGIN
  EXECUTE $bootstrap_sql_9dd5f3461400$CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events(order_id, received_at DESC)$bootstrap_sql_9dd5f3461400$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dd5f3461400$;

DO $bootstrap_do_c71c78727815$
BEGIN
  EXECUTE $bootstrap_sql_c71c78727815$REVOKE ALL ON public.payment_webhook_events FROM anon, authenticated$bootstrap_sql_c71c78727815$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c71c78727815$;

DO $bootstrap_do_463ec21ea015$
BEGIN
  EXECUTE $bootstrap_sql_463ec21ea015$GRANT ALL ON public.payment_webhook_events TO service_role$bootstrap_sql_463ec21ea015$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_463ec21ea015$;

DO $bootstrap_do_1bd9a26a6266$
BEGIN
  EXECUTE $bootstrap_sql_1bd9a26a6266$ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY$bootstrap_sql_1bd9a26a6266$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1bd9a26a6266$;

DO $bootstrap_do_4caee0849913$
BEGIN
  EXECUTE $bootstrap_sql_4caee0849913$DROP POLICY IF EXISTS "Service role manages payment webhook events"
  ON public.payment_webhook_events$bootstrap_sql_4caee0849913$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4caee0849913$;

DO $bootstrap_do_5a5f4489afe9$
BEGIN
  EXECUTE $bootstrap_sql_5a5f4489afe9$CREATE POLICY "Service role manages payment webhook events"
  ON public.payment_webhook_events FOR ALL TO service_role
  USING (true) WITH CHECK (true)$bootstrap_sql_5a5f4489afe9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a5f4489afe9$;

DO $bootstrap_do_76866591b886$
BEGIN
  EXECUTE $bootstrap_sql_76866591b886$
