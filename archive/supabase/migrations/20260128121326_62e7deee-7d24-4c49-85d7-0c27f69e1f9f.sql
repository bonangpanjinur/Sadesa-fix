-- Flash Sales Table
CREATE TABLE IF NOT EXISTS public.flash_sales (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  original_price INTEGER NOT NULL,
  flash_price INTEGER NOT NULL,
  stock_available INTEGER NOT NULL DEFAULT 1,
  stock_sold INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  start_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  end_time TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED', 'CANCELLED')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_826282b1d408$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_826282b1d408$;

DO $bootstrap_do_6a7b6fbdf974$
BEGIN
  EXECUTE $bootstrap_sql_6a7b6fbdf974$-- RLS for flash_sales
ALTER TABLE public.flash_sales ENABLE ROW LEVEL SECURITY$bootstrap_sql_6a7b6fbdf974$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a7b6fbdf974$;

DO $bootstrap_do_431dfc2fdbd1$
BEGIN
  EXECUTE $bootstrap_sql_431dfc2fdbd1$DROP POLICY IF EXISTS "Public can view active flash sales" ON public.flash_sales$bootstrap_sql_431dfc2fdbd1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_431dfc2fdbd1$;

DO $bootstrap_do_1672709300b1$
BEGIN
  EXECUTE $bootstrap_sql_1672709300b1$CREATE POLICY "Public can view active flash sales"
ON public.flash_sales FOR SELECT
USING (status = 'ACTIVE' AND end_time > now())$bootstrap_sql_1672709300b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1672709300b1$;

DO $bootstrap_do_0bd4dee91e13$
BEGIN
  EXECUTE $bootstrap_sql_0bd4dee91e13$DROP POLICY IF EXISTS "Merchants can manage their flash sales" ON public.flash_sales$bootstrap_sql_0bd4dee91e13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0bd4dee91e13$;

DO $bootstrap_do_07a7c0f3f814$
BEGIN
  EXECUTE $bootstrap_sql_07a7c0f3f814$CREATE POLICY "Merchants can manage their flash sales"
ON public.flash_sales FOR ALL
USING (
  merchant_id IN (
    SELECT id FROM public.merchants WHERE user_id = auth.uid()
  )
)$bootstrap_sql_07a7c0f3f814$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07a7c0f3f814$;

DO $bootstrap_do_9b88188b3325$
BEGIN
  EXECUTE $bootstrap_sql_9b88188b3325$DROP POLICY IF EXISTS "Admins can manage all flash sales" ON public.flash_sales$bootstrap_sql_9b88188b3325$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b88188b3325$;

DO $bootstrap_do_469b056044c1$
BEGIN
  EXECUTE $bootstrap_sql_469b056044c1$CREATE POLICY "Admins can manage all flash sales"
ON public.flash_sales FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
)$bootstrap_sql_469b056044c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_469b056044c1$;

DO $bootstrap_do_d7079e9b235a$
BEGIN
  EXECUTE $bootstrap_sql_d7079e9b235a$-- Add verified badge to merchants if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'merchants' AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE public.merchants ADD COLUMN is_verified BOOLEAN DEFAULT false;
    ALTER TABLE public.merchants ADD COLUMN verified_at TIMESTAMP WITH TIME ZONE;
    ALTER TABLE public.merchants ADD COLUMN verified_by UUID;
  END IF;
END $$$bootstrap_sql_d7079e9b235a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7079e9b235a$;

DO $bootstrap_do_98e2eda5eab8$
BEGIN
  EXECUTE $bootstrap_sql_98e2eda5eab8$-- Fix RLS policies that are too permissive
-- Drop and recreate permissive policies with proper checks

-- Fix product_variants policies
DROP POLICY IF EXISTS "Public can view product variants" ON public.product_variants$bootstrap_sql_98e2eda5eab8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_98e2eda5eab8$;

DO $bootstrap_do_3773dff5faac$
BEGIN
  EXECUTE $bootstrap_sql_3773dff5faac$DROP POLICY IF EXISTS "Public can view active product variants" ON public.product_variants$bootstrap_sql_3773dff5faac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3773dff5faac$;

DO $bootstrap_do_7351d4fb99be$
BEGIN
  EXECUTE $bootstrap_sql_7351d4fb99be$CREATE POLICY "Public can view active product variants"
ON public.product_variants FOR SELECT
USING (is_active = true)$bootstrap_sql_7351d4fb99be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7351d4fb99be$;

DO $bootstrap_do_8b3939ef7db4$
BEGIN
  EXECUTE $bootstrap_sql_8b3939ef7db4$-- Fix product_images policies
DROP POLICY IF EXISTS "Public can view product images" ON public.product_images$bootstrap_sql_8b3939ef7db4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b3939ef7db4$;

DO $bootstrap_do_f8039f46ed6d$
BEGIN
  EXECUTE $bootstrap_sql_f8039f46ed6d$CREATE POLICY "Public can view product images"
ON public.product_images FOR SELECT
USING (true)$bootstrap_sql_f8039f46ed6d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8039f46ed6d$;

DO $bootstrap_do_a567b24e84fc$
BEGIN
  EXECUTE $bootstrap_sql_a567b24e84fc$-- Add index for flash sale queries
CREATE INDEX IF NOT EXISTS idx_flash_sales_status_end ON public.flash_sales(status, end_time)$bootstrap_sql_a567b24e84fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a567b24e84fc$;

DO $bootstrap_do_7ef62e76c695$
BEGIN
  EXECUTE $bootstrap_sql_7ef62e76c695$CREATE INDEX IF NOT EXISTS idx_flash_sales_merchant ON public.flash_sales(merchant_id)$bootstrap_sql_7ef62e76c695$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ef62e76c695$;

DO $bootstrap_do_3de7efdc956e$
BEGIN
  EXECUTE $bootstrap_sql_3de7efdc956e$-- Enable realtime for flash_sales
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'flash_sales'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.flash_sales;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_3de7efdc956e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3de7efdc956e$;

DO $bootstrap_do_5d20ad708383$
BEGIN
  EXECUTE $bootstrap_sql_5d20ad708383$
