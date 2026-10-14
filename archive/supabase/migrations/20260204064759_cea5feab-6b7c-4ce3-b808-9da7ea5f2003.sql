-- =====================================================
-- STEP 1: CREATE ALL SECURITY DEFINER FUNCTIONS FIRST
-- =====================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
$$$bootstrap_sql_c29d2f07208e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c29d2f07208e$;

DO $bootstrap_do_caf8a2cbad62$
BEGIN
  EXECUTE $bootstrap_sql_caf8a2cbad62$CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$$bootstrap_sql_caf8a2cbad62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_caf8a2cbad62$;

DO $bootstrap_do_b6b250091a2c$
BEGIN
  EXECUTE $bootstrap_sql_b6b250091a2c$CREATE OR REPLACE FUNCTION public.get_user_merchant_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.merchants WHERE user_id = auth.uid() LIMIT 1
$$$bootstrap_sql_b6b250091a2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6b250091a2c$;

DO $bootstrap_do_1ac7bc9b6c52$
BEGIN
  EXECUTE $bootstrap_sql_1ac7bc9b6c52$CREATE OR REPLACE FUNCTION public.get_user_courier_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.couriers WHERE user_id = auth.uid() LIMIT 1
$$$bootstrap_sql_1ac7bc9b6c52$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ac7bc9b6c52$;

DO $bootstrap_do_fb251a4f12d5$
BEGIN
  EXECUTE $bootstrap_sql_fb251a4f12d5$CREATE OR REPLACE FUNCTION public.is_order_merchant(_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.merchants m ON o.merchant_id = m.id
    WHERE o.id = _order_id AND m.user_id = auth.uid()
  )
$$$bootstrap_sql_fb251a4f12d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb251a4f12d5$;

DO $bootstrap_do_d9dafa2d3405$
BEGIN
  EXECUTE $bootstrap_sql_d9dafa2d3405$CREATE OR REPLACE FUNCTION public.is_order_courier(_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.couriers c ON o.courier_id = c.id
    WHERE o.id = _order_id AND c.user_id = auth.uid()
  )
$$$bootstrap_sql_d9dafa2d3405$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9dafa2d3405$;

DO $bootstrap_do_0e99ec61ece5$
BEGIN
  EXECUTE $bootstrap_sql_0e99ec61ece5$CREATE OR REPLACE FUNCTION public.get_quota_cost(product_price INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT credit_cost FROM public.quota_tiers
     WHERE is_active = true
     AND product_price >= min_price
     AND (max_price IS NULL OR product_price <= max_price)
     ORDER BY min_price DESC
     LIMIT 1),
    1
  )
$$$bootstrap_sql_0e99ec61ece5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e99ec61ece5$;

DO $bootstrap_do_31d61b497457$
BEGIN
  EXECUTE $bootstrap_sql_31d61b497457$CREATE OR REPLACE FUNCTION public.use_merchant_quota(
  _merchant_id UUID,
  _product_price INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _subscription_id UUID;
  _remaining_quota INTEGER;
  _cost INTEGER;
BEGIN
  _cost := public.get_quota_cost(_product_price);

  SELECT id, (transaction_quota - used_quota) INTO _subscription_id, _remaining_quota
  FROM public.merchant_subscriptions
  WHERE merchant_id = _merchant_id
    AND status = 'ACTIVE'
    AND expired_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF _subscription_id IS NULL OR _remaining_quota < _cost THEN
    RETURN FALSE;
  END IF;

  UPDATE public.merchant_subscriptions
  SET used_quota = used_quota + _cost, updated_at = now()
  WHERE id = _subscription_id;

  RETURN TRUE;
END;
$$$bootstrap_sql_31d61b497457$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31d61b497457$;

DO $bootstrap_do_b2c7d6f684f8$
BEGIN
  EXECUTE $bootstrap_sql_b2c7d6f684f8$-- =====================================================
-- STEP 2: NOW CREATE POLICIES THAT USE THESE FUNCTIONS
-- =====================================================

-- Quota tiers policies
DROP POLICY IF EXISTS "quota_tiers_public_read" ON public.quota_tiers$bootstrap_sql_b2c7d6f684f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2c7d6f684f8$;

DO $bootstrap_do_55be3b734b31$
BEGIN
  EXECUTE $bootstrap_sql_55be3b734b31$DROP POLICY IF EXISTS "quota_tiers_admin_all" ON public.quota_tiers$bootstrap_sql_55be3b734b31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55be3b734b31$;

DO $bootstrap_do_b663729eaad8$
BEGIN
  EXECUTE $bootstrap_sql_b663729eaad8$CREATE POLICY "quota_tiers_public_read" ON public.quota_tiers
  FOR SELECT USING (true)$bootstrap_sql_b663729eaad8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b663729eaad8$;

DO $bootstrap_do_8c7095d44b84$
BEGIN
  EXECUTE $bootstrap_sql_8c7095d44b84$CREATE POLICY "quota_tiers_admin_all" ON public.quota_tiers
  FOR ALL USING (public.is_admin())$bootstrap_sql_8c7095d44b84$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c7095d44b84$;

DO $bootstrap_do_22cc703e495d$
BEGIN
  EXECUTE $bootstrap_sql_22cc703e495d$-- Couriers policies
DROP POLICY IF EXISTS "couriers_own_access" ON public.couriers$bootstrap_sql_22cc703e495d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22cc703e495d$;

DO $bootstrap_do_b7f3171ce667$
BEGIN
  EXECUTE $bootstrap_sql_b7f3171ce667$DROP POLICY IF EXISTS "couriers_admin_access" ON public.couriers$bootstrap_sql_b7f3171ce667$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b7f3171ce667$;

DO $bootstrap_do_6b2fefe0aa88$
BEGIN
  EXECUTE $bootstrap_sql_6b2fefe0aa88$DROP POLICY IF EXISTS "couriers_public_read" ON public.couriers$bootstrap_sql_6b2fefe0aa88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b2fefe0aa88$;

DO $bootstrap_do_00f3561a9510$
BEGIN
  EXECUTE $bootstrap_sql_00f3561a9510$CREATE POLICY "couriers_public_read" ON public.couriers
  FOR SELECT USING (registration_status = 'APPROVED' AND status = 'ACTIVE')$bootstrap_sql_00f3561a9510$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00f3561a9510$;

DO $bootstrap_do_00668e3afdc6$
BEGIN
  EXECUTE $bootstrap_sql_00668e3afdc6$DROP POLICY IF EXISTS "couriers_own_access" ON public.couriers$bootstrap_sql_00668e3afdc6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00668e3afdc6$;

DO $bootstrap_do_c795f26d2b8b$
BEGIN
  EXECUTE $bootstrap_sql_c795f26d2b8b$CREATE POLICY "couriers_own_access" ON public.couriers
  FOR ALL USING (user_id = auth.uid())$bootstrap_sql_c795f26d2b8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c795f26d2b8b$;

DO $bootstrap_do_3f0d0d786a75$
BEGIN
  EXECUTE $bootstrap_sql_3f0d0d786a75$DROP POLICY IF EXISTS "couriers_admin_access" ON public.couriers$bootstrap_sql_3f0d0d786a75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f0d0d786a75$;

DO $bootstrap_do_fbfff4bedba3$
BEGIN
  EXECUTE $bootstrap_sql_fbfff4bedba3$CREATE POLICY "couriers_admin_access" ON public.couriers
  FOR ALL USING (public.is_admin())$bootstrap_sql_fbfff4bedba3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fbfff4bedba3$;

DO $bootstrap_do_2a0d302c69c4$
BEGIN
  EXECUTE $bootstrap_sql_2a0d302c69c4$-- Orders policies
DROP POLICY IF EXISTS "orders_buyer_access" ON public.orders$bootstrap_sql_2a0d302c69c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a0d302c69c4$;

DO $bootstrap_do_1dc476bbf57f$
BEGIN
  EXECUTE $bootstrap_sql_1dc476bbf57f$DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders$bootstrap_sql_1dc476bbf57f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1dc476bbf57f$;

DO $bootstrap_do_229845d8f688$
BEGIN
  EXECUTE $bootstrap_sql_229845d8f688$DROP POLICY IF EXISTS "orders_courier_access" ON public.orders$bootstrap_sql_229845d8f688$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_229845d8f688$;

DO $bootstrap_do_2bc5c9765955$
BEGIN
  EXECUTE $bootstrap_sql_2bc5c9765955$DROP POLICY IF EXISTS "orders_admin_access" ON public.orders$bootstrap_sql_2bc5c9765955$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bc5c9765955$;

DO $bootstrap_do_49c2d6cfd0f9$
BEGIN
  EXECUTE $bootstrap_sql_49c2d6cfd0f9$DROP POLICY IF EXISTS "orders_buyer_access" ON public.orders$bootstrap_sql_49c2d6cfd0f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49c2d6cfd0f9$;

DO $bootstrap_do_f126bbb6d780$
BEGIN
  EXECUTE $bootstrap_sql_f126bbb6d780$CREATE POLICY "orders_buyer_access" ON public.orders
  FOR ALL USING (buyer_id = auth.uid())$bootstrap_sql_f126bbb6d780$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f126bbb6d780$;

DO $bootstrap_do_9d9d52356362$
BEGIN
  EXECUTE $bootstrap_sql_9d9d52356362$DROP POLICY IF EXISTS "orders_merchant_access" ON public.orders$bootstrap_sql_9d9d52356362$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9d9d52356362$;

DO $bootstrap_do_9e523b983d9f$
BEGIN
  EXECUTE $bootstrap_sql_9e523b983d9f$CREATE POLICY "orders_merchant_access" ON public.orders
  FOR ALL USING (public.is_order_merchant(id))$bootstrap_sql_9e523b983d9f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e523b983d9f$;

DO $bootstrap_do_057363baf330$
BEGIN
  EXECUTE $bootstrap_sql_057363baf330$DROP POLICY IF EXISTS "orders_courier_access" ON public.orders$bootstrap_sql_057363baf330$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_057363baf330$;

DO $bootstrap_do_107bc4a12c4b$
BEGIN
  EXECUTE $bootstrap_sql_107bc4a12c4b$CREATE POLICY "orders_courier_access" ON public.orders
  FOR ALL USING (public.is_order_courier(id))$bootstrap_sql_107bc4a12c4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_107bc4a12c4b$;

DO $bootstrap_do_b13853fe7a28$
BEGIN
  EXECUTE $bootstrap_sql_b13853fe7a28$DROP POLICY IF EXISTS "orders_admin_access" ON public.orders$bootstrap_sql_b13853fe7a28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b13853fe7a28$;

DO $bootstrap_do_578b14ea7945$
BEGIN
  EXECUTE $bootstrap_sql_578b14ea7945$CREATE POLICY "orders_admin_access" ON public.orders
  FOR ALL USING (public.is_admin())$bootstrap_sql_578b14ea7945$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_578b14ea7945$;

DO $bootstrap_do_ee6e2d69fe17$
BEGIN
  EXECUTE $bootstrap_sql_ee6e2d69fe17$
