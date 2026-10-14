-- 1. Add missing columns to villages table
ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS province text$bootstrap_sql_95186726d7c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95186726d7c1$;

DO $bootstrap_do_f2f203943a00$
BEGIN
  EXECUTE $bootstrap_sql_f2f203943a00$ALTER TABLE public.villages ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now()$bootstrap_sql_f2f203943a00$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2f203943a00$;

DO $bootstrap_do_0ad8301142a2$
BEGIN
  EXECUTE $bootstrap_sql_0ad8301142a2$-- 2. Fix RLS policies for villages table
-- Drop existing INSERT policy that's too restrictive
DROP POLICY IF EXISTS "Anyone can register village" ON public.villages$bootstrap_sql_0ad8301142a2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ad8301142a2$;

DO $bootstrap_do_00e29f9ba6c9$
BEGIN
  EXECUTE $bootstrap_sql_00e29f9ba6c9$DROP POLICY IF EXISTS "villages_register" ON public.villages$bootstrap_sql_00e29f9ba6c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00e29f9ba6c9$;

DO $bootstrap_do_43f37bd80f3e$
BEGIN
  EXECUTE $bootstrap_sql_43f37bd80f3e$-- Allow authenticated users to register villages (PENDING + inactive)
DROP POLICY IF EXISTS "Authenticated users can register village" ON public.villages$bootstrap_sql_43f37bd80f3e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_43f37bd80f3e$;

DO $bootstrap_do_398db8f62e6d$
BEGIN
  EXECUTE $bootstrap_sql_398db8f62e6d$CREATE POLICY "Authenticated users can register village"
ON public.villages
FOR INSERT
TO authenticated
WITH CHECK (
  registration_status = 'PENDING' AND is_active = false
)$bootstrap_sql_398db8f62e6d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_398db8f62e6d$;

DO $bootstrap_do_3f1ee97fab95$
BEGIN
  EXECUTE $bootstrap_sql_3f1ee97fab95$-- Ensure admin ALL policy covers everything (recreate to be safe)
DROP POLICY IF EXISTS "Admins can manage villages" ON public.villages$bootstrap_sql_3f1ee97fab95$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3f1ee97fab95$;

DO $bootstrap_do_565c17688a07$
BEGIN
  EXECUTE $bootstrap_sql_565c17688a07$CREATE POLICY "Admins can manage villages"
ON public.villages
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin())$bootstrap_sql_565c17688a07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_565c17688a07$;

DO $bootstrap_do_478d07e39ddd$
BEGIN
  EXECUTE $bootstrap_sql_478d07e39ddd$-- Allow admin_desa to update their own village
DROP POLICY IF EXISTS "Admin desa can update own village" ON public.villages$bootstrap_sql_478d07e39ddd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_478d07e39ddd$;

DO $bootstrap_do_e157f7026f63$
BEGIN
  EXECUTE $bootstrap_sql_e157f7026f63$CREATE POLICY "Admin desa can update own village"
ON public.villages
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_villages uv
    WHERE uv.village_id = id AND uv.user_id = auth.uid()
  )
)$bootstrap_sql_e157f7026f63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e157f7026f63$;

DO $bootstrap_do_d76a49f27e2c$
BEGIN
  EXECUTE $bootstrap_sql_d76a49f27e2c$-- 3. Fix RLS policies for user_villages table
-- Drop existing policies
DROP POLICY IF EXISTS "Admins manage village assignments" ON public.user_villages$bootstrap_sql_d76a49f27e2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d76a49f27e2c$;

DO $bootstrap_do_7d95aecbff16$
BEGIN
  EXECUTE $bootstrap_sql_7d95aecbff16$DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages$bootstrap_sql_7d95aecbff16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d95aecbff16$;

DO $bootstrap_do_a253b4ce6df3$
BEGIN
  EXECUTE $bootstrap_sql_a253b4ce6df3$-- Admin full access
CREATE POLICY "Admins manage village assignments"
ON public.user_villages
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin())$bootstrap_sql_a253b4ce6df3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a253b4ce6df3$;

DO $bootstrap_do_4f8fe538206d$
BEGIN
  EXECUTE $bootstrap_sql_4f8fe538206d$-- Users can view their own assignments
DROP POLICY IF EXISTS "Users view own village assignments" ON public.user_villages$bootstrap_sql_4f8fe538206d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4f8fe538206d$;

DO $bootstrap_do_920b15b23e2f$
BEGIN
  EXECUTE $bootstrap_sql_920b15b23e2f$CREATE POLICY "Users view own village assignments"
ON public.user_villages
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin())$bootstrap_sql_920b15b23e2f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_920b15b23e2f$;

DO $bootstrap_do_c5933d917afd$
BEGIN
  EXECUTE $bootstrap_sql_c5933d917afd$-- Authenticated users can insert their own assignment (for registration)
DROP POLICY IF EXISTS "Users can register own village assignment" ON public.user_villages$bootstrap_sql_c5933d917afd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5933d917afd$;

DO $bootstrap_do_e3d5e9dc1302$
BEGIN
  EXECUTE $bootstrap_sql_e3d5e9dc1302$CREATE POLICY "Users can register own village assignment"
ON public.user_villages
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid())$bootstrap_sql_e3d5e9dc1302$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e3d5e9dc1302$;

DO $bootstrap_do_302b8fb8ead8$
BEGIN
  EXECUTE $bootstrap_sql_302b8fb8ead8$-- Add updated_at trigger for villages
DROP TRIGGER IF EXISTS update_villages_updated_at ON public.villages$bootstrap_sql_302b8fb8ead8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_302b8fb8ead8$;

DO $bootstrap_do_a082ebb3d461$
BEGIN
  EXECUTE $bootstrap_sql_a082ebb3d461$CREATE TRIGGER update_villages_updated_at
BEFORE UPDATE ON public.villages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_a082ebb3d461$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a082ebb3d461$;

DO $bootstrap_do_0d32db806c3c$
BEGIN
  EXECUTE $bootstrap_sql_0d32db806c3c$
