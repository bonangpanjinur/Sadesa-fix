-- Drop the restrictive buyer update policy and replace with one that covers all buyer-updatable statuses
DROP POLICY IF EXISTS "Buyers can update own pending orders" ON public.orders$bootstrap_sql_fa9d4931d015$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa9d4931d015$;

DO $bootstrap_do_6e9d9cbeba4c$
BEGIN
  EXECUTE $bootstrap_sql_6e9d9cbeba4c$DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders$bootstrap_sql_6e9d9cbeba4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e9d9cbeba4c$;

DO $bootstrap_do_0346bb67586d$
BEGIN
  EXECUTE $bootstrap_sql_0346bb67586d$CREATE POLICY "Buyers can update own orders"
ON public.orders
FOR UPDATE
USING (
  auth.uid() = buyer_id
  AND status IN ('NEW', 'PENDING_PAYMENT', 'DELIVERED')
)
WITH CHECK (
  auth.uid() = buyer_id
)$bootstrap_sql_0346bb67586d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0346bb67586d$;

DO $bootstrap_do_95186726d7c1$
BEGIN
  EXECUTE $bootstrap_sql_95186726d7c1$
