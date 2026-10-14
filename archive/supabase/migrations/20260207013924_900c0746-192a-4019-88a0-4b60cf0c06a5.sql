-- Create a function to deduct a specific number of credits from merchant quota
-- This replaces the single-deduction version for tier-based quota costs
CREATE OR REPLACE FUNCTION public.deduct_merchant_quota(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_id UUID;
  v_remaining INTEGER;
BEGIN
  -- Find active subscription with enough remaining quota (FIFO by expiry)
  SELECT id, (transaction_quota - used_quota)
  INTO v_sub_id, v_remaining
  FROM public.merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;

  RETURN TRUE;
END;
$$$bootstrap_sql_01c04dd192da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01c04dd192da$;

DO $bootstrap_do_9b59248d9645$
BEGIN
  EXECUTE $bootstrap_sql_9b59248d9645$
