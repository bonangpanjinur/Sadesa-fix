-- DesaMart canonical bootstrap bundle; generated from an ordered deployment migration.
-- Apply only through the approved database migration process.

-- ===== BEGIN SOURCE: 20261008180000_publish_profiles_for_admin_geography_realtime.sql =====
DO $bootstrap_do_20261008180000$
BEGIN
  EXECUTE $bootstrap_sql_20261008180000$-- Publish profile changes so the admin-only user geography dashboard can refresh live.
-- Realtime subscribers remain subject to the existing profiles SELECT RLS policies.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
END;
$$;
$bootstrap_sql_20261008180000$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20261008180000$;
-- ===== END SOURCE: 20261008180000_publish_profiles_for_admin_geography_realtime.sql =====
