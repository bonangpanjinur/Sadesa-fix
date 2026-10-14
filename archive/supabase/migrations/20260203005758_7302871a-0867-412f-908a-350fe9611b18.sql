-- Drop the problematic policies and recreate them without circular dependencies
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_06a1c980c209$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06a1c980c209$;

DO $bootstrap_do_3f0a75b6d20b$
BEGIN
  EXECUTE $bootstrap_sql_3f0a75b6d20b$DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_3f0a75b6d20b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f0a75b6d20b$;

DO $bootstrap_do_2fd1e1b83078$
BEGIN
  EXECUTE $bootstrap_sql_2fd1e1b83078$-- Recreate Buyers policy without is_admin() call to avoid recursion
CREATE POLICY "Buyers can view own orders"
  ON public.orders
  FOR SELECT
  USING (auth.uid() = buyer_id)$bootstrap_sql_2fd1e1b83078$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2fd1e1b83078$;

DO $bootstrap_do_a5f2f7a84327$
BEGIN
  EXECUTE $bootstrap_sql_a5f2f7a84327$-- Recreate Admin policy using direct check without function call
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_a5f2f7a84327$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5f2f7a84327$;

DO $bootstrap_do_017fe6648647$
BEGIN
  EXECUTE $bootstrap_sql_017fe6648647$CREATE POLICY "Admins can manage all orders"
  ON public.orders
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  )$bootstrap_sql_017fe6648647$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_017fe6648647$;

DO $bootstrap_do_4cd818e6374e$
BEGIN
  EXECUTE $bootstrap_sql_4cd818e6374e$
