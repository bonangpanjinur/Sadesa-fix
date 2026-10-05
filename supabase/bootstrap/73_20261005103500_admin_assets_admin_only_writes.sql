-- Scope admin-assets writes to global admins. The public read policy remains
-- unchanged so storefront images stay publicly accessible.
DO $bootstrap_do_admin_assets_admin_only_writes$
BEGIN
  EXECUTE $bootstrap_sql_drop_legacy_admin_assets_insert$
    DROP POLICY IF EXISTS "Authenticated users can upload admin assets" ON storage.objects
  $bootstrap_sql_drop_legacy_admin_assets_insert$;

  EXECUTE $bootstrap_sql_drop_legacy_admin_assets_delete$
    DROP POLICY IF EXISTS "Authenticated users can delete admin assets" ON storage.objects
  $bootstrap_sql_drop_legacy_admin_assets_delete$;

  EXECUTE $bootstrap_sql_drop_admin_assets_insert$
    DROP POLICY IF EXISTS "Admins can upload admin assets" ON storage.objects
  $bootstrap_sql_drop_admin_assets_insert$;
  EXECUTE $bootstrap_sql_create_admin_assets_insert$
    CREATE POLICY "Admins can upload admin assets"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'admin-assets' AND public.is_admin())
  $bootstrap_sql_create_admin_assets_insert$;

  EXECUTE $bootstrap_sql_drop_admin_assets_update$
    DROP POLICY IF EXISTS "Admins can update admin assets" ON storage.objects
  $bootstrap_sql_drop_admin_assets_update$;
  EXECUTE $bootstrap_sql_create_admin_assets_update$
    CREATE POLICY "Admins can update admin assets"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'admin-assets' AND public.is_admin())
    WITH CHECK (bucket_id = 'admin-assets' AND public.is_admin())
  $bootstrap_sql_create_admin_assets_update$;

  EXECUTE $bootstrap_sql_drop_admin_assets_delete$
    DROP POLICY IF EXISTS "Admins can delete admin assets" ON storage.objects
  $bootstrap_sql_drop_admin_assets_delete$;
  EXECUTE $bootstrap_sql_create_admin_assets_delete$
    CREATE POLICY "Admins can delete admin assets"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'admin-assets' AND public.is_admin())
  $bootstrap_sql_create_admin_assets_delete$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END;
$bootstrap_do_admin_assets_admin_only_writes$;
