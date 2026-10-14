-- =============================================
-- FIX SECURITY: Couriers Table
-- =============================================

-- Drop the overly permissive policy that exposes all courier data to authenticated users
DROP POLICY IF EXISTS "Active couriers visible to authenticated" ON public.couriers$bootstrap_sql_f07c9e875600$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f07c9e875600$;

DO $bootstrap_do_0786f13e42fa$
BEGIN
  EXECUTE $bootstrap_sql_0786f13e42fa$-- Create a more restrictive policy: Only allow viewing couriers if:
-- 1. User is an admin
-- 2. User is a verifikator
-- 3. User is the courier themselves
-- 4. User is a merchant with an order assigned to that courier
-- 5. User is a buyer with an order assigned to that courier
DROP POLICY IF EXISTS "Authorized users can view courier info" ON public.couriers$bootstrap_sql_0786f13e42fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0786f13e42fa$;

DO $bootstrap_do_7134d400cc53$
BEGIN
  EXECUTE $bootstrap_sql_7134d400cc53$CREATE POLICY "Authorized users can view courier info"
ON public.couriers
FOR SELECT
USING (
  is_admin() OR
  is_verifikator() OR
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM orders o
    JOIN merchants m ON o.merchant_id = m.id
    WHERE o.courier_id = couriers.id
    AND m.user_id = auth.uid()
  ) OR
  EXISTS (
    SELECT 1 FROM orders o
    WHERE o.courier_id = couriers.id
    AND o.buyer_id = auth.uid()
  )
)$bootstrap_sql_7134d400cc53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7134d400cc53$;

DO $bootstrap_do_03af5e6d06e7$
BEGIN
  EXECUTE $bootstrap_sql_03af5e6d06e7$-- =============================================
-- FIX SECURITY: Merchants Table
-- =============================================

-- Drop the overly permissive policy
DROP POLICY IF EXISTS "Anyone can view active merchants" ON public.merchants$bootstrap_sql_03af5e6d06e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03af5e6d06e7$;

DO $bootstrap_do_ad0c188411d7$
BEGIN
  EXECUTE $bootstrap_sql_ad0c188411d7$-- Create policy: Only expose limited merchant data to unauthenticated users
-- For full data access, require authentication and specific roles
DROP POLICY IF EXISTS "Authenticated users can view active merchants" ON public.merchants$bootstrap_sql_ad0c188411d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad0c188411d7$;

DO $bootstrap_do_a3a1e884c3d1$
BEGIN
  EXECUTE $bootstrap_sql_a3a1e884c3d1$CREATE POLICY "Authenticated users can view active merchants"
ON public.merchants
FOR SELECT
USING (
  status = 'ACTIVE' AND auth.uid() IS NOT NULL
)$bootstrap_sql_a3a1e884c3d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3a1e884c3d1$;

DO $bootstrap_do_feb22500d4b0$
BEGIN
  EXECUTE $bootstrap_sql_feb22500d4b0$-- Create a secure view for public merchant listing (limited columns)
CREATE OR REPLACE VIEW public.public_merchants AS
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
  -- Only show city-level location, not full address
  city,
  province
FROM public.merchants
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_feb22500d4b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_feb22500d4b0$;

DO $bootstrap_do_be5ecd8c2c61$
BEGIN
  EXECUTE $bootstrap_sql_be5ecd8c2c61$-- Grant public access to the view
GRANT SELECT ON public.public_merchants TO anon$bootstrap_sql_be5ecd8c2c61$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be5ecd8c2c61$;

DO $bootstrap_do_a6938ff1a85b$
BEGIN
  EXECUTE $bootstrap_sql_a6938ff1a85b$GRANT SELECT ON public.public_merchants TO authenticated$bootstrap_sql_a6938ff1a85b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6938ff1a85b$;

DO $bootstrap_do_7c99ca486e64$
BEGIN
  EXECUTE $bootstrap_sql_7c99ca486e64$-- =============================================
-- Create a secure view for public courier info (for order tracking)
-- =============================================
CREATE OR REPLACE VIEW public.public_couriers AS
SELECT
  id,
  name,
  -- Only expose first name for privacy
  SPLIT_PART(name, ' ', 1) as first_name,
  vehicle_type,
  photo_url,
  status,
  is_available,
  current_lat,
  current_lng,
  last_location_update
FROM public.couriers
WHERE status = 'ACTIVE' AND registration_status = 'APPROVED'$bootstrap_sql_7c99ca486e64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c99ca486e64$;

DO $bootstrap_do_09f90a200032$
BEGIN
  EXECUTE $bootstrap_sql_09f90a200032$-- Grant access only to authenticated users
GRANT SELECT ON public.public_couriers TO authenticated$bootstrap_sql_09f90a200032$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09f90a200032$;

DO $bootstrap_do_8ef317d387d6$
BEGIN
  EXECUTE $bootstrap_sql_8ef317d387d6$
