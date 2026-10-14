-- Create verifikator_withdrawals table for withdrawal requests
CREATE TABLE IF NOT EXISTS public.verifikator_withdrawals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  verifikator_id UUID NOT NULL,
  amount INTEGER NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_8958cc263e18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8958cc263e18$;

DO $bootstrap_do_8e63861082bf$
BEGIN
  EXECUTE $bootstrap_sql_8e63861082bf$-- Enable RLS
ALTER TABLE public.verifikator_withdrawals ENABLE ROW LEVEL SECURITY$bootstrap_sql_8e63861082bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e63861082bf$;

DO $bootstrap_do_48a4fab30c49$
BEGIN
  EXECUTE $bootstrap_sql_48a4fab30c49$-- RLS Policies
DROP POLICY IF EXISTS "Verifikators can view own withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_48a4fab30c49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_48a4fab30c49$;

DO $bootstrap_do_a4a79afb7e44$
BEGIN
  EXECUTE $bootstrap_sql_a4a79afb7e44$DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_a4a79afb7e44$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4a79afb7e44$;

DO $bootstrap_do_007dd8bfa74a$
BEGIN
  EXECUTE $bootstrap_sql_007dd8bfa74a$DROP POLICY IF EXISTS "Admins can manage all withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_007dd8bfa74a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_007dd8bfa74a$;

DO $bootstrap_do_4c0df6f9cf7e$
BEGIN
  EXECUTE $bootstrap_sql_4c0df6f9cf7e$DROP POLICY IF EXISTS "Verifikators can view own withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_4c0df6f9cf7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c0df6f9cf7e$;

DO $bootstrap_do_d8cc979b3268$
BEGIN
  EXECUTE $bootstrap_sql_d8cc979b3268$CREATE POLICY "Verifikators can view own withdrawals" ON public.verifikator_withdrawals
  FOR SELECT USING (verifikator_id = auth.uid())$bootstrap_sql_d8cc979b3268$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8cc979b3268$;

DO $bootstrap_do_073d24604425$
BEGIN
  EXECUTE $bootstrap_sql_073d24604425$DROP POLICY IF EXISTS "Verifikators can create withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_073d24604425$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_073d24604425$;

DO $bootstrap_do_d3d7d8a3325e$
BEGIN
  EXECUTE $bootstrap_sql_d3d7d8a3325e$CREATE POLICY "Verifikators can create withdrawals" ON public.verifikator_withdrawals
  FOR INSERT WITH CHECK (verifikator_id = auth.uid() AND status = 'PENDING')$bootstrap_sql_d3d7d8a3325e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3d7d8a3325e$;

DO $bootstrap_do_c132fcc069e2$
BEGIN
  EXECUTE $bootstrap_sql_c132fcc069e2$DROP POLICY IF EXISTS "Admins can manage all withdrawals" ON public.verifikator_withdrawals$bootstrap_sql_c132fcc069e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c132fcc069e2$;

DO $bootstrap_do_76be0f1e7bbe$
BEGIN
  EXECUTE $bootstrap_sql_76be0f1e7bbe$CREATE POLICY "Admins can manage all withdrawals" ON public.verifikator_withdrawals
  FOR ALL USING (is_admin())$bootstrap_sql_76be0f1e7bbe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76be0f1e7bbe$;

DO $bootstrap_do_7d2364a87582$
BEGIN
  EXECUTE $bootstrap_sql_7d2364a87582$-- Add balance columns to track verifikator earnings
ALTER TABLE public.verifikator_earnings ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE$bootstrap_sql_7d2364a87582$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d2364a87582$;

DO $bootstrap_do_124516be7002$
BEGIN
  EXECUTE $bootstrap_sql_124516be7002$-- Function to process verifikator withdrawal
CREATE OR REPLACE FUNCTION process_verifikator_withdrawal(
  p_withdrawal_id UUID,
  p_status TEXT,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
  v_withdrawal RECORD;
  v_total_pending INTEGER;
BEGIN
  -- Get the withdrawal
  SELECT * INTO v_withdrawal FROM verifikator_withdrawals WHERE id = p_withdrawal_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Withdrawal not found';
  END IF;

  IF v_withdrawal.status != 'PENDING' THEN
    RAISE EXCEPTION 'Withdrawal already processed';
  END IF;

  IF p_status = 'APPROVED' THEN
    -- Calculate total pending earnings for this verifikator
    SELECT COALESCE(SUM(commission_amount), 0) INTO v_total_pending
    FROM verifikator_earnings
    WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING';

    IF v_total_pending < v_withdrawal.amount THEN
      RAISE EXCEPTION 'Insufficient pending balance';
    END IF;

    -- Mark earnings as PAID up to the withdrawal amount
    WITH earnings_to_pay AS (
      SELECT id, commission_amount,
        SUM(commission_amount) OVER (ORDER BY created_at) as running_total
      FROM verifikator_earnings
      WHERE verifikator_id = v_withdrawal.verifikator_id AND status = 'PENDING'
      ORDER BY created_at
    )
    UPDATE verifikator_earnings
    SET status = 'PAID', paid_at = now()
    WHERE id IN (
      SELECT id FROM earnings_to_pay WHERE running_total <= v_withdrawal.amount
    );
  END IF;

  -- Update withdrawal status
  UPDATE verifikator_withdrawals
  SET
    status = p_status,
    admin_notes = p_admin_notes,
    processed_by = auth.uid(),
    processed_at = now(),
    updated_at = now()
  WHERE id = p_withdrawal_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_124516be7002$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_124516be7002$;

DO $bootstrap_do_ede29d3b9e6e$
BEGIN
  EXECUTE $bootstrap_sql_ede29d3b9e6e$
