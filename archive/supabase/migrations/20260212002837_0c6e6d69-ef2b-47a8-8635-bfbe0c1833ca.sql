-- 1. Add user_id column to villages table for linking desa to user accounts
ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id)$bootstrap_sql_5a043f05e227$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a043f05e227$;

DO $bootstrap_do_f90b5b100f3d$
BEGIN
  EXECUTE $bootstrap_sql_f90b5b100f3d$-- 2. Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_villages_user_id ON public.villages(user_id)$bootstrap_sql_f90b5b100f3d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f90b5b100f3d$;

DO $bootstrap_do_0e1e3eefd26d$
BEGIN
  EXECUTE $bootstrap_sql_0e1e3eefd26d$-- 3. Add RLS policy for village owners to view their own village
DROP POLICY IF EXISTS "Village owners can view own village" ON public.villages$bootstrap_sql_0e1e3eefd26d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e1e3eefd26d$;

DO $bootstrap_do_8703c4a1974a$
BEGIN
  EXECUTE $bootstrap_sql_8703c4a1974a$CREATE POLICY "Village owners can view own village"
ON public.villages FOR SELECT
USING (user_id = auth.uid())$bootstrap_sql_8703c4a1974a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8703c4a1974a$;

DO $bootstrap_do_4df674e824b9$
BEGIN
  EXECUTE $bootstrap_sql_4df674e824b9$-- 4. Add RLS policy for village owners to update their own village
DROP POLICY IF EXISTS "Village owners can update own village" ON public.villages$bootstrap_sql_4df674e824b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4df674e824b9$;

DO $bootstrap_do_e24045070df9$
BEGIN
  EXECUTE $bootstrap_sql_e24045070df9$CREATE POLICY "Village owners can update own village"
ON public.villages FOR UPDATE
USING (user_id = auth.uid())$bootstrap_sql_e24045070df9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e24045070df9$;

DO $bootstrap_do_3d31e56afb73$
BEGIN
  EXECUTE $bootstrap_sql_3d31e56afb73$-- 5. Fix refund_requests RLS - allow merchants to read refunds for their orders
DROP POLICY IF EXISTS "Merchants can view refunds for their orders" ON public.refund_requests$bootstrap_sql_3d31e56afb73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d31e56afb73$;

DO $bootstrap_do_f116c698adb6$
BEGIN
  EXECUTE $bootstrap_sql_f116c698adb6$CREATE POLICY "Merchants can view refunds for their orders"
ON public.refund_requests FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.id = refund_requests.order_id
    AND m.user_id = auth.uid()
  )
)$bootstrap_sql_f116c698adb6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f116c698adb6$;

DO $bootstrap_do_2bf3171d1915$
BEGIN
  EXECUTE $bootstrap_sql_2bf3171d1915$-- 6. Ensure buyers can view own refund requests
DROP POLICY IF EXISTS "Buyers can view own refund requests" ON public.refund_requests$bootstrap_sql_2bf3171d1915$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bf3171d1915$;

DO $bootstrap_do_d288e728c0c0$
BEGIN
  EXECUTE $bootstrap_sql_d288e728c0c0$CREATE POLICY "Buyers can view own refund requests"
ON public.refund_requests FOR SELECT
USING (buyer_id = auth.uid())$bootstrap_sql_d288e728c0c0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d288e728c0c0$;

DO $bootstrap_do_91574933ad8f$
BEGIN
  EXECUTE $bootstrap_sql_91574933ad8f$-- 7. Ensure buyers can create refund requests
DROP POLICY IF EXISTS "Buyers can create refund requests" ON public.refund_requests$bootstrap_sql_91574933ad8f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_91574933ad8f$;

DO $bootstrap_do_16f7d5bced68$
BEGIN
  EXECUTE $bootstrap_sql_16f7d5bced68$CREATE POLICY "Buyers can create refund requests"
ON public.refund_requests FOR INSERT
WITH CHECK (buyer_id = auth.uid())$bootstrap_sql_16f7d5bced68$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16f7d5bced68$;

DO $bootstrap_do_7db57fcc3b1e$
BEGIN
  EXECUTE $bootstrap_sql_7db57fcc3b1e$-- 8. Admin full access to refund_requests
DROP POLICY IF EXISTS "Admins can manage refund requests" ON public.refund_requests$bootstrap_sql_7db57fcc3b1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7db57fcc3b1e$;

DO $bootstrap_do_3510c4a9e88f$
BEGIN
  EXECUTE $bootstrap_sql_3510c4a9e88f$CREATE POLICY "Admins can manage refund requests"
ON public.refund_requests FOR ALL
USING (is_admin())$bootstrap_sql_3510c4a9e88f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3510c4a9e88f$;

DO $bootstrap_do_ae61ae744683$
BEGIN
  EXECUTE $bootstrap_sql_ae61ae744683$-- 9. Fix order_items RLS - merchants should also be able to read order items for their orders
DROP POLICY IF EXISTS "Merchants can view order items" ON public.order_items$bootstrap_sql_ae61ae744683$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae61ae744683$;

DO $bootstrap_do_355f8dd81d4d$
BEGIN
  EXECUTE $bootstrap_sql_355f8dd81d4d$CREATE POLICY "Merchants can view order items"
ON public.order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.id = order_items.order_id
    AND m.user_id = auth.uid()
  )
)$bootstrap_sql_355f8dd81d4d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_355f8dd81d4d$;

DO $bootstrap_do_f12c73f2be57$
BEGIN
  EXECUTE $bootstrap_sql_f12c73f2be57$-- 10. Couriers should be able to read order items for their deliveries
DROP POLICY IF EXISTS "Couriers can view order items" ON public.order_items$bootstrap_sql_f12c73f2be57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f12c73f2be57$;

DO $bootstrap_do_ded7a589ccc7$
BEGIN
  EXECUTE $bootstrap_sql_ded7a589ccc7$CREATE POLICY "Couriers can view order items"
ON public.order_items FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM orders o
    JOIN couriers c ON o.courier_id = c.id
    WHERE o.id = order_items.order_id
    AND c.user_id = auth.uid()
  )
)$bootstrap_sql_ded7a589ccc7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ded7a589ccc7$;

DO $bootstrap_do_1e6d408b0473$
BEGIN
  EXECUTE $bootstrap_sql_1e6d408b0473$
