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
);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_events_order
  ON public.payment_webhook_events(order_id, received_at DESC);

REVOKE ALL ON public.payment_webhook_events FROM anon, authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages payment webhook events"
  ON public.payment_webhook_events;
CREATE POLICY "Service role manages payment webhook events"
  ON public.payment_webhook_events FOR ALL TO service_role
  USING (true) WITH CHECK (true);
