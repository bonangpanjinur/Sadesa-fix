-- Add courier assignment to orders
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS courier_id UUID REFERENCES public.couriers(id),
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS delivery_lat NUMERIC,
ADD COLUMN IF NOT EXISTS delivery_lng NUMERIC$bootstrap_sql_ed04c7350052$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ed04c7350052$;

DO $bootstrap_do_d6c6358f9a74$
BEGIN
  EXECUTE $bootstrap_sql_d6c6358f9a74$-- Create index for courier lookups
CREATE INDEX IF NOT EXISTS idx_orders_courier_id ON public.orders(courier_id)$bootstrap_sql_d6c6358f9a74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6c6358f9a74$;

DO $bootstrap_do_94a82850ff49$
BEGIN
  EXECUTE $bootstrap_sql_94a82850ff49$CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status)$bootstrap_sql_94a82850ff49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94a82850ff49$;

DO $bootstrap_do_b3a939396c75$
BEGIN
  EXECUTE $bootstrap_sql_b3a939396c75$-- Update RLS policies for couriers to view assigned orders
DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders$bootstrap_sql_b3a939396c75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3a939396c75$;

DO $bootstrap_do_0fd1c57dbebc$
BEGIN
  EXECUTE $bootstrap_sql_0fd1c57dbebc$CREATE POLICY "Couriers can view assigned orders"
ON public.orders
FOR SELECT
USING (courier_id IN (SELECT id FROM couriers WHERE user_id = auth.uid()))$bootstrap_sql_0fd1c57dbebc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0fd1c57dbebc$;

DO $bootstrap_do_57f0a29dda95$
BEGIN
  EXECUTE $bootstrap_sql_57f0a29dda95$-- Couriers can update assigned orders (status changes)
DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders$bootstrap_sql_57f0a29dda95$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57f0a29dda95$;

DO $bootstrap_do_c9a215a75ffa$
BEGIN
  EXECUTE $bootstrap_sql_c9a215a75ffa$CREATE POLICY "Couriers can update assigned orders"
ON public.orders
FOR UPDATE
USING (courier_id IN (SELECT id FROM couriers WHERE user_id = auth.uid()))$bootstrap_sql_c9a215a75ffa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9a215a75ffa$;

DO $bootstrap_do_d27d1c590bcd$
BEGIN
  EXECUTE $bootstrap_sql_d27d1c590bcd$
