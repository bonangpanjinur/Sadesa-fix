-- Merchant catalog integration for POS with per-outlet operational stock.
-- Merchant products are the source of truth; pos_products is a compatibility projection
-- because existing POS sales and stock tables reference pos_products IDs.

ALTER TABLE public.pos_tenants
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_tenants_merchant_id
  ON public.pos_tenants(merchant_id)
  WHERE merchant_id IS NOT NULL;

UPDATE public.pos_tenants t
SET merchant_id = m.id
FROM public.merchants m
WHERE t.merchant_id IS NULL
  AND m.user_id = t.user_id;

ALTER TABLE public.pos_products
  ADD COLUMN IF NOT EXISTS merchant_product_id uuid REFERENCES public.products(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_merchant_product
  ON public.pos_products(tenant_id, merchant_product_id)
  WHERE merchant_product_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_to_pos(p_product_id uuid, p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product public.products%ROWTYPE;
  v_pos_product_id uuid;
BEGIN
  SELECT * INTO v_product
  FROM public.products
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_pos_product_id
  FROM public.pos_products
  WHERE tenant_id = p_tenant_id
    AND merchant_product_id = p_product_id
  LIMIT 1;

  IF v_pos_product_id IS NULL THEN
    INSERT INTO public.pos_products (
      tenant_id, merchant_product_id, name, price, image_url, description, is_active,
      is_stock_tracked, has_variants, unit, cost_price, tax_rate
    ) VALUES (
      p_tenant_id, v_product.id, v_product.name, v_product.price, v_product.image_url,
      v_product.description, v_product.is_active, true, false, 'pcs', 0, 0
    ) RETURNING id INTO v_pos_product_id;
  ELSE
    UPDATE public.pos_products
    SET name = v_product.name,
        price = v_product.price,
        image_url = v_product.image_url,
        description = v_product.description,
        is_active = v_product.is_active,
        updated_at = now()
    WHERE id = v_pos_product_id;
  END IF;

  RETURN v_pos_product_id;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_product_to_pos(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.ensure_pos_stock_rows_for_product(p_product_id uuid, p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_outlet public.pos_outlets%ROWTYPE;
BEGIN
  -- A failed or deleted projection must never result in an invalid
  -- pos_stock row with a NULL product_id.
  IF p_product_id IS NULL THEN
    RETURN;
  END IF;

  FOR v_outlet IN
    SELECT *
    FROM public.pos_outlets
    WHERE tenant_id = p_tenant_id
      AND is_active = true
  LOOP
    -- Existing quantity and min_stock are operational data and must never be overwritten.
    INSERT INTO public.pos_stock (tenant_id, product_id, outlet_id, quantity, min_stock)
    VALUES (p_tenant_id, p_product_id, v_outlet.id, 0, 0)
    ON CONFLICT (product_id, variant_id, outlet_id) DO NOTHING;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_pos_stock_rows_for_product(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_to_pos_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT * FROM public.pos_tenants WHERE merchant_id = NEW.merchant_id AND is_active = true
  LOOP
    PERFORM public.sync_merchant_product_to_pos(NEW.id, v_tenant.id);
    PERFORM public.ensure_pos_stock_rows_for_product(
      (SELECT id FROM public.pos_products WHERE tenant_id = v_tenant.id AND merchant_product_id = NEW.id LIMIT 1),
      v_tenant.id
    );
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_to_pos ON public.products;
CREATE TRIGGER trg_sync_merchant_product_to_pos
AFTER INSERT OR UPDATE OF name, price, image_url, description, is_active, merchant_id
ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.sync_merchant_product_to_pos_trigger();

-- Backfill existing Merchant products into every linked POS tenant.
DO $$
DECLARE
  v_product public.products%ROWTYPE;
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_product IN SELECT * FROM public.products LOOP
    FOR v_tenant IN
      SELECT * FROM public.pos_tenants
      WHERE merchant_id = v_product.merchant_id AND is_active = true
    LOOP
      PERFORM public.sync_merchant_product_to_pos(v_product.id, v_tenant.id);
      PERFORM public.ensure_pos_stock_rows_for_product(
        (SELECT id FROM public.pos_products WHERE tenant_id = v_tenant.id AND merchant_product_id = v_product.id LIMIT 1),
        v_tenant.id
      );
    END LOOP;
  END LOOP;
END;
$$;

COMMENT ON COLUMN public.pos_tenants.merchant_id IS 'Canonical Merchant owner for the POS tenant.';
COMMENT ON COLUMN public.pos_products.merchant_product_id IS 'Source product in Merchant catalog; POS stock remains per outlet in pos_stock.';
