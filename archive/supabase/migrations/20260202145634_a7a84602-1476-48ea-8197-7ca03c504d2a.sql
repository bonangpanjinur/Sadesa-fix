-- Fix SECURITY DEFINER warnings by recreating views with SECURITY INVOKER

-- Drop and recreate public_merchants with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_merchants$bootstrap_sql_a22c7ac8454b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a22c7ac8454b$;

DO $bootstrap_do_3de33443675f$
BEGIN
  EXECUTE $bootstrap_sql_3de33443675f$CREATE VIEW public.public_merchants
WITH (security_invoker = true) AS
SELECT
  id,
  name,
  image_url,
  business_category,
  business_description,
  village_id,
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  city,
  district,
  province,
  CASE
    WHEN location_lat IS NOT NULL THEN
      ROUND(location_lat::numeric, 2)
    ELSE NULL
  END as location_lat_approx,
  CASE
    WHEN location_lng IS NOT NULL THEN
      ROUND(location_lng::numeric, 2)
    ELSE NULL
  END as location_lng_approx,
  is_open,
  open_time,
  close_time,
  rating_avg,
  rating_count,
  is_verified,
  badge,
  order_mode
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_3de33443675f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3de33443675f$;

DO $bootstrap_do_a858bb604cb4$
BEGIN
  EXECUTE $bootstrap_sql_a858bb604cb4$GRANT SELECT ON public.public_merchants TO anon$bootstrap_sql_a858bb604cb4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a858bb604cb4$;

DO $bootstrap_do_535f7d44ec0b$
BEGIN
  EXECUTE $bootstrap_sql_535f7d44ec0b$GRANT SELECT ON public.public_merchants TO authenticated$bootstrap_sql_535f7d44ec0b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_535f7d44ec0b$;

DO $bootstrap_do_9afe0b8e7db3$
BEGIN
  EXECUTE $bootstrap_sql_9afe0b8e7db3$-- Drop and recreate public_couriers with SECURITY INVOKER
DROP VIEW IF EXISTS public.public_couriers$bootstrap_sql_9afe0b8e7db3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9afe0b8e7db3$;

DO $bootstrap_do_93b428fadacb$
BEGIN
  EXECUTE $bootstrap_sql_93b428fadacb$CREATE VIEW public.public_couriers
WITH (security_invoker = true) AS
SELECT
  id,
  name,
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  photo_url,
  vehicle_type,
  CASE
    WHEN current_lat IS NOT NULL THEN
      ROUND(current_lat::numeric, 3)
    ELSE NULL
  END as current_lat_approx,
  CASE
    WHEN current_lng IS NOT NULL THEN
      ROUND(current_lng::numeric, 3)
    ELSE NULL
  END as current_lng_approx,
  is_available,
  status,
  village_id
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_93b428fadacb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93b428fadacb$;

DO $bootstrap_do_ae21d80e9d42$
BEGIN
  EXECUTE $bootstrap_sql_ae21d80e9d42$GRANT SELECT ON public.public_couriers TO anon$bootstrap_sql_ae21d80e9d42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae21d80e9d42$;

DO $bootstrap_do_e2f74f5efd08$
BEGIN
  EXECUTE $bootstrap_sql_e2f74f5efd08$GRANT SELECT ON public.public_couriers TO authenticated$bootstrap_sql_e2f74f5efd08$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e2f74f5efd08$;

DO $bootstrap_do_06a1c980c209$
BEGIN
  EXECUTE $bootstrap_sql_06a1c980c209$
