-- Cashback and promotion program hardening.
-- Adds merchant-owned cashback rules and an authoritative ledger lifecycle.

ALTER TABLE public.cashback_rules
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE;

ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'earn',
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cashback_balance numeric(14,2) NOT NULL DEFAULT 0;

ALTER TABLE public.cashback_transactions
  DROP CONSTRAINT IF EXISTS cashback_transactions_status_valid;
ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_status_valid
  CHECK (status IN ('pending', 'confirmed', 'cancelled', 'reversed', 'expired', 'redeemed'));
ALTER TABLE public.cashback_transactions
  ADD CONSTRAINT cashback_transactions_type_valid
  CHECK (type IN ('earn', 'redeem', 'expire'));

CREATE INDEX IF NOT EXISTS cashback_rules_merchant_period_idx
  ON public.cashback_rules (merchant_id, is_active, valid_from, valid_until);

DROP POLICY IF EXISTS "Merchants manage own cashback rules" ON public.cashback_rules;
CREATE POLICY "Merchants manage own cashback rules"
  ON public.cashback_rules FOR ALL TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Merchants view own cashback rules" ON public.cashback_rules;
CREATE POLICY "Merchants view own cashback rules"
  ON public.cashback_rules FOR SELECT TO authenticated
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

CREATE OR REPLACE FUNCTION public.award_cashback_for_order(p_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_rule public.cashback_rules%ROWTYPE;
  v_amount numeric(14,2);
  v_awarded integer := 0;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status NOT IN ('DONE', 'DELIVERED') THEN
    RETURN 0;
  END IF;

  FOR v_rule IN
    SELECT r.*
    FROM public.cashback_rules r
    WHERE r.is_active
      AND r.valid_from <= now()
      AND (r.valid_until IS NULL OR r.valid_until >= now())
      AND (r.merchant_id IS NULL OR r.merchant_id = v_order.merchant_id)
      AND v_order.subtotal >= r.min_order_amount
      AND (r.category IS NULL OR EXISTS (
        SELECT 1
        FROM public.order_items oi
        JOIN public.products p ON p.id = oi.product_id
        WHERE oi.order_id = v_order.id AND lower(p.category) = lower(r.category)
      ))
    ORDER BY (r.merchant_id IS NOT NULL) DESC, r.cashback_percent DESC, r.created_at ASC
  LOOP
    v_amount := round((v_order.subtotal * v_rule.cashback_percent / 100)::numeric, 2);
    IF v_rule.max_cashback IS NOT NULL THEN
      v_amount := LEAST(v_amount, v_rule.max_cashback);
    END IF;
    IF v_amount <= 0 THEN CONTINUE; END IF;

    INSERT INTO public.cashback_transactions
      (user_id, order_id, rule_id, amount, type, status, expires_at)
    VALUES
      (v_order.buyer_id, v_order.id, v_rule.id, v_amount, 'earn', 'pending', now() + interval '90 days')
    ON CONFLICT (order_id, rule_id) WHERE order_id IS NOT NULL AND rule_id IS NOT NULL AND status <> 'reversed'
    DO NOTHING;

    IF FOUND THEN v_awarded := v_awarded + 1; END IF;
  END LOOP;
  RETURN v_awarded;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_due_cashback()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admin or service role may confirm cashback' USING ERRCODE = '42501';
  END IF;
  WITH confirmed AS (
    UPDATE public.cashback_transactions t
    SET status = 'confirmed', confirmed_at = now()
    WHERE t.type = 'earn' AND t.status = 'pending'
      AND t.created_at <= now() - interval '3 days'
      AND (t.expires_at IS NULL OR t.expires_at > now())
    RETURNING t.user_id, t.amount
  )
  UPDATE public.profiles p
  SET cashback_balance = p.cashback_balance + c.amount, updated_at = now()
  FROM (SELECT user_id, sum(amount) AS amount FROM confirmed GROUP BY user_id) c
  WHERE p.user_id = c.user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_order_done_award_cashback()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('DONE', 'DELIVERED') AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.award_cashback_for_order(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_cashback_award_trigger ON public.orders;
CREATE TRIGGER orders_cashback_award_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_done_award_cashback();

REVOKE ALL ON FUNCTION public.award_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.award_cashback_for_order(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.confirm_due_cashback() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_due_cashback() TO authenticated, service_role;
COMMENT ON FUNCTION public.award_cashback_for_order(uuid) IS 'Authoritative, idempotent cashback award invoked when an order is delivered or done.';
COMMENT ON FUNCTION public.confirm_due_cashback() IS 'Confirms cashback after the three-day dispute window and updates buyer balance.';
