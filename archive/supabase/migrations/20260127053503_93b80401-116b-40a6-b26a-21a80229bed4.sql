-- Create helper functions for role checking
CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id uuid)
RETURNS text[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(role::text), ARRAY[]::text[])
  FROM public.user_roles
  WHERE user_id = _user_id
$$$bootstrap_sql_68fbd3a38fac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68fbd3a38fac$;

DO $bootstrap_do_31da73227292$
BEGIN
  EXECUTE $bootstrap_sql_31da73227292$CREATE OR REPLACE FUNCTION public.has_any_role(_user_id uuid, _roles app_role[])
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = ANY(_roles)
  )
$$$bootstrap_sql_31da73227292$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31da73227292$;

DO $bootstrap_do_be39061f9031$
BEGIN
  EXECUTE $bootstrap_sql_be39061f9031$-- Function to check if user is merchant
CREATE OR REPLACE FUNCTION public.is_merchant()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'merchant')
$$$bootstrap_sql_be39061f9031$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be39061f9031$;

DO $bootstrap_do_c78858a7bb3b$
BEGIN
  EXECUTE $bootstrap_sql_c78858a7bb3b$-- Function to check if user is courier
CREATE OR REPLACE FUNCTION public.is_courier()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'courier')
$$$bootstrap_sql_c78858a7bb3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c78858a7bb3b$;

DO $bootstrap_do_a1b3e437a61a$
BEGIN
  EXECUTE $bootstrap_sql_a1b3e437a61a$-- Function to check if user is admin desa
CREATE OR REPLACE FUNCTION public.is_admin_desa()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_role(auth.uid(), 'admin_desa')
$$$bootstrap_sql_a1b3e437a61a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1b3e437a61a$;

DO $bootstrap_do_0391d4c3eb48$
BEGIN
  EXECUTE $bootstrap_sql_0391d4c3eb48$
