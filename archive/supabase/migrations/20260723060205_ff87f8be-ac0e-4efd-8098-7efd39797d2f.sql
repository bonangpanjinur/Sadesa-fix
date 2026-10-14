-- Add missing columns to existing tables so policies compile

ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id)$bootstrap_sql_692f9f7980a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_692f9f7980a5$;

DO $bootstrap_do_c5a4c9f16d8e$
BEGIN
  EXECUTE $bootstrap_sql_c5a4c9f16d8e$ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS refund_type text DEFAULT 'FULL'$bootstrap_sql_c5a4c9f16d8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5a4c9f16d8e$;

DO $bootstrap_do_4de32a84c103$
BEGIN
  EXECUTE $bootstrap_sql_4de32a84c103$ALTER TABLE public.refund_requests ADD COLUMN IF NOT EXISTS evidence_urls text[] DEFAULT '{}'$bootstrap_sql_4de32a84c103$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4de32a84c103$;

DO $bootstrap_do_69d0f742594d$
BEGIN
  EXECUTE $bootstrap_sql_69d0f742594d$-- Tables (idempotent)
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
)$bootstrap_sql_69d0f742594d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_69d0f742594d$;

DO $bootstrap_do_f8cec6ef4f3a$
BEGIN
  EXECUTE $bootstrap_sql_f8cec6ef4f3a$CREATE TABLE IF NOT EXISTS public.product_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url text NOT NULL, is_primary boolean DEFAULT false,
  sort_order integer DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_f8cec6ef4f3a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8cec6ef4f3a$;

DO $bootstrap_do_41363d1476f0$
BEGIN
  EXECUTE $bootstrap_sql_41363d1476f0$CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name text NOT NULL, price_adjustment integer DEFAULT 0, stock integer DEFAULT 0,
  sku text, is_active boolean DEFAULT true, sort_order integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_41363d1476f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_41363d1476f0$;

DO $bootstrap_do_03a9a545d49f$
BEGIN
  EXECUTE $bootstrap_sql_03a9a545d49f$-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status)$bootstrap_sql_03a9a545d49f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03a9a545d49f$;

DO $bootstrap_do_34f4175284ba$
BEGIN
  EXECUTE $bootstrap_sql_34f4175284ba$CREATE INDEX IF NOT EXISTS idx_orders_buyer ON public.orders(buyer_id)$bootstrap_sql_34f4175284ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_34f4175284ba$;

DO $bootstrap_do_d7d7ec35ebdd$
BEGIN
  EXECUTE $bootstrap_sql_d7d7ec35ebdd$CREATE INDEX IF NOT EXISTS idx_orders_merchant ON public.orders(merchant_id)$bootstrap_sql_d7d7ec35ebdd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7d7ec35ebdd$;

DO $bootstrap_do_3a6337b9b841$
BEGIN
  EXECUTE $bootstrap_sql_3a6337b9b841$CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON public.orders(courier_id)$bootstrap_sql_3a6337b9b841$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a6337b9b841$;

DO $bootstrap_do_258bccefe408$
BEGIN
  EXECUTE $bootstrap_sql_258bccefe408$CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status)$bootstrap_sql_258bccefe408$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_258bccefe408$;

DO $bootstrap_do_cab26d0f58df$
BEGIN
  EXECUTE $bootstrap_sql_cab26d0f58df$CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON public.product_images(product_id)$bootstrap_sql_cab26d0f58df$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cab26d0f58df$;

DO $bootstrap_do_ef0c21d18505$
BEGIN
  EXECUTE $bootstrap_sql_ef0c21d18505$CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id)$bootstrap_sql_ef0c21d18505$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef0c21d18505$;

DO $bootstrap_do_62f3f0e0704e$
BEGIN
  EXECUTE $bootstrap_sql_62f3f0e0704e$CREATE INDEX IF NOT EXISTS idx_flash_sales_merchant ON public.flash_sales(merchant_id)$bootstrap_sql_62f3f0e0704e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_62f3f0e0704e$;

DO $bootstrap_do_d5d64b1f47c6$
BEGIN
  EXECUTE $bootstrap_sql_d5d64b1f47c6$CREATE INDEX IF NOT EXISTS idx_flash_sales_status_end ON public.flash_sales(status, end_time)$bootstrap_sql_d5d64b1f47c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5d64b1f47c6$;

DO $bootstrap_do_6b86a7bbffac$
BEGIN
  EXECUTE $bootstrap_sql_6b86a7bbffac$CREATE INDEX IF NOT EXISTS idx_ride_requests_passenger ON public.ride_requests(passenger_id)$bootstrap_sql_6b86a7bbffac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b86a7bbffac$;

DO $bootstrap_do_5d1c2f1f989a$
BEGIN
  EXECUTE $bootstrap_sql_5d1c2f1f989a$CREATE INDEX IF NOT EXISTS idx_ride_requests_driver ON public.ride_requests(driver_id)$bootstrap_sql_5d1c2f1f989a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d1c2f1f989a$;

DO $bootstrap_do_40b930dc3eec$
BEGIN
  EXECUTE $bootstrap_sql_40b930dc3eec$CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON public.ride_requests(status)$bootstrap_sql_40b930dc3eec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40b930dc3eec$;

DO $bootstrap_do_4e0645885258$
BEGIN
  EXECUTE $bootstrap_sql_4e0645885258$CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant ON public.refund_requests(merchant_id)$bootstrap_sql_4e0645885258$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e0645885258$;

DO $bootstrap_do_d9ffefe30f3d$
BEGIN
  EXECUTE $bootstrap_sql_d9ffefe30f3d$-- Grants
GRANT SELECT ON public.products TO anon, authenticated$bootstrap_sql_d9ffefe30f3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9ffefe30f3d$;

DO $bootstrap_do_4e358471c107$
BEGIN
  EXECUTE $bootstrap_sql_4e358471c107$GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated$bootstrap_sql_4e358471c107$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e358471c107$;

DO $bootstrap_do_88970bf46208$
BEGIN
  EXECUTE $bootstrap_sql_88970bf46208$GRANT ALL ON public.products TO service_role$bootstrap_sql_88970bf46208$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88970bf46208$;

DO $bootstrap_do_8f6317183d83$
BEGIN
  EXECUTE $bootstrap_sql_8f6317183d83$GRANT SELECT ON public.product_images TO anon, authenticated$bootstrap_sql_8f6317183d83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8f6317183d83$;

DO $bootstrap_do_377369ede4ed$
BEGIN
  EXECUTE $bootstrap_sql_377369ede4ed$GRANT INSERT, UPDATE, DELETE ON public.product_images TO authenticated$bootstrap_sql_377369ede4ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_377369ede4ed$;

DO $bootstrap_do_73c92980d9a7$
BEGIN
  EXECUTE $bootstrap_sql_73c92980d9a7$GRANT ALL ON public.product_images TO service_role$bootstrap_sql_73c92980d9a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_73c92980d9a7$;

DO $bootstrap_do_36f9fecec14d$
BEGIN
  EXECUTE $bootstrap_sql_36f9fecec14d$GRANT SELECT ON public.product_variants TO anon, authenticated$bootstrap_sql_36f9fecec14d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_36f9fecec14d$;

DO $bootstrap_do_4961e98dce59$
BEGIN
  EXECUTE $bootstrap_sql_4961e98dce59$GRANT INSERT, UPDATE, DELETE ON public.product_variants TO authenticated$bootstrap_sql_4961e98dce59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4961e98dce59$;

DO $bootstrap_do_bd10036d4eb3$
BEGIN
  EXECUTE $bootstrap_sql_bd10036d4eb3$GRANT ALL ON public.product_variants TO service_role$bootstrap_sql_bd10036d4eb3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd10036d4eb3$;

DO $bootstrap_do_3c92b205e345$
BEGIN
  EXECUTE $bootstrap_sql_3c92b205e345$GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated$bootstrap_sql_3c92b205e345$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c92b205e345$;

DO $bootstrap_do_9deca03dda62$
BEGIN
  EXECUTE $bootstrap_sql_9deca03dda62$GRANT ALL ON public.orders TO service_role$bootstrap_sql_9deca03dda62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9deca03dda62$;

DO $bootstrap_do_ab5563394862$
BEGIN
  EXECUTE $bootstrap_sql_ab5563394862$GRANT SELECT, INSERT ON public.order_items TO authenticated$bootstrap_sql_ab5563394862$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab5563394862$;

DO $bootstrap_do_14a65f52971f$
BEGIN
  EXECUTE $bootstrap_sql_14a65f52971f$GRANT ALL ON public.order_items TO service_role$bootstrap_sql_14a65f52971f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14a65f52971f$;

DO $bootstrap_do_50f6398969d7$
BEGIN
  EXECUTE $bootstrap_sql_50f6398969d7$GRANT SELECT ON public.flash_sales TO anon, authenticated$bootstrap_sql_50f6398969d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50f6398969d7$;

DO $bootstrap_do_3d8fc33df00a$
BEGIN
  EXECUTE $bootstrap_sql_3d8fc33df00a$GRANT INSERT, UPDATE, DELETE ON public.flash_sales TO authenticated$bootstrap_sql_3d8fc33df00a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d8fc33df00a$;

DO $bootstrap_do_fbb25a6e1400$
BEGIN
  EXECUTE $bootstrap_sql_fbb25a6e1400$GRANT ALL ON public.flash_sales TO service_role$bootstrap_sql_fbb25a6e1400$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbb25a6e1400$;

DO $bootstrap_do_f546d86fdde8$
BEGIN
  EXECUTE $bootstrap_sql_f546d86fdde8$GRANT SELECT ON public.reviews TO anon, authenticated$bootstrap_sql_f546d86fdde8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f546d86fdde8$;

DO $bootstrap_do_07bcadf5595e$
BEGIN
  EXECUTE $bootstrap_sql_07bcadf5595e$GRANT INSERT, UPDATE ON public.reviews TO authenticated$bootstrap_sql_07bcadf5595e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_07bcadf5595e$;

DO $bootstrap_do_bbb4823b5166$
BEGIN
  EXECUTE $bootstrap_sql_bbb4823b5166$GRANT ALL ON public.reviews TO service_role$bootstrap_sql_bbb4823b5166$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbb4823b5166$;

DO $bootstrap_do_0581669a62d4$
BEGIN
  EXECUTE $bootstrap_sql_0581669a62d4$GRANT SELECT, INSERT, UPDATE ON public.refund_requests TO authenticated$bootstrap_sql_0581669a62d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0581669a62d4$;

DO $bootstrap_do_5fd76fa7be63$
BEGIN
  EXECUTE $bootstrap_sql_5fd76fa7be63$GRANT ALL ON public.refund_requests TO service_role$bootstrap_sql_5fd76fa7be63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fd76fa7be63$;

DO $bootstrap_do_bb39be0dd351$
BEGIN
  EXECUTE $bootstrap_sql_bb39be0dd351$GRANT SELECT, INSERT, UPDATE ON public.withdrawal_requests TO authenticated$bootstrap_sql_bb39be0dd351$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb39be0dd351$;

DO $bootstrap_do_7cd1fce02730$
BEGIN
  EXECUTE $bootstrap_sql_7cd1fce02730$GRANT ALL ON public.withdrawal_requests TO service_role$bootstrap_sql_7cd1fce02730$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cd1fce02730$;

DO $bootstrap_do_cf4419d0d58d$
BEGIN
  EXECUTE $bootstrap_sql_cf4419d0d58d$GRANT SELECT, INSERT, UPDATE ON public.platform_fees TO authenticated$bootstrap_sql_cf4419d0d58d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf4419d0d58d$;

DO $bootstrap_do_4b6f00237843$
BEGIN
  EXECUTE $bootstrap_sql_4b6f00237843$GRANT ALL ON public.platform_fees TO service_role$bootstrap_sql_4b6f00237843$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4b6f00237843$;

DO $bootstrap_do_8d32ab181f41$
BEGIN
  EXECUTE $bootstrap_sql_8d32ab181f41$GRANT SELECT, INSERT, UPDATE ON public.insurance_fund TO authenticated$bootstrap_sql_8d32ab181f41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d32ab181f41$;

DO $bootstrap_do_cf141419e356$
BEGIN
  EXECUTE $bootstrap_sql_cf141419e356$GRANT ALL ON public.insurance_fund TO service_role$bootstrap_sql_cf141419e356$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf141419e356$;

DO $bootstrap_do_bc930945610b$
BEGIN
  EXECUTE $bootstrap_sql_bc930945610b$GRANT SELECT ON public.vouchers TO anon, authenticated$bootstrap_sql_bc930945610b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc930945610b$;

DO $bootstrap_do_81daef64adcd$
BEGIN
  EXECUTE $bootstrap_sql_81daef64adcd$GRANT INSERT, UPDATE, DELETE ON public.vouchers TO authenticated$bootstrap_sql_81daef64adcd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_81daef64adcd$;

DO $bootstrap_do_456969e420c6$
BEGIN
  EXECUTE $bootstrap_sql_456969e420c6$GRANT ALL ON public.vouchers TO service_role$bootstrap_sql_456969e420c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_456969e420c6$;

DO $bootstrap_do_08cd14ab9b86$
BEGIN
  EXECUTE $bootstrap_sql_08cd14ab9b86$GRANT SELECT, INSERT ON public.voucher_usages TO authenticated$bootstrap_sql_08cd14ab9b86$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08cd14ab9b86$;

DO $bootstrap_do_f8ad9dc159e2$
BEGIN
  EXECUTE $bootstrap_sql_f8ad9dc159e2$GRANT ALL ON public.voucher_usages TO service_role$bootstrap_sql_f8ad9dc159e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8ad9dc159e2$;

DO $bootstrap_do_4a873e180511$
BEGIN
  EXECUTE $bootstrap_sql_4a873e180511$GRANT SELECT ON public.promotions TO anon, authenticated$bootstrap_sql_4a873e180511$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a873e180511$;

DO $bootstrap_do_ff5bbf027d1e$
BEGIN
  EXECUTE $bootstrap_sql_ff5bbf027d1e$GRANT INSERT, UPDATE ON public.promotions TO authenticated$bootstrap_sql_ff5bbf027d1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff5bbf027d1e$;

DO $bootstrap_do_8b594e906954$
BEGIN
  EXECUTE $bootstrap_sql_8b594e906954$GRANT ALL ON public.promotions TO service_role$bootstrap_sql_8b594e906954$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b594e906954$;

DO $bootstrap_do_0759881c61be$
BEGIN
  EXECUTE $bootstrap_sql_0759881c61be$GRANT SELECT, INSERT, UPDATE ON public.ride_requests TO authenticated$bootstrap_sql_0759881c61be$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0759881c61be$;

DO $bootstrap_do_108f37bae28e$
BEGIN
  EXECUTE $bootstrap_sql_108f37bae28e$GRANT ALL ON public.ride_requests TO service_role$bootstrap_sql_108f37bae28e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_108f37bae28e$;

DO $bootstrap_do_0882725d13cd$
BEGIN
  EXECUTE $bootstrap_sql_0882725d13cd$-- Enable RLS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY$bootstrap_sql_0882725d13cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0882725d13cd$;

DO $bootstrap_do_26806e437d8b$
BEGIN
  EXECUTE $bootstrap_sql_26806e437d8b$ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY$bootstrap_sql_26806e437d8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_26806e437d8b$;

DO $bootstrap_do_968509e309b4$
BEGIN
  EXECUTE $bootstrap_sql_968509e309b4$ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY$bootstrap_sql_968509e309b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_968509e309b4$;

DO $bootstrap_do_f0278279486a$
BEGIN
  EXECUTE $bootstrap_sql_f0278279486a$ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY$bootstrap_sql_f0278279486a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f0278279486a$;

DO $bootstrap_do_662f7580d065$
BEGIN
  EXECUTE $bootstrap_sql_662f7580d065$ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY$bootstrap_sql_662f7580d065$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_662f7580d065$;

DO $bootstrap_do_2d9924841fc0$
BEGIN
  EXECUTE $bootstrap_sql_2d9924841fc0$ALTER TABLE public.flash_sales ENABLE ROW LEVEL SECURITY$bootstrap_sql_2d9924841fc0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d9924841fc0$;

DO $bootstrap_do_1d37ddd32d01$
BEGIN
  EXECUTE $bootstrap_sql_1d37ddd32d01$ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY$bootstrap_sql_1d37ddd32d01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d37ddd32d01$;

DO $bootstrap_do_8be23ba3031e$
BEGIN
  EXECUTE $bootstrap_sql_8be23ba3031e$ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_8be23ba3031e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8be23ba3031e$;

DO $bootstrap_do_0eb02b745e31$
BEGIN
  EXECUTE $bootstrap_sql_0eb02b745e31$ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_0eb02b745e31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0eb02b745e31$;

DO $bootstrap_do_448044ef6ba0$
BEGIN
  EXECUTE $bootstrap_sql_448044ef6ba0$ALTER TABLE public.platform_fees ENABLE ROW LEVEL SECURITY$bootstrap_sql_448044ef6ba0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_448044ef6ba0$;

DO $bootstrap_do_fbe72264f671$
BEGIN
  EXECUTE $bootstrap_sql_fbe72264f671$ALTER TABLE public.insurance_fund ENABLE ROW LEVEL SECURITY$bootstrap_sql_fbe72264f671$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbe72264f671$;

DO $bootstrap_do_7ed540a01977$
BEGIN
  EXECUTE $bootstrap_sql_7ed540a01977$ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY$bootstrap_sql_7ed540a01977$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ed540a01977$;

DO $bootstrap_do_047e7e82d82c$
BEGIN
  EXECUTE $bootstrap_sql_047e7e82d82c$ALTER TABLE public.voucher_usages ENABLE ROW LEVEL SECURITY$bootstrap_sql_047e7e82d82c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_047e7e82d82c$;

DO $bootstrap_do_bddce1c7a861$
BEGIN
  EXECUTE $bootstrap_sql_bddce1c7a861$ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY$bootstrap_sql_bddce1c7a861$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bddce1c7a861$;

DO $bootstrap_do_6c784bf559e7$
BEGIN
  EXECUTE $bootstrap_sql_6c784bf559e7$ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_6c784bf559e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c784bf559e7$;

DO $bootstrap_do_70d3cbd5dd3d$
BEGIN
  EXECUTE $bootstrap_sql_70d3cbd5dd3d$-- Helpers
CREATE OR REPLACE FUNCTION public.is_order_merchant(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = _order_id AND m.user_id = auth.uid()) $$$bootstrap_sql_70d3cbd5dd3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_70d3cbd5dd3d$;

DO $bootstrap_do_ab47315ef16f$
BEGIN
  EXECUTE $bootstrap_sql_ab47315ef16f$CREATE OR REPLACE FUNCTION public.is_order_courier(_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = _order_id AND c.user_id = auth.uid()) $$$bootstrap_sql_ab47315ef16f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab47315ef16f$;

DO $bootstrap_do_b6d12b240b8d$
BEGIN
  EXECUTE $bootstrap_sql_b6d12b240b8d$-- Triggers
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products$bootstrap_sql_b6d12b240b8d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6d12b240b8d$;

DO $bootstrap_do_b5c8c775c1b8$
BEGIN
  EXECUTE $bootstrap_sql_b5c8c775c1b8$CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_b5c8c775c1b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5c8c775c1b8$;

DO $bootstrap_do_f9c26518d40c$
BEGIN
  EXECUTE $bootstrap_sql_f9c26518d40c$DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants$bootstrap_sql_f9c26518d40c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f9c26518d40c$;

DO $bootstrap_do_f46837493b6e$
BEGIN
  EXECUTE $bootstrap_sql_f46837493b6e$CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_f46837493b6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f46837493b6e$;

DO $bootstrap_do_b0a14785cba6$
BEGIN
  EXECUTE $bootstrap_sql_b0a14785cba6$DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders$bootstrap_sql_b0a14785cba6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0a14785cba6$;

DO $bootstrap_do_8b2051b26ebb$
BEGIN
  EXECUTE $bootstrap_sql_8b2051b26ebb$CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_8b2051b26ebb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b2051b26ebb$;

DO $bootstrap_do_2dd308d568c9$
BEGIN
  EXECUTE $bootstrap_sql_2dd308d568c9$DROP TRIGGER IF EXISTS update_reviews_updated_at ON public.reviews$bootstrap_sql_2dd308d568c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dd308d568c9$;

DO $bootstrap_do_541fe7299ef3$
BEGIN
  EXECUTE $bootstrap_sql_541fe7299ef3$CREATE TRIGGER update_reviews_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_541fe7299ef3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_541fe7299ef3$;

DO $bootstrap_do_5c14f8fb53b4$
BEGIN
  EXECUTE $bootstrap_sql_5c14f8fb53b4$DROP TRIGGER IF EXISTS update_refund_requests_updated_at ON public.refund_requests$bootstrap_sql_5c14f8fb53b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5c14f8fb53b4$;

DO $bootstrap_do_ff03873e860d$
BEGIN
  EXECUTE $bootstrap_sql_ff03873e860d$CREATE TRIGGER update_refund_requests_updated_at BEFORE UPDATE ON public.refund_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_ff03873e860d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ff03873e860d$;

DO $bootstrap_do_af6d16704de5$
BEGIN
  EXECUTE $bootstrap_sql_af6d16704de5$DROP TRIGGER IF EXISTS update_ride_requests_updated_at ON public.ride_requests$bootstrap_sql_af6d16704de5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_af6d16704de5$;

DO $bootstrap_do_3b5d94be0632$
BEGIN
  EXECUTE $bootstrap_sql_3b5d94be0632$CREATE TRIGGER update_ride_requests_updated_at BEFORE UPDATE ON public.ride_requests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_3b5d94be0632$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b5d94be0632$;

DO $bootstrap_do_ed335a5e945c$
BEGIN
  EXECUTE $bootstrap_sql_ed335a5e945c$-- Policies
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products$bootstrap_sql_ed335a5e945c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed335a5e945c$;

DO $bootstrap_do_11fe744063c9$
BEGIN
  EXECUTE $bootstrap_sql_11fe744063c9$CREATE POLICY "Anyone can view active products" ON public.products FOR SELECT USING (is_active = true)$bootstrap_sql_11fe744063c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11fe744063c9$;

DO $bootstrap_do_15d865c6241a$
BEGIN
  EXECUTE $bootstrap_sql_15d865c6241a$DROP POLICY IF EXISTS "Admins can manage products" ON public.products$bootstrap_sql_15d865c6241a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_15d865c6241a$;

DO $bootstrap_do_9e8dac5ac0a1$
BEGIN
  EXECUTE $bootstrap_sql_9e8dac5ac0a1$CREATE POLICY "Admins can manage products" ON public.products FOR ALL USING (public.is_admin())$bootstrap_sql_9e8dac5ac0a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e8dac5ac0a1$;

DO $bootstrap_do_ea029832adbb$
BEGIN
  EXECUTE $bootstrap_sql_ea029832adbb$DROP POLICY IF EXISTS "Merchants can manage own products" ON public.products$bootstrap_sql_ea029832adbb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea029832adbb$;

DO $bootstrap_do_bb79aa4aac08$
BEGIN
  EXECUTE $bootstrap_sql_bb79aa4aac08$CREATE POLICY "Merchants can manage own products" ON public.products FOR ALL
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = products.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_bb79aa4aac08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb79aa4aac08$;

DO $bootstrap_do_f7d2f886374d$
BEGIN
  EXECUTE $bootstrap_sql_f7d2f886374d$DROP POLICY IF EXISTS "Anyone can view product images" ON public.product_images$bootstrap_sql_f7d2f886374d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7d2f886374d$;

DO $bootstrap_do_9f1fd49f6df2$
BEGIN
  EXECUTE $bootstrap_sql_9f1fd49f6df2$CREATE POLICY "Anyone can view product images" ON public.product_images FOR SELECT USING (true)$bootstrap_sql_9f1fd49f6df2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f1fd49f6df2$;

DO $bootstrap_do_0a7bd5ebf3a8$
BEGIN
  EXECUTE $bootstrap_sql_0a7bd5ebf3a8$DROP POLICY IF EXISTS "Admins can manage all product images" ON public.product_images$bootstrap_sql_0a7bd5ebf3a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a7bd5ebf3a8$;

DO $bootstrap_do_2f7141f72328$
BEGIN
  EXECUTE $bootstrap_sql_2f7141f72328$CREATE POLICY "Admins can manage all product images" ON public.product_images FOR ALL USING (public.is_admin())$bootstrap_sql_2f7141f72328$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f7141f72328$;

DO $bootstrap_do_ea28e003de74$
BEGIN
  EXECUTE $bootstrap_sql_ea28e003de74$DROP POLICY IF EXISTS "Merchants can manage their product images" ON public.product_images$bootstrap_sql_ea28e003de74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea28e003de74$;

DO $bootstrap_do_485e542be6a0$
BEGIN
  EXECUTE $bootstrap_sql_485e542be6a0$CREATE POLICY "Merchants can manage their product images" ON public.product_images FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_images.product_id AND m.user_id = auth.uid()))$bootstrap_sql_485e542be6a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_485e542be6a0$;

DO $bootstrap_do_18aa0e9a8524$
BEGIN
  EXECUTE $bootstrap_sql_18aa0e9a8524$DROP POLICY IF EXISTS "Anyone can view active product variants" ON public.product_variants$bootstrap_sql_18aa0e9a8524$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18aa0e9a8524$;

DO $bootstrap_do_bb85782bfd98$
BEGIN
  EXECUTE $bootstrap_sql_bb85782bfd98$CREATE POLICY "Anyone can view active product variants" ON public.product_variants FOR SELECT USING (is_active = true)$bootstrap_sql_bb85782bfd98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb85782bfd98$;

DO $bootstrap_do_8091b393bf71$
BEGIN
  EXECUTE $bootstrap_sql_8091b393bf71$DROP POLICY IF EXISTS "Admins can manage all product variants" ON public.product_variants$bootstrap_sql_8091b393bf71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8091b393bf71$;

DO $bootstrap_do_e72758b14838$
BEGIN
  EXECUTE $bootstrap_sql_e72758b14838$CREATE POLICY "Admins can manage all product variants" ON public.product_variants FOR ALL USING (public.is_admin())$bootstrap_sql_e72758b14838$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e72758b14838$;

DO $bootstrap_do_57956fe348ac$
BEGIN
  EXECUTE $bootstrap_sql_57956fe348ac$DROP POLICY IF EXISTS "Merchants can manage their product variants" ON public.product_variants$bootstrap_sql_57956fe348ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57956fe348ac$;

DO $bootstrap_do_27eae61ef96f$
BEGIN
  EXECUTE $bootstrap_sql_27eae61ef96f$CREATE POLICY "Merchants can manage their product variants" ON public.product_variants FOR ALL
  USING (EXISTS (SELECT 1 FROM public.products p JOIN public.merchants m ON p.merchant_id = m.id
    WHERE p.id = product_variants.product_id AND m.user_id = auth.uid()))$bootstrap_sql_27eae61ef96f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27eae61ef96f$;

DO $bootstrap_do_abe502ad1079$
BEGIN
  EXECUTE $bootstrap_sql_abe502ad1079$DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_abe502ad1079$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_abe502ad1079$;

DO $bootstrap_do_9cabfe5a2824$
BEGIN
  EXECUTE $bootstrap_sql_9cabfe5a2824$CREATE POLICY "Admins can manage all orders" ON public.orders FOR ALL TO authenticated USING (public.is_admin())$bootstrap_sql_9cabfe5a2824$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cabfe5a2824$;

DO $bootstrap_do_6d85a1cee697$
BEGIN
  EXECUTE $bootstrap_sql_6d85a1cee697$DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_6d85a1cee697$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d85a1cee697$;

DO $bootstrap_do_75fb29d20181$
BEGIN
  EXECUTE $bootstrap_sql_75fb29d20181$CREATE POLICY "Buyers can create orders" ON public.orders FOR INSERT TO authenticated WITH CHECK (auth.uid() = buyer_id)$bootstrap_sql_75fb29d20181$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75fb29d20181$;

DO $bootstrap_do_e86139649454$
BEGIN
  EXECUTE $bootstrap_sql_e86139649454$DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_e86139649454$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e86139649454$;

DO $bootstrap_do_2360482c5156$
BEGIN
  EXECUTE $bootstrap_sql_2360482c5156$CREATE POLICY "Buyers can view own orders" ON public.orders FOR SELECT TO authenticated USING (auth.uid() = buyer_id)$bootstrap_sql_2360482c5156$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2360482c5156$;

DO $bootstrap_do_061b08c1857c$
BEGIN
  EXECUTE $bootstrap_sql_061b08c1857c$DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders$bootstrap_sql_061b08c1857c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_061b08c1857c$;

DO $bootstrap_do_a73bb022d895$
BEGIN
  EXECUTE $bootstrap_sql_a73bb022d895$CREATE POLICY "Buyers can update own orders" ON public.orders FOR UPDATE
  USING (auth.uid() = buyer_id AND status IN ('NEW','PENDING_PAYMENT','DELIVERED'))
  WITH CHECK (auth.uid() = buyer_id)$bootstrap_sql_a73bb022d895$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a73bb022d895$;

DO $bootstrap_do_662b9ac640aa$
BEGIN
  EXECUTE $bootstrap_sql_662b9ac640aa$DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders$bootstrap_sql_662b9ac640aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_662b9ac640aa$;

DO $bootstrap_do_4fe0c195ce9f$
BEGIN
  EXECUTE $bootstrap_sql_4fe0c195ce9f$CREATE POLICY "Merchants can view own orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id))$bootstrap_sql_4fe0c195ce9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fe0c195ce9f$;

DO $bootstrap_do_f2b3c966402e$
BEGIN
  EXECUTE $bootstrap_sql_f2b3c966402e$DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders$bootstrap_sql_f2b3c966402e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2b3c966402e$;

DO $bootstrap_do_3fd168cff86a$
BEGIN
  EXECUTE $bootstrap_sql_3fd168cff86a$CREATE POLICY "Merchants can update own orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_order_merchant(auth.uid(), merchant_id))$bootstrap_sql_3fd168cff86a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3fd168cff86a$;

DO $bootstrap_do_bc3ac542eeab$
BEGIN
  EXECUTE $bootstrap_sql_bc3ac542eeab$DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders$bootstrap_sql_bc3ac542eeab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc3ac542eeab$;

DO $bootstrap_do_a6890c8a5517$
BEGIN
  EXECUTE $bootstrap_sql_a6890c8a5517$CREATE POLICY "Couriers can view assigned orders" ON public.orders FOR SELECT TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id))$bootstrap_sql_a6890c8a5517$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6890c8a5517$;

DO $bootstrap_do_2c1f41c86f3a$
BEGIN
  EXECUTE $bootstrap_sql_2c1f41c86f3a$DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders$bootstrap_sql_2c1f41c86f3a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c1f41c86f3a$;

DO $bootstrap_do_d4073bbc1226$
BEGIN
  EXECUTE $bootstrap_sql_d4073bbc1226$CREATE POLICY "Couriers can update assigned orders" ON public.orders FOR UPDATE TO authenticated
  USING (public.is_courier_owner(auth.uid(), courier_id))$bootstrap_sql_d4073bbc1226$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d4073bbc1226$;

DO $bootstrap_do_2dda1a4e9117$
BEGIN
  EXECUTE $bootstrap_sql_2dda1a4e9117$DROP POLICY IF EXISTS "Users can insert order items for own orders" ON public.order_items$bootstrap_sql_2dda1a4e9117$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2dda1a4e9117$;

DO $bootstrap_do_f9f471458ba0$
BEGIN
  EXECUTE $bootstrap_sql_f9f471458ba0$CREATE POLICY "Users can insert order items for own orders" ON public.order_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.buyer_id = auth.uid()))$bootstrap_sql_f9f471458ba0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f9f471458ba0$;

DO $bootstrap_do_58f53d3471da$
BEGIN
  EXECUTE $bootstrap_sql_58f53d3471da$DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items$bootstrap_sql_58f53d3471da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_58f53d3471da$;

DO $bootstrap_do_998908416ff0$
BEGIN
  EXECUTE $bootstrap_sql_998908416ff0$CREATE POLICY "Users can view own order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND (orders.buyer_id = auth.uid() OR public.is_admin())))$bootstrap_sql_998908416ff0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_998908416ff0$;

DO $bootstrap_do_2a77a68a1145$
BEGIN
  EXECUTE $bootstrap_sql_2a77a68a1145$DROP POLICY IF EXISTS "Merchants can view order items" ON public.order_items$bootstrap_sql_2a77a68a1145$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a77a68a1145$;

DO $bootstrap_do_594f27d73b20$
BEGIN
  EXECUTE $bootstrap_sql_594f27d73b20$CREATE POLICY "Merchants can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = order_items.order_id AND m.user_id = auth.uid()))$bootstrap_sql_594f27d73b20$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_594f27d73b20$;

DO $bootstrap_do_3073c510366a$
BEGIN
  EXECUTE $bootstrap_sql_3073c510366a$DROP POLICY IF EXISTS "Couriers can view order items" ON public.order_items$bootstrap_sql_3073c510366a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3073c510366a$;

DO $bootstrap_do_de4b9cf555a1$
BEGIN
  EXECUTE $bootstrap_sql_de4b9cf555a1$CREATE POLICY "Couriers can view order items" ON public.order_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.orders o JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = order_items.order_id AND c.user_id = auth.uid()))$bootstrap_sql_de4b9cf555a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de4b9cf555a1$;

DO $bootstrap_do_b24428887027$
BEGIN
  EXECUTE $bootstrap_sql_b24428887027$DROP POLICY IF EXISTS "Public can view active flash sales" ON public.flash_sales$bootstrap_sql_b24428887027$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b24428887027$;

DO $bootstrap_do_3df3fe89cd0b$
BEGIN
  EXECUTE $bootstrap_sql_3df3fe89cd0b$CREATE POLICY "Public can view active flash sales" ON public.flash_sales FOR SELECT
  USING (status = 'ACTIVE' AND end_time > now())$bootstrap_sql_3df3fe89cd0b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3df3fe89cd0b$;

DO $bootstrap_do_6227f0bccd08$
BEGIN
  EXECUTE $bootstrap_sql_6227f0bccd08$DROP POLICY IF EXISTS "Admins can manage all flash sales" ON public.flash_sales$bootstrap_sql_6227f0bccd08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6227f0bccd08$;

DO $bootstrap_do_7f7836ae33c0$
BEGIN
  EXECUTE $bootstrap_sql_7f7836ae33c0$CREATE POLICY "Admins can manage all flash sales" ON public.flash_sales FOR ALL USING (public.is_admin())$bootstrap_sql_7f7836ae33c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f7836ae33c0$;

DO $bootstrap_do_77f84981ea28$
BEGIN
  EXECUTE $bootstrap_sql_77f84981ea28$DROP POLICY IF EXISTS "Merchants can manage their flash sales" ON public.flash_sales$bootstrap_sql_77f84981ea28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77f84981ea28$;

DO $bootstrap_do_cae92f3dac85$
BEGIN
  EXECUTE $bootstrap_sql_cae92f3dac85$CREATE POLICY "Merchants can manage their flash sales" ON public.flash_sales FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_cae92f3dac85$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cae92f3dac85$;

DO $bootstrap_do_43e1e99dd709$
BEGIN
  EXECUTE $bootstrap_sql_43e1e99dd709$DROP POLICY IF EXISTS "Anyone can view visible reviews" ON public.reviews$bootstrap_sql_43e1e99dd709$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43e1e99dd709$;

DO $bootstrap_do_6c275641c5c2$
BEGIN
  EXECUTE $bootstrap_sql_6c275641c5c2$CREATE POLICY "Anyone can view visible reviews" ON public.reviews FOR SELECT USING (is_visible = true)$bootstrap_sql_6c275641c5c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c275641c5c2$;

DO $bootstrap_do_27ac884241b8$
BEGIN
  EXECUTE $bootstrap_sql_27ac884241b8$DROP POLICY IF EXISTS "Buyers can create reviews for their orders" ON public.reviews$bootstrap_sql_27ac884241b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27ac884241b8$;

DO $bootstrap_do_0591908afcba$
BEGIN
  EXECUTE $bootstrap_sql_0591908afcba$CREATE POLICY "Buyers can create reviews for their orders" ON public.reviews FOR INSERT WITH CHECK (buyer_id = auth.uid())$bootstrap_sql_0591908afcba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0591908afcba$;

DO $bootstrap_do_69ff413a50ee$
BEGIN
  EXECUTE $bootstrap_sql_69ff413a50ee$DROP POLICY IF EXISTS "Merchants can reply to their reviews" ON public.reviews$bootstrap_sql_69ff413a50ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_69ff413a50ee$;

DO $bootstrap_do_4110e2b9687e$
BEGIN
  EXECUTE $bootstrap_sql_4110e2b9687e$CREATE POLICY "Merchants can reply to their reviews" ON public.reviews FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = reviews.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_4110e2b9687e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4110e2b9687e$;

DO $bootstrap_do_fa8e4d91ddb0$
BEGIN
  EXECUTE $bootstrap_sql_fa8e4d91ddb0$DROP POLICY IF EXISTS "Admins can manage reviews" ON public.reviews$bootstrap_sql_fa8e4d91ddb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa8e4d91ddb0$;

DO $bootstrap_do_c7b8fec35874$
BEGIN
  EXECUTE $bootstrap_sql_c7b8fec35874$CREATE POLICY "Admins can manage reviews" ON public.reviews FOR ALL USING (public.is_admin())$bootstrap_sql_c7b8fec35874$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7b8fec35874$;

DO $bootstrap_do_4ed52aa244b1$
BEGIN
  EXECUTE $bootstrap_sql_4ed52aa244b1$DROP POLICY IF EXISTS "Admins can manage refunds" ON public.refund_requests$bootstrap_sql_4ed52aa244b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ed52aa244b1$;

DO $bootstrap_do_99853ef71b91$
BEGIN
  EXECUTE $bootstrap_sql_99853ef71b91$CREATE POLICY "Admins can manage refunds" ON public.refund_requests FOR ALL USING (public.is_admin())$bootstrap_sql_99853ef71b91$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99853ef71b91$;

DO $bootstrap_do_94fc812c2d3f$
BEGIN
  EXECUTE $bootstrap_sql_94fc812c2d3f$DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests$bootstrap_sql_94fc812c2d3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94fc812c2d3f$;

DO $bootstrap_do_f6795870ad7e$
BEGIN
  EXECUTE $bootstrap_sql_f6795870ad7e$CREATE POLICY "Buyers can create refund requests" ON public.refund_requests FOR INSERT WITH CHECK (buyer_id = auth.uid())$bootstrap_sql_f6795870ad7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f6795870ad7e$;

DO $bootstrap_do_73baa426c1fd$
BEGIN
  EXECUTE $bootstrap_sql_73baa426c1fd$DROP POLICY IF EXISTS "Buyers can view own refunds" ON public.refund_requests$bootstrap_sql_73baa426c1fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_73baa426c1fd$;

DO $bootstrap_do_f755ce061e1d$
BEGIN
  EXECUTE $bootstrap_sql_f755ce061e1d$CREATE POLICY "Buyers can view own refunds" ON public.refund_requests FOR SELECT USING (buyer_id = auth.uid())$bootstrap_sql_f755ce061e1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f755ce061e1d$;

DO $bootstrap_do_7c7f6822737a$
BEGIN
  EXECUTE $bootstrap_sql_7c7f6822737a$DROP POLICY IF EXISTS "Merchants can view own refunds" ON public.refund_requests$bootstrap_sql_7c7f6822737a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c7f6822737a$;

DO $bootstrap_do_ed3ee6dfdd11$
BEGIN
  EXECUTE $bootstrap_sql_ed3ee6dfdd11$CREATE POLICY "Merchants can view own refunds" ON public.refund_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants m WHERE m.id = refund_requests.merchant_id AND m.user_id = auth.uid()))$bootstrap_sql_ed3ee6dfdd11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed3ee6dfdd11$;

DO $bootstrap_do_974cebb5d115$
BEGIN
  EXECUTE $bootstrap_sql_974cebb5d115$DROP POLICY IF EXISTS "Admins can manage withdrawals" ON public.withdrawal_requests$bootstrap_sql_974cebb5d115$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_974cebb5d115$;

DO $bootstrap_do_ebcc75884230$
BEGIN
  EXECUTE $bootstrap_sql_ebcc75884230$CREATE POLICY "Admins can manage withdrawals" ON public.withdrawal_requests FOR ALL USING (public.is_admin())$bootstrap_sql_ebcc75884230$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ebcc75884230$;

DO $bootstrap_do_d07d8c31cf19$
BEGIN
  EXECUTE $bootstrap_sql_d07d8c31cf19$DROP POLICY IF EXISTS "Merchants can create withdrawals" ON public.withdrawal_requests$bootstrap_sql_d07d8c31cf19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d07d8c31cf19$;

DO $bootstrap_do_63ca59908520$
BEGIN
  EXECUTE $bootstrap_sql_63ca59908520$CREATE POLICY "Merchants can create withdrawals" ON public.withdrawal_requests FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()) AND status = 'PENDING')$bootstrap_sql_63ca59908520$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63ca59908520$;

DO $bootstrap_do_3f5d850980b5$
BEGIN
  EXECUTE $bootstrap_sql_3f5d850980b5$DROP POLICY IF EXISTS "Merchants can view own withdrawals" ON public.withdrawal_requests$bootstrap_sql_3f5d850980b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f5d850980b5$;

DO $bootstrap_do_e9930b660549$
BEGIN
  EXECUTE $bootstrap_sql_e9930b660549$CREATE POLICY "Merchants can view own withdrawals" ON public.withdrawal_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = withdrawal_requests.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_e9930b660549$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e9930b660549$;

DO $bootstrap_do_1d019b22bbb3$
BEGIN
  EXECUTE $bootstrap_sql_1d019b22bbb3$DROP POLICY IF EXISTS "Admins can manage platform_fees" ON public.platform_fees$bootstrap_sql_1d019b22bbb3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1d019b22bbb3$;

DO $bootstrap_do_f00660acd39c$
BEGIN
  EXECUTE $bootstrap_sql_f00660acd39c$CREATE POLICY "Admins can manage platform_fees" ON public.platform_fees FOR ALL USING (public.is_admin())$bootstrap_sql_f00660acd39c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f00660acd39c$;

DO $bootstrap_do_d7393c853310$
BEGIN
  EXECUTE $bootstrap_sql_d7393c853310$DROP POLICY IF EXISTS "Merchants can view own fees" ON public.platform_fees$bootstrap_sql_d7393c853310$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7393c853310$;

DO $bootstrap_do_e6087c0d806a$
BEGIN
  EXECUTE $bootstrap_sql_e6087c0d806a$CREATE POLICY "Merchants can view own fees" ON public.platform_fees FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = platform_fees.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_e6087c0d806a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6087c0d806a$;

DO $bootstrap_do_3e54e0d59948$
BEGIN
  EXECUTE $bootstrap_sql_3e54e0d59948$DROP POLICY IF EXISTS "Admins can manage insurance fund" ON public.insurance_fund$bootstrap_sql_3e54e0d59948$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3e54e0d59948$;

DO $bootstrap_do_e451e48efbda$
BEGIN
  EXECUTE $bootstrap_sql_e451e48efbda$CREATE POLICY "Admins can manage insurance fund" ON public.insurance_fund FOR ALL USING (public.is_admin())$bootstrap_sql_e451e48efbda$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e451e48efbda$;

DO $bootstrap_do_330e8d43209f$
BEGIN
  EXECUTE $bootstrap_sql_330e8d43209f$DROP POLICY IF EXISTS "Merchants can view own insurance" ON public.insurance_fund$bootstrap_sql_330e8d43209f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_330e8d43209f$;

DO $bootstrap_do_3b82bcecd007$
BEGIN
  EXECUTE $bootstrap_sql_3b82bcecd007$CREATE POLICY "Merchants can view own insurance" ON public.insurance_fund FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid()))$bootstrap_sql_3b82bcecd007$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b82bcecd007$;

DO $bootstrap_do_874a2d6f933f$
BEGIN
  EXECUTE $bootstrap_sql_874a2d6f933f$DROP POLICY IF EXISTS "Merchants can create claims" ON public.insurance_fund$bootstrap_sql_874a2d6f933f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_874a2d6f933f$;

DO $bootstrap_do_181d5ea2ff4b$
BEGIN
  EXECUTE $bootstrap_sql_181d5ea2ff4b$CREATE POLICY "Merchants can create claims" ON public.insurance_fund FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.merchants WHERE merchants.id = insurance_fund.merchant_id AND merchants.user_id = auth.uid())
    AND type = 'claim' AND status = 'PENDING')$bootstrap_sql_181d5ea2ff4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_181d5ea2ff4b$;

DO $bootstrap_do_6d427f996690$
BEGIN
  EXECUTE $bootstrap_sql_6d427f996690$DROP POLICY IF EXISTS "Vouchers viewable by everyone" ON public.vouchers$bootstrap_sql_6d427f996690$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d427f996690$;

DO $bootstrap_do_2e03172185e7$
BEGIN
  EXECUTE $bootstrap_sql_2e03172185e7$CREATE POLICY "Vouchers viewable by everyone" ON public.vouchers FOR SELECT
  USING (is_active = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()))$bootstrap_sql_2e03172185e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e03172185e7$;

DO $bootstrap_do_2bd659e552aa$
BEGIN
  EXECUTE $bootstrap_sql_2bd659e552aa$DROP POLICY IF EXISTS "Admins manage all vouchers" ON public.vouchers$bootstrap_sql_2bd659e552aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bd659e552aa$;

DO $bootstrap_do_90db0664a77e$
BEGIN
  EXECUTE $bootstrap_sql_90db0664a77e$CREATE POLICY "Admins manage all vouchers" ON public.vouchers FOR ALL USING (public.is_admin())$bootstrap_sql_90db0664a77e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90db0664a77e$;

DO $bootstrap_do_51bc20b5dcbf$
BEGIN
  EXECUTE $bootstrap_sql_51bc20b5dcbf$DROP POLICY IF EXISTS "Merchants manage own vouchers" ON public.vouchers$bootstrap_sql_51bc20b5dcbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51bc20b5dcbf$;

DO $bootstrap_do_2436628814e3$
BEGIN
  EXECUTE $bootstrap_sql_2436628814e3$CREATE POLICY "Merchants manage own vouchers" ON public.vouchers FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()) OR public.is_admin())$bootstrap_sql_2436628814e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2436628814e3$;

DO $bootstrap_do_0e99acfa12fa$
BEGIN
  EXECUTE $bootstrap_sql_0e99acfa12fa$DROP POLICY IF EXISTS "Users can use vouchers" ON public.voucher_usages$bootstrap_sql_0e99acfa12fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e99acfa12fa$;

DO $bootstrap_do_015fca5a83ec$
BEGIN
  EXECUTE $bootstrap_sql_015fca5a83ec$CREATE POLICY "Users can use vouchers" ON public.voucher_usages FOR INSERT WITH CHECK (user_id = auth.uid())$bootstrap_sql_015fca5a83ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_015fca5a83ec$;

DO $bootstrap_do_d096a2ede6bd$
BEGIN
  EXECUTE $bootstrap_sql_d096a2ede6bd$DROP POLICY IF EXISTS "Users view own usage" ON public.voucher_usages$bootstrap_sql_d096a2ede6bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d096a2ede6bd$;

DO $bootstrap_do_52c9bb9215d9$
BEGIN
  EXECUTE $bootstrap_sql_52c9bb9215d9$CREATE POLICY "Users view own usage" ON public.voucher_usages FOR SELECT USING (user_id = auth.uid() OR public.is_admin())$bootstrap_sql_52c9bb9215d9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52c9bb9215d9$;

DO $bootstrap_do_05c161508241$
BEGIN
  EXECUTE $bootstrap_sql_05c161508241$DROP POLICY IF EXISTS "Anyone can view active promotions" ON public.promotions$bootstrap_sql_05c161508241$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_05c161508241$;

DO $bootstrap_do_557f88ae74a5$
BEGIN
  EXECUTE $bootstrap_sql_557f88ae74a5$CREATE POLICY "Anyone can view active promotions" ON public.promotions FOR SELECT
  USING (is_active = true AND is_approved = true AND start_date <= now() AND (end_date IS NULL OR end_date >= now()))$bootstrap_sql_557f88ae74a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_557f88ae74a5$;

DO $bootstrap_do_602580d865db$
BEGIN
  EXECUTE $bootstrap_sql_602580d865db$DROP POLICY IF EXISTS "Admins can manage promotions" ON public.promotions$bootstrap_sql_602580d865db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_602580d865db$;

DO $bootstrap_do_9d61ed66c4ec$
BEGIN
  EXECUTE $bootstrap_sql_9d61ed66c4ec$CREATE POLICY "Admins can manage promotions" ON public.promotions FOR ALL USING (public.is_admin())$bootstrap_sql_9d61ed66c4ec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9d61ed66c4ec$;

DO $bootstrap_do_bff71e8e2ea8$
BEGIN
  EXECUTE $bootstrap_sql_bff71e8e2ea8$DROP POLICY IF EXISTS "Merchants can create own promotions" ON public.promotions$bootstrap_sql_bff71e8e2ea8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bff71e8e2ea8$;

DO $bootstrap_do_d3aea76b8aa6$
BEGIN
  EXECUTE $bootstrap_sql_d3aea76b8aa6$CREATE POLICY "Merchants can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'merchant' AND is_approved = false)$bootstrap_sql_d3aea76b8aa6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3aea76b8aa6$;

DO $bootstrap_do_1f5f6ba55454$
BEGIN
  EXECUTE $bootstrap_sql_1f5f6ba55454$DROP POLICY IF EXISTS "Villages can create own promotions" ON public.promotions$bootstrap_sql_1f5f6ba55454$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f5f6ba55454$;

DO $bootstrap_do_38d11d8e12f9$
BEGIN
  EXECUTE $bootstrap_sql_38d11d8e12f9$CREATE POLICY "Villages can create own promotions" ON public.promotions FOR INSERT
  WITH CHECK (advertiser_type = 'village' AND is_approved = false)$bootstrap_sql_38d11d8e12f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_38d11d8e12f9$;

DO $bootstrap_do_5b6a14463e9b$
BEGIN
  EXECUTE $bootstrap_sql_5b6a14463e9b$DROP POLICY IF EXISTS "Passengers can create ride requests" ON public.ride_requests$bootstrap_sql_5b6a14463e9b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b6a14463e9b$;

DO $bootstrap_do_19d30cf762d8$
BEGIN
  EXECUTE $bootstrap_sql_19d30cf762d8$CREATE POLICY "Passengers can create ride requests" ON public.ride_requests FOR INSERT TO authenticated
  WITH CHECK (passenger_id = auth.uid())$bootstrap_sql_19d30cf762d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19d30cf762d8$;

DO $bootstrap_do_0ab2cf4783e2$
BEGIN
  EXECUTE $bootstrap_sql_0ab2cf4783e2$DROP POLICY IF EXISTS "Passengers can view own rides" ON public.ride_requests$bootstrap_sql_0ab2cf4783e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ab2cf4783e2$;

DO $bootstrap_do_641dbbd37bd6$
BEGIN
  EXECUTE $bootstrap_sql_641dbbd37bd6$CREATE POLICY "Passengers can view own rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (passenger_id = auth.uid())$bootstrap_sql_641dbbd37bd6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_641dbbd37bd6$;

DO $bootstrap_do_5706c077bf65$
BEGIN
  EXECUTE $bootstrap_sql_5706c077bf65$DROP POLICY IF EXISTS "Couriers can view searching rides" ON public.ride_requests$bootstrap_sql_5706c077bf65$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5706c077bf65$;

DO $bootstrap_do_8ecd44ffe273$
BEGIN
  EXECUTE $bootstrap_sql_8ecd44ffe273$CREATE POLICY "Couriers can view searching rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (status = 'SEARCHING' AND EXISTS (SELECT 1 FROM public.couriers
    WHERE user_id = auth.uid() AND status = 'ACTIVE' AND is_available = true))$bootstrap_sql_8ecd44ffe273$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ecd44ffe273$;

DO $bootstrap_do_ed00d40dfff6$
BEGIN
  EXECUTE $bootstrap_sql_ed00d40dfff6$DROP POLICY IF EXISTS "Couriers can view assigned rides" ON public.ride_requests$bootstrap_sql_ed00d40dfff6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed00d40dfff6$;

DO $bootstrap_do_8040ae657fbb$
BEGIN
  EXECUTE $bootstrap_sql_8040ae657fbb$CREATE POLICY "Couriers can view assigned rides" ON public.ride_requests FOR SELECT TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()))$bootstrap_sql_8040ae657fbb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8040ae657fbb$;

DO $bootstrap_do_4d0f4d7241b5$
BEGIN
  EXECUTE $bootstrap_sql_4d0f4d7241b5$DROP POLICY IF EXISTS "Couriers can update assigned rides" ON public.ride_requests$bootstrap_sql_4d0f4d7241b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d0f4d7241b5$;

DO $bootstrap_do_73a7782e51a5$
BEGIN
  EXECUTE $bootstrap_sql_73a7782e51a5$CREATE POLICY "Couriers can update assigned rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (driver_id IN (SELECT id FROM public.couriers WHERE user_id = auth.uid()))$bootstrap_sql_73a7782e51a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_73a7782e51a5$;

DO $bootstrap_do_6a7b99c74a8a$
BEGIN
  EXECUTE $bootstrap_sql_6a7b99c74a8a$DROP POLICY IF EXISTS "Admins can manage all rides" ON public.ride_requests$bootstrap_sql_6a7b99c74a8a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a7b99c74a8a$;

DO $bootstrap_do_c32abcc1e3ba$
BEGIN
  EXECUTE $bootstrap_sql_c32abcc1e3ba$CREATE POLICY "Admins can manage all rides" ON public.ride_requests FOR ALL TO authenticated USING (public.is_admin())$bootstrap_sql_c32abcc1e3ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c32abcc1e3ba$;

DO $bootstrap_do_2ed05fe5beba$
BEGIN
  EXECUTE $bootstrap_sql_2ed05fe5beba$DROP POLICY IF EXISTS "Passengers can update own rides" ON public.ride_requests$bootstrap_sql_2ed05fe5beba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ed05fe5beba$;

DO $bootstrap_do_f8caf7ea0923$
BEGIN
  EXECUTE $bootstrap_sql_f8caf7ea0923$CREATE POLICY "Passengers can update own rides" ON public.ride_requests FOR UPDATE TO authenticated
  USING (passenger_id = auth.uid() AND status IN ('SEARCHING', 'ACCEPTED'))$bootstrap_sql_f8caf7ea0923$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8caf7ea0923$;

DO $bootstrap_do_659492747129$
BEGIN
  EXECUTE $bootstrap_sql_659492747129$
