-- Cashback redemption and refund reversal hardening.
-- The checkout integration should call redeem_cashback inside the same authoritative
-- checkout transaction once the checkout contract accepts a cashback amount.

ALTER TABLE public.cashback_transactions
  ADD COLUMN IF NOT EXISTS reversal_of uuid REFERENCES public.cashback_transactions(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS cashback_reversal_once_idx
  ON public.cashback_transactions (reversal_of)
  WHERE reversal_of IS NOT NULL;

CREATE OR REPLACE FUNCTION public.redeem_cashback(
  p_amount numeric,
  p_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_balance numeric(14,2);
  v_tx_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN
    RAISE EXCEPTION 'Redeem amount is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT cashback_balance INTO v_balance
  FROM public.profiles
  WHERE user_id = v_user_id
  FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_balance, 0) < p_amount THEN
    RAISE EXCEPTION 'Insufficient cashback balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.cashback_transactions
    (user_id, amount, type, status, confirmed_at)
  VALUES
    (v_user_id, p_amount, 'redeem', 'confirmed', now())
  RETURNING id INTO v_tx_id;

  UPDATE public.profiles
  SET cashback_balance = cashback_balance - p_amount, updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('id', v_tx_id, 'amount', p_amount, 'reference', p_reference);
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_cashback_for_order(p_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx public.cashback_transactions%ROWTYPE;
  v_count integer := 0;
BEGIN
  FOR v_tx IN
    SELECT * FROM public.cashback_transactions
    WHERE order_id = p_order_id AND type = 'earn' AND status IN ('pending', 'confirmed')
    FOR UPDATE
  LOOP
    IF v_tx.status = 'pending' THEN
      UPDATE public.cashback_transactions
      SET status = 'cancelled'
      WHERE id = v_tx.id;
    ELSE
      INSERT INTO public.cashback_transactions
        (user_id, order_id, amount, type, status, confirmed_at, reversal_of)
      VALUES
        (v_tx.user_id, v_tx.order_id, v_tx.amount, 'expire', 'confirmed', now(), v_tx.id)
      ON CONFLICT (reversal_of) WHERE reversal_of IS NOT NULL DO NOTHING;

      IF FOUND THEN
        UPDATE public.profiles
        SET cashback_balance = GREATEST(0, cashback_balance - v_tx.amount), updated_at = now()
        WHERE user_id = v_tx.user_id;
      END IF;
      UPDATE public.cashback_transactions SET status = 'reversed' WHERE id = v_tx.id;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_order_refunded_reverse_cashback()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'REFUNDED' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.reverse_cashback_for_order(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_cashback_reversal_trigger ON public.orders;
CREATE TRIGGER orders_cashback_reversal_trigger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.on_order_refunded_reverse_cashback();

REVOKE ALL ON FUNCTION public.redeem_cashback(numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_cashback(numeric, text) TO authenticated;
REVOKE ALL ON FUNCTION public.reverse_cashback_for_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_cashback_for_order(uuid) TO service_role;
COMMENT ON FUNCTION public.redeem_cashback(numeric, text) IS 'Atomically consumes confirmed buyer cashback; checkout should call this inside its transaction.';
COMMENT ON FUNCTION public.reverse_cashback_for_order(uuid) IS 'Creates an auditable reversal or cancels pending cashback when an order is refunded.';
