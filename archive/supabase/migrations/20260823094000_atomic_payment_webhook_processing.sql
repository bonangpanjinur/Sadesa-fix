-- Process a provider callback and its idempotency ledger in one transaction.
-- The order row is locked before the event is recorded, preventing concurrent
-- callbacks from racing through terminal-state checks.
CREATE OR REPLACE FUNCTION public.process_payment_webhook_event(
  p_provider text,
  p_event_key text,
  p_invoice_id text,
  p_order_id uuid,
  p_status text,
  p_paid_at timestamptz DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_payment_channel text DEFAULT NULL,
  p_paid_amount numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_inserted boolean := false;
  v_current_status text;
  v_order_total numeric;
BEGIN
  IF NULLIF(trim(p_provider), '') IS NULL
     OR NULLIF(trim(p_event_key), '') IS NULL
     OR NULLIF(trim(p_invoice_id), '') IS NULL
     OR p_order_id IS NULL
     OR p_status NOT IN ('PAID', 'EXPIRED', 'PENDING') THEN
    RAISE EXCEPTION 'Invalid payment webhook event' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.payment_invoice_id IS NULL OR v_order.payment_invoice_id <> p_invoice_id THEN
    RAISE EXCEPTION 'Invoice mismatch' USING ERRCODE = '23P01';
  END IF;

  v_order_total := v_order.total;
  IF v_order_total IS NULL OR v_order_total <= 0 OR v_order_total <> trunc(v_order_total) THEN
    RAISE EXCEPTION 'Invalid order total' USING ERRCODE = '22023';
  END IF;

  IF p_status = 'PAID' AND (p_paid_amount IS NULL OR p_paid_amount <> v_order_total) THEN
    RAISE EXCEPTION 'Payment amount mismatch' USING ERRCODE = '22003';
  END IF;

  INSERT INTO public.payment_webhook_events(provider, event_key, invoice_id, order_id, status)
  VALUES (lower(trim(p_provider)), trim(p_event_key), p_invoice_id, p_order_id, p_status)
  ON CONFLICT (provider, event_key) DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT COALESCE(v_inserted, false) THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true);
  END IF;

  v_current_status := COALESCE(v_order.payment_status, 'UNPAID');
  IF v_current_status = 'PAID'
     OR (v_current_status = 'EXPIRED' AND p_status = 'PENDING') THEN
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;

  UPDATE public.orders
  SET payment_status = p_status,
      payment_paid_at = CASE WHEN p_status = 'PAID' THEN COALESCE(p_paid_at, now()) ELSE NULL END,
      payment_method = NULLIF(trim(p_payment_method), ''),
      payment_channel = NULLIF(trim(p_payment_channel), ''),
      status = CASE
        WHEN p_status = 'PAID' THEN 'CONFIRMED'
        WHEN p_status = 'EXPIRED' AND v_current_status <> 'PAID' THEN 'CANCELLED'
        ELSE status
      END
  WHERE id = p_order_id;

  RETURN jsonb_build_object('success', true, 'processed', true, 'status', p_status);
END;
$$$bootstrap_sql_e12ca8e87ff0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e12ca8e87ff0$;

DO $bootstrap_do_2314aad13b1f$
BEGIN
  EXECUTE $bootstrap_sql_2314aad13b1f$REVOKE ALL ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  FROM PUBLIC, anon, authenticated$bootstrap_sql_2314aad13b1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2314aad13b1f$;

DO $bootstrap_do_f9ccbe27ff2c$
BEGIN
  EXECUTE $bootstrap_sql_f9ccbe27ff2c$GRANT EXECUTE ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  TO service_role$bootstrap_sql_f9ccbe27ff2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f9ccbe27ff2c$;

DO $bootstrap_do_877a0916b1cd$
BEGIN
  EXECUTE $bootstrap_sql_877a0916b1cd$COMMENT ON FUNCTION public.process_payment_webhook_event(text, text, text, uuid, text, timestamptz, text, text, numeric)
  IS 'Atomically validates, deduplicates, and applies payment provider callbacks.'$bootstrap_sql_877a0916b1cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_877a0916b1cd$;

DO $bootstrap_do_5970bc776786$
BEGIN
  EXECUTE $bootstrap_sql_5970bc776786$-- Prevent direct SQL updates from downgrading a paid order payment status.
CREATE OR REPLACE FUNCTION public.prevent_paid_payment_downgrade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.payment_status = 'PAID' AND NEW.payment_status IS DISTINCT FROM 'PAID' THEN
    RAISE EXCEPTION 'Paid order payment status is terminal' USING ERRCODE = '27000';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_5970bc776786$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5970bc776786$;

DO $bootstrap_do_aa0364243498$
BEGIN
  EXECUTE $bootstrap_sql_aa0364243498$DROP TRIGGER IF EXISTS trg_prevent_paid_payment_downgrade ON public.orders$bootstrap_sql_aa0364243498$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa0364243498$;

DO $bootstrap_do_825d0ffc0eb5$
BEGIN
  EXECUTE $bootstrap_sql_825d0ffc0eb5$CREATE TRIGGER trg_prevent_paid_payment_downgrade
  BEFORE UPDATE OF payment_status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.prevent_paid_payment_downgrade()$bootstrap_sql_825d0ffc0eb5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_825d0ffc0eb5$;

DO $bootstrap_do_ce7a0b21849b$
BEGIN
  EXECUTE $bootstrap_sql_ce7a0b21849b$REVOKE ALL ON FUNCTION public.prevent_paid_payment_downgrade() FROM PUBLIC, anon, authenticated$bootstrap_sql_ce7a0b21849b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce7a0b21849b$;

DO $bootstrap_do_ad742eebbf4c$
BEGIN
  EXECUTE $bootstrap_sql_ad742eebbf4c$GRANT EXECUTE ON FUNCTION public.prevent_paid_payment_downgrade() TO service_role$bootstrap_sql_ad742eebbf4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad742eebbf4c$;

DO $bootstrap_do_6d7fdeb68b4e$
BEGIN
  EXECUTE $bootstrap_sql_6d7fdeb68b4e$-- Rollback note: drop the trigger/function only after restoring the previous
-- webhook implementation; the function is intentionally retained for staged rollout.
