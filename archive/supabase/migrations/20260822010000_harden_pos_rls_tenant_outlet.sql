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
$$;

DO $$
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
$$;

-- Ensure outlet-access records cannot cross tenant boundaries.
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
$$;

DO $$
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
$$;

-- Replace the broad tenant-wide outlet read policy with owner-or-assigned
-- outlet access. Owners retain visibility over every outlet in their tenant.
DROP POLICY IF EXISTS "tenant_users_select_outlets" ON public.pos_outlets;
DROP POLICY IF EXISTS "POS users can view assigned outlets" ON public.pos_outlets;
CREATE POLICY "POS users can view assigned outlets" ON public.pos_outlets
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
  );

-- Only owners may manage outlet assignments; users may inspect their own
-- active assignments. This avoids exposing all staff assignments to any
-- active user in the tenant.
DROP POLICY IF EXISTS "tenant_owner_manage_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "tenant_users_read_access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS owners manage outlet access" ON public.pos_user_outlet_access;
DROP POLICY IF EXISTS "POS users read own outlet access" ON public.pos_user_outlet_access;

CREATE POLICY "POS owners manage outlet access" ON public.pos_user_outlet_access
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
  );

CREATE POLICY "POS users read own outlet access" ON public.pos_user_outlet_access
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.id = pos_user_outlet_access.pos_user_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  );

-- Explicit WITH CHECK clauses make the intended mutation boundary clear for
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
$$;

-- Reusable access predicate for outlet-scoped POS data.
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
$$;

-- Remove broad tenant-wide read policies for outlet-scoped data.
DROP POLICY IF EXISTS "tenant_users_select_stock" ON public.pos_stock;
DROP POLICY IF EXISTS "tenant_users_select_mutations" ON public.pos_stock_mutations;
DROP POLICY IF EXISTS "tenant_users_select_sales" ON public.pos_sales;
DROP POLICY IF EXISTS "tenant_users_select_held_bills" ON public.pos_held_bills;
DROP POLICY IF EXISTS "tenant_users_select_returns" ON public.pos_sale_returns;
DROP POLICY IF EXISTS "tenant_users_select_pos_users" ON public.pos_users;

CREATE POLICY "POS users can view assigned stock" ON public.pos_stock
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE POLICY "POS users can view assigned stock mutations" ON public.pos_stock_mutations
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE POLICY "POS users can view assigned sales" ON public.pos_sales
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE POLICY "POS users can view assigned held bills" ON public.pos_held_bills
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE POLICY "POS users can view assigned returns" ON public.pos_sale_returns
  FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

-- Staff can see their own POS identity; only tenant owners can see the full
-- tenant user directory.
CREATE POLICY "POS users can view own POS identity" ON public.pos_users
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Explicitly grant the helper only to API roles; the function itself does not
-- expose any data and is used solely inside RLS predicates.
REVOKE ALL ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_user_can_access_outlet(uuid, uuid) TO authenticated;
