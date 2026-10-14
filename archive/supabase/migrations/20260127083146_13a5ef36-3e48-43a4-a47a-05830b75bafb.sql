-- Add POD (Proof of Delivery) columns to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS pod_image_url TEXT,
ADD COLUMN IF NOT EXISTS pod_notes TEXT,
ADD COLUMN IF NOT EXISTS pod_uploaded_at TIMESTAMP WITH TIME ZONE$bootstrap_sql_0ed12aca6eec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ed12aca6eec$;

DO $bootstrap_do_07595be08e8c$
BEGIN
  EXECUTE $bootstrap_sql_07595be08e8c$-- Create platform_fees table for financial tracking
CREATE TABLE IF NOT EXISTS public.platform_fees (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE SET NULL,
  order_total INTEGER NOT NULL DEFAULT 0,
  shipping_cost INTEGER NOT NULL DEFAULT 0,
  platform_fee INTEGER NOT NULL DEFAULT 0,
  platform_fee_percent NUMERIC NOT NULL DEFAULT 0,
  courier_fee INTEGER NOT NULL DEFAULT 0,
  merchant_revenue INTEGER NOT NULL DEFAULT 0,
  fee_type TEXT NOT NULL DEFAULT 'ORDER',
  status TEXT NOT NULL DEFAULT 'PENDING',
  collected_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_07595be08e8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07595be08e8c$;

DO $bootstrap_do_f20ef83ecdd3$
BEGIN
  EXECUTE $bootstrap_sql_f20ef83ecdd3$-- Enable RLS
ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY$bootstrap_sql_f20ef83ecdd3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f20ef83ecdd3$;

DO $bootstrap_do_c8cb1d25f2bb$
BEGIN
  EXECUTE $bootstrap_sql_c8cb1d25f2bb$-- RLS policies for platform_fees
DROP POLICY IF EXISTS "Admins can manage platform_fees" ON public.platform_fees$bootstrap_sql_c8cb1d25f2bb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8cb1d25f2bb$;

DO $bootstrap_do_c8ab66d2b6ef$
BEGIN
  EXECUTE $bootstrap_sql_c8ab66d2b6ef$CREATE POLICY "Admins can manage platform_fees" ON public.platform_fees
  FOR ALL USING (is_admin())$bootstrap_sql_c8ab66d2b6ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8ab66d2b6ef$;

DO $bootstrap_do_47742e855c6d$
BEGIN
  EXECUTE $bootstrap_sql_47742e855c6d$DROP POLICY IF EXISTS "Merchants can view own fees" ON public.platform_fees$bootstrap_sql_47742e855c6d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47742e855c6d$;

DO $bootstrap_do_cbef0426c2c9$
BEGIN
  EXECUTE $bootstrap_sql_cbef0426c2c9$CREATE POLICY "Merchants can view own fees" ON public.platform_fees
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id = platform_fees.merchant_id
      AND merchants.user_id = auth.uid()
    )
  )$bootstrap_sql_cbef0426c2c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cbef0426c2c9$;

DO $bootstrap_do_d9ef9674273c$
BEGIN
  EXECUTE $bootstrap_sql_d9ef9674273c$-- Create broadcast_notifications table
CREATE TABLE IF NOT EXISTS public.broadcast_notifications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  target_audience TEXT NOT NULL DEFAULT 'ALL',
  target_roles TEXT[] DEFAULT '{}',
  scheduled_at TIMESTAMP WITH TIME ZONE,
  sent_at TIMESTAMP WITH TIME ZONE,
  sent_count INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  created_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_d9ef9674273c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9ef9674273c$;

DO $bootstrap_do_56bdaae8c1a8$
BEGIN
  EXECUTE $bootstrap_sql_56bdaae8c1a8$-- Enable RLS
ALTER TABLE public.broadcast_notifications ENABLE ROW LEVEL SECURITY$bootstrap_sql_56bdaae8c1a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56bdaae8c1a8$;

DO $bootstrap_do_825d8a8450da$
BEGIN
  EXECUTE $bootstrap_sql_825d8a8450da$-- RLS policies for broadcast_notifications
DROP POLICY IF EXISTS "Admins can manage broadcasts" ON public.broadcast_notifications$bootstrap_sql_825d8a8450da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_825d8a8450da$;

DO $bootstrap_do_5130beb03a2b$
BEGIN
  EXECUTE $bootstrap_sql_5130beb03a2b$CREATE POLICY "Admins can manage broadcasts" ON public.broadcast_notifications
  FOR ALL USING (is_admin())$bootstrap_sql_5130beb03a2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5130beb03a2b$;

DO $bootstrap_do_6b5fa6123196$
BEGIN
  EXECUTE $bootstrap_sql_6b5fa6123196$-- Add courier earnings table
CREATE TABLE IF NOT EXISTS public.courier_earnings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  amount INTEGER NOT NULL DEFAULT 0,
  type TEXT NOT NULL DEFAULT 'DELIVERY',
  status TEXT NOT NULL DEFAULT 'PENDING',
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_6b5fa6123196$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b5fa6123196$;

DO $bootstrap_do_2e723a2395fe$
BEGIN
  EXECUTE $bootstrap_sql_2e723a2395fe$-- Enable RLS
ALTER TABLE public.courier_earnings ENABLE ROW LEVEL SECURITY$bootstrap_sql_2e723a2395fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e723a2395fe$;

DO $bootstrap_do_f7781eaa421e$
BEGIN
  EXECUTE $bootstrap_sql_f7781eaa421e$-- RLS policies for courier_earnings
DROP POLICY IF EXISTS "Admins can manage courier earnings" ON public.courier_earnings$bootstrap_sql_f7781eaa421e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7781eaa421e$;

DO $bootstrap_do_cf87261487bc$
BEGIN
  EXECUTE $bootstrap_sql_cf87261487bc$CREATE POLICY "Admins can manage courier earnings" ON public.courier_earnings
  FOR ALL USING (is_admin())$bootstrap_sql_cf87261487bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf87261487bc$;

DO $bootstrap_do_c0dda1e9f83c$
BEGIN
  EXECUTE $bootstrap_sql_c0dda1e9f83c$DROP POLICY IF EXISTS "Couriers can view own earnings" ON public.courier_earnings$bootstrap_sql_c0dda1e9f83c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c0dda1e9f83c$;

DO $bootstrap_do_78234c9c1417$
BEGIN
  EXECUTE $bootstrap_sql_78234c9c1417$CREATE POLICY "Couriers can view own earnings" ON public.courier_earnings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM couriers
      WHERE couriers.id = courier_earnings.courier_id
      AND couriers.user_id = auth.uid()
    )
  )$bootstrap_sql_78234c9c1417$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78234c9c1417$;

DO $bootstrap_do_d31892b6b9f4$
BEGIN
  EXECUTE $bootstrap_sql_d31892b6b9f4$-- Create storage bucket for POD images
INSERT INTO storage.buckets (id, name, public)
VALUES ('pod-images', 'pod-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_d31892b6b9f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d31892b6b9f4$;

DO $bootstrap_do_ef79d02739f3$
BEGIN
  EXECUTE $bootstrap_sql_ef79d02739f3$-- Storage policies for POD images (safe to retry)
DROP POLICY IF EXISTS "Anyone can view POD images" ON storage.objects$bootstrap_sql_ef79d02739f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef79d02739f3$;

DO $bootstrap_do_51bb2948b595$
BEGIN
  EXECUTE $bootstrap_sql_51bb2948b595$DROP POLICY IF EXISTS "Couriers can upload POD images" ON storage.objects$bootstrap_sql_51bb2948b595$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51bb2948b595$;

DO $bootstrap_do_076504267a02$
BEGIN
  EXECUTE $bootstrap_sql_076504267a02$CREATE POLICY "Anyone can view POD images" ON storage.objects
  FOR SELECT USING (bucket_id = 'pod-images')$bootstrap_sql_076504267a02$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_076504267a02$;

DO $bootstrap_do_ce762bfbe25c$
BEGIN
  EXECUTE $bootstrap_sql_ce762bfbe25c$CREATE POLICY "Couriers can upload POD images" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'pod-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_ce762bfbe25c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce762bfbe25c$;

DO $bootstrap_do_a172cc70bae1$
BEGIN
  EXECUTE $bootstrap_sql_a172cc70bae1$-- Enable realtime for orders (for courier tracking)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'courier_earnings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_earnings;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_a172cc70bae1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a172cc70bae1$;

DO $bootstrap_do_a06466910e91$
BEGIN
  EXECUTE $bootstrap_sql_a06466910e91$
