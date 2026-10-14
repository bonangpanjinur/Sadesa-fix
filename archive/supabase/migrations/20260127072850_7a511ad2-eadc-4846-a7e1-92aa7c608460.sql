-- Create trade_groups table
CREATE TABLE public.trade_groups (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  verifikator_id UUID NOT NULL,
  monthly_fee INTEGER NOT NULL DEFAULT 10000,
  village_id UUID REFERENCES public.villages(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true
)$bootstrap_sql_6c10699cf985$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c10699cf985$;

DO $bootstrap_do_c8ffe8eb0aa6$
BEGIN
  EXECUTE $bootstrap_sql_c8ffe8eb0aa6$-- Create group_members table (linking merchants to groups)
CREATE TABLE public.group_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  UNIQUE(group_id, merchant_id)
)$bootstrap_sql_c8ffe8eb0aa6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8ffe8eb0aa6$;

DO $bootstrap_do_f4ec8de3a5cf$
BEGIN
  EXECUTE $bootstrap_sql_f4ec8de3a5cf$-- Create kas_payments table for monthly fee tracking
CREATE TABLE public.kas_payments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES public.trade_groups(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL,
  payment_month INTEGER NOT NULL,
  payment_year INTEGER NOT NULL,
  payment_date TIMESTAMP WITH TIME ZONE,
  status TEXT NOT NULL DEFAULT 'UNPAID',
  notes TEXT,
  collected_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(group_id, merchant_id, payment_month, payment_year)
)$bootstrap_sql_f4ec8de3a5cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4ec8de3a5cf$;

DO $bootstrap_do_9861a20958d6$
BEGIN
  EXECUTE $bootstrap_sql_9861a20958d6$-- Enable RLS
ALTER TABLE public.trade_groups ENABLE ROW LEVEL SECURITY$bootstrap_sql_9861a20958d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9861a20958d6$;

DO $bootstrap_do_52c8e65a9136$
BEGIN
  EXECUTE $bootstrap_sql_52c8e65a9136$ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY$bootstrap_sql_52c8e65a9136$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52c8e65a9136$;

DO $bootstrap_do_fb5a02faf207$
BEGIN
  EXECUTE $bootstrap_sql_fb5a02faf207$ALTER TABLE public.kas_payments ENABLE ROW LEVEL SECURITY$bootstrap_sql_fb5a02faf207$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb5a02faf207$;

DO $bootstrap_do_e6be965c957b$
BEGIN
  EXECUTE $bootstrap_sql_e6be965c957b$-- Trade Groups Policies
DROP POLICY IF EXISTS "Verifikators can manage own groups" ON public.trade_groups$bootstrap_sql_e6be965c957b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6be965c957b$;

DO $bootstrap_do_e4a30d3d673f$
BEGIN
  EXECUTE $bootstrap_sql_e4a30d3d673f$CREATE POLICY "Verifikators can manage own groups"
ON public.trade_groups FOR ALL
USING (verifikator_id = auth.uid() OR is_admin())$bootstrap_sql_e4a30d3d673f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4a30d3d673f$;

DO $bootstrap_do_50c636c13671$
BEGIN
  EXECUTE $bootstrap_sql_50c636c13671$DROP POLICY IF EXISTS "Admins can manage all groups" ON public.trade_groups$bootstrap_sql_50c636c13671$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50c636c13671$;

DO $bootstrap_do_7f562d942fc4$
BEGIN
  EXECUTE $bootstrap_sql_7f562d942fc4$CREATE POLICY "Admins can manage all groups"
ON public.trade_groups FOR ALL
USING (is_admin())$bootstrap_sql_7f562d942fc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f562d942fc4$;

DO $bootstrap_do_34716e3b5b05$
BEGIN
  EXECUTE $bootstrap_sql_34716e3b5b05$DROP POLICY IF EXISTS "Anyone can view active groups" ON public.trade_groups$bootstrap_sql_34716e3b5b05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34716e3b5b05$;

DO $bootstrap_do_bc4e12df9c04$
BEGIN
  EXECUTE $bootstrap_sql_bc4e12df9c04$CREATE POLICY "Anyone can view active groups"
ON public.trade_groups FOR SELECT
USING (is_active = true)$bootstrap_sql_bc4e12df9c04$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc4e12df9c04$;

DO $bootstrap_do_793fc389a4fd$
BEGIN
  EXECUTE $bootstrap_sql_793fc389a4fd$-- Group Members Policies
DROP POLICY IF EXISTS "Verifikators can manage group members" ON public.group_members$bootstrap_sql_793fc389a4fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_793fc389a4fd$;

DO $bootstrap_do_fb9edaa8c434$
BEGIN
  EXECUTE $bootstrap_sql_fb9edaa8c434$CREATE POLICY "Verifikators can manage group members"
ON public.group_members FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups
    WHERE trade_groups.id = group_members.group_id
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
)$bootstrap_sql_fb9edaa8c434$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb9edaa8c434$;

DO $bootstrap_do_9426f3953000$
BEGIN
  EXECUTE $bootstrap_sql_9426f3953000$DROP POLICY IF EXISTS "Merchants can view own membership" ON public.group_members$bootstrap_sql_9426f3953000$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9426f3953000$;

DO $bootstrap_do_d9d76b5f5f34$
BEGIN
  EXECUTE $bootstrap_sql_d9d76b5f5f34$CREATE POLICY "Merchants can view own membership"
ON public.group_members FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = group_members.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_d9d76b5f5f34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9d76b5f5f34$;

DO $bootstrap_do_0c649e9d8b2c$
BEGIN
  EXECUTE $bootstrap_sql_0c649e9d8b2c$DROP POLICY IF EXISTS "Admins can manage all members" ON public.group_members$bootstrap_sql_0c649e9d8b2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c649e9d8b2c$;

DO $bootstrap_do_613cc799dc1b$
BEGIN
  EXECUTE $bootstrap_sql_613cc799dc1b$CREATE POLICY "Admins can manage all members"
ON public.group_members FOR ALL
USING (is_admin())$bootstrap_sql_613cc799dc1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_613cc799dc1b$;

DO $bootstrap_do_ef42e99b9435$
BEGIN
  EXECUTE $bootstrap_sql_ef42e99b9435$-- Kas Payments Policies
DROP POLICY IF EXISTS "Verifikators can manage payments in their groups" ON public.kas_payments$bootstrap_sql_ef42e99b9435$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef42e99b9435$;

DO $bootstrap_do_471d531f8b92$
BEGIN
  EXECUTE $bootstrap_sql_471d531f8b92$CREATE POLICY "Verifikators can manage payments in their groups"
ON public.kas_payments FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM trade_groups
    WHERE trade_groups.id = kas_payments.group_id
    AND (trade_groups.verifikator_id = auth.uid() OR is_admin())
  )
)$bootstrap_sql_471d531f8b92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_471d531f8b92$;

DO $bootstrap_do_152826f47642$
BEGIN
  EXECUTE $bootstrap_sql_152826f47642$DROP POLICY IF EXISTS "Merchants can view own payments" ON public.kas_payments$bootstrap_sql_152826f47642$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_152826f47642$;

DO $bootstrap_do_3cfc64ad689d$
BEGIN
  EXECUTE $bootstrap_sql_3cfc64ad689d$CREATE POLICY "Merchants can view own payments"
ON public.kas_payments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = kas_payments.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_3cfc64ad689d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3cfc64ad689d$;

DO $bootstrap_do_b79a4ccb8d3b$
BEGIN
  EXECUTE $bootstrap_sql_b79a4ccb8d3b$DROP POLICY IF EXISTS "Admins can manage all payments" ON public.kas_payments$bootstrap_sql_b79a4ccb8d3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b79a4ccb8d3b$;

DO $bootstrap_do_92c28ed5eab6$
BEGIN
  EXECUTE $bootstrap_sql_92c28ed5eab6$CREATE POLICY "Admins can manage all payments"
ON public.kas_payments FOR ALL
USING (is_admin())$bootstrap_sql_92c28ed5eab6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92c28ed5eab6$;

DO $bootstrap_do_001e9257fbab$
BEGIN
  EXECUTE $bootstrap_sql_001e9257fbab$-- Create function to generate monthly kas records for all group members
CREATE OR REPLACE FUNCTION public.generate_monthly_kas(p_group_id UUID, p_month INTEGER, p_year INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_member RECORD;
  v_count INTEGER := 0;
BEGIN
  -- Get group info
  SELECT * INTO v_group FROM trade_groups WHERE id = p_group_id;

  IF v_group IS NULL THEN
    RETURN 0;
  END IF;

  -- Insert kas records for all active members
  FOR v_member IN
    SELECT * FROM group_members
    WHERE group_id = p_group_id AND status = 'ACTIVE'
  LOOP
    INSERT INTO kas_payments (group_id, merchant_id, amount, payment_month, payment_year, status)
    VALUES (p_group_id, v_member.merchant_id, v_group.monthly_fee, p_month, p_year, 'UNPAID')
    ON CONFLICT (group_id, merchant_id, payment_month, payment_year) DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$$bootstrap_sql_001e9257fbab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_001e9257fbab$;

DO $bootstrap_do_942efdcae4fb$
BEGIN
  EXECUTE $bootstrap_sql_942efdcae4fb$-- Create updated_at trigger for new tables
DROP TRIGGER IF EXISTS update_trade_groups_updated_at ON public.trade_groups$bootstrap_sql_942efdcae4fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_942efdcae4fb$;

DO $bootstrap_do_1497ff42b166$
BEGIN
  EXECUTE $bootstrap_sql_1497ff42b166$CREATE TRIGGER update_trade_groups_updated_at
  BEFORE UPDATE ON public.trade_groups
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_1497ff42b166$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1497ff42b166$;

DO $bootstrap_do_66fa396367a1$
BEGIN
  EXECUTE $bootstrap_sql_66fa396367a1$DROP TRIGGER IF EXISTS update_kas_payments_updated_at ON public.kas_payments$bootstrap_sql_66fa396367a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66fa396367a1$;

DO $bootstrap_do_aa9d404436bf$
BEGIN
  EXECUTE $bootstrap_sql_aa9d404436bf$CREATE TRIGGER update_kas_payments_updated_at
  BEFORE UPDATE ON public.kas_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_aa9d404436bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aa9d404436bf$;

DO $bootstrap_do_34b433c7e58b$
BEGIN
  EXECUTE $bootstrap_sql_34b433c7e58b$
