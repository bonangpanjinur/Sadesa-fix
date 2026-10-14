-- Transaction Packages Table (paket_transaksi)
CREATE TABLE public.transaction_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  classification_price TEXT NOT NULL,
  price_per_transaction INTEGER NOT NULL DEFAULT 0,
  kas_fee INTEGER NOT NULL DEFAULT 0,
  transaction_quota INTEGER NOT NULL DEFAULT 100,
  validity_days INTEGER NOT NULL DEFAULT 30,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_cea914ffee17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cea914ffee17$;

DO $bootstrap_do_5106aa93c175$
BEGIN
  EXECUTE $bootstrap_sql_5106aa93c175$-- Merchant Subscriptions Table (langganan pedagang)
CREATE TABLE public.merchant_subscriptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID NOT NULL REFERENCES public.transaction_packages(id),
  transaction_quota INTEGER NOT NULL DEFAULT 0,
  used_quota INTEGER NOT NULL DEFAULT 0,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  expired_at TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  payment_status TEXT NOT NULL DEFAULT 'UNPAID',
  payment_amount INTEGER NOT NULL DEFAULT 0,
  paid_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_5106aa93c175$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5106aa93c175$;

DO $bootstrap_do_1f5f951fd155$
BEGIN
  EXECUTE $bootstrap_sql_1f5f951fd155$-- Enable RLS
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_1f5f951fd155$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f5f951fd155$;

DO $bootstrap_do_e7690c237ae8$
BEGIN
  EXECUTE $bootstrap_sql_e7690c237ae8$ALTER TABLE public.merchant_subscriptions ENABLE ROW LEVEL SECURITY$bootstrap_sql_e7690c237ae8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7690c237ae8$;

DO $bootstrap_do_2a4fc4d9d2ef$
BEGIN
  EXECUTE $bootstrap_sql_2a4fc4d9d2ef$-- RLS for transaction_packages (public read, admin manage)
DROP POLICY IF EXISTS "Anyone can view active packages" ON public.transaction_packages$bootstrap_sql_2a4fc4d9d2ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a4fc4d9d2ef$;

DO $bootstrap_do_7c1a15cc7ad0$
BEGIN
  EXECUTE $bootstrap_sql_7c1a15cc7ad0$CREATE POLICY "Anyone can view active packages"
ON public.transaction_packages FOR SELECT
USING (is_active = true)$bootstrap_sql_7c1a15cc7ad0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c1a15cc7ad0$;

DO $bootstrap_do_5f3664a222d4$
BEGIN
  EXECUTE $bootstrap_sql_5f3664a222d4$DROP POLICY IF EXISTS "Admins can manage packages" ON public.transaction_packages$bootstrap_sql_5f3664a222d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f3664a222d4$;

DO $bootstrap_do_765a56b7f5f5$
BEGIN
  EXECUTE $bootstrap_sql_765a56b7f5f5$CREATE POLICY "Admins can manage packages"
ON public.transaction_packages FOR ALL
USING (is_admin())$bootstrap_sql_765a56b7f5f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_765a56b7f5f5$;

DO $bootstrap_do_e255e66f39fe$
BEGIN
  EXECUTE $bootstrap_sql_e255e66f39fe$-- RLS for merchant_subscriptions
DROP POLICY IF EXISTS "Merchants can view own subscriptions" ON public.merchant_subscriptions$bootstrap_sql_e255e66f39fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e255e66f39fe$;

DO $bootstrap_do_86ca494f864d$
BEGIN
  EXECUTE $bootstrap_sql_86ca494f864d$CREATE POLICY "Merchants can view own subscriptions"
ON public.merchant_subscriptions FOR SELECT
USING (EXISTS (
  SELECT 1 FROM merchants
  WHERE merchants.id = merchant_subscriptions.merchant_id
  AND merchants.user_id = auth.uid()
))$bootstrap_sql_86ca494f864d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86ca494f864d$;

DO $bootstrap_do_2fab51d08afb$
BEGIN
  EXECUTE $bootstrap_sql_2fab51d08afb$DROP POLICY IF EXISTS "Merchants can create subscriptions" ON public.merchant_subscriptions$bootstrap_sql_2fab51d08afb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2fab51d08afb$;

DO $bootstrap_do_6adef4e70ff0$
BEGIN
  EXECUTE $bootstrap_sql_6adef4e70ff0$CREATE POLICY "Merchants can create subscriptions"
ON public.merchant_subscriptions FOR INSERT
WITH CHECK (EXISTS (
  SELECT 1 FROM merchants
  WHERE merchants.id = merchant_subscriptions.merchant_id
  AND merchants.user_id = auth.uid()
) AND status = 'PENDING')$bootstrap_sql_6adef4e70ff0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6adef4e70ff0$;

DO $bootstrap_do_7e5cdd57eccb$
BEGIN
  EXECUTE $bootstrap_sql_7e5cdd57eccb$DROP POLICY IF EXISTS "Admins can manage all subscriptions" ON public.merchant_subscriptions$bootstrap_sql_7e5cdd57eccb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e5cdd57eccb$;

DO $bootstrap_do_1e3c5a7e0392$
BEGIN
  EXECUTE $bootstrap_sql_1e3c5a7e0392$CREATE POLICY "Admins can manage all subscriptions"
ON public.merchant_subscriptions FOR ALL
USING (is_admin())$bootstrap_sql_1e3c5a7e0392$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e3c5a7e0392$;

DO $bootstrap_do_2ba1a011989f$
BEGIN
  EXECUTE $bootstrap_sql_2ba1a011989f$-- Add current_subscription_id to merchants table for quick access
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS current_subscription_id UUID REFERENCES public.merchant_subscriptions(id)$bootstrap_sql_2ba1a011989f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ba1a011989f$;

DO $bootstrap_do_e11bf01ef805$
BEGIN
  EXECUTE $bootstrap_sql_e11bf01ef805$-- Create indexes
CREATE INDEX idx_merchant_subscriptions_merchant ON public.merchant_subscriptions(merchant_id)$bootstrap_sql_e11bf01ef805$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e11bf01ef805$;

DO $bootstrap_do_897f37f9a03c$
BEGIN
  EXECUTE $bootstrap_sql_897f37f9a03c$CREATE INDEX idx_merchant_subscriptions_status ON public.merchant_subscriptions(status)$bootstrap_sql_897f37f9a03c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_897f37f9a03c$;

DO $bootstrap_do_a7888febd129$
BEGIN
  EXECUTE $bootstrap_sql_a7888febd129$CREATE INDEX idx_transaction_packages_classification ON public.transaction_packages(classification_price)$bootstrap_sql_a7888febd129$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7888febd129$;

DO $bootstrap_do_f6f9d6ced1d3$
BEGIN
  EXECUTE $bootstrap_sql_f6f9d6ced1d3$-- Insert default packages based on classification
INSERT INTO public.transaction_packages (name, classification_price, price_per_transaction, kas_fee, transaction_quota, validity_days, description) VALUES
('Paket UMKM Mikro', 'UNDER_5K', 500, 1000, 50, 30, 'Untuk produk harga dibawah Rp 5.000'),
('Paket UMKM Kecil', 'FROM_5K_TO_10K', 750, 1500, 75, 30, 'Untuk produk harga Rp 5.000 - 10.000'),
('Paket UMKM Menengah', 'FROM_10K_TO_20K', 1000, 2000, 100, 30, 'Untuk produk harga Rp 10.000 - 20.000'),
('Paket UMKM Premium', 'ABOVE_20K', 1500, 2500, 150, 30, 'Untuk produk harga diatas Rp 20.000')
ON CONFLICT DO NOTHING$bootstrap_sql_f6f9d6ced1d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f6f9d6ced1d3$;

DO $bootstrap_do_761ee4bf03ea$
BEGIN
  EXECUTE $bootstrap_sql_761ee4bf03ea$-- Function to check and decrement quota
CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_subscription RECORD;
BEGIN
  -- Get active subscription
  SELECT * INTO v_subscription
  FROM merchant_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND used_quota < transaction_quota
  ORDER BY expired_at DESC
  LIMIT 1;

  IF v_subscription IS NULL THEN
    RETURN jsonb_build_object(
      'can_transact', false,
      'reason', 'Tidak ada kuota transaksi aktif. Silakan beli paket terlebih dahulu.',
      'remaining_quota', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'can_transact', true,
    'remaining_quota', v_subscription.transaction_quota - v_subscription.used_quota,
    'subscription_id', v_subscription.id
  );
END;
$$$bootstrap_sql_761ee4bf03ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_761ee4bf03ea$;

DO $bootstrap_do_48af56bfe282$
BEGIN
  EXECUTE $bootstrap_sql_48af56bfe282$-- Function to use quota (call after successful order)
CREATE OR REPLACE FUNCTION public.use_merchant_quota(p_merchant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE merchant_subscriptions
  SET used_quota = used_quota + 1, updated_at = now()
  WHERE merchant_id = p_merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
    AND used_quota < transaction_quota;

  RETURN FOUND;
END;
$$$bootstrap_sql_48af56bfe282$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_48af56bfe282$;

DO $bootstrap_do_93c8d17d9f8d$
BEGIN
  EXECUTE $bootstrap_sql_93c8d17d9f8d$-- Trigger to update timestamps
DROP TRIGGER IF EXISTS update_transaction_packages_updated_at ON public.transaction_packages$bootstrap_sql_93c8d17d9f8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93c8d17d9f8d$;

DO $bootstrap_do_ecb34ca28b97$
BEGIN
  EXECUTE $bootstrap_sql_ecb34ca28b97$CREATE TRIGGER update_transaction_packages_updated_at
BEFORE UPDATE ON public.transaction_packages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_ecb34ca28b97$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ecb34ca28b97$;

DO $bootstrap_do_809ad20eed4a$
BEGIN
  EXECUTE $bootstrap_sql_809ad20eed4a$DROP TRIGGER IF EXISTS update_merchant_subscriptions_updated_at ON public.merchant_subscriptions$bootstrap_sql_809ad20eed4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_809ad20eed4a$;

DO $bootstrap_do_9f3c327b02d3$
BEGIN
  EXECUTE $bootstrap_sql_9f3c327b02d3$CREATE TRIGGER update_merchant_subscriptions_updated_at
BEFORE UPDATE ON public.merchant_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_9f3c327b02d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f3c327b02d3$;

DO $bootstrap_do_6c10699cf985$
BEGIN
  EXECUTE $bootstrap_sql_6c10699cf985$
