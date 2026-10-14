-- =============================================
-- MERCHANT DASHBOARD & COD SECURITY SCHEMA
-- =============================================

-- 1. Add product analytics columns
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS order_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS discount_percent INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS discount_end_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS min_stock_alert INTEGER DEFAULT 5$bootstrap_sql_0ddf13359f1b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ddf13359f1b$;

DO $bootstrap_do_48836acb5c62$
BEGIN
  EXECUTE $bootstrap_sql_48836acb5c62$-- 2. Add COD security fields to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS cod_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS trust_score INTEGER DEFAULT 100,
ADD COLUMN IF NOT EXISTS cod_fail_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_verified_buyer BOOLEAN DEFAULT false$bootstrap_sql_48836acb5c62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_48836acb5c62$;

DO $bootstrap_do_26e78c63dcd5$
BEGIN
  EXECUTE $bootstrap_sql_26e78c63dcd5$-- 3. Create reviews table
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  buyer_id UUID NOT NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  image_urls TEXT[] DEFAULT '{}',
  merchant_reply TEXT,
  merchant_replied_at TIMESTAMP WITH TIME ZONE,
  is_visible BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
)$bootstrap_sql_26e78c63dcd5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26e78c63dcd5$;

DO $bootstrap_do_01adfbd828cf$
BEGIN
  EXECUTE $bootstrap_sql_01adfbd828cf$-- 4. Create withdrawal_requests table
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  bank_name TEXT NOT NULL,
  account_number TEXT NOT NULL,
  account_holder TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
)$bootstrap_sql_01adfbd828cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01adfbd828cf$;

DO $bootstrap_do_3267077139c2$
BEGIN
  EXECUTE $bootstrap_sql_3267077139c2$-- 5. Create insurance_fund table for COD protection
CREATE TABLE IF NOT EXISTS public.insurance_fund (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  type TEXT NOT NULL, -- 'contribution' or 'claim'
  status TEXT DEFAULT 'PENDING', -- For claims: PENDING, APPROVED, REJECTED
  claim_reason TEXT,
  evidence_urls TEXT[] DEFAULT '{}',
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
)$bootstrap_sql_3267077139c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3267077139c2$;

DO $bootstrap_do_412a0adfe215$
BEGIN
  EXECUTE $bootstrap_sql_412a0adfe215$-- 6. Add COD-related fields to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS confirmation_deadline TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS is_flash_sale BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS flash_sale_discount INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cod_service_fee INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS buyer_distance_km NUMERIC$bootstrap_sql_412a0adfe215$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_412a0adfe215$;

DO $bootstrap_do_8e5d3e263842$
BEGIN
  EXECUTE $bootstrap_sql_8e5d3e263842$-- 7. Add merchant balance tracking
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS available_balance INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS pending_balance INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_withdrawn INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS cod_max_amount INTEGER DEFAULT 75000,
ADD COLUMN IF NOT EXISTS cod_max_distance_km NUMERIC DEFAULT 3$bootstrap_sql_8e5d3e263842$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e5d3e263842$;

DO $bootstrap_do_0d7d2967c61c$
BEGIN
  EXECUTE $bootstrap_sql_0d7d2967c61c$-- Enable RLS on new tables
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY$bootstrap_sql_0d7d2967c61c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d7d2967c61c$;

DO $bootstrap_do_ad8bfd3e66f8$
BEGIN
  EXECUTE $bootstrap_sql_ad8bfd3e66f8$ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_ad8bfd3e66f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad8bfd3e66f8$;

DO $bootstrap_do_9bc9e69fd59a$
BEGIN
  EXECUTE $bootstrap_sql_9bc9e69fd59a$ALTER TABLE public.insurance_fund ENABLE ROW LEVEL SECURITY$bootstrap_sql_9bc9e69fd59a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9bc9e69fd59a$;

DO $bootstrap_do_5625591e9b47$
BEGIN
  EXECUTE $bootstrap_sql_5625591e9b47$-- Reviews policies
DROP POLICY IF EXISTS "Anyone can view visible reviews" ON public.reviews$bootstrap_sql_5625591e9b47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5625591e9b47$;

DO $bootstrap_do_869abe66d8fb$
BEGIN
  EXECUTE $bootstrap_sql_869abe66d8fb$CREATE POLICY "Anyone can view visible reviews" ON public.reviews
FOR SELECT USING (is_visible = true)$bootstrap_sql_869abe66d8fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_869abe66d8fb$;

DO $bootstrap_do_c22450a9df55$
BEGIN
  EXECUTE $bootstrap_sql_c22450a9df55$DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews$bootstrap_sql_c22450a9df55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c22450a9df55$;

DO $bootstrap_do_f607c82ade6f$
BEGIN
  EXECUTE $bootstrap_sql_f607c82ade6f$CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews
FOR INSERT WITH CHECK (buyer_id = auth.uid())$bootstrap_sql_f607c82ade6f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f607c82ade6f$;

DO $bootstrap_do_983c8a189cb3$
BEGIN
  EXECUTE $bootstrap_sql_983c8a189cb3$DROP POLICY IF EXISTS "Merchants can reply to their reviews" ON public.reviews$bootstrap_sql_983c8a189cb3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_983c8a189cb3$;

DO $bootstrap_do_0da4696721db$
BEGIN
  EXECUTE $bootstrap_sql_0da4696721db$CREATE POLICY "Merchants can reply to their reviews" ON public.reviews
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = reviews.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_0da4696721db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0da4696721db$;

DO $bootstrap_do_6158c64f15fd$
BEGIN
  EXECUTE $bootstrap_sql_6158c64f15fd$DROP POLICY IF EXISTS "Admins can manage reviews" ON public.reviews$bootstrap_sql_6158c64f15fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6158c64f15fd$;

DO $bootstrap_do_9cdf21d9ff48$
BEGIN
  EXECUTE $bootstrap_sql_9cdf21d9ff48$CREATE POLICY "Admins can manage reviews" ON public.reviews
FOR ALL USING (is_admin())$bootstrap_sql_9cdf21d9ff48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cdf21d9ff48$;

DO $bootstrap_do_37dddc0322ec$
BEGIN
  EXECUTE $bootstrap_sql_37dddc0322ec$-- Withdrawal requests policies
DROP POLICY IF EXISTS "Merchants can view own withdrawals" ON public.withdrawal_requests$bootstrap_sql_37dddc0322ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_37dddc0322ec$;

DO $bootstrap_do_768846ee00cb$
BEGIN
  EXECUTE $bootstrap_sql_768846ee00cb$CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = withdrawal_requests.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_768846ee00cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_768846ee00cb$;

DO $bootstrap_do_289c984d69fe$
BEGIN
  EXECUTE $bootstrap_sql_289c984d69fe$DROP POLICY IF EXISTS "Merchants can create withdrawals" ON public.withdrawal_requests$bootstrap_sql_289c984d69fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_289c984d69fe$;

DO $bootstrap_do_8c551416640f$
BEGIN
  EXECUTE $bootstrap_sql_8c551416640f$CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = withdrawal_requests.merchant_id
    AND merchants.user_id = auth.uid()
  ) AND status = 'PENDING'
)$bootstrap_sql_8c551416640f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c551416640f$;

DO $bootstrap_do_cf10cbd04375$
BEGIN
  EXECUTE $bootstrap_sql_cf10cbd04375$DROP POLICY IF EXISTS "Admins can manage withdrawals" ON public.withdrawal_requests$bootstrap_sql_cf10cbd04375$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf10cbd04375$;

DO $bootstrap_do_7204f9153d45$
BEGIN
  EXECUTE $bootstrap_sql_7204f9153d45$CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests
FOR ALL USING (is_admin())$bootstrap_sql_7204f9153d45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7204f9153d45$;

DO $bootstrap_do_6262c58cfe1d$
BEGIN
  EXECUTE $bootstrap_sql_6262c58cfe1d$-- Insurance fund policies
DROP POLICY IF EXISTS "Merchants can view own insurance" ON public.insurance_fund$bootstrap_sql_6262c58cfe1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6262c58cfe1d$;

DO $bootstrap_do_fba77a70baeb$
BEGIN
  EXECUTE $bootstrap_sql_fba77a70baeb$CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = insurance_fund.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_fba77a70baeb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fba77a70baeb$;

DO $bootstrap_do_c5de78507811$
BEGIN
  EXECUTE $bootstrap_sql_c5de78507811$DROP POLICY IF EXISTS "Merchants can create claims" ON public.insurance_fund$bootstrap_sql_c5de78507811$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5de78507811$;

DO $bootstrap_do_efbc790d94a6$
BEGIN
  EXECUTE $bootstrap_sql_efbc790d94a6$CREATE POLICY "Merchants can create claims" ON public.insurance_fund
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM merchants
    WHERE merchants.id = insurance_fund.merchant_id
    AND merchants.user_id = auth.uid()
  ) AND type = 'claim' AND status = 'PENDING'
)$bootstrap_sql_efbc790d94a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efbc790d94a6$;

DO $bootstrap_do_d96cbfde3c03$
BEGIN
  EXECUTE $bootstrap_sql_d96cbfde3c03$DROP POLICY IF EXISTS "Admins can manage insurance fund" ON public.insurance_fund$bootstrap_sql_d96cbfde3c03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d96cbfde3c03$;

DO $bootstrap_do_63393ba7da6f$
BEGIN
  EXECUTE $bootstrap_sql_63393ba7da6f$CREATE POLICY "Admins can manage insurance fund" ON public.insurance_fund
FOR ALL USING (is_admin())$bootstrap_sql_63393ba7da6f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63393ba7da6f$;

DO $bootstrap_do_3919b3ee6fea$
BEGIN
  EXECUTE $bootstrap_sql_3919b3ee6fea$-- Function to check COD eligibility
CREATE OR REPLACE FUNCTION public.check_cod_eligibility(
  p_buyer_id UUID,
  p_merchant_id UUID,
  p_total_amount INTEGER,
  p_distance_km NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile RECORD;
  v_merchant RECORD;
  v_result JSONB;
BEGIN
  -- Get buyer profile
  SELECT cod_enabled, trust_score, cod_fail_count
  INTO v_profile
  FROM profiles
  WHERE user_id = p_buyer_id;

  -- Get merchant settings
  SELECT cod_max_amount, cod_max_distance_km
  INTO v_merchant
  FROM merchants
  WHERE id = p_merchant_id;

  -- Check eligibility
  IF v_profile.cod_enabled = false THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Akun Anda tidak dapat menggunakan fitur COD.');
  END IF;

  IF v_profile.trust_score < 50 THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Skor kepercayaan Anda terlalu rendah untuk COD.');
  END IF;

  IF p_total_amount > COALESCE(v_merchant.cod_max_amount, 75000) THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Nominal terlalu besar untuk COD. Maks: Rp ' || COALESCE(v_merchant.cod_max_amount, 75000));
  END IF;

  IF p_distance_km IS NOT NULL AND p_distance_km > COALESCE(v_merchant.cod_max_distance_km, 3) THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Jarak terlalu jauh untuk COD. Maks: ' || COALESCE(v_merchant.cod_max_distance_km, 3) || ' KM');
  END IF;

  RETURN jsonb_build_object('eligible', true, 'reason', NULL);
END;
$$$bootstrap_sql_3919b3ee6fea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3919b3ee6fea$;

DO $bootstrap_do_a2ddeaa43ca3$
BEGIN
  EXECUTE $bootstrap_sql_a2ddeaa43ca3$-- Function to update trust score after COD result
CREATE OR REPLACE FUNCTION public.update_trust_score()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If order was rejected by buyer (COD failed)
  IF NEW.status = 'REJECTED_BY_BUYER' AND OLD.status != 'REJECTED_BY_BUYER' THEN
    UPDATE profiles
    SET
      trust_score = GREATEST(0, trust_score - 50),
      cod_fail_count = cod_fail_count + 1,
      cod_enabled = CASE WHEN trust_score - 50 < 50 THEN false ELSE cod_enabled END
    WHERE user_id = NEW.buyer_id;
  END IF;

  -- If COD order completed successfully
  IF NEW.status = 'DONE' AND OLD.status != 'DONE' AND NEW.payment_method = 'COD' THEN
    UPDATE profiles
    SET trust_score = LEAST(100, trust_score + 1)
    WHERE user_id = NEW.buyer_id;
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_a2ddeaa43ca3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2ddeaa43ca3$;

DO $bootstrap_do_15f840fa3713$
BEGIN
  EXECUTE $bootstrap_sql_15f840fa3713$-- Create trigger for trust score updates
DROP TRIGGER IF EXISTS trigger_update_trust_score ON orders$bootstrap_sql_15f840fa3713$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15f840fa3713$;

DO $bootstrap_do_a230c8c4cb9a$
BEGIN
  EXECUTE $bootstrap_sql_a230c8c4cb9a$CREATE TRIGGER trigger_update_trust_score
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION update_trust_score()$bootstrap_sql_a230c8c4cb9a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a230c8c4cb9a$;

DO $bootstrap_do_a30693f594b4$
BEGIN
  EXECUTE $bootstrap_sql_a30693f594b4$-- Function to auto-cancel pending confirmation orders
CREATE OR REPLACE FUNCTION public.auto_cancel_pending_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE orders
  SET
    status = 'CANCELED',
    notes = COALESCE(notes, '') || ' [Auto-canceled: Tidak dikonfirmasi dalam 15 menit]',
    updated_at = now()
  WHERE
    status = 'PENDING_CONFIRMATION'
    AND confirmation_deadline < now();
END;
$$$bootstrap_sql_a30693f594b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a30693f594b4$;

DO $bootstrap_do_193f06929722$
BEGIN
  EXECUTE $bootstrap_sql_193f06929722$-- Update updated_at trigger for new tables
DROP TRIGGER IF EXISTS update_reviews_updated_at ON public.reviews$bootstrap_sql_193f06929722$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_193f06929722$;

DO $bootstrap_do_51e42294208a$
BEGIN
  EXECUTE $bootstrap_sql_51e42294208a$CREATE TRIGGER update_reviews_updated_at
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_51e42294208a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51e42294208a$;

DO $bootstrap_do_6ee4c7ad260b$
BEGIN
  EXECUTE $bootstrap_sql_6ee4c7ad260b$DROP TRIGGER IF EXISTS update_withdrawal_requests_updated_at ON public.withdrawal_requests$bootstrap_sql_6ee4c7ad260b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ee4c7ad260b$;

DO $bootstrap_do_8122176f3f40$
BEGIN
  EXECUTE $bootstrap_sql_8122176f3f40$CREATE TRIGGER update_withdrawal_requests_updated_at
  BEFORE UPDATE ON public.withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_8122176f3f40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8122176f3f40$;

DO $bootstrap_do_d3b318bbd1e3$
BEGIN
  EXECUTE $bootstrap_sql_d3b318bbd1e3$
