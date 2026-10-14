-- Create trigger function to auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(NEW.email, '@', 1)
    )
  )
  ON CONFLICT (user_id) DO UPDATE SET
    full_name = COALESCE(
      EXCLUDED.full_name,
      public.profiles.full_name
    );
  RETURN NEW;
END;
$$$bootstrap_sql_30ee508ed7f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_30ee508ed7f9$;

DO $bootstrap_do_b683a954ea78$
BEGIN
  EXECUTE $bootstrap_sql_b683a954ea78$-- Drop existing trigger if any
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users$bootstrap_sql_b683a954ea78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b683a954ea78$;

DO $bootstrap_do_29818be03aae$
BEGIN
  EXECUTE $bootstrap_sql_29818be03aae$-- Create trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user()$bootstrap_sql_29818be03aae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_29818be03aae$;

DO $bootstrap_do_68f003f5ed67$
BEGIN
  EXECUTE $bootstrap_sql_68f003f5ed67$-- Backfill: create profiles for existing users who don't have one
INSERT INTO public.profiles (user_id, full_name)
SELECT
  u.id,
  COALESCE(
    u.raw_user_meta_data->>'full_name',
    u.raw_user_meta_data->>'name',
    split_part(u.email, '@', 1)
  )
FROM auth.users u
LEFT JOIN public.profiles p ON p.user_id = u.id
WHERE p.user_id IS NULL
ON CONFLICT DO NOTHING$bootstrap_sql_68f003f5ed67$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68f003f5ed67$;

DO $bootstrap_do_cf431239ec01$
BEGIN
  EXECUTE $bootstrap_sql_cf431239ec01$
