-- Product Variants table
CREATE TABLE IF NOT EXISTS public.product_variants (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sku TEXT,
  price_adjustment INTEGER DEFAULT 0,
  stock INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_6be3e5791b28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6be3e5791b28$;

DO $bootstrap_do_c6927f9d39e6$
BEGIN
  EXECUTE $bootstrap_sql_c6927f9d39e6$-- Product Images table
CREATE TABLE IF NOT EXISTS public.product_images (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  is_primary BOOLEAN DEFAULT false,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_c6927f9d39e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6927f9d39e6$;

DO $bootstrap_do_9a87a3ffe597$
BEGIN
  EXECUTE $bootstrap_sql_9a87a3ffe597$-- Enable RLS
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY$bootstrap_sql_9a87a3ffe597$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a87a3ffe597$;

DO $bootstrap_do_c596f28700d2$
BEGIN
  EXECUTE $bootstrap_sql_c596f28700d2$ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY$bootstrap_sql_c596f28700d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c596f28700d2$;

DO $bootstrap_do_a6bea351108f$
BEGIN
  EXECUTE $bootstrap_sql_a6bea351108f$-- RLS Policies for product_variants
DROP POLICY IF EXISTS "Anyone can view active product variants" ON public.product_variants$bootstrap_sql_a6bea351108f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6bea351108f$;

DO $bootstrap_do_d007166cb7f6$
BEGIN
  EXECUTE $bootstrap_sql_d007166cb7f6$CREATE POLICY "Anyone can view active product variants"
ON public.product_variants FOR SELECT
USING (is_active = true)$bootstrap_sql_d007166cb7f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d007166cb7f6$;

DO $bootstrap_do_805dde3b8bd9$
BEGIN
  EXECUTE $bootstrap_sql_805dde3b8bd9$DROP POLICY IF EXISTS "Merchants can manage their product variants" ON public.product_variants$bootstrap_sql_805dde3b8bd9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_805dde3b8bd9$;

DO $bootstrap_do_b85ec157a971$
BEGIN
  EXECUTE $bootstrap_sql_b85ec157a971$CREATE POLICY "Merchants can manage their product variants"
ON public.product_variants FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM products p
    JOIN merchants m ON p.merchant_id = m.id
    WHERE p.id = product_variants.product_id
    AND m.user_id = auth.uid()
  )
)$bootstrap_sql_b85ec157a971$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b85ec157a971$;

DO $bootstrap_do_d993b927f0a9$
BEGIN
  EXECUTE $bootstrap_sql_d993b927f0a9$-- RLS Policies for product_images
DROP POLICY IF EXISTS "Anyone can view product images" ON public.product_images$bootstrap_sql_d993b927f0a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d993b927f0a9$;

DO $bootstrap_do_17f278803771$
BEGIN
  EXECUTE $bootstrap_sql_17f278803771$CREATE POLICY "Anyone can view product images"
ON public.product_images FOR SELECT
USING (true)$bootstrap_sql_17f278803771$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17f278803771$;

DO $bootstrap_do_84432b51715c$
BEGIN
  EXECUTE $bootstrap_sql_84432b51715c$DROP POLICY IF EXISTS "Merchants can manage their product images" ON public.product_images$bootstrap_sql_84432b51715c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_84432b51715c$;

DO $bootstrap_do_2a0a5420c6a7$
BEGIN
  EXECUTE $bootstrap_sql_2a0a5420c6a7$CREATE POLICY "Merchants can manage their product images"
ON public.product_images FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM products p
    JOIN merchants m ON p.merchant_id = m.id
    WHERE p.id = product_images.product_id
    AND m.user_id = auth.uid()
  )
)$bootstrap_sql_2a0a5420c6a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a0a5420c6a7$;

DO $bootstrap_do_3875e6ffc022$
BEGIN
  EXECUTE $bootstrap_sql_3875e6ffc022$-- Admin policies
DROP POLICY IF EXISTS "Admins can manage all product variants" ON public.product_variants$bootstrap_sql_3875e6ffc022$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3875e6ffc022$;

DO $bootstrap_do_7e793c6d970b$
BEGIN
  EXECUTE $bootstrap_sql_7e793c6d970b$CREATE POLICY "Admins can manage all product variants"
ON public.product_variants FOR ALL
USING (public.is_admin())$bootstrap_sql_7e793c6d970b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e793c6d970b$;

DO $bootstrap_do_b530c174df71$
BEGIN
  EXECUTE $bootstrap_sql_b530c174df71$DROP POLICY IF EXISTS "Admins can manage all product images" ON public.product_images$bootstrap_sql_b530c174df71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b530c174df71$;

DO $bootstrap_do_b5ddc041d11d$
BEGIN
  EXECUTE $bootstrap_sql_b5ddc041d11d$CREATE POLICY "Admins can manage all product images"
ON public.product_images FOR ALL
USING (public.is_admin())$bootstrap_sql_b5ddc041d11d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b5ddc041d11d$;

DO $bootstrap_do_2029c36bb356$
BEGIN
  EXECUTE $bootstrap_sql_2029c36bb356$-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id)$bootstrap_sql_2029c36bb356$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2029c36bb356$;

DO $bootstrap_do_928bdd84621c$
BEGIN
  EXECUTE $bootstrap_sql_928bdd84621c$CREATE INDEX IF NOT EXISTS idx_product_images_product_id ON public.product_images(product_id)$bootstrap_sql_928bdd84621c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_928bdd84621c$;

DO $bootstrap_do_578acb67e744$
BEGIN
  EXECUTE $bootstrap_sql_578acb67e744$CREATE INDEX IF NOT EXISTS idx_product_images_primary ON public.product_images(product_id, is_primary) WHERE is_primary = true$bootstrap_sql_578acb67e744$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_578acb67e744$;

DO $bootstrap_do_39d7422a208a$
BEGIN
  EXECUTE $bootstrap_sql_39d7422a208a$-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants$bootstrap_sql_39d7422a208a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39d7422a208a$;

DO $bootstrap_do_9e3d223afc3c$
BEGIN
  EXECUTE $bootstrap_sql_9e3d223afc3c$CREATE TRIGGER update_product_variants_updated_at
BEFORE UPDATE ON public.product_variants
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_9e3d223afc3c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e3d223afc3c$;

DO $bootstrap_do_826282b1d408$
BEGIN
  EXECUTE $bootstrap_sql_826282b1d408$
