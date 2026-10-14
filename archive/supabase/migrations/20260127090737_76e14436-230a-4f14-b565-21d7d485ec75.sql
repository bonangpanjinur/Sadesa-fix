-- Fix Security Definer View warnings by using SECURITY INVOKER

-- Drop and recreate public_merchants view with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_merchants$bootstrap_sql_8ef317d387d6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ef317d387d6$;

DO $bootstrap_do_8109ce7391b8$
BEGIN
  EXECUTE $bootstrap_sql_8109ce7391b8$CREATE VIEW public.public_merchants
WITH (security_invoker = true)
AS
SELECT
  id,
  name,
  business_category,
  business_description,
  image_url,
  is_open,
  open_time,
  close_time,
  badge,
  rating_avg,
  rating_count,
  classification_price,
  village_id,
  city,
  province
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_8109ce7391b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8109ce7391b8$;

DO $bootstrap_do_222afaf65ec0$
BEGIN
  EXECUTE $bootstrap_sql_222afaf65ec0$-- Grant access to the view
GRANT SELECT ON public.public_merchants TO anon$bootstrap_sql_222afaf65ec0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_222afaf65ec0$;

DO $bootstrap_do_031376b239a5$
BEGIN
  EXECUTE $bootstrap_sql_031376b239a5$GRANT SELECT ON public.public_merchants TO authenticated$bootstrap_sql_031376b239a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_031376b239a5$;

DO $bootstrap_do_876c15681008$
BEGIN
  EXECUTE $bootstrap_sql_876c15681008$-- Drop and recreate public_couriers view with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_couriers$bootstrap_sql_876c15681008$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_876c15681008$;

DO $bootstrap_do_d383f4d8b35d$
BEGIN
  EXECUTE $bootstrap_sql_d383f4d8b35d$CREATE VIEW public.public_couriers
WITH (security_invoker = true)
AS
SELECT
  id,
  name,
  SPLIT_PART(name, ' ', 1) as first_name,
  vehicle_type,
  photo_url,
  status,
  is_available,
  current_lat,
  current_lng,
  last_location_update
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_d383f4d8b35d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d383f4d8b35d$;

DO $bootstrap_do_46ca55a9014e$
BEGIN
  EXECUTE $bootstrap_sql_46ca55a9014e$-- Grant access only to authenticated users
GRANT SELECT ON public.public_couriers TO authenticated$bootstrap_sql_46ca55a9014e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46ca55a9014e$;

DO $bootstrap_do_73fc73ca0e15$
BEGIN
  EXECUTE $bootstrap_sql_73fc73ca0e15$-- Also add policy for anon users to view public merchants (via view)
-- We need a basic SELECT policy for the underlying table to work with the view
DROP POLICY IF EXISTS "Anon can view basic merchant info" ON public.merchants$bootstrap_sql_73fc73ca0e15$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_73fc73ca0e15$;

DO $bootstrap_do_767548159306$
BEGIN
  EXECUTE $bootstrap_sql_767548159306$CREATE POLICY "Anon can view basic merchant info"
ON public.merchants
FOR SELECT
TO anon
USING (status = 'ACTIVE' AND registration_status = 'APPROVED')$bootstrap_sql_767548159306$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_767548159306$;

DO $bootstrap_do_61b9f67712d0$
BEGIN
  EXECUTE $bootstrap_sql_61b9f67712d0$
