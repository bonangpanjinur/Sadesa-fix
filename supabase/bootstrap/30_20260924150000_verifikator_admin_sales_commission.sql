-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_060727c995ed$
BEGIN
  EXECUTE $bootstrap_sql_060727c995ed$-- Dynamic verifier commissions and admin-owned sales (driver / merchant).
-- All monetary calculations and referral attribution happen server-side.

ALTER TABLE public.verifikator_earnings
  ALTER COLUMN merchant_id DROP NOT NULL,
  ALTER COLUMN subscription_id DROP NOT NULL,
  ALTER COLUMN package_id DROP NOT NULL$bootstrap_sql_060727c995ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_060727c995ed$;

DO $bootstrap_do_8171aff3cd72$
BEGIN
  EXECUTE $bootstrap_sql_8171aff3cd72$ALTER TABLE public.verifikator_earnings
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'QUOTA_SALE',
  ADD COLUMN IF NOT EXISTS sale_order_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_role text,
  ADD COLUMN IF NOT EXISTS description text$bootstrap_sql_8171aff3cd72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8171aff3cd72$;

DO $bootstrap_do_479da9317f8f$
BEGIN
  EXECUTE $bootstrap_sql_479da9317f8f$ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_id uuid,
  ADD COLUMN IF NOT EXISTS verifikator_code text$bootstrap_sql_479da9317f8f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_479da9317f8f$;

DO $bootstrap_do_cef7d6189235$
BEGIN
  EXECUTE $bootstrap_sql_cef7d6189235$CREATE TABLE IF NOT EXISTS public.verifikator_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL UNIQUE CHECK (source_type IN ('TRANSACTION','QUOTA_SALE','ADMIN_PRODUCT_DRIVER','ADMIN_PRODUCT_MERCHANT')),
  label text NOT NULL,
  commission_percent numeric NOT NULL DEFAULT 0 CHECK (commission_percent >= 0 AND commission_percent <= 100),
  basis text NOT NULL DEFAULT 'TOTAL',
  is_active boolean NOT NULL DEFAULT true,
  updated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_cef7d6189235$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cef7d6189235$;

DO $bootstrap_do_198198d134a0$
BEGIN
  EXECUTE $bootstrap_sql_198198d134a0$INSERT INTO public.verifikator_commission_rules (source_type, label, commission_percent, basis)
VALUES
 ('TRANSACTION','Transaksi layanan',0,'TOTAL'),
 ('QUOTA_SALE','Penjualan kuota merchant',0,'TOTAL'),
 ('ADMIN_PRODUCT_DRIVER','Penjualan produk ke driver',0,'TOTAL'),
 ('ADMIN_PRODUCT_MERCHANT','Penjualan produk ke merchant',0,'TOTAL')
ON CONFLICT (source_type) DO NOTHING$bootstrap_sql_198198d134a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_198198d134a0$;

DO $bootstrap_do_66a1a8429bb4$
BEGIN
  EXECUTE $bootstrap_sql_66a1a8429bb4$CREATE TABLE IF NOT EXISTS public.admin_store_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  sku text UNIQUE,
  description text,
  target_role text NOT NULL DEFAULT 'ALL' CHECK (target_role IN ('ALL','DRIVER','MERCHANT')),
  price integer NOT NULL CHECK (price >= 0),
  stock integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_66a1a8429bb4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66a1a8429bb4$;

DO $bootstrap_do_a32482c06ffd$
BEGIN
  EXECUTE $bootstrap_sql_a32482c06ffd$CREATE TABLE IF NOT EXISTS public.admin_store_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL,
  buyer_role text NOT NULL CHECK (buyer_role IN ('DRIVER','MERCHANT')),
  courier_id uuid REFERENCES public.couriers(id) ON DELETE SET NULL,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL,
  referral_verifikator_id uuid,
  pickup_verifikator_id uuid,
  total_amount integer NOT NULL CHECK (total_amount >= 0),
  status text NOT NULL DEFAULT 'WAITING_PAYMENT' CHECK (status IN ('WAITING_PAYMENT','PAID','READY_FOR_PICKUP','COMPLETED','CANCELLED')),
  payment_status text NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID','PAID','REFUNDED')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  completed_at timestamptz
)$bootstrap_sql_a32482c06ffd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a32482c06ffd$;

DO $bootstrap_do_2b20ac562d2b$
BEGIN
  EXECUTE $bootstrap_sql_2b20ac562d2b$CREATE TABLE IF NOT EXISTS public.admin_store_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.admin_store_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.admin_store_products(id),
  product_name text NOT NULL,
  unit_price integer NOT NULL CHECK (unit_price >= 0),
  quantity integer NOT NULL CHECK (quantity > 0),
  line_total integer NOT NULL CHECK (line_total >= 0)
)$bootstrap_sql_2b20ac562d2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b20ac562d2b$;

DO $bootstrap_do_7bd60c0b8f0b$
BEGIN
  EXECUTE $bootstrap_sql_7bd60c0b8f0b$CREATE INDEX IF NOT EXISTS idx_store_orders_referral ON public.admin_store_orders(referral_verifikator_id, created_at DESC)$bootstrap_sql_7bd60c0b8f0b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bd60c0b8f0b$;

DO $bootstrap_do_1f0fdddef569$
BEGIN
  EXECUTE $bootstrap_sql_1f0fdddef569$CREATE INDEX IF NOT EXISTS idx_store_orders_buyer ON public.admin_store_orders(buyer_user_id, created_at DESC)$bootstrap_sql_1f0fdddef569$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f0fdddef569$;

DO $bootstrap_do_79560772b43c$
BEGIN
  EXECUTE $bootstrap_sql_79560772b43c$CREATE UNIQUE INDEX IF NOT EXISTS idx_verifier_earning_sale_once ON public.verifikator_earnings(sale_order_id) WHERE sale_order_id IS NOT NULL$bootstrap_sql_79560772b43c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79560772b43c$;

DO $bootstrap_do_f87c098facb5$
BEGIN
  EXECUTE $bootstrap_sql_f87c098facb5$ALTER TABLE public.verifikator_commission_rules ENABLE ROW LEVEL SECURITY$bootstrap_sql_f87c098facb5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f87c098facb5$;

DO $bootstrap_do_125ba046b96a$
BEGIN
  EXECUTE $bootstrap_sql_125ba046b96a$ALTER TABLE public.admin_store_products ENABLE ROW LEVEL SECURITY$bootstrap_sql_125ba046b96a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_125ba046b96a$;

DO $bootstrap_do_081ac712e47f$
BEGIN
  EXECUTE $bootstrap_sql_081ac712e47f$ALTER TABLE public.admin_store_orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_081ac712e47f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_081ac712e47f$;

DO $bootstrap_do_10d47178e9de$
BEGIN
  EXECUTE $bootstrap_sql_10d47178e9de$ALTER TABLE public.admin_store_order_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_10d47178e9de$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10d47178e9de$;

DO $bootstrap_do_04734c9a4792$
BEGIN
  EXECUTE $bootstrap_sql_04734c9a4792$DROP POLICY IF EXISTS "Admins manage commission rules" ON public.verifikator_commission_rules$bootstrap_sql_04734c9a4792$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04734c9a4792$;

DO $bootstrap_do_806aa639f673$
BEGIN
  EXECUTE $bootstrap_sql_806aa639f673$CREATE POLICY "Admins manage commission rules" ON public.verifikator_commission_rules FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_806aa639f673$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_806aa639f673$;

DO $bootstrap_do_fb8b522eb74d$
BEGIN
  EXECUTE $bootstrap_sql_fb8b522eb74d$DROP POLICY IF EXISTS "Authenticated read commission rules" ON public.verifikator_commission_rules$bootstrap_sql_fb8b522eb74d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb8b522eb74d$;

DO $bootstrap_do_5c99001a7bed$
BEGIN
  EXECUTE $bootstrap_sql_5c99001a7bed$CREATE POLICY "Authenticated read commission rules" ON public.verifikator_commission_rules FOR SELECT TO authenticated USING (true)$bootstrap_sql_5c99001a7bed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c99001a7bed$;

DO $bootstrap_do_d7ef4dc86690$
BEGIN
  EXECUTE $bootstrap_sql_d7ef4dc86690$DROP POLICY IF EXISTS "Admins manage store products" ON public.admin_store_products$bootstrap_sql_d7ef4dc86690$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7ef4dc86690$;

DO $bootstrap_do_751579592c96$
BEGIN
  EXECUTE $bootstrap_sql_751579592c96$CREATE POLICY "Admins manage store products" ON public.admin_store_products FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_751579592c96$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_751579592c96$;

DO $bootstrap_do_e827fce48c7f$
BEGIN
  EXECUTE $bootstrap_sql_e827fce48c7f$DROP POLICY IF EXISTS "Authenticated read active store products" ON public.admin_store_products$bootstrap_sql_e827fce48c7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e827fce48c7f$;

DO $bootstrap_do_6770909df38b$
BEGIN
  EXECUTE $bootstrap_sql_6770909df38b$CREATE POLICY "Authenticated read active store products" ON public.admin_store_products FOR SELECT TO authenticated USING (is_active = true)$bootstrap_sql_6770909df38b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6770909df38b$;

DO $bootstrap_do_ddf955d78ddf$
BEGIN
  EXECUTE $bootstrap_sql_ddf955d78ddf$DROP POLICY IF EXISTS "Users read own store orders" ON public.admin_store_orders$bootstrap_sql_ddf955d78ddf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddf955d78ddf$;

DO $bootstrap_do_5da9c4936b22$
BEGIN
  EXECUTE $bootstrap_sql_5da9c4936b22$CREATE POLICY "Users read own store orders" ON public.admin_store_orders FOR SELECT TO authenticated USING (buyer_user_id = auth.uid() OR referral_verifikator_id = auth.uid() OR pickup_verifikator_id = auth.uid() OR public.is_admin())$bootstrap_sql_5da9c4936b22$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5da9c4936b22$;

DO $bootstrap_do_9b60f634a73b$
BEGIN
  EXECUTE $bootstrap_sql_9b60f634a73b$DROP POLICY IF EXISTS "Users read own store order items" ON public.admin_store_order_items$bootstrap_sql_9b60f634a73b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b60f634a73b$;

DO $bootstrap_do_d72bfd796c75$
BEGIN
  EXECUTE $bootstrap_sql_d72bfd796c75$CREATE POLICY "Users read own store order items" ON public.admin_store_order_items FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.admin_store_orders o WHERE o.id = order_id AND (o.buyer_user_id = auth.uid() OR o.referral_verifikator_id = auth.uid() OR o.pickup_verifikator_id = auth.uid() OR public.is_admin())))$bootstrap_sql_d72bfd796c75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d72bfd796c75$;

DO $bootstrap_do_6f9298840ff0$
BEGIN
  EXECUTE $bootstrap_sql_6f9298840ff0$CREATE OR REPLACE FUNCTION public.create_admin_store_order(p_product_id uuid, p_quantity integer, p_pickup_verifikator_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_product public.admin_store_products%ROWTYPE; v_courier public.couriers%ROWTYPE; v_merchant public.merchants%ROWTYPE; v_role text; v_referrer uuid; v_order uuid; v_total integer;
BEGIN
  IF v_uid IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Data pembelian tidak valid'; END IF;
  SELECT * INTO v_product FROM public.admin_store_products WHERE id = p_product_id AND is_active = true FOR UPDATE;
  IF NOT FOUND OR v_product.stock < p_quantity THEN RAISE EXCEPTION 'Produk tidak tersedia atau stok tidak cukup'; END IF;
  SELECT * INTO v_courier FROM public.couriers WHERE user_id = v_uid LIMIT 1;
  SELECT * INTO v_merchant FROM public.merchants WHERE user_id = v_uid LIMIT 1;
  IF v_courier.id IS NOT NULL THEN v_role := 'DRIVER'; v_referrer := v_courier.verifikator_id;
  ELSIF v_merchant.id IS NOT NULL THEN v_role := 'MERCHANT'; v_referrer := v_merchant.verifikator_id;
  ELSE RAISE EXCEPTION 'Akun belum terdaftar sebagai driver atau merchant'; END IF;
  IF v_referrer IS NULL THEN
    IF v_role = 'DRIVER' AND v_courier.verifikator_code IS NOT NULL THEN SELECT verifikator_id INTO v_referrer FROM public.verifikator_codes WHERE code = upper(v_courier.verifikator_code) AND is_active = true LIMIT 1; END IF;
    IF v_role = 'MERCHANT' AND v_merchant.verifikator_code IS NOT NULL THEN SELECT verifikator_id INTO v_referrer FROM public.verifikator_codes WHERE code = upper(v_merchant.verifikator_code) AND is_active = true LIMIT 1; END IF;
  END IF;
  IF v_product.target_role <> 'ALL' AND v_product.target_role <> v_role THEN RAISE EXCEPTION 'Produk tidak tersedia untuk role ini'; END IF;
  v_total := v_product.price * p_quantity;
  INSERT INTO public.admin_store_orders (buyer_user_id, buyer_role, courier_id, merchant_id, referral_verifikator_id, pickup_verifikator_id, total_amount)
  VALUES (v_uid, v_role, v_courier.id, v_merchant.id, v_referrer, p_pickup_verifikator_id, v_total) RETURNING id INTO v_order;
  INSERT INTO public.admin_store_order_items (order_id, product_id, product_name, unit_price, quantity, line_total) VALUES (v_order, v_product.id, v_product.name, v_product.price, p_quantity, v_total);
  UPDATE public.admin_store_products SET stock = stock - p_quantity, updated_at = now() WHERE id = v_product.id;
  RETURN v_order;
END; $$$bootstrap_sql_6f9298840ff0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f9298840ff0$;

DO $bootstrap_do_ec7353b55693$
BEGIN
  EXECUTE $bootstrap_sql_ec7353b55693$CREATE OR REPLACE FUNCTION public.admin_mark_store_order_paid(p_order_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_order public.admin_store_orders%ROWTYPE; v_rule public.verifikator_commission_rules%ROWTYPE; v_percent numeric; v_commission integer;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Hanya admin yang dapat mengonfirmasi pembayaran'; END IF;
  SELECT * INTO v_order FROM public.admin_store_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.payment_status = 'PAID' THEN RETURN true; END IF;
  UPDATE public.admin_store_orders SET payment_status = 'PAID', status = 'READY_FOR_PICKUP', paid_at = now() WHERE id = p_order_id;
  SELECT * INTO v_rule FROM public.verifikator_commission_rules WHERE source_type = CASE WHEN v_order.buyer_role = 'DRIVER' THEN 'ADMIN_PRODUCT_DRIVER' ELSE 'ADMIN_PRODUCT_MERCHANT' END AND is_active = true;
  v_percent := COALESCE(v_rule.commission_percent, 0);
  v_commission := floor(v_order.total_amount * v_percent / 100);
  IF v_order.referral_verifikator_id IS NOT NULL AND v_commission > 0 THEN
    INSERT INTO public.verifikator_earnings (verifikator_id, merchant_id, subscription_id, package_id, package_amount, commission_percent, commission_amount, status, source_type, sale_order_id, buyer_role, description)
    VALUES (v_order.referral_verifikator_id, v_order.merchant_id, NULL, NULL, v_order.total_amount, v_percent, v_commission, 'PENDING', CASE WHEN v_order.buyer_role = 'DRIVER' THEN 'ADMIN_PRODUCT_DRIVER' ELSE 'ADMIN_PRODUCT_MERCHANT' END, v_order.id, v_order.buyer_role, 'Komisi penjualan produk admin');
  END IF;
  RETURN true;
END; $$$bootstrap_sql_ec7353b55693$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec7353b55693$;

DO $bootstrap_do_3f3b1f555895$
BEGIN
  EXECUTE $bootstrap_sql_3f3b1f555895$-- Existing quota commission remains backward-compatible, but can now be controlled centrally.
CREATE OR REPLACE FUNCTION public.record_verifikator_commission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_merchant RECORD; v_package RECORD; v_commission integer; v_percent numeric;
BEGIN
  IF NEW.payment_status = 'PAID' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'PAID') THEN
    SELECT * INTO v_merchant FROM public.merchants WHERE id = NEW.merchant_id;
    IF v_merchant.verifikator_id IS NOT NULL THEN
      SELECT * INTO v_package FROM public.transaction_packages WHERE id = NEW.package_id;
      SELECT commission_percent INTO v_percent FROM public.verifikator_commission_rules WHERE source_type = 'QUOTA_SALE' AND is_active = true;
      v_percent := COALESCE(v_percent, v_package.group_commission_percent);
      v_commission := FLOOR(NEW.payment_amount * v_percent / 100);
      IF v_commission > 0 THEN
        INSERT INTO public.verifikator_earnings (verifikator_id, merchant_id, subscription_id, package_id, package_amount, commission_percent, commission_amount, status, source_type, buyer_role, description)
        VALUES (v_merchant.verifikator_id, NEW.merchant_id, NEW.id, NEW.package_id, NEW.payment_amount, v_percent, v_commission, 'PENDING', 'QUOTA_SALE', 'MERCHANT', 'Komisi penjualan kuota');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END; $$$bootstrap_sql_3f3b1f555895$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f3b1f555895$;

DO $bootstrap_do_d2368dd42498$
BEGIN
  EXECUTE $bootstrap_sql_d2368dd42498$GRANT EXECUTE ON FUNCTION public.create_admin_store_order(uuid, integer, uuid) TO authenticated$bootstrap_sql_d2368dd42498$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2368dd42498$;

DO $bootstrap_do_551776933d77$
BEGIN
  EXECUTE $bootstrap_sql_551776933d77$GRANT EXECUTE ON FUNCTION public.admin_mark_store_order_paid(uuid) TO authenticated$bootstrap_sql_551776933d77$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_551776933d77$;
