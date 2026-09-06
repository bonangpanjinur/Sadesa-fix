-- Merchant-POS control plane.
-- Merchant is the canonical business identity and product catalog.
-- POS keeps only its operational projection and outlet-level stock.

CREATE OR REPLACE FUNCTION public.sync_pos_tenant_catalog(p_tenant_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_count integer := 0;
  v_pos_product_id uuid;
BEGIN
  SELECT * INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN 0;
  END IF;

  FOR v_product IN
    SELECT *
    FROM public.products
    WHERE merchant_id = v_tenant.merchant_id
  LOOP
    v_pos_product_id := public.sync_merchant_product_to_pos(v_product.id, p_tenant_id);
    PERFORM public.ensure_pos_stock_rows_for_product(v_pos_product_id, p_tenant_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_pos_tenant_catalog(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_pos_tenant_catalog_after_mapping()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.merchant_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.merchant_id IS DISTINCT FROM NEW.merchant_id) THEN
    PERFORM public.sync_pos_tenant_catalog(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_tenant_catalog_after_mapping ON public.pos_tenants;
CREATE TRIGGER trg_sync_pos_tenant_catalog_after_mapping
AFTER INSERT OR UPDATE OF merchant_id ON public.pos_tenants
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_tenant_catalog_after_mapping();

CREATE OR REPLACE FUNCTION public.ensure_merchant_pos_workspace(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_timezone text DEFAULT 'Asia/Jakarta',
  p_currency text DEFAULT 'IDR',
  p_outlet_name text DEFAULT NULL,
  p_outlet_address text DEFAULT NULL,
  p_outlet_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_merchant_id uuid;
  v_tenant public.pos_tenants%ROWTYPE;
  v_outlet public.pos_outlets%ROWTYPE;
  v_source_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.id
  INTO v_merchant_id
  FROM public.merchants m
  WHERE m.user_id = v_user_id
  ORDER BY (m.registration_status = 'APPROVED') DESC, m.updated_at DESC NULLS LAST, m.created_at DESC
  LIMIT 1;

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant profile is required before enabling POS' USING ERRCODE = '23503';
  END IF;

  INSERT INTO public.pos_tenants (
    user_id, name, phone, address, timezone, currency, merchant_id, is_active
  )
  VALUES (
    v_user_id,
    NULLIF(trim(p_name), ''),
    NULLIF(trim(p_phone), ''),
    NULLIF(trim(p_address), ''),
    COALESCE(NULLIF(trim(p_timezone), ''), 'Asia/Jakarta'),
    COALESCE(NULLIF(trim(p_currency), ''), 'IDR'),
    v_merchant_id,
    true
  )
  ON CONFLICT (user_id) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.pos_tenants.name),
    phone = COALESCE(EXCLUDED.phone, public.pos_tenants.phone),
    address = COALESCE(EXCLUDED.address, public.pos_tenants.address),
    timezone = COALESCE(EXCLUDED.timezone, public.pos_tenants.timezone),
    currency = COALESCE(EXCLUDED.currency, public.pos_tenants.currency),
    merchant_id = COALESCE(public.pos_tenants.merchant_id, EXCLUDED.merchant_id),
    is_active = true,
    updated_at = now()
  RETURNING * INTO v_tenant;

  IF v_tenant.merchant_id IS NULL THEN
    RAISE EXCEPTION 'POS tenant is not mapped to a merchant' USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO v_outlet
  FROM public.pos_outlets
  WHERE tenant_id = v_tenant.id AND is_active = true
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.pos_outlets (tenant_id, name, address, phone, is_active)
    VALUES (
      v_tenant.id,
      COALESCE(NULLIF(trim(p_outlet_name), ''), v_tenant.name || ' - Outlet Utama'),
      NULLIF(trim(COALESCE(p_outlet_address, p_address)), ''),
      NULLIF(trim(COALESCE(p_outlet_phone, p_phone)), ''),
      true
    )
    RETURNING * INTO v_outlet;
  END IF;

  v_source_count := public.sync_pos_tenant_catalog(v_tenant.id);

  RETURN jsonb_build_object(
    'tenant', to_jsonb(v_tenant),
    'outlet', to_jsonb(v_outlet),
    'merchant_id', v_tenant.merchant_id,
    'source_products_synced', v_source_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_merchant_pos_workspace(text, text, text, text, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pos_integration_health()
RETURNS TABLE (
  tenant_id uuid,
  tenant_name text,
  merchant_id uuid,
  merchant_name text,
  owner_user_id uuid,
  outlet_count bigint,
  source_product_count bigint,
  linked_product_count bigint,
  unlinked_pos_product_count bigint,
  sync_gap_count bigint,
  status text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.name,
    t.merchant_id,
    m.name,
    t.user_id,
    (SELECT count(*) FROM public.pos_outlets o WHERE o.tenant_id = t.id AND o.is_active),
    (SELECT count(*) FROM public.products p WHERE p.merchant_id = t.merchant_id),
    (SELECT count(*) FROM public.pos_products pp WHERE pp.tenant_id = t.id AND pp.merchant_product_id IS NOT NULL),
    (SELECT count(*) FROM public.pos_products pp WHERE pp.tenant_id = t.id AND pp.merchant_product_id IS NULL),
    CASE
      WHEN t.merchant_id IS NULL THEN NULL::bigint
      ELSE (
        SELECT count(*)
        FROM public.products p
        WHERE p.merchant_id = t.merchant_id
          AND NOT EXISTS (
            SELECT 1
            FROM public.pos_products pp
            WHERE pp.tenant_id = t.id
              AND pp.merchant_product_id = p.id
          )
      )
    END,
    CASE
      WHEN t.merchant_id IS NULL THEN 'NEEDS_MAPPING'
      WHEN EXISTS (
        SELECT 1
        FROM public.products p
        WHERE p.merchant_id = t.merchant_id
          AND NOT EXISTS (
            SELECT 1 FROM public.pos_products pp
            WHERE pp.tenant_id = t.id AND pp.merchant_product_id = p.id
          )
      ) THEN 'NEEDS_SYNC'
      WHEN NOT EXISTS (
        SELECT 1 FROM public.pos_outlets o
        WHERE o.tenant_id = t.id AND o.is_active
      ) THEN 'NEEDS_OUTLET'
      ELSE 'READY'
    END
  FROM public.pos_tenants t
  LEFT JOIN public.merchants m ON m.id = t.merchant_id
  WHERE public.is_admin()
  ORDER BY t.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.get_pos_integration_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pos_integration_health() TO authenticated;