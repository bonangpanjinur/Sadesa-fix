-- Fix RLS policies for user_roles to allow the system/trigger to manage roles
-- and ensure users can always see their own roles.

-- 1. Ensure the trigger function exists and is robust
CREATE OR REPLACE FUNCTION public.handle_merchant_approval_role()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if status is APPROVED (either on insert or update)
  IF (NEW.registration_status = 'APPROVED') THEN
    -- Ensure user_id exists
    IF NEW.user_id IS NOT NULL THEN
      -- Add merchant role to user_roles table
      -- SECURITY DEFINER in the function handles the permission
      INSERT INTO public.user_roles (user_id, role)
      VALUES (NEW.user_id, 'merchant')
      ON CONFLICT (user_id, role) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER$bootstrap_sql_a3b89606a87e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3b89606a87e$;

DO $bootstrap_do_b78290e75db3$
BEGIN
  EXECUTE $bootstrap_sql_b78290e75db3$-- 2. Re-apply the trigger for both INSERT and UPDATE
-- This ensures that if a merchant is created with 'APPROVED' status, the role is added immediately.
DROP TRIGGER IF EXISTS on_merchant_approval_insert ON public.merchants$bootstrap_sql_b78290e75db3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b78290e75db3$;

DO $bootstrap_do_819ff4f1e089$
BEGIN
  EXECUTE $bootstrap_sql_819ff4f1e089$CREATE TRIGGER on_merchant_approval_insert
  AFTER INSERT ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role()$bootstrap_sql_819ff4f1e089$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_819ff4f1e089$;

DO $bootstrap_do_7ea629c7c631$
BEGIN
  EXECUTE $bootstrap_sql_7ea629c7c631$DROP TRIGGER IF EXISTS on_merchant_approval_update ON public.merchants$bootstrap_sql_7ea629c7c631$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7ea629c7c631$;

DO $bootstrap_do_cf7c44d78f48$
BEGIN
  EXECUTE $bootstrap_sql_cf7c44d78f48$CREATE TRIGGER on_merchant_approval_update
  AFTER UPDATE ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_merchant_approval_role()$bootstrap_sql_cf7c44d78f48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf7c44d78f48$;

DO $bootstrap_do_344898dfec6e$
BEGIN
  EXECUTE $bootstrap_sql_344898dfec6e$-- 3. Fix RLS for user_roles to be more reliable
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles$bootstrap_sql_344898dfec6e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_344898dfec6e$;

DO $bootstrap_do_0f8b140046e9$
BEGIN
  EXECUTE $bootstrap_sql_0f8b140046e9$CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_0f8b140046e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f8b140046e9$;

DO $bootstrap_do_674e0ebd5f47$
BEGIN
  EXECUTE $bootstrap_sql_674e0ebd5f47$-- 4. Ensure the enum 'merchant' is correctly handled (it already exists based on previous migrations)
