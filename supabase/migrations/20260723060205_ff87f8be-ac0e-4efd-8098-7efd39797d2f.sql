-- Add missing columns to existing tables so policies compile

ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id);
ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS refund_type text DEFAULT 'FULL';
ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS evidence_urls text[] DEFAULT '{}';

-- Tables (idempotent)
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name text NOT NULL, description text, price integer NOT NULL,
  stock integer NOT NULL DEFAULT 0, category text NOT NULL, image_url text,
  is_active boolean NOT NULL DEFAULT true, is_promo boolean NOT NULL DEFAULT false,
  discount_percent integer DEFAULT 0, discount_end_date timestamptz,
  min_stock_alert integer DEFAULT 5, low_stock_threshold integer DEFAULT 5,
  view_count integer DEFAULT 0, order_count integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.product_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url text NOT NULL, is_primary boolean DEFAULT false,
  sort_order integer DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name text NOT NULL, price_adjustment integer DEFAULT 0, stock integer DEFAULT 0,
  sku text, is_active boolean DEFAULT true, sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_buyer ON public.orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant ON public.orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON public.orders(courier_id);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON public.product_images(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_flash_sales_merchant ON public.flash_sales(merchant_id);
CREATE INDEX IF NOT EXISTS idx_flash_sales_status_end ON public.flash_sales(status, end_time);
CREATE INDEX IF NOT EXISTS idx_ride_requests_passenger ON public.ride_requests(passenger_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_driver ON public.ride_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON public.ride_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant ON public.refund_requests(merchant_id);

-- Grants
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT ALL ON public.products TO service_role;
GRANT SELECT ON public.product_images TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_images TO authenticated;
GRANT ALL ON public.product_images TO service_role;
GRANT SELECT ON public.product_variants TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_variants TO authenticated;
GRANT ALL ON public.product_variants TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;
GRANT SELECT, INSERT ON public.order_items TO authenticated;
GRANT ALL ON public.order_items TO service_role;
GRANT SELECT ON public.flash_sales TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.flash_sales TO authenticated;
GRANT ALL ON public.flash_sales TO service_role;
GRANT SELECT ON public.reviews TO anon, authenticated;
GRANT INSERT, UPDATE ON public.reviews TO authenticated;
GRANT ALL ON public.reviews TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.refund_requests TO authenticated;
GRANT ALL ON public.refund_requests TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.withdrawal_requests TO authenticated;
GRANT ALL ON public.withdrawal_requests TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.platform_fees TO authenticated;
GRANT ALL ON public.platform_fees TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.insurance_fund TO authenticated;
GRANT ALL ON public.insurance_fund TO service_role;
GRANT SELECT ON public.vouchers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.vouchers TO authenticated;
GRANT ALL ON public.vouchers TO service_role;
GRANT SELECT, INSERT ON public.voucher_usages TO authenticated;
GRANT ALL ON public.voucher_usages TO service_role;
GRANT SELECT ON public.promotions TO anon, authenticated;
GRANT INSERT, UPDATE ON public.promotions TO authenticated;
GRANT ALL ON public.promotions TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.ride_requests TO authenticated;
GRANT ALL ON public.ride_requests TO service_role;

-- Enable RLS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flash_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_fund ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voucher_usages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

-- Helpers
CREATE OR REPLACE FUNCTION public.is_order_merchant(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = _order_id AND m.user_id = auth.uid()) $$;
CREATE OR REPLACE FUNCTION public.is_order_courier(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = _order_id AND c.user_id = auth.uid()) $$;

-- Triggers
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_reviews_updated_at ON public.reviews;
CREATE TRIGGER update_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON public.refund_requests;
CREATE TRIGGER update_refund_requests_updated_at BEFORE UPDATE ON public.refund_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS update_ride_requests_updated_at ON public.ride_requests;
CREATE TRIGGER update_ride_requests_updated_at BEFORE UPDATE ON public.ride_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Policies
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products;
CREATE POLICY "Anyone can view active products" ON public.products FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
CREATE POLICY "Admins can manage products" ON public.products FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage own products" ON public.products;
CREATE POLICY "Merchants can manage own products" ON public.products FOR ALL
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view product images" ON public.product_images;
CREATE POLICY "Anyone can view product images" ON public.product_images FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admins can manage all product images" ON public.product_images;
CREATE POLICY "Admins can manage all product images" ON public.product_images FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their product images" ON public.product_images;
CREATE POLICY "Merchants can manage their product images" ON public.product_images FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_images.product_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view active product variants" ON public.product_variants;
CREATE POLICY "Anyone can view active product variants" ON public.product_variants FOR SELECT USING (is_active = true);
DROP POLICY IF EXISTS "Admins can manage all product variants" ON public.product_variants;
CREATE POLICY "Admins can manage all product variants" ON public.product_variants FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their product variants" ON public.product_variants;
CREATE POLICY "Merchants can manage their product variants" ON public.product_variants FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_variants.product_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders;
CREATE POLICY "Admins can manage all orders" ON public.orders FOR ALL TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders;
CREATE POLICY "Buyers can create orders" ON public.orders FOR INSERT TO authenticated WITH CHECK (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
CREATE POLICY "Buyers can view own orders" ON public.orders FOR SELECT TO authenticated USING (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders;
CREATE POLICY "Buyers can update own orders" ON public.orders FOR UPDATE
  USING (auth.uid() = buyer_id AND status IN ('NEW','PENDING_PAYMENT','DELIVERED'))
  WITH CHECK (auth.uid() = buyer_id);
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders;
CREATE POLICY "Merchants can view own orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id));
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders;
CREATE POLICY "Merchants can update own orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id));
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders;
CREATE POLICY "Couriers can view assigned orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id));
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders;
CREATE POLICY "Couriers can update assigned orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id));

DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items;
CREATE POLICY "Users can insert order items for own orders" ON public.order_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.buyer_id = auth.uid()));
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
CREATE POLICY "Users can view own order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND (orders.buyer_id = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS "Merchants can view order items" ON public.order_items;
CREATE POLICY "Merchants can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = order_items.order_id AND m.user_id = auth.uid()));
DROP POLICY IF EXISTS "Couriers can view order items" ON public.order_items;
CREATE POLICY "Couriers can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = order_items.order_id AND c.user_id = auth.uid()));

DROP POLICY IF EXISTS "Public can view active flash sales" ON public.flash_sales;
CREATE POLICY "Public can view active flash sales" ON public.flash_sales FOR SELECT
  USING (status = 'ACTIVE' AND end_time > now());
DROP POLICY IF EXISTS "Admins can manage all flash sales" ON public.flash_sales;
CREATE POLICY "Admins can manage all flash sales" ON public.flash_sales FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can manage their flash sales" ON public.flash_sales;
CREATE POLICY "Merchants can manage their flash sales" ON public.flash_sales FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Anyone can view visible reviews" ON public.reviews;
CREATE POLICY "Anyone can view visible reviews" ON public.reviews FOR SELECT USING (is_visible = true);
DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews;
CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants can reply to their reviews" ON public.reviews;
CREATE POLICY "Merchants can reply to their reviews" ON public.reviews FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = reviews.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins can manage reviews" ON public.reviews;
CREATE POLICY "Admins can manage reviews" ON public.reviews FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can manage refunds" ON public.refund_requests;
CREATE POLICY "Admins can manage refunds" ON public.refund_requests FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests;
CREATE POLICY "Buyers can create refund requests" ON public.refund_requests FOR INSERT WITH CHECK (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Buyers can view own refunds" ON public.refund_requests;
CREATE POLICY "Buyers can view own refunds" ON public.refund_requests FOR SELECT USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS "Merchants can view own refunds" ON public.refund_requests;
CREATE POLICY "Merchants can view own refunds" ON public.refund_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = refund_requests.merchant_id AND m.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can create withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()) AND status = 'PENDING');
DROP POLICY IF EXISTS "Merchants can view own withdrawals" ON public.withdrawal_requests;
CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage platform_fees" ON public.platform_fees;
CREATE POLICY "Admins can manage platform_fees" ON public.platform_fees FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own fees" ON public.platform_fees;
CREATE POLICY "Merchants can view own fees" ON public.platform_fees FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = platform_fees.merchant_id AND merchants.user_id = auth.uid()));

DROP POLICY IF EXISTS "Admins can manage insurance fund" ON public.insurance_fund;
CREATE POLICY "Admins can manage insurance fund" ON public.insurance_fund FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can view own insurance" ON public.insurance_fund;
CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid()));
DROP POLICY IF EXISTS "Merchants can create claims" ON public.insurance_fund;
CREATE POLICY "Merchants can create claims" ON public.insurance_fund FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid())
    AND type = 'claim' AND status = 'PENDING');

DROP POLICY IF EXISTS "Vouchers viewable by everyone" ON public.vouchers;
CREATE POLICY "Vouchers viewable by everyone" ON public.vouchers FOR SELECT
  USING (is_active = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()));
DROP POLICY IF EXISTS "Admins manage all vouchers" ON public.vouchers;
CREATE POLICY "Admins manage all vouchers" ON public.vouchers FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants manage own vouchers" ON public.vouchers;
CREATE POLICY "Merchants manage own vouchers" ON public.vouchers FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin());

DROP POLICY IF EXISTS "Users can use vouchers" ON public.voucher_usages;
CREATE POLICY "Users can use vouchers" ON public.voucher_usages FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Users view own usage" ON public.voucher_usages;
CREATE POLICY "Users view own usage" ON public.voucher_usages FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Anyone can view active promotions" ON public.promotions;
CREATE POLICY "Anyone can view active promotions" ON public.promotions FOR SELECT
  USING (is_active = true AND is_approved = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()));
DROP POLICY IF EXISTS "Admins can manage promotions" ON public.promotions;
CREATE POLICY "Admins can manage promotions" ON public.promotions FOR ALL USING (public.is_admin());
DROP POLICY IF EXISTS "Merchants can create own promotions" ON public.promotions;
CREATE POLICY "Merchants can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'merchant' AND is_approved = false);
DROP POLICY IF EXISTS "Villages can create own promotions" ON public.promotions;
CREATE POLICY "Villages can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'village' AND is_approved = false);

DROP POLICY IF EXISTS "Passengers can create ride requests" ON public.ride_requests;
CREATE POLICY "Passengers can create ride requests" ON public.ride_requests FOR INSERT TO authenticated
  WITH CHECK (passenger_id = auth.uid());
DROP POLICY IF EXISTS "Passengers can view own rides" ON public.ride_requests;
CREATE POLICY "Passengers can view own rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (passenger_id = auth.uid());
DROP POLICY IF EXISTS "Couriers can view searching rides" ON public.ride_requests;
CREATE POLICY "Couriers can view searching rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (status = 'SEARCHING' AND EXISTS (SELECT 1 FROM public.couriers
    WHERE user_id = auth.uid() AND status = 'ACTIVE' AND is_available = true));
DROP POLICY IF EXISTS "Couriers can view assigned rides" ON public.ride_requests;
CREATE POLICY "Couriers can view assigned rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Couriers can update assigned rides" ON public.ride_requests;
CREATE POLICY "Couriers can update assigned rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "Admins can manage all rides" ON public.ride_requests;
CREATE POLICY "Admins can manage all rides" ON public.ride_requests FOR ALL TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS "Passengers can update own rides" ON public.ride_requests;
CREATE POLICY "Passengers can update own rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (passenger_id = auth.uid() AND status IN ('SEARCHING', 'ACCEPTED'));