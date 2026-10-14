-- Add address component columns to profiles table for auto-fill functionality
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS province_id TEXT,
ADD COLUMN IF NOT EXISTS province_name TEXT,
ADD COLUMN IF NOT EXISTS city_id TEXT,
ADD COLUMN IF NOT EXISTS city_name TEXT,
ADD COLUMN IF NOT EXISTS district_id TEXT,
ADD COLUMN IF NOT EXISTS district_name TEXT,
ADD COLUMN IF NOT EXISTS village_id TEXT,
ADD COLUMN IF NOT EXISTS village_name TEXT,
ADD COLUMN IF NOT EXISTS address_detail TEXT$bootstrap_sql_f14be90e4e47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f14be90e4e47$;

DO $bootstrap_do_932cb9bdb437$
BEGIN
  EXECUTE $bootstrap_sql_932cb9bdb437$-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id)$bootstrap_sql_932cb9bdb437$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_932cb9bdb437$;

DO $bootstrap_do_ed04c7350052$
BEGIN
  EXECUTE $bootstrap_sql_ed04c7350052$
