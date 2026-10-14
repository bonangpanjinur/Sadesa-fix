-- Add policies for user_roles to allow admins to manage roles
-- First, ensure the is_admin() function exists and is working correctly
-- (It should already exist based on previous migrations, but we use it in policies)

-- Policy for Admins to view all roles
DROP POLICY IF EXISTS "Admins can view all roles" ON public.user_roles$bootstrap_sql_b3b2578bd7c3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b3b2578bd7c3$;

DO $bootstrap_do_f617e8b242c8$
BEGIN
  EXECUTE $bootstrap_sql_f617e8b242c8$CREATE POLICY "Admins can view all roles"
    ON public.user_roles FOR SELECT
    USING (public.is_admin())$bootstrap_sql_f617e8b242c8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f617e8b242c8$;

DO $bootstrap_do_9bc3bfe0d8a4$
BEGIN
  EXECUTE $bootstrap_sql_9bc3bfe0d8a4$-- Policy for Admins to insert roles
DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles$bootstrap_sql_9bc3bfe0d8a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9bc3bfe0d8a4$;

DO $bootstrap_do_c10588185397$
BEGIN
  EXECUTE $bootstrap_sql_c10588185397$CREATE POLICY "Admins can insert roles"
    ON public.user_roles FOR INSERT
    WITH CHECK (public.is_admin())$bootstrap_sql_c10588185397$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c10588185397$;

DO $bootstrap_do_dfb1121c6530$
BEGIN
  EXECUTE $bootstrap_sql_dfb1121c6530$-- Policy for Admins to update roles
DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles$bootstrap_sql_dfb1121c6530$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dfb1121c6530$;

DO $bootstrap_do_506a9bcdc347$
BEGIN
  EXECUTE $bootstrap_sql_506a9bcdc347$CREATE POLICY "Admins can update roles"
    ON public.user_roles FOR UPDATE
    USING (public.is_admin())$bootstrap_sql_506a9bcdc347$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_506a9bcdc347$;

DO $bootstrap_do_06672a7230ba$
BEGIN
  EXECUTE $bootstrap_sql_06672a7230ba$-- Policy for Admins to delete roles
DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles$bootstrap_sql_06672a7230ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06672a7230ba$;

DO $bootstrap_do_be6dd61904fd$
BEGIN
  EXECUTE $bootstrap_sql_be6dd61904fd$CREATE POLICY "Admins can delete roles"
    ON public.user_roles FOR DELETE
    USING (public.is_admin())$bootstrap_sql_be6dd61904fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be6dd61904fd$;

DO $bootstrap_do_6ac2a10c19d6$
BEGIN
  EXECUTE $bootstrap_sql_6ac2a10c19d6$-- Also add policy for profiles so admins can view all profiles
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles$bootstrap_sql_6ac2a10c19d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6ac2a10c19d6$;

DO $bootstrap_do_b9d6f3d2ee59$
BEGIN
  EXECUTE $bootstrap_sql_b9d6f3d2ee59$CREATE POLICY "Admins can view all profiles"
    ON public.profiles FOR SELECT
    USING (public.is_admin())$bootstrap_sql_b9d6f3d2ee59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9d6f3d2ee59$;

DO $bootstrap_do_8962511c5a0c$
BEGIN
  EXECUTE $bootstrap_sql_8962511c5a0c$
