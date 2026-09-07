-- POS outlet stock is the operational source of truth for linked products.
-- products.stock is the marketplace projection of available POS stock across
-- active outlets: quantity minus POS reservations.

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_internal(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_mapping record;
  v_available numeric;
  v_projected_stock integer;
  v_processed integer := 0;
  v_updated integer := 0;
BEGIN
  SELECT *
  INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id;

  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'tenant_id', p_tenant_id,
      'processed', 0,
      'updated', 0,
      'status', 'unmapped'
    );
  END IF;

  FOR v_mapping IN
    SELECT
      pp.id AS pos_product_id,
      COALESCE(ms.marketplace_product_id, pp.merchant_product_id) AS marketplace_product_id,
      ms.id AS sync_id
    FROM public.pos_products pp
    LEFT JOIN public.pos_marketplace_sync ms
      ON ms.tenant_id = pp.tenant_id
      AND ms.pos_product_id = pp.id
    JOIN public.products marketplace_product
      ON marketplace_product.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
      AND marketplace_product.merchant_id = v_tenant.merchant_id
    WHERE pp.tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pp.id = p_pos_product_id)
      AND (ms.id IS NULL OR (ms.sync_stock = true AND ms.sync_status = 'synced'))
  LOOP
    v_processed := v_processed + 1;

    SELECT COALESCE(SUM(
      GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)
    ), 0)
    INTO v_available
    FROM public.pos_stock ps
    JOIN public.pos_outlets po
      ON po.id = ps.outlet_id
      AND po.tenant_id = ps.tenant_id
      AND po.is_active = true
    WHERE ps.tenant_id = p_tenant_id
      AND ps.product_id = v_mapping.pos_product_id
      AND ps.variant_id IS NULL;

    -- products.stock is integer-based while POS supports fractional units.
    -- Round only at the marketplace boundary; POS retains exact quantities.
    v_projected_stock := GREATEST(0, ROUND(v_available))::integer;

    UPDATE public.products
    SET stock = v_projected_stock,
        updated_at = now()
    WHERE id = v_mapping.marketplace_product_id
      AND merchant_id = v_tenant.merchant_id
      AND stock IS DISTINCT FROM v_projected_stock;

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;

    IF v_mapping.sync_id IS NOT NULL THEN
      UPDATE public.pos_marketplace_sync
      SET last_synced_at = now(),
          sync_status = 'synced',
          error_message = NULL,
          updated_at = now()
      WHERE id = v_mapping.sync_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'processed', v_processed,
    'updated', v_updated,
    'status', 'success'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.pos_tenants t
      WHERE t.id = p_tenant_id
        AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.pos_users u
      WHERE u.tenant_id = p_tenant_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock synchronization access denied'
      USING ERRCODE = '42501';
  END IF;

  RETURN public.sync_pos_stock_to_marketplace_internal(p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
  v_product_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;
BEGIN
  PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant_id, v_product_id);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_stock_to_marketplace ON public.pos_stock;
CREATE TRIGGER trg_sync_pos_stock_to_marketplace
AFTER INSERT OR UPDATE OF quantity, reserved_quantity, product_id, tenant_id, outlet_id OR DELETE
ON public.pos_stock
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_stock_to_marketplace_after_change();

REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_after_change() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) TO authenticated;

DO $$
DECLARE
  v_tenant_id uuid;
BEGIN
  FOR v_tenant_id IN
    SELECT id FROM public.pos_tenants WHERE is_active = true
  LOOP
    PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant_id);
  END LOOP;
END;
$$;