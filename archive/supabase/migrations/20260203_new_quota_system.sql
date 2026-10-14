-- New Quota System Migration

-- 0. Cleanup old rules if necessary
-- The old logic was hardcoded in the application and simple decrement in DB.
-- We will replace the use_merchant_quota function.

-- 1. Create table for Quota Tiers Configuration
CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL,
  max_price INTEGER, -- NULL means no upper limit
  credit_cost INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_531f991da00d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_531f991da00d$;

DO $bootstrap_do_3cfd540de2a8$
BEGIN
  EXECUTE $bootstrap_sql_3cfd540de2a8$-- Enable RLS
ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY$bootstrap_sql_3cfd540de2a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3cfd540de2a8$;

DO $bootstrap_do_604e77bddf47$
BEGIN
  EXECUTE $bootstrap_sql_604e77bddf47$-- RLS for quota_tiers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Anyone can view quota tiers'
  ) THEN
    CREATE POLICY "Anyone can view quota tiers"
    ON public.quota_tiers FOR SELECT
    USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'quota_tiers'
      AND policyname = 'Admins can manage quota tiers'
  ) THEN
    CREATE POLICY "Admins can manage quota tiers"
    ON public.quota_tiers FOR ALL
    USING (is_admin());
  END IF;
END $$$bootstrap_sql_604e77bddf47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_604e77bddf47$;

DO $bootstrap_do_bcd497aec266$
BEGIN
  EXECUTE $bootstrap_sql_bcd497aec266$-- Insert default tiers based on user request
INSERT INTO public.quota_tiers (min_price, max_price, credit_cost) VALUES
(0, 3000, 1),
(3001, 4999, 2),
(5000, 9999, 3),
(10000, 14999, 5),
(15000, NULL, 10)
ON CONFLICT DO NOTHING$bootstrap_sql_bcd497aec266$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bcd497aec266$;

DO $bootstrap_do_bb3d351f789e$
BEGIN
  EXECUTE $bootstrap_sql_bb3d351f789e$-- 2. Modify transaction_packages to use "credits" instead of "transactions"
-- We'll keep the column name transaction_quota but treat it as credits conceptually,
-- or we can add a comment to clarify.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'transaction_packages'
      AND column_name = 'transaction_quota'
  ) THEN
    COMMENT ON COLUMN public.transaction_packages.transaction_quota IS 'Total credits provided by this package';
  END IF;
END $$$bootstrap_sql_bb3d351f789e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb3d351f789e$;

DO $bootstrap_do_f64508f8fc08$
BEGIN
  EXECUTE $bootstrap_sql_f64508f8fc08$-- 3. Create a function to calculate credit cost based on product price
CREATE OR REPLACE FUNCTION public.calculate_order_credit_cost(p_order_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_credits INTEGER := 0;
  v_item RECORD;
  v_tier_cost INTEGER;
BEGIN
  -- Loop through items in the order
  FOR v_item IN SELECT product_price, quantity FROM order_items WHERE order_id = p_order_id LOOP
    -- Find the matching tier for this product price
    SELECT credit_cost INTO v_tier_cost
    FROM quota_tiers
    WHERE v_item.product_price >= min_price
      AND (max_price IS NULL OR v_item.product_price <= max_price)
    LIMIT 1;

    -- Default to 1 if no tier found (safety)
    IF v_tier_cost IS NULL THEN
      v_tier_cost := 1;
    END IF;

    v_total_credits := v_total_credits + (v_tier_cost * v_item.quantity);
  END LOOP;

  RETURN v_total_credits;
END;
$$$bootstrap_sql_f64508f8fc08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f64508f8fc08$;

DO $bootstrap_do_acfa9d5d1be8$
BEGIN
  EXECUTE $bootstrap_sql_acfa9d5d1be8$-- 4. Update use_merchant_quota to accept credit amount
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub_id UUID;
BEGIN
  -- Find active subscription with enough quota
  SELECT id INTO v_sub_id
  FROM merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND (transaction_quota - used_quota) >= p_credits
  ORDER BY expired_at ASC -- Use the one expiring soonest first
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;

  RETURN TRUE;
END;
$$$bootstrap_sql_acfa9d5d1be8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_acfa9d5d1be8$;

DO $bootstrap_do_99618539d4f5$
BEGIN
  EXECUTE $bootstrap_sql_99618539d4f5$-- 5. Keep the old use_merchant_quota for backward compatibility but update it to use 1 credit
CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN use_merchant_quota_v2(p_merchant_id, 1);
END;
$$$bootstrap_sql_99618539d4f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99618539d4f5$;

DO $bootstrap_do_d8da1b2477ac$
BEGIN
  EXECUTE $bootstrap_sql_d8da1b2477ac$
