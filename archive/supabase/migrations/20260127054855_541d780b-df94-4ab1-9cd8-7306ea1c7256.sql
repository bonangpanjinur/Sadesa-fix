-- Allow merchants to manage their own products
DROP POLICY IF EXISTS "Merchants can manage own products" ON public.products$bootstrap_sql_0391d4c3eb48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0391d4c3eb48$;

DO $bootstrap_do_8fa79e1b4999$
BEGIN
  EXECUTE $bootstrap_sql_8fa79e1b4999$CREATE POLICY "Merchants can manage own products"
ON public.products
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = products.merchant_id
    AND merchants.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = products.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_8fa79e1b4999$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8fa79e1b4999$;

DO $bootstrap_do_d35612dd3006$
BEGIN
  EXECUTE $bootstrap_sql_d35612dd3006$-- Allow merchants to view their own orders
DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders$bootstrap_sql_d35612dd3006$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d35612dd3006$;

DO $bootstrap_do_712297bb838b$
BEGIN
  EXECUTE $bootstrap_sql_712297bb838b$CREATE POLICY "Merchants can view own orders"
ON public.orders
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = orders.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_712297bb838b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_712297bb838b$;

DO $bootstrap_do_dae36b6eaaa9$
BEGIN
  EXECUTE $bootstrap_sql_dae36b6eaaa9$-- Allow merchants to update their own orders
DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders$bootstrap_sql_dae36b6eaaa9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dae36b6eaaa9$;

DO $bootstrap_do_f827ca5d7135$
BEGIN
  EXECUTE $bootstrap_sql_f827ca5d7135$CREATE POLICY "Merchants can update own orders"
ON public.orders
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.merchants
    WHERE merchants.id = orders.merchant_id
    AND merchants.user_id = auth.uid()
  )
)$bootstrap_sql_f827ca5d7135$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f827ca5d7135$;

DO $bootstrap_do_f8de8aeff115$
BEGIN
  EXECUTE $bootstrap_sql_f8de8aeff115$-- Allow merchants to view own data
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants$bootstrap_sql_f8de8aeff115$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8de8aeff115$;

DO $bootstrap_do_f46c11510b9f$
BEGIN
  EXECUTE $bootstrap_sql_f46c11510b9f$CREATE POLICY "Merchants can view own data"
ON public.merchants
FOR SELECT
USING (user_id = auth.uid())$bootstrap_sql_f46c11510b9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f46c11510b9f$;

DO $bootstrap_do_c44bb0f15969$
BEGIN
  EXECUTE $bootstrap_sql_c44bb0f15969$-- Allow merchants to update own data
DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants$bootstrap_sql_c44bb0f15969$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c44bb0f15969$;

DO $bootstrap_do_6461f1d795f2$
BEGIN
  EXECUTE $bootstrap_sql_6461f1d795f2$CREATE POLICY "Merchants can update own data"
ON public.merchants
FOR UPDATE
USING (user_id = auth.uid())$bootstrap_sql_6461f1d795f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6461f1d795f2$;

DO $bootstrap_do_ea4ce1913455$
BEGIN
  EXECUTE $bootstrap_sql_ea4ce1913455$-- Allow admin desa to manage tourism in their village
DROP POLICY IF EXISTS "Admin desa can manage tourism" ON public.tourism$bootstrap_sql_ea4ce1913455$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ea4ce1913455$;

DO $bootstrap_do_78d6ba9d7fe3$
BEGIN
  EXECUTE $bootstrap_sql_78d6ba9d7fe3$CREATE POLICY "Admin desa can manage tourism"
ON public.tourism
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.villages
    WHERE villages.id = tourism.village_id
    AND villages.registration_status = 'APPROVED'
  )
  AND is_admin_desa()
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.villages
    WHERE villages.id = tourism.village_id
    AND villages.registration_status = 'APPROVED'
  )
  AND is_admin_desa()
)$bootstrap_sql_78d6ba9d7fe3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_78d6ba9d7fe3$;

DO $bootstrap_do_87b42084289d$
BEGIN
  EXECUTE $bootstrap_sql_87b42084289d$
