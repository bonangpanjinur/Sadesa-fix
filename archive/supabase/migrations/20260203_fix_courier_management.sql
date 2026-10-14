-- Fix RLS for couriers table to allow admins and verifikators to manage it properly
-- This fixes the issue where data might not load due to permission errors

-- 1. Ensure the is_verifikator function exists (referenced in previous migrations but let's be sure)
CREATE OR REPLACE FUNCTION public.is_verifikator()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = 'verifikator'
  );
$$$bootstrap_sql_28ed581fea97$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_28ed581fea97$;

DO $bootstrap_do_8f76acf47e0d$
BEGIN
  EXECUTE $bootstrap_sql_8f76acf47e0d$-- 2. Drop existing policies to recreate them cleanly
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_8f76acf47e0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8f76acf47e0d$;

DO $bootstrap_do_9308c8d36b42$
BEGIN
  EXECUTE $bootstrap_sql_9308c8d36b42$DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_9308c8d36b42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9308c8d36b42$;

DO $bootstrap_do_377dc70f5800$
BEGIN
  EXECUTE $bootstrap_sql_377dc70f5800$DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_377dc70f5800$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_377dc70f5800$;

DO $bootstrap_do_89305cd649f2$
BEGIN
  EXECUTE $bootstrap_sql_89305cd649f2$DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers$bootstrap_sql_89305cd649f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89305cd649f2$;

DO $bootstrap_do_13de353145d0$
BEGIN
  EXECUTE $bootstrap_sql_13de353145d0$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_13de353145d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_13de353145d0$;

DO $bootstrap_do_fa65e85d0492$
BEGIN
  EXECUTE $bootstrap_sql_fa65e85d0492$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_fa65e85d0492$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fa65e85d0492$;

DO $bootstrap_do_cd0db33dd147$
BEGIN
  EXECUTE $bootstrap_sql_cd0db33dd147$-- 3. Recreate policies with proper function calls
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_cd0db33dd147$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd0db33dd147$;

DO $bootstrap_do_d3279874a821$
BEGIN
  EXECUTE $bootstrap_sql_d3279874a821$CREATE POLICY "Admins can manage couriers" ON public.couriers
FOR ALL USING (public.is_admin())$bootstrap_sql_d3279874a821$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3279874a821$;

DO $bootstrap_do_dbdfc0034723$
BEGIN
  EXECUTE $bootstrap_sql_dbdfc0034723$DROP POLICY IF EXISTS "Verifikator can manage couriers" ON public.couriers$bootstrap_sql_dbdfc0034723$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dbdfc0034723$;

DO $bootstrap_do_4c57910a5cf1$
BEGIN
  EXECUTE $bootstrap_sql_4c57910a5cf1$CREATE POLICY "Verifikator can manage couriers" ON public.couriers
FOR ALL USING (public.is_verifikator())$bootstrap_sql_4c57910a5cf1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c57910a5cf1$;

DO $bootstrap_do_9b283a50feac$
BEGIN
  EXECUTE $bootstrap_sql_9b283a50feac$DROP POLICY IF EXISTS "Anyone can register as courier" ON public.couriers$bootstrap_sql_9b283a50feac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b283a50feac$;

DO $bootstrap_do_421d6b35beee$
BEGIN
  EXECUTE $bootstrap_sql_421d6b35beee$CREATE POLICY "Anyone can register as courier" ON public.couriers
FOR INSERT WITH CHECK (registration_status = 'PENDING' AND status = 'INACTIVE')$bootstrap_sql_421d6b35beee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_421d6b35beee$;

DO $bootstrap_do_ad34419fb8dd$
BEGIN
  EXECUTE $bootstrap_sql_ad34419fb8dd$DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers$bootstrap_sql_ad34419fb8dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad34419fb8dd$;

DO $bootstrap_do_bc4fe92a4736$
BEGIN
  EXECUTE $bootstrap_sql_bc4fe92a4736$CREATE POLICY "Active couriers visible to authenticated" ON public.couriers
FOR SELECT USING (status = 'ACTIVE' AND auth.uid() IS NOT NULL)$bootstrap_sql_bc4fe92a4736$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc4fe92a4736$;

DO $bootstrap_do_3d243b93111c$
BEGIN
  EXECUTE $bootstrap_sql_3d243b93111c$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_3d243b93111c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d243b93111c$;

DO $bootstrap_do_2ea42ca31d0c$
BEGIN
  EXECUTE $bootstrap_sql_2ea42ca31d0c$CREATE POLICY "Couriers can view own data" ON public.couriers
FOR SELECT USING (user_id = auth.uid())$bootstrap_sql_2ea42ca31d0c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ea42ca31d0c$;

DO $bootstrap_do_66cd4a887636$
BEGIN
  EXECUTE $bootstrap_sql_66cd4a887636$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_66cd4a887636$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_66cd4a887636$;

DO $bootstrap_do_6cc045c11325$
BEGIN
  EXECUTE $bootstrap_sql_6cc045c11325$CREATE POLICY "Couriers can update own location" ON public.couriers
FOR UPDATE USING (user_id = auth.uid() AND status = 'ACTIVE')$bootstrap_sql_6cc045c11325$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6cc045c11325$;

DO $bootstrap_do_82a62c3a24c6$
BEGIN
  EXECUTE $bootstrap_sql_82a62c3a24c6$-- 4. Add index for performance
CREATE INDEX IF NOT EXISTS idx_couriers_registration_status ON public.couriers(registration_status)$bootstrap_sql_82a62c3a24c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82a62c3a24c6$;

DO $bootstrap_do_a1bdfde1286a$
BEGIN
  EXECUTE $bootstrap_sql_a1bdfde1286a$CREATE INDEX IF NOT EXISTS idx_couriers_village_id ON public.couriers(village_id)$bootstrap_sql_a1bdfde1286a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1bdfde1286a$;

DO $bootstrap_do_2d863c390e29$
BEGIN
  EXECUTE $bootstrap_sql_2d863c390e29$
