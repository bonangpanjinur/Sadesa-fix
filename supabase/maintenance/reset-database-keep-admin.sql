-- SaDesa / Supabase destructive reset
--
-- PURPOSE
--   Remove application data and all Auth users
--   except the administrator identified below. Database objects, tables,
--   functions, policies, storage buckets, storage objects, and migrations are
--   preserved.
--
-- HOW TO RUN
--   Run this file once from the Supabase SQL Editor using a privileged
--   database role. Do not run it through the public/anon client.
--
-- IMPORTANT
--   This is destructive and cannot be undone without a backup. Take a
--   database/storage backup before execution if any data may be needed later.
--   The transaction is rolled back automatically if any statement fails.
--
-- STORAGE NOTE
--   Supabase intentionally blocks direct DELETE/TRUNCATE statements against
--   storage.objects. Uploaded files must be removed separately through the
--   Supabase Storage API or Dashboard after this SQL completes. The database
--   reset below does not orphan or modify Storage metadata.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '10min';

DO $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT id
    INTO v_admin_id
  FROM auth.users
  WHERE lower(email) = lower('bopan86@gmail.com')
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION
      'ABORTED: auth user bopan86@gmail.com was not found. No reset was performed.';
  END IF;

  -- Keep the exact admin profile and role rows while all public tables are
  -- truncated. The temporary tables disappear automatically at transaction end.
  CREATE TEMP TABLE _reset_admin_profiles ON COMMIT DROP AS
    SELECT * FROM public.profiles WHERE user_id = v_admin_id;

  CREATE TEMP TABLE _reset_admin_user_roles ON COMMIT DROP AS
    SELECT * FROM public.user_roles WHERE user_id = v_admin_id;

  -- Truncate every ordinary/partitioned table in public. The two identity
  -- tables are excluded and restored from the temporary snapshots below.
  -- CASCADE handles the many application foreign-key relationships without
  -- dropping schema objects.
  EXECUTE (
    SELECT 'TRUNCATE TABLE ' || string_agg(format('%I.%I', n.nspname, c.relname), ', ')
           || ' RESTART IDENTITY CASCADE'
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname NOT IN ('profiles', 'user_roles')
  );

  -- Remove every Supabase Auth account except the named administrator. The
  -- admin's auth identity, password, MFA configuration, and metadata remain.
  DELETE FROM auth.users
  WHERE id <> v_admin_id;

  -- Restore the administrator's application identity after the public reset.
  -- These statements are intentionally dynamic so the script remains useful
  -- if a future migration adds nullable columns to either table.
  INSERT INTO public.profiles
  SELECT * FROM _reset_admin_profiles;

  INSERT INTO public.user_roles
  SELECT * FROM _reset_admin_user_roles;

  RAISE NOTICE 'Reset completed for all public tables except admin identity rows.';
END $$;

-- Verification: these checks abort the transaction if the exception was not
-- respected. Review the NOTICE output in the Supabase SQL Editor.
DO $$
DECLARE
  v_admin_count bigint;
  v_auth_count bigint;
  v_profile_count bigint;
  v_role_count bigint;
  v_storage_count bigint;
BEGIN
  SELECT count(*) INTO v_admin_count
  FROM auth.users
  WHERE lower(email) = lower('bopan86@gmail.com');

  SELECT count(*) INTO v_auth_count FROM auth.users;
  SELECT count(*) INTO v_profile_count FROM public.profiles;
  SELECT count(*) INTO v_role_count FROM public.user_roles;
  IF v_admin_count <> 1 THEN
    RAISE EXCEPTION 'Verification failed: expected exactly one admin account, found %', v_admin_count;
  END IF;

  IF v_auth_count <> 1 THEN
    RAISE EXCEPTION 'Verification failed: expected exactly one Auth user, found %', v_auth_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.user_id
    WHERE lower(u.email) <> lower('bopan86@gmail.com')
  ) THEN
    RAISE EXCEPTION 'Verification failed: a non-admin profile remains';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_roles r
    JOIN auth.users u ON u.id = r.user_id
    WHERE lower(u.email) <> lower('bopan86@gmail.com')
  ) THEN
    RAISE EXCEPTION 'Verification failed: a non-admin role remains';
  END IF;

  RAISE NOTICE 'Verified: auth_users=%, admin=%, profiles=%, admin_roles=%',
    v_auth_count, v_admin_count, v_profile_count, v_role_count;
END $$;

COMMIT;

-- Expected result after COMMIT:
--   auth.users: exactly bopan86@gmail.com
--   public.profiles / public.user_roles: only rows belonging to that admin
--   storage.objects: unchanged; clear files separately via Storage API/Dashboard
--   all other public tables: empty
--   schema, migrations, functions, policies, and storage buckets: preserved
