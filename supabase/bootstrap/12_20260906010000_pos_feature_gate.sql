-- POS feature gate.
-- POS status belongs to the merchant-owned tenant and is enforced for
-- operational mutations. The legacy is_active column remains for compatibility.

ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS business_type text,
  ADD COLUMN IF NOT EXISTS enabled_modules jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS trial_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS activated_at timestamptz,
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz;

UPDATE public.pos_tenants
SET status = CASE WHEN is_active THEN 'active' ELSE 'inactive' END
WHERE status IS NULL OR status NOT IN ('inactive', 'setup_required', 'trial', 'active', 'suspended', 'cancelled');

ALTER TABLE public.pos_tenants
  DROP CONSTRAINT IF EXISTS pos_tenants_status_check;

ALTER TABLE public.pos_tenants
  ADD CONSTRAINT pos_tenants_status_check
  CHECK (status IN ('inactive', 'setup_required', 'trial', 'active', 'suspended', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_pos_tenants_status
  ON public.pos_tenants(status);

CREATE OR REPLACE FUNCTION public.is_pos_tenant_active(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants
    WHERE id = p_tenant_id
      AND is_active = true
      AND status IN ('trial', 'active')
  );
$$;

REVOKE ALL ON FUNCTION public.is_pos_tenant_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pos_tenant_active(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_active_pos_tenant_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;

  IF NOT public.is_pos_tenant_active(v_tenant_id) THEN
    RAISE EXCEPTION 'POS is not active for this merchant'
      USING ERRCODE = '42501';
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_active_pos_tenant_mutation() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_table record;
BEGIN
  FOR v_table IN
    SELECT DISTINCT c.table_schema, c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND c.table_name LIKE 'pos_%'
      AND c.table_name <> 'pos_tenants'
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS enforce_active_pos_tenant_mutation ON %I.%I',
      v_table.table_schema, v_table.table_name
    );
    EXECUTE format(
      'CREATE TRIGGER enforce_active_pos_tenant_mutation
       BEFORE INSERT OR UPDATE OR DELETE ON %I.%I
       FOR EACH ROW EXECUTE FUNCTION public.enforce_active_pos_tenant_mutation()',
      v_table.table_schema, v_table.table_name
    );
  END LOOP;
END;
$$;

-- POS transactions/settings use merchant_id instead of tenant_id. Keep
-- subscription requests available before activation, but protect operational
-- transaction and settings mutations once a tenant is suspended/cancelled.
DROP POLICY IF EXISTS "Merchants can manage own POS transactions" ON public.pos_transactions;
CREATE POLICY "Merchants can manage own active POS transactions"
  ON public.pos_transactions FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_transactions.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_transactions.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  );

DROP POLICY IF EXISTS "Merchants can manage own POS settings" ON public.pos_settings;
CREATE POLICY "Merchants can manage own active POS settings"
  ON public.pos_settings FOR ALL
  USING (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_settings.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.merchants m
      JOIN public.pos_tenants t ON t.merchant_id = m.id
      WHERE m.id = pos_settings.merchant_id
        AND m.user_id = auth.uid()
        AND public.is_pos_tenant_active(t.id)
    )
  );

CREATE OR REPLACE FUNCTION public.activate_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL,
  p_business_type text DEFAULT 'simple',
  p_enabled_modules jsonb DEFAULT '["cashier"]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_tenant_id uuid;
BEGIN
  v_result := public.ensure_merchant_pos_workspace(
    p_name, p_phone, p_address, p_timezone, p_currency,
    p_outlet_name, p_outlet_address, p_outlet_phone
  );
  v_tenant_id := (v_result->'tenant'->>'id')::uuid;

  UPDATE public.pos_tenants
  SET status = 'active',
      business_type = NULLIF(trim(p_business_type), ''),
      enabled_modules = CASE
        WHEN jsonb_typeof(p_enabled_modules) = 'array' THEN p_enabled_modules
        ELSE '["cashier"]'::jsonb
      END,
      activated_at = COALESCE(activated_at, now()),
      updated_at = now()
  WHERE id = v_tenant_id;

  RETURN v_result || jsonb_build_object(
    'status', 'active',
    'business_type', NULLIF(trim(p_business_type), ''),
    'enabled_modules', p_enabled_modules
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_merchant_pos_workspace(text, text, text, text, text, text, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_merchant_pos_workspace(text, text, text, text, text, text, text, text, text, jsonb) TO authenticated;