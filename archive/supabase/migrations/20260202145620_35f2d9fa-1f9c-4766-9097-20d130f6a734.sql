-- Fix Security Issues: Profiles, Saved Addresses, and Merchants RLS

-- ============================================
-- 1. PROFILES TABLE - Stricter RLS
-- ============================================

-- Drop existing policies if not already dropped
DROP POLICY IF EXISTS "Users can view own profile only" ON public.profiles$bootstrap_sql_d69e09238f26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d69e09238f26$;

DO $bootstrap_do_00c0f25b830a$
BEGIN
  EXECUTE $bootstrap_sql_00c0f25b830a$DROP POLICY IF EXISTS "Service role has full access to profiles" ON public.profiles$bootstrap_sql_00c0f25b830a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00c0f25b830a$;

DO $bootstrap_do_e4b7b13f96fd$
BEGIN
  EXECUTE $bootstrap_sql_e4b7b13f96fd$-- Create stricter policies
CREATE POLICY "Users can view own profile only"
ON public.profiles
FOR SELECT
USING (auth.uid() = user_id)$bootstrap_sql_e4b7b13f96fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e4b7b13f96fd$;

DO $bootstrap_do_a21773934a05$
BEGIN
  EXECUTE $bootstrap_sql_a21773934a05$DROP POLICY IF EXISTS "Service role has full access to profiles" ON public.profiles$bootstrap_sql_a21773934a05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a21773934a05$;

DO $bootstrap_do_392664ff6da6$
BEGIN
  EXECUTE $bootstrap_sql_392664ff6da6$CREATE POLICY "Service role has full access to profiles"
ON public.profiles
FOR ALL
USING (auth.jwt() ->> 'role' = 'service_role')$bootstrap_sql_392664ff6da6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_392664ff6da6$;

DO $bootstrap_do_22fbfb83f11a$
BEGIN
  EXECUTE $bootstrap_sql_22fbfb83f11a$-- ============================================
-- 2. SAVED_ADDRESSES TABLE - Add service role access
-- ============================================

DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses$bootstrap_sql_22fbfb83f11a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22fbfb83f11a$;

DO $bootstrap_do_d2d14d43712a$
BEGIN
  EXECUTE $bootstrap_sql_d2d14d43712a$CREATE POLICY "Service role has full access to saved_addresses"
ON public.saved_addresses
FOR ALL
USING (auth.jwt() ->> 'role' = 'service_role')$bootstrap_sql_d2d14d43712a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2d14d43712a$;

DO $bootstrap_do_c8faf22d6bcb$
BEGIN
  EXECUTE $bootstrap_sql_c8faf22d6bcb$-- ============================================
-- 3. MERCHANTS TABLE - Protect sensitive data with views
-- ============================================

-- Drop existing view first to recreate with new structure
DROP VIEW IF EXISTS public.public_merchants CASCADE$bootstrap_sql_c8faf22d6bcb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8faf22d6bcb$;

DO $bootstrap_do_f8866d0134c9$
BEGIN
  EXECUTE $bootstrap_sql_f8866d0134c9$-- Create a secure view for public merchant data (masks phone number)
CREATE VIEW public.public_merchants AS
SELECT
  id,
  name,
  image_url,
  business_category,
  business_description,
  village_id,
  -- Mask phone number - only show last 4 digits
  CASE
    WHEN phone IS NOT NULL THEN
      CONCAT('****', RIGHT(phone, 4))
    ELSE NULL
  END as phone_masked,
  -- Only show general location (city level), not exact address
  city,
  district,
  province,
  -- Hide exact coordinates for public view
  -- Show approximate location (rounded to ~1km precision)
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
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_f8866d0134c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8866d0134c9$;

DO $bootstrap_do_2726132b178a$
BEGIN
  EXECUTE $bootstrap_sql_2726132b178a$-- Grant access to the public view
GRANT SELECT ON public.public_merchants TO anon$bootstrap_sql_2726132b178a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2726132b178a$;

DO $bootstrap_do_d184ee8fbb90$
BEGIN
  EXECUTE $bootstrap_sql_d184ee8fbb90$GRANT SELECT ON public.public_merchants TO authenticated$bootstrap_sql_d184ee8fbb90$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d184ee8fbb90$;

DO $bootstrap_do_56f00e0692b0$
BEGIN
  EXECUTE $bootstrap_sql_56f00e0692b0$-- Update merchant policies
DROP POLICY IF EXISTS "Authenticated users view active merchants basic info" ON public.merchants$bootstrap_sql_56f00e0692b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56f00e0692b0$;

DO $bootstrap_do_e6c58361d4a5$
BEGIN
  EXECUTE $bootstrap_sql_e6c58361d4a5$CREATE POLICY "Authenticated users view active merchants basic info"
ON public.merchants
FOR SELECT
USING (
  (user_id = auth.uid())
  OR
  (status = 'ACTIVE' AND registration_status = 'APPROVED' AND auth.uid() IS NOT NULL)
  OR
  is_admin()
  OR
  is_verifikator()
)$bootstrap_sql_e6c58361d4a5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6c58361d4a5$;

DO $bootstrap_do_109e10177a3a$
BEGIN
  EXECUTE $bootstrap_sql_109e10177a3a$-- ============================================
-- 4. COURIERS TABLE - Protect sensitive data with views
-- ============================================

DROP VIEW IF EXISTS public.public_couriers CASCADE$bootstrap_sql_109e10177a3a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_109e10177a3a$;

DO $bootstrap_do_6a0b6cc75c16$
BEGIN
  EXECUTE $bootstrap_sql_6a0b6cc75c16$CREATE VIEW public.public_couriers AS
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
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_6a0b6cc75c16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a0b6cc75c16$;

DO $bootstrap_do_0768564edf29$
BEGIN
  EXECUTE $bootstrap_sql_0768564edf29$GRANT SELECT ON public.public_couriers TO anon$bootstrap_sql_0768564edf29$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0768564edf29$;

DO $bootstrap_do_dda1e282edc7$
BEGIN
  EXECUTE $bootstrap_sql_dda1e282edc7$GRANT SELECT ON public.public_couriers TO authenticated$bootstrap_sql_dda1e282edc7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dda1e282edc7$;

DO $bootstrap_do_a22c7ac8454b$
BEGIN
  EXECUTE $bootstrap_sql_a22c7ac8454b$
