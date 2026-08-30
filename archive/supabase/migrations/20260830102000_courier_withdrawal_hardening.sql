-- OJK-03: prevent concurrent withdrawal requests from overspending balance.
CREATE OR REPLACE FUNCTION public.request_courier_withdrawal(
  p_amount numeric,
  p_bank_name text,
  p_account_number text,
  p_account_holder text,
  p_minimum_balance numeric DEFAULT 50000
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_reserved numeric;
  v_available numeric;
  v_minimum_balance numeric;
  v_request_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0
     OR NULLIF(trim(p_bank_name), '') IS NULL
     OR NULLIF(trim(p_account_number), '') IS NULL
     OR NULLIF(trim(p_account_holder), '') IS NULL THEN
    RAISE EXCEPTION 'Invalid withdrawal request' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(NULLIF(value->>'amount', '')::numeric, 50000)
  INTO v_minimum_balance
  FROM public.app_settings
  WHERE key = 'courier_minimum_balance';
  v_minimum_balance := COALESCE(v_minimum_balance, 50000);

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE user_id = auth.uid()
    AND registration_status = 'APPROVED'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Approved courier profile not found' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_reserved
  FROM public.courier_withdrawal_requests
  WHERE courier_id = v_courier.id
    AND status IN ('PENDING', 'APPROVED')
    AND id IS NOT NULL;

  v_available := COALESCE(v_courier.available_balance, 0) - v_reserved;
  IF p_amount > v_available OR v_available - p_amount < v_minimum_balance THEN
    RAISE EXCEPTION 'Insufficient withdrawable balance' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.courier_withdrawal_requests(
    courier_id, amount, bank_name, account_number, account_holder, status
  ) VALUES (
    v_courier.id, p_amount, trim(p_bank_name), trim(p_account_number), trim(p_account_holder), 'PENDING'
  ) RETURNING id INTO v_request_id;

  RETURN jsonb_build_object('request_id', v_request_id, 'amount', p_amount, 'status', 'PENDING');
END;
$$;

REVOKE ALL ON FUNCTION public.request_courier_withdrawal(numeric, text, text, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_courier_withdrawal(numeric, text, text, text, numeric) TO authenticated;
REVOKE INSERT, DELETE ON public.courier_withdrawal_requests FROM authenticated;
GRANT SELECT, UPDATE ON public.courier_withdrawal_requests TO authenticated;
