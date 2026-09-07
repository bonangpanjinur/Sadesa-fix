-- Phase 2: enforce tenant-scoped catalog identities and detect stale projections.
--
-- SKU/barcode are operational identities, not display labels. They must be
-- unique within a tenant across both parent products and their variants.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.pos_products
    WHERE NULLIF(BTRIM(sku), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(sku))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_product_variants
    WHERE NULLIF(BTRIM(sku), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(sku))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_products p
    JOIN public.pos_product_variants v
      ON v.tenant_id = p.tenant_id
     AND LOWER(BTRIM(v.sku)) = LOWER(BTRIM(p.sku))
    WHERE NULLIF(BTRIM(p.sku), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Duplicate SKU values exist within a POS tenant; clean them before applying catalog identity constraints';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pos_products
    WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(barcode))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_product_variants
    WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(barcode))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_products p
    JOIN public.pos_product_variants v
      ON v.tenant_id = p.tenant_id
     AND LOWER(BTRIM(v.barcode)) = LOWER(BTRIM(p.barcode))
    WHERE NULLIF(BTRIM(p.barcode), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Duplicate barcode values exist within a POS tenant; clean them before applying catalog identity constraints';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_tenant_sku_unique
  ON public.pos_products (tenant_id, LOWER(BTRIM(sku)))
  WHERE NULLIF(BTRIM(sku), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_product_variants_tenant_sku_unique
  ON public.pos_product_variants (tenant_id, LOWER(BTRIM(sku)))
  WHERE NULLIF(BTRIM(sku), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_tenant_barcode_unique
  ON public.pos_products (tenant_id, LOWER(BTRIM(barcode)))
  WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_product_variants_tenant_barcode_unique
  ON public.pos_product_variants (tenant_id, LOWER(BTRIM(barcode)))
  WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.validate_pos_catalog_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := NULLIF(LOWER(BTRIM(NEW.sku)), '');
  v_barcode text := NULLIF(LOWER(BTRIM(NEW.barcode)), '');
BEGIN
  IF TG_TABLE_NAME = 'pos_products' THEN
    IF v_sku IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(sku)) = v_sku
    ) THEN
      RAISE EXCEPTION 'SKU sudah digunakan oleh varian lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
    IF v_barcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(barcode)) = v_barcode
    ) THEN
      RAISE EXCEPTION 'Barcode sudah digunakan oleh varian lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
  ELSE
    IF v_sku IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_products
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(sku)) = v_sku
    ) THEN
      RAISE EXCEPTION 'SKU sudah digunakan oleh produk lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
    IF v_barcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_products
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(barcode)) = v_barcode
    ) THEN
      RAISE EXCEPTION 'Barcode sudah digunakan oleh produk lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_product_identity ON public.pos_products;
CREATE TRIGGER trg_validate_pos_product_identity
BEFORE INSERT OR UPDATE OF tenant_id, sku, barcode ON public.pos_products
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_catalog_identity();

DROP TRIGGER IF EXISTS trg_validate_pos_variant_identity ON public.pos_product_variants;
CREATE TRIGGER trg_validate_pos_variant_identity
BEFORE INSERT OR UPDATE OF tenant_id, sku, barcode ON public.pos_product_variants
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_catalog_identity();

CREATE OR REPLACE FUNCTION public.validate_pos_variant_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian harus berada pada tenant dan produk POS yang sama' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_variant_scope ON public.pos_product_variants;
CREATE TRIGGER trg_validate_pos_variant_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id ON public.pos_product_variants
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_variant_scope();

CREATE OR REPLACE FUNCTION public.validate_pos_stock_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada tenant dan produk POS yang sama' USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada outlet tenant yang sama' USING ERRCODE = '23514';
  END IF;

  IF NEW.variant_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE id = NEW.variant_id
      AND product_id = NEW.product_id
      AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian stok tidak cocok dengan produk dan tenant' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_stock_scope ON public.pos_stock;
CREATE TRIGGER trg_validate_pos_stock_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id, variant_id, outlet_id ON public.pos_stock
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_stock_scope();

CREATE OR REPLACE FUNCTION public.detect_pos_stock_sync_stale(
  p_tenant_id uuid,
  p_stale_after_minutes integer DEFAULT 120
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sync record;
  v_cutoff timestamptz := now() - make_interval(mins => GREATEST(COALESCE(p_stale_after_minutes, 120), 15));
  v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.pos_tenants WHERE id = p_tenant_id AND user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.pos_users
      WHERE tenant_id = p_tenant_id AND user_id = auth.uid() AND is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock stale detection access denied' USING ERRCODE = '42501';
  END IF;

  FOR v_sync IN
    SELECT ms.id, ms.tenant_id, pp.name, ms.last_synced_at
    FROM public.pos_marketplace_sync ms
    JOIN public.pos_products pp ON pp.id = ms.pos_product_id
    WHERE ms.tenant_id = p_tenant_id
      AND ms.sync_stock = true
      AND ms.sync_status = 'synced'
      AND (ms.last_synced_at IS NULL OR ms.last_synced_at < v_cutoff)
  LOOP
    INSERT INTO public.pos_stock_sync_alerts (
      tenant_id, sync_id, alert_code, severity, message, status,
      first_seen_at, last_seen_at, resolved_at
    )
    VALUES (
      v_sync.tenant_id,
      v_sync.id,
      'STOCK_PROJECTION_STALE',
      'warning',
      format('Projection stok "%s" belum diperbarui sejak %s.', v_sync.name,
        COALESCE(to_char(v_sync.last_synced_at AT TIME ZONE 'Asia/Jakarta', 'DD Mon YYYY HH24:MI'), 'belum pernah')),
      'open',
      now(), now(), NULL
    )
    ON CONFLICT (sync_id, alert_code) DO UPDATE
    SET severity = 'warning',
        message = EXCLUDED.message,
        status = 'open',
        last_seen_at = now(),
        resolved_at = NULL;
    v_count := v_count + 1;
  END LOOP;

  UPDATE public.pos_stock_sync_alerts alert
  SET status = 'resolved', resolved_at = now(), last_seen_at = now()
  WHERE alert.tenant_id = p_tenant_id
    AND alert.alert_code = 'STOCK_PROJECTION_STALE'
    AND alert.status = 'open'
    AND NOT EXISTS (
      SELECT 1
      FROM public.pos_marketplace_sync ms
      WHERE ms.id = alert.sync_id
        AND ms.sync_stock = true
        AND ms.sync_status = 'synced'
        AND (ms.last_synced_at IS NULL OR ms.last_synced_at < v_cutoff)
    );

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_pos_catalog_identity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_variant_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_stock_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detect_pos_stock_sync_stale(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_pos_stock_sync_stale(uuid, integer) TO authenticated;