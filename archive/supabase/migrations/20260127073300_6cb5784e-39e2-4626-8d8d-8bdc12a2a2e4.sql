-- Rename kas_fee to group_commission_percent in transaction_packages
ALTER TABLE public.transaction_packages
  DROP COLUMN kas_fee,
  ADD COLUMN group_commission_percent numeric NOT NULL DEFAULT 5$bootstrap_sql_34b433c7e58b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34b433c7e58b$;

DO $bootstrap_do_2533457dbad0$
BEGIN
  EXECUTE $bootstrap_sql_2533457dbad0$-- Add comment for clarity
COMMENT ON COLUMN public.transaction_packages.group_commission_percent IS 'Percentage of package price that goes to the trade group/verifikator'$bootstrap_sql_2533457dbad0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2533457dbad0$;

DO $bootstrap_do_d01e625c79a9$
BEGIN
  EXECUTE $bootstrap_sql_d01e625c79a9$-- Create table to track verifikator earnings from package purchases
CREATE TABLE public.verifikator_earnings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  verifikator_id UUID NOT NULL,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  package_id UUID NOT NULL REFERENCES public.transaction_packages(id) ON DELETE CASCADE,
  package_amount INTEGER NOT NULL,
  commission_percent NUMERIC NOT NULL,
  commission_amount INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_d01e625c79a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d01e625c79a9$;

DO $bootstrap_do_4b5938458bb3$
BEGIN
  EXECUTE $bootstrap_sql_4b5938458bb3$-- Enable RLS
ALTER TABLE public.verifikator_earnings ENABLE ROW LEVEL SECURITY$bootstrap_sql_4b5938458bb3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b5938458bb3$;

DO $bootstrap_do_6de00803f6e4$
BEGIN
  EXECUTE $bootstrap_sql_6de00803f6e4$-- RLS Policies
DROP POLICY IF EXISTS "Admins can manage all earnings" ON public.verifikator_earnings$bootstrap_sql_6de00803f6e4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6de00803f6e4$;

DO $bootstrap_do_92071907f55a$
BEGIN
  EXECUTE $bootstrap_sql_92071907f55a$CREATE POLICY "Admins can manage all earnings"
  ON public.verifikator_earnings FOR ALL
  USING (is_admin())$bootstrap_sql_92071907f55a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92071907f55a$;

DO $bootstrap_do_c3ec7bafc64f$
BEGIN
  EXECUTE $bootstrap_sql_c3ec7bafc64f$DROP POLICY IF EXISTS "Verifikators can view own earnings" ON public.verifikator_earnings$bootstrap_sql_c3ec7bafc64f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3ec7bafc64f$;

DO $bootstrap_do_1b93167dca1f$
BEGIN
  EXECUTE $bootstrap_sql_1b93167dca1f$CREATE POLICY "Verifikators can view own earnings"
  ON public.verifikator_earnings FOR SELECT
  USING (verifikator_id = auth.uid())$bootstrap_sql_1b93167dca1f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b93167dca1f$;

DO $bootstrap_do_2d5c53fc7f0e$
BEGIN
  EXECUTE $bootstrap_sql_2d5c53fc7f0e$-- Add group_id to merchants to track their trade group membership
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.trade_groups(id) ON DELETE SET NULL$bootstrap_sql_2d5c53fc7f0e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d5c53fc7f0e$;

DO $bootstrap_do_db456769a660$
BEGIN
  EXECUTE $bootstrap_sql_db456769a660$-- Function to auto-assign merchant to trade group when registering with verifikator code
CREATE OR REPLACE FUNCTION public.auto_assign_merchant_to_group()
RETURNS TRIGGER AS $$
DECLARE
  v_code RECORD;
  v_group RECORD;
BEGIN
  -- If merchant has verifikator_code, find the group and assign
  IF NEW.verifikator_code IS NOT NULL AND NEW.group_id IS NULL THEN
    -- Get verifikator code info
    SELECT * INTO v_code FROM verifikator_codes
    WHERE code = NEW.verifikator_code AND is_active = true
    LIMIT 1;

    IF v_code IS NOT NULL THEN
      -- Find trade group by verifikator
      SELECT * INTO v_group FROM trade_groups
      WHERE verifikator_id = v_code.verifikator_id AND is_active = true
      LIMIT 1;

      IF v_group IS NOT NULL THEN
        NEW.group_id := v_group.id;

        -- Also insert into group_members if not exists
        INSERT INTO group_members (group_id, merchant_id, status)
        VALUES (v_group.id, NEW.id, 'ACTIVE')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_db456769a660$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db456769a660$;

DO $bootstrap_do_e306f5cfae45$
BEGIN
  EXECUTE $bootstrap_sql_e306f5cfae45$-- Create trigger
DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON merchants$bootstrap_sql_e306f5cfae45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e306f5cfae45$;

DO $bootstrap_do_9a2d98638c13$
BEGIN
  EXECUTE $bootstrap_sql_9a2d98638c13$DROP TRIGGER IF EXISTS trigger_auto_assign_merchant_group ON public.merchants$bootstrap_sql_9a2d98638c13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a2d98638c13$;

DO $bootstrap_do_0197f3ecc133$
BEGIN
  EXECUTE $bootstrap_sql_0197f3ecc133$CREATE TRIGGER trigger_auto_assign_merchant_group
  BEFORE INSERT OR UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_assign_merchant_to_group()$bootstrap_sql_0197f3ecc133$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0197f3ecc133$;

DO $bootstrap_do_b07d5bc71cea$
BEGIN
  EXECUTE $bootstrap_sql_b07d5bc71cea$-- Function to calculate and record commission when subscription is paid
CREATE OR REPLACE FUNCTION public.record_verifikator_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_merchant RECORD;
  v_package RECORD;
  v_commission INTEGER;
BEGIN
  -- Only process when payment status changes to PAID
  IF NEW.payment_status = 'PAID' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'PAID') THEN
    -- Get merchant info
    SELECT * INTO v_merchant FROM merchants WHERE id = NEW.merchant_id;

    IF v_merchant.verifikator_id IS NOT NULL THEN
      -- Get package info
      SELECT * INTO v_package FROM transaction_packages WHERE id = NEW.package_id;

      -- Calculate commission
      v_commission := FLOOR(NEW.payment_amount * v_package.group_commission_percent / 100);

      IF v_commission > 0 THEN
        INSERT INTO verifikator_earnings (
          verifikator_id,
          merchant_id,
          subscription_id,
          package_id,
          package_amount,
          commission_percent,
          commission_amount,
          status
        ) VALUES (
          v_merchant.verifikator_id,
          NEW.merchant_id,
          NEW.id,
          NEW.package_id,
          NEW.payment_amount,
          v_package.group_commission_percent,
          v_commission,
          'PENDING'
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public$bootstrap_sql_b07d5bc71cea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b07d5bc71cea$;

DO $bootstrap_do_d94f17ccf0cf$
BEGIN
  EXECUTE $bootstrap_sql_d94f17ccf0cf$-- Create trigger for commission recording
DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON merchant_subscriptions$bootstrap_sql_d94f17ccf0cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d94f17ccf0cf$;

DO $bootstrap_do_4e7a6eb406d9$
BEGIN
  EXECUTE $bootstrap_sql_4e7a6eb406d9$DROP TRIGGER IF EXISTS trigger_record_verifikator_commission ON public.merchant_subscriptions$bootstrap_sql_4e7a6eb406d9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e7a6eb406d9$;

DO $bootstrap_do_6606f9b53d9f$
BEGIN
  EXECUTE $bootstrap_sql_6606f9b53d9f$CREATE TRIGGER trigger_record_verifikator_commission
  AFTER INSERT OR UPDATE ON public.merchant_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.record_verifikator_commission()$bootstrap_sql_6606f9b53d9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6606f9b53d9f$;

DO $bootstrap_do_8958cc263e18$
BEGIN
  EXECUTE $bootstrap_sql_8958cc263e18$
