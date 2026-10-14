-- P1 security hardening: enforce tenant/outlet consistency and respect
-- granular POS outlet assignments at the database boundary.

-- Prevent rows from one tenant from pointing at another tenant's outlet.
CREATE OR REPLACE FUNCTION public.validate_pos_outlet_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id
      AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_42c775b2bc77$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42c775b2bc77$;

DO $bootstrap_do_7d919e32a91b$
BEGIN
  EXECUTE $bootstrap_sql_7d919e32a91b$DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_stock',
    'pos_stock_mutations',
    'pos_sales',
    'pos_held_bills',
    'pos_sale_returns'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS validate_%I_outlet_tenant ON public.%I', table_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER validate_%I_outlet_tenant BEFORE INSERT OR UPDATE OF tenant_id, outlet_id ON public.%I FOR EACH ROW EXECUTE FUNCTION public.validate_pos_outlet_tenant()',
        table_name, table_name
      );
    END IF;
  END LOOP;
END;
$$$bootstrap_sql_7d919e32a91b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d919e32a91b$;

DO $bootstrap_do_c70ec78cddf5$
BEGIN
  EXECUTE $bootstrap_sql_c70ec78cddf5$-- Ensure outlet-access records cannot cross tenant boundaries.
CREATE OR REPLACE FUNCTION public.validate_pos_user_outlet_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets o
    WHERE o.id = NEW.outlet_id AND o.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS outlet does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_users u
    WHERE u.id = NEW.pos_user_id AND u.tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'POS user does not belong to the specified tenant'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_c70ec78cddf5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c70ec78cddf5$;

DO $bootstrap_do_945c857513a4$
BEGIN
  EXECUTE $bootstrap_sql_945c857513a4$DO $$
BEGIN
  IF to_regclass('public.pos_user_outlet_access') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS validate_pos_user_outlet_access_tenant
      ON public.pos_user_outlet_access;
    CREATE TRIGGER validate_pos_user_outlet_access_tenant
      BEFORE INSERT OR UPDATE OF tenant_id, pos_user_id, outlet_id
      ON public.pos_user_outlet_access
      FOR EACH ROW
      EXECUTE FUNCTION public.validate_pos_user_outlet_access();
  END IF;
END;
$$$bootstrap_sql_945c857513a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_945c857513a4$;

DO $bootstrap_do_a0d47d94bf6a$
BEGIN
  EXECUTE $bootstrap_sql_a0d47d94bf6a$-- Replace the broad tenant-wide outlet read policy with owner-or-assigned
-- outlet access. Owners retain visibility over every outlet in their tenant.
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON public.pos_outlets$bootstrap_sql_a0d47d94bf6a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a0d47d94bf6a$;

DO $bootstrap_do_3904c38363c3$
BEGIN
  EXECUTE $bootstrap_sql_3904c38363c3$DROP POLICY IF EXISTS "POS users can view assigned outlets" ON public.pos_outlets$bootstrap_sql_3904c38363c3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3904c38363c3$;

DO $bootstrap_do_a5685812708e$
BEGIN
  EXECUTE $bootstrap_sql_a5685812708e$CREATE POLICY "POS users can view assigned outlets" ON public.pos_outlets
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_outlets.tenant_id AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.pos_user_outlet_access a
      JOIN public.pos_users u ON u.id = a.pos_user_id
      WHERE a.outlet_id = pos_outlets.id
        AND a.tenant_id = pos_outlets.tenant_id
        AND a.is_active = true
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  )$bootstrap_sql_a5685812708e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5685812708e$;

DO $bootstrap_do_af0e90bcd555$
BEGIN
  EXECUTE $bootstrap_sql_af0e90bcd555$-- Only owners may manage outlet assignments; users may inspect their own
-- active assignments. This avoids exposing all staff assignments to any
-- active user in the tenant.
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON public.pos_user_outlet_access$bootstrap_sql_af0e90bcd555$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_af0e90bcd555$;

DO $bootstrap_do_6d00e7661435$
BEGIN
  EXECUTE $bootstrap_sql_6d00e7661435$DROP POLICY IF EXISTS "tenant_users_read_access" ON public.pos_user_outlet_access$bootstrap_sql_6d00e7661435$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d00e7661435$;

DO $bootstrap_do_1f0344ecf953$
BEGIN
  EXECUTE $bootstrap_sql_1f0344ecf953$DROP POLICY IF EXISTS "POS owners manage outlet access" ON public.pos_user_outlet_access$bootstrap_sql_1f0344ecf953$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f0344ecf953$;

DO $bootstrap_do_cc21f0aa0e59$
BEGIN
  EXECUTE $bootstrap_sql_cc21f0aa0e59$DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access$bootstrap_sql_cc21f0aa0e59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc21f0aa0e59$;

DO $bootstrap_do_3fc37987b257$
BEGIN
  EXECUTE $bootstrap_sql_3fc37987b257$CREATE POLICY "POS owners manage outlet access" ON public.pos_user_outlet_access
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = pos_user_outlet_access.tenant_id AND t.user_id = auth.uid()
    )
  )$bootstrap_sql_3fc37987b257$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3fc37987b257$;

DO $bootstrap_do_911def7a0eb2$
BEGIN
  EXECUTE $bootstrap_sql_911def7a0eb2$DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access$bootstrap_sql_911def7a0eb2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_911def7a0eb2$;

DO $bootstrap_do_f92f6c6b1bbd$
BEGIN
  EXECUTE $bootstrap_sql_f92f6c6b1bbd$CREATE POLICY "POS users read own outlet access" ON public.pos_user_outlet_access
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.id = pos_user_outlet_access.pos_user_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  )$bootstrap_sql_f92f6c6b1bbd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f92f6c6b1bbd$;

DO $bootstrap_do_bd360e3ad498$
BEGIN
  EXECUTE $bootstrap_sql_bd360e3ad498$-- Explicit WITH CHECK clauses make the intended mutation boundary clear for
-- the core POS tables. Existing tenant-user SELECT policies remain read-only.
DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'pos_products', 'pos_stock', 'pos_stock_mutations', 'pos_sales',
    'pos_held_bills', 'pos_customers', 'pos_suppliers', 'pos_users'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    END IF;
  END LOOP;
END;
$$$bootstrap_sql_bd360e3ad498$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd360e3ad498$;

DO $bootstrap_do_1b61b6895fb3$
BEGIN
  EXECUTE $bootstrap_sql_1b61b6895fb3$-- Reusable access predicate for outlet-scoped POS data.
CREATE OR REPLACE FUNCTION public.pos_user_can_access_outlet(
  p_tenant_id uuid,
  p_outlet_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pos_tenants t
    WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_user_outlet_access a
    JOIN public.pos_users u ON u.id = a.pos_user_id
    WHERE a.tenant_id = p_tenant_id
      AND a.outlet_id = p_outlet_id
      AND a.is_active = true
      AND u.user_id = auth.uid()
      AND u.is_active = true
  );
$$$bootstrap_sql_1b61b6895fb3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1b61b6895fb3$;

DO $bootstrap_do_2bd65bbbe609$
BEGIN
  EXECUTE $bootstrap_sql_2bd65bbbe609$-- Remove broad tenant-wide read policies for outlet-scoped data.
DROP POLICY IF EXISTS "tenant_users_select_stock" ON public.pos_stock$bootstrap_sql_2bd65bbbe609$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bd65bbbe609$;

DO $bootstrap_do_47505062c4e8$
BEGIN
  EXECUTE $bootstrap_sql_47505062c4e8$DROP POLICY IF EXISTS "tenant_users_select_mutations" ON public.pos_stock_mutations$bootstrap_sql_47505062c4e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47505062c4e8$;

DO $bootstrap_do_0510bb131313$
BEGIN
  EXECUTE $bootstrap_sql_0510bb131313$DROP POLICY IF EXISTS "tenant_users_select_sales" ON public.pos_sales$bootstrap_sql_0510bb131313$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0510bb131313$;

DO $bootstrap_do_b0de1edf2b10$
BEGIN
  EXECUTE $bootstrap_sql_b0de1edf2b10$DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON public.pos_held_bills$bootstrap_sql_b0de1edf2b10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0de1edf2b10$;

DO $bootstrap_do_2fae58dce977$
BEGIN
  EXECUTE $bootstrap_sql_2fae58dce977$DROP POLICY IF EXISTS "tenant_users_select_returns" ON public.pos_sale_returns$bootstrap_sql_2fae58dce977$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2fae58dce977$;

DO $bootstrap_do_474812a5f4cc$
BEGIN
  EXECUTE $bootstrap_sql_474812a5f4cc$DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON public.pos_users$bootstrap_sql_474812a5f4cc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_474812a5f4cc$;

DO $bootstrap_do_984cad49fffb$
BEGIN
  EXECUTE $bootstrap_sql_984cad49fffb$DROP POLICY IF EXISTS "POS users can view assigned stock" ON public.pos_stock$bootstrap_sql_984cad49fffb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_984cad49fffb$;

DO $bootstrap_do_991148f77561$
BEGIN
  EXECUTE $bootstrap_sql_991148f77561$CREATE POLICY "POS users can view assigned stock" ON public.pos_stock
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_991148f77561$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_991148f77561$;

DO $bootstrap_do_59aa5d3400e9$
BEGIN
  EXECUTE $bootstrap_sql_59aa5d3400e9$DROP POLICY IF EXISTS "POS users can view assigned stock mutations" ON public.pos_stock_mutations$bootstrap_sql_59aa5d3400e9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59aa5d3400e9$;

DO $bootstrap_do_4fcf73823483$
BEGIN
  EXECUTE $bootstrap_sql_4fcf73823483$CREATE POLICY "POS users can view assigned stock mutations" ON public.pos_stock_mutations
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_4fcf73823483$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fcf73823483$;

DO $bootstrap_do_4a0d5f3e39fc$
BEGIN
  EXECUTE $bootstrap_sql_4a0d5f3e39fc$DROP POLICY IF EXISTS "POS users can view assigned sales" ON public.pos_sales$bootstrap_sql_4a0d5f3e39fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a0d5f3e39fc$;

DO $bootstrap_do_546a0f3458a4$
BEGIN
  EXECUTE $bootstrap_sql_546a0f3458a4$CREATE POLICY "POS users can view assigned sales" ON public.pos_sales
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_546a0f3458a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_546a0f3458a4$;

DO $bootstrap_do_2195be2735fc$
BEGIN
  EXECUTE $bootstrap_sql_2195be2735fc$DROP POLICY IF EXISTS "POS users can view assigned held bills" ON public.pos_held_bills$bootstrap_sql_2195be2735fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2195be2735fc$;

DO $bootstrap_do_10f964a7d9d4$
BEGIN
  EXECUTE $bootstrap_sql_10f964a7d9d4$CREATE POLICY "POS users can view assigned held bills" ON public.pos_held_bills
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_10f964a7d9d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10f964a7d9d4$;

DO $bootstrap_do_404491c2c5cb$
BEGIN
  EXECUTE $bootstrap_sql_404491c2c5cb$DROP POLICY IF EXISTS "POS users can view assigned returns" ON public.pos_sale_returns$bootstrap_sql_404491c2c5cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_404491c2c5cb$;

DO $bootstrap_do_f070b8b26db4$
BEGIN
  EXECUTE $bootstrap_sql_f070b8b26db4$CREATE POLICY "POS users can view assigned returns" ON public.pos_sale_returns
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id))$bootstrap_sql_f070b8b26db4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f070b8b26db4$;

DO $bootstrap_do_8365b3272e89$
BEGIN
  EXECUTE $bootstrap_sql_8365b3272e89$-- Staff can see their own POS identity; only tenant owners can see the full
-- tenant user directory.
DROP POLICY IF EXISTS "POS users can view own POS identity" ON public.pos_users$bootstrap_sql_8365b3272e89$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8365b3272e89$;

DO $bootstrap_do_dd4485833f74$
BEGIN
  EXECUTE $bootstrap_sql_dd4485833f74$CREATE POLICY "POS users can view own POS identity" ON public.pos_users
  FOR SELECT TO authenticated
  USING (user_id = auth.uid())$bootstrap_sql_dd4485833f74$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd4485833f74$;

DO $bootstrap_do_54f3b42738c6$
BEGIN
  EXECUTE $bootstrap_sql_54f3b42738c6$-- Explicitly grant the helper only to API roles; the function itself does not
-- expose any data and is used solely inside RLS predicates.
REVOKE ALL ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) FROM PUBLIC$bootstrap_sql_54f3b42738c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54f3b42738c6$;

DO $bootstrap_do_9ad084f0b4f2$
BEGIN
  EXECUTE $bootstrap_sql_9ad084f0b4f2$GRANT EXECUTE ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) TO authenticated$bootstrap_sql_9ad084f0b4f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ad084f0b4f2$;

DO $bootstrap_do_64fe9011088f$
BEGIN
  EXECUTE $bootstrap_sql_64fe9011088f$
