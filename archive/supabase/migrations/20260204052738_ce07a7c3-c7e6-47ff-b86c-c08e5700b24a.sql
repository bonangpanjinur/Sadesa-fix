-- ============================================================
-- FIX 1: Create SECURITY DEFINER functions to break RLS recursion
-- ============================================================

-- Function to check courier ownership without RLS
CREATE OR REPLACE FUNCTION public.get_user_courier_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.couriers WHERE user_id = _user_id LIMIT 1
$$$bootstrap_sql_3066a8dc2fcd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3066a8dc2fcd$;

DO $bootstrap_do_808dcb1a0e2d$
BEGIN
  EXECUTE $bootstrap_sql_808dcb1a0e2d$-- Function to check merchant ownership without RLS
CREATE OR REPLACE FUNCTION public.get_user_merchant_id(_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.merchants WHERE user_id = _user_id LIMIT 1
$$$bootstrap_sql_808dcb1a0e2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_808dcb1a0e2d$;

DO $bootstrap_do_adfab79d6870$
BEGIN
  EXECUTE $bootstrap_sql_adfab79d6870$-- Function to check if user is courier for specific courier_id
CREATE OR REPLACE FUNCTION public.is_courier_owner(_user_id UUID, _courier_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.couriers
    WHERE id = _courier_id AND user_id = _user_id
  )
$$$bootstrap_sql_adfab79d6870$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_adfab79d6870$;

DO $bootstrap_do_49b33912a608$
BEGIN
  EXECUTE $bootstrap_sql_49b33912a608$-- Function to check if user is merchant for specific order
CREATE OR REPLACE FUNCTION public.is_order_merchant(_user_id UUID, _merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.merchants
    WHERE id = _merchant_id AND user_id = _user_id
  )
$$$bootstrap_sql_49b33912a608$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49b33912a608$;

DO $bootstrap_do_903607a3913f$
BEGIN
  EXECUTE $bootstrap_sql_903607a3913f$-- ============================================================
-- FIX 2: Drop and recreate couriers RLS policies
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_903607a3913f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_903607a3913f$;

DO $bootstrap_do_cdff8c4b59df$
BEGIN
  EXECUTE $bootstrap_sql_cdff8c4b59df$DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_cdff8c4b59df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cdff8c4b59df$;

DO $bootstrap_do_980217fcf1ce$
BEGIN
  EXECUTE $bootstrap_sql_980217fcf1ce$DROP POLICY IF EXISTS "Authorized users can view courier info" ON public.couriers$bootstrap_sql_980217fcf1ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_980217fcf1ce$;

DO $bootstrap_do_b19e207fc917$
BEGIN
  EXECUTE $bootstrap_sql_b19e207fc917$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_b19e207fc917$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b19e207fc917$;

DO $bootstrap_do_edab0c221cce$
BEGIN
  EXECUTE $bootstrap_sql_edab0c221cce$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_edab0c221cce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_edab0c221cce$;

DO $bootstrap_do_82cb206d5ba1$
BEGIN
  EXECUTE $bootstrap_sql_82cb206d5ba1$DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_82cb206d5ba1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82cb206d5ba1$;

DO $bootstrap_do_183714bb2b98$
BEGIN
  EXECUTE $bootstrap_sql_183714bb2b98$-- 1. Couriers can view their own data (simple, no recursion)
CREATE POLICY "Couriers can view own data"
ON public.couriers
FOR SELECT
TO authenticated
USING (user_id = auth.uid())$bootstrap_sql_183714bb2b98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_183714bb2b98$;

DO $bootstrap_do_f26a31fec9c6$
BEGIN
  EXECUTE $bootstrap_sql_f26a31fec9c6$-- 2. Admins can manage all couriers using security definer function
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_f26a31fec9c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f26a31fec9c6$;

DO $bootstrap_do_4524061594b4$
BEGIN
  EXECUTE $bootstrap_sql_4524061594b4$CREATE POLICY "Admins can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_4524061594b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4524061594b4$;

DO $bootstrap_do_d4d218c5bade$
BEGIN
  EXECUTE $bootstrap_sql_d4d218c5bade$-- 3. Verifikator can manage couriers
DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_d4d218c5bade$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4d218c5bade$;

DO $bootstrap_do_b31b4793e4cf$
BEGIN
  EXECUTE $bootstrap_sql_b31b4793e4cf$CREATE POLICY "Verifikator can manage couriers"
ON public.couriers
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'verifikator'))$bootstrap_sql_b31b4793e4cf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b31b4793e4cf$;

DO $bootstrap_do_34362363f4bc$
BEGIN
  EXECUTE $bootstrap_sql_34362363f4bc$-- 4. Anyone can register as courier
DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_34362363f4bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34362363f4bc$;

DO $bootstrap_do_6444093d0afc$
BEGIN
  EXECUTE $bootstrap_sql_6444093d0afc$CREATE POLICY "Anyone can register as courier"
ON public.couriers
FOR INSERT
TO authenticated
WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE')$bootstrap_sql_6444093d0afc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6444093d0afc$;

DO $bootstrap_do_87abd4062c4e$
BEGIN
  EXECUTE $bootstrap_sql_87abd4062c4e$-- 5. Couriers can update own location
DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_87abd4062c4e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_87abd4062c4e$;

DO $bootstrap_do_6b4fab07b414$
BEGIN
  EXECUTE $bootstrap_sql_6b4fab07b414$CREATE POLICY "Couriers can update own location"
ON public.couriers
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() AND status = 'ACTIVE')$bootstrap_sql_6b4fab07b414$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b4fab07b414$;

DO $bootstrap_do_b43b27976561$
BEGIN
  EXECUTE $bootstrap_sql_b43b27976561$-- 6. Public view for approved couriers (for order assignment)
DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers$bootstrap_sql_b43b27976561$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b43b27976561$;

DO $bootstrap_do_11497965a57b$
BEGIN
  EXECUTE $bootstrap_sql_11497965a57b$CREATE POLICY "Public can view approved couriers"
ON public.couriers
FOR SELECT
TO authenticated
USING (registration_status = 'APPROVED' AND status = 'ACTIVE')$bootstrap_sql_11497965a57b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11497965a57b$;

DO $bootstrap_do_388e80d47864$
BEGIN
  EXECUTE $bootstrap_sql_388e80d47864$-- ============================================================
-- FIX 3: Drop and recreate orders RLS policies
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_388e80d47864$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_388e80d47864$;

DO $bootstrap_do_4ca37d0d7733$
BEGIN
  EXECUTE $bootstrap_sql_4ca37d0d7733$DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_4ca37d0d7733$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ca37d0d7733$;

DO $bootstrap_do_6b29dafd14f7$
BEGIN
  EXECUTE $bootstrap_sql_6b29dafd14f7$DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders$bootstrap_sql_6b29dafd14f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b29dafd14f7$;

DO $bootstrap_do_a1a67e07b235$
BEGIN
  EXECUTE $bootstrap_sql_a1a67e07b235$DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_a1a67e07b235$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1a67e07b235$;

DO $bootstrap_do_f4b470f59d13$
BEGIN
  EXECUTE $bootstrap_sql_f4b470f59d13$DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders$bootstrap_sql_f4b470f59d13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4b470f59d13$;

DO $bootstrap_do_4fd7aa2843dc$
BEGIN
  EXECUTE $bootstrap_sql_4fd7aa2843dc$DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders$bootstrap_sql_4fd7aa2843dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fd7aa2843dc$;

DO $bootstrap_do_571e3861d329$
BEGIN
  EXECUTE $bootstrap_sql_571e3861d329$DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders$bootstrap_sql_571e3861d329$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_571e3861d329$;

DO $bootstrap_do_3e506ea30491$
BEGIN
  EXECUTE $bootstrap_sql_3e506ea30491$DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders$bootstrap_sql_3e506ea30491$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e506ea30491$;

DO $bootstrap_do_3f113fbd5d68$
BEGIN
  EXECUTE $bootstrap_sql_3f113fbd5d68$-- 1. Buyers can view and manage their own orders
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_3f113fbd5d68$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f113fbd5d68$;

DO $bootstrap_do_530551e6a948$
BEGIN
  EXECUTE $bootstrap_sql_530551e6a948$CREATE POLICY "Buyers can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (auth.uid() = buyer_id)$bootstrap_sql_530551e6a948$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_530551e6a948$;

DO $bootstrap_do_88bfcba0311c$
BEGIN
  EXECUTE $bootstrap_sql_88bfcba0311c$DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_88bfcba0311c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88bfcba0311c$;

DO $bootstrap_do_a3860283a788$
BEGIN
  EXECUTE $bootstrap_sql_a3860283a788$CREATE POLICY "Buyers can create orders"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id)$bootstrap_sql_a3860283a788$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3860283a788$;

DO $bootstrap_do_04cdf703a0dc$
BEGIN
  EXECUTE $bootstrap_sql_04cdf703a0dc$DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders$bootstrap_sql_04cdf703a0dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04cdf703a0dc$;

DO $bootstrap_do_5d5f00c0f431$
BEGIN
  EXECUTE $bootstrap_sql_5d5f00c0f431$CREATE POLICY "Buyers can update own pending orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (auth.uid() = buyer_id AND status = 'NEW')$bootstrap_sql_5d5f00c0f431$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d5f00c0f431$;

DO $bootstrap_do_cac9510efa46$
BEGIN
  EXECUTE $bootstrap_sql_cac9510efa46$-- 2. Admins can manage all orders
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_cac9510efa46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cac9510efa46$;

DO $bootstrap_do_7749a21ea9d6$
BEGIN
  EXECUTE $bootstrap_sql_7749a21ea9d6$CREATE POLICY "Admins can manage all orders"
ON public.orders
FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_7749a21ea9d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7749a21ea9d6$;

DO $bootstrap_do_00ddd1c974ba$
BEGIN
  EXECUTE $bootstrap_sql_00ddd1c974ba$-- 3. Couriers can view and update assigned orders using security definer
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders$bootstrap_sql_00ddd1c974ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00ddd1c974ba$;

DO $bootstrap_do_4c0591180191$
BEGIN
  EXECUTE $bootstrap_sql_4c0591180191$CREATE POLICY "Couriers can view assigned orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id))$bootstrap_sql_4c0591180191$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c0591180191$;

DO $bootstrap_do_eb4c70f8f7e4$
BEGIN
  EXECUTE $bootstrap_sql_eb4c70f8f7e4$DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders$bootstrap_sql_eb4c70f8f7e4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb4c70f8f7e4$;

DO $bootstrap_do_b59e5fea8b07$
BEGIN
  EXECUTE $bootstrap_sql_b59e5fea8b07$CREATE POLICY "Couriers can update assigned orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_courier_owner(auth.uid(), courier_id))$bootstrap_sql_b59e5fea8b07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b59e5fea8b07$;

DO $bootstrap_do_e98654ceeb64$
BEGIN
  EXECUTE $bootstrap_sql_e98654ceeb64$-- 4. Merchants can view and update their orders using security definer
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders$bootstrap_sql_e98654ceeb64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e98654ceeb64$;

DO $bootstrap_do_457e32359884$
BEGIN
  EXECUTE $bootstrap_sql_457e32359884$CREATE POLICY "Merchants can view own orders"
ON public.orders
FOR SELECT
TO authenticated
USING (public.is_order_merchant(auth.uid(), merchant_id))$bootstrap_sql_457e32359884$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_457e32359884$;

DO $bootstrap_do_43b1f5cedf82$
BEGIN
  EXECUTE $bootstrap_sql_43b1f5cedf82$DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders$bootstrap_sql_43b1f5cedf82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43b1f5cedf82$;

DO $bootstrap_do_db65cc5b3b3c$
BEGIN
  EXECUTE $bootstrap_sql_db65cc5b3b3c$CREATE POLICY "Merchants can update own orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (public.is_order_merchant(auth.uid(), merchant_id))$bootstrap_sql_db65cc5b3b3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_db65cc5b3b3c$;

DO $bootstrap_do_e5931911c404$
BEGIN
  EXECUTE $bootstrap_sql_e5931911c404$-- ============================================================
-- FIX 4: Create quota_tiers table for dynamic pricing
-- ============================================================

CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL DEFAULT 0,
  max_price INTEGER DEFAULT NULL,
  credit_cost INTEGER NOT NULL DEFAULT 1,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_e5931911c404$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e5931911c404$;

DO $bootstrap_do_2df704bc37f9$
BEGIN
  EXECUTE $bootstrap_sql_2df704bc37f9$-- CREATE TABLE IF NOT EXISTS does not add columns to an existing table.
ALTER TABLE public.quota_tiers
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0$bootstrap_sql_2df704bc37f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2df704bc37f9$;

DO $bootstrap_do_d027a192161d$
BEGIN
  EXECUTE $bootstrap_sql_d027a192161d$-- Enable RLS
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY$bootstrap_sql_d027a192161d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d027a192161d$;

DO $bootstrap_do_b95b435a8b67$
BEGIN
  EXECUTE $bootstrap_sql_b95b435a8b67$-- RLS policies for quota_tiers. Earlier migrations may have created
-- policies with the same names, so creation must be idempotent.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Anyone can view quota tiers'
  ) THEN
    CREATE POLICY "Anyone can view quota tiers"
    ON public.quota_tiers
    FOR SELECT
    TO authenticated
    USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Admins can manage quota tiers'
  ) THEN
    CREATE POLICY "Admins can manage quota tiers"
    ON public.quota_tiers
    FOR ALL
    TO authenticated
    USING (public.has_role(auth.uid(), 'admin'));
  END IF;
END $$$bootstrap_sql_b95b435a8b67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b95b435a8b67$;

DO $bootstrap_do_081ffa8086ea$
BEGIN
  EXECUTE $bootstrap_sql_081ffa8086ea$-- Insert default tiers
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost, description, sort_order) VALUES
(0, 3000, 1, 'Produk harga rendah (Rp 0 - Rp 3.000)', 1),
(3001, 5000, 2, 'Produk harga menengah bawah (Rp 3.001 - Rp 5.000)', 2),
(5001, 8000, 3, 'Produk harga menengah (Rp 5.001 - Rp 8.000)', 3),
(8001, 15000, 4, 'Produk harga menengah atas (Rp 8.001 - Rp 15.000)', 4),
(15001, NULL, 5, 'Produk harga tinggi (Rp 15.001+)', 5)
ON CONFLICT DO NOTHING$bootstrap_sql_081ffa8086ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_081ffa8086ea$;

DO $bootstrap_do_f4d25e79b2e6$
BEGIN
  EXECUTE $bootstrap_sql_f4d25e79b2e6$-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_quota_tiers_updated_at ON public.quota_tiers$bootstrap_sql_f4d25e79b2e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4d25e79b2e6$;

DO $bootstrap_do_4e7791a7e4cb$
BEGIN
  EXECUTE $bootstrap_sql_4e7791a7e4cb$CREATE TRIGGER update_quota_tiers_updated_at
BEFORE UPDATE ON public.quota_tiers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_4e7791a7e4cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e7791a7e4cb$;

DO $bootstrap_do_f21311ef6f3b$
BEGIN
  EXECUTE $bootstrap_sql_f21311ef6f3b$-- ============================================================
-- FIX 5: Update transaction_packages table structure
-- ============================================================

-- Add missing columns if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public'
                 AND table_name = 'transaction_packages'
                 AND column_name = 'total_credits') THEN
    ALTER TABLE public.transaction_packages ADD COLUMN total_credits INTEGER NOT NULL DEFAULT 100;
  END IF;
END
$$$bootstrap_sql_f21311ef6f3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f21311ef6f3b$;

DO $bootstrap_do_b0c7fa2e17b4$
BEGIN
  EXECUTE $bootstrap_sql_b0c7fa2e17b4$-- Rename transaction_quota to total_credits if needed and update data
UPDATE public.transaction_packages SET total_credits = transaction_quota WHERE total_credits = 100$bootstrap_sql_b0c7fa2e17b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0c7fa2e17b4$;

DO $bootstrap_do_c29d2f07208e$
BEGIN
  EXECUTE $bootstrap_sql_c29d2f07208e$-- ============================================================
-- FIX 6: Add location columns to merchants if missing
-- ============================================================

-- location_lat and location_lng already exist based on types.ts
