-- Cleanup duplicate RLS policies on orders table
-- Keep: orders_admin_access, orders_buyer_access, orders_merchant_access, orders_courier_access (FOR ALL)
-- Remove: granular per-command duplicates
DROP POLICY IF EXISTS "Admins can manage all orders" ON public.orders$bootstrap_sql_120bc10b03a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_120bc10b03a4$;

DO $bootstrap_do_cc0bb805efc6$
BEGIN
  EXECUTE $bootstrap_sql_cc0bb805efc6$DROP POLICY IF EXISTS "Buyers can create orders" ON public.orders$bootstrap_sql_cc0bb805efc6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc0bb805efc6$;

DO $bootstrap_do_ad691f55a11b$
BEGIN
  EXECUTE $bootstrap_sql_ad691f55a11b$DROP POLICY IF EXISTS "Buyers can update own orders" ON public.orders$bootstrap_sql_ad691f55a11b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad691f55a11b$;

DO $bootstrap_do_4ccb9df34d30$
BEGIN
  EXECUTE $bootstrap_sql_4ccb9df34d30$DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders$bootstrap_sql_4ccb9df34d30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ccb9df34d30$;

DO $bootstrap_do_e32a32e6847e$
BEGIN
  EXECUTE $bootstrap_sql_e32a32e6847e$DROP POLICY IF EXISTS "Couriers can update assigned orders" ON public.orders$bootstrap_sql_e32a32e6847e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e32a32e6847e$;

DO $bootstrap_do_a7aff3c7ecba$
BEGIN
  EXECUTE $bootstrap_sql_a7aff3c7ecba$DROP POLICY IF EXISTS "Couriers can view assigned orders" ON public.orders$bootstrap_sql_a7aff3c7ecba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7aff3c7ecba$;

DO $bootstrap_do_a3a9fc6c3c62$
BEGIN
  EXECUTE $bootstrap_sql_a3a9fc6c3c62$DROP POLICY IF EXISTS "Merchants can update own orders" ON public.orders$bootstrap_sql_a3a9fc6c3c62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3a9fc6c3c62$;

DO $bootstrap_do_175fc9d0ab1d$
BEGIN
  EXECUTE $bootstrap_sql_175fc9d0ab1d$DROP POLICY IF EXISTS "Merchants can view own orders" ON public.orders$bootstrap_sql_175fc9d0ab1d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_175fc9d0ab1d$;

DO $bootstrap_do_d7184952dc0e$
BEGIN
  EXECUTE $bootstrap_sql_d7184952dc0e$-- Cleanup duplicate RLS policies on couriers table
-- Keep: couriers_admin_access, couriers_own_access, couriers_public_read
-- Remove: named duplicates
DROP POLICY IF EXISTS "Admins can manage couriers" ON public.couriers$bootstrap_sql_d7184952dc0e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7184952dc0e$;

DO $bootstrap_do_2a9eba4f9f77$
BEGIN
  EXECUTE $bootstrap_sql_2a9eba4f9f77$DROP POLICY IF EXISTS "Couriers can view own data" ON public.couriers$bootstrap_sql_2a9eba4f9f77$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a9eba4f9f77$;

DO $bootstrap_do_df9a04e4bc82$
BEGIN
  EXECUTE $bootstrap_sql_df9a04e4bc82$DROP POLICY IF EXISTS "Couriers can update own location" ON public.couriers$bootstrap_sql_df9a04e4bc82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df9a04e4bc82$;

DO $bootstrap_do_19b64e3857b4$
BEGIN
  EXECUTE $bootstrap_sql_19b64e3857b4$DROP POLICY IF EXISTS "Public can view approved couriers" ON public.couriers$bootstrap_sql_19b64e3857b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19b64e3857b4$;

DO $bootstrap_do_18386b15f862$
BEGIN
  EXECUTE $bootstrap_sql_18386b15f862$-- Cleanup duplicate RLS policies on merchants table
-- Keep: Admins can manage merchants, Anyone can register merchant, Merchants can update own data, Verifikator can manage merchants
-- Remove overlapping SELECT policies
DROP POLICY IF EXISTS "Authenticated users can view active merchants" ON public.merchants$bootstrap_sql_18386b15f862$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18386b15f862$;

DO $bootstrap_do_a4d8bd62bcac$
BEGIN
  EXECUTE $bootstrap_sql_a4d8bd62bcac$DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants$bootstrap_sql_a4d8bd62bcac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a4d8bd62bcac$;

DO $bootstrap_do_ba8bed2958e4$
BEGIN
  EXECUTE $bootstrap_sql_ba8bed2958e4$
