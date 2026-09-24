-- Dynamic verifier commissions and admin-owned sales (driver / merchant).
-- All monetary calculations and referral attribution happen server-side.

ALTER TABLE public.verifikator_earnings
  ALTER COLUMN merchant_id DROP NOT NULL,
  ALTER COLUMN subscription_id DROP NOT NULL,
  ALTER COLUMN package_id DROP NOT NULL;
ALTER TABLE public.verifikator_earnings
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'QUOTA_SALE',
  ADD COLUMN IF NOT EXISTS sale_order_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_role text,
  ADD COLUMN IF NOT EXISTS description text;

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_id uuid,
  ADD COLUMN IF NOT EXISTS verifikator_code text;

CREATE TABLE IF NOT EXISTS public.verifikator_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text NOT NULL UNIQUE CHECK (source_type IN ('TRANSACTION','QUOTA_SALE','ADMIN_PRODUCT_DRIVER','ADMIN_PRODUCT_MERCHANT')),
  label text NOT NULL,
  commission_percent numeric NOT NULL DEFAULT 0 CHECK (commission_percent >= 0 AND commission_percent <= 100),
  basis text NOT NULL DEFAULT 'TOTAL',
  is_active boolean NOT NULL DEFAULT true,
  updated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.verifikator_commission_rules (source_type, label, commission_percent, basis)
VALUES
 ('TRANSACTION','Transaksi layanan',0,'TOTAL'),
 ('QUOTA_SALE','Penjualan kuota merchant',0,'TOTAL'),
 ('ADMIN_PRODUCT_DRIVER','Penjualan produk ke driver',0,'TOTAL'),
 ('ADMIN_PRODUCT_MERCHANT','Penjualan produk ke merchant',0,'TOTAL')
ON CONFLICT (source_type) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.admin_store_products (
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
);

CREATE TABLE IF NOT EXISTS public.admin_store_orders (
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
);

CREATE TABLE IF NOT EXISTS public.admin_store_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.admin_store_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.admin_store_products(id),
  product_name text NOT NULL,
  unit_price integer NOT NULL CHECK (unit_price >= 0),
  quantity integer NOT NULL CHECK (quantity > 0),
  line_total integer NOT NULL CHECK (line_total >= 0)
);

CREATE INDEX IF NOT EXISTS idx_store_orders_referral ON public.admin_store_orders(referral_verifikator_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_store_orders_buyer ON public.admin_store_orders(buyer_user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_verifier_earning_sale_once ON public.verifikator_earnings(sale_order_id) WHERE sale_order_id IS NOT NULL;

ALTER TABLE public.verifikator_commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_store_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_store_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_store_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage commission rules" ON public.verifikator_commission_rules;
CREATE POLICY "Admins manage commission rules" ON public.verifikator_commission_rules FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Authenticated read commission rules" ON public.verifikator_commission_rules;
CREATE POLICY "Authenticated read commission rules" ON public.verifikator_commission_rules FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins manage store products" ON public.admin_store_products;
CREATE POLICY "Admins manage store products" ON public.admin_store_products FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Authenticated read active store products" ON public.admin_store_products;
CREATE POLICY "Authenticated read active store products" ON public.admin_store_products FOR SELECT TO authenticated USING (is_active = true);
DROP POLICY IF EXISTS "Users read own store orders" ON public.admin_store_orders;
CREATE POLICY "Users read own store orders" ON public.admin_store_orders FOR SELECT TO authenticated USING (buyer_user_id = auth.uid() OR referral_verifikator_id = auth.uid() OR pickup_verifikator_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Users read own store order items" ON public.admin_store_order_items;
CREATE POLICY "Users read own store order items" ON public.admin_store_order_items FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.admin_store_orders o WHERE o.id = order_id AND (o.buyer_user_id = auth.uid() OR o.referral_verifikator_id = auth.uid() OR o.pickup_verifikator_id = auth.uid() OR public.is_admin())));

CREATE OR REPLACE FUNCTION public.create_admin_store_order(p_product_id uuid, p_quantity integer, p_pickup_verifikator_id uuid DEFAULT NULL)
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
END; $$;

CREATE OR REPLACE FUNCTION public.admin_mark_store_order_paid(p_order_id uuid)
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
END; $$;

-- Existing quota commission remains backward-compatible, but can now be controlled centrally.
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
END; $$;
GRANT EXECUTE ON FUNCTION public.create_admin_store_order(uuid, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mark_store_order_paid(uuid) TO authenticated;
