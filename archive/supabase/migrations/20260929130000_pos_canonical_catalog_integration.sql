-- POS canonical catalog integration for merchants that have an active POS tenant.
-- POS owns operational product fields and outlet stock; marketplace products remain
-- the public projection consumed by the buyer experience.

CREATE OR REPLACE FUNCTION public.sync_pos_product_to_merchant_catalog(p_pos_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pos public.pos_products%ROWTYPE;
BEGIN
  SELECT * INTO v_pos FROM public.pos_products WHERE id = p_pos_product_id;
  IF NOT FOUND OR v_pos.merchant_product_id IS NULL THEN RETURN; END IF;

  PERFORM set_config('app.pos_catalog_projection', 'on', true);
  UPDATE public.products
  SET name = v_pos.name,
      price = GREATEST(0, ROUND(v_pos.price))::integer,
      image_url = v_pos.image_url,
      description = v_pos.description,
      is_active = v_pos.is_active,
      updated_at = now()
  WHERE id = v_pos.merchant_product_id
    AND EXISTS (
      SELECT 1
      FROM public.pos_tenants pt
      WHERE pt.id = v_pos.tenant_id
        AND pt.merchant_id = products.merchant_id
        AND pt.is_active = true
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_product_to_merchant_catalog_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(current_setting('app.merchant_catalog_projection', true), '') <> 'on' THEN
    PERFORM public.sync_pos_product_to_merchant_catalog(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pos_product_to_merchant_catalog ON public.pos_products;
CREATE TRIGGER trg_sync_pos_product_to_merchant_catalog
AFTER UPDATE OF name, price, image_url, description, is_active, merchant_product_id, tenant_id
ON public.pos_products
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_product_to_merchant_catalog_trigger();

-- Restore the stock projection trigger in the current canonical bootstrap. This
-- keeps products.stock and variant stock equal to available POS outlet stock.
DROP TRIGGER IF EXISTS trg_sync_pos_stock_to_marketplace ON public.pos_stock;
CREATE TRIGGER trg_sync_pos_stock_to_marketplace
AFTER INSERT OR UPDATE OF quantity, reserved_quantity, product_id, tenant_id, outlet_id OR DELETE
ON public.pos_stock
FOR EACH ROW
EXECUTE FUNCTION public.sync_pos_stock_to_marketplace_after_change();

-- Any direct marketplace stock edit for an active POS-linked product is invalid.
CREATE OR REPLACE FUNCTION public.prevent_manual_stock_edit_for_pos_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.stock IS DISTINCT FROM OLD.stock
     AND COALESCE(current_setting('app.pos_stock_projection', true), '') <> 'on'
     AND EXISTS (
       SELECT 1
       FROM public.pos_products pp
       JOIN public.pos_tenants pt ON pt.id = pp.tenant_id
       WHERE pp.merchant_product_id = NEW.id
         AND pt.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Stock produk tertaut POS hanya dapat diubah dari stok outlet POS'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_stock_edit_for_pos_product ON public.products;
CREATE TRIGGER trg_prevent_manual_stock_edit_for_pos_product
BEFORE UPDATE OF stock ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.prevent_manual_stock_edit_for_pos_product();

-- POS is the operational source for core catalog fields once linked.
CREATE OR REPLACE FUNCTION public.prevent_manual_core_edit_for_pos_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(current_setting('app.pos_catalog_projection', true), '') <> 'on'
     AND (NEW.name IS DISTINCT FROM OLD.name
       OR NEW.price IS DISTINCT FROM OLD.price
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.image_url IS DISTINCT FROM OLD.image_url
       OR NEW.is_active IS DISTINCT FROM OLD.is_active)
     AND EXISTS (
       SELECT 1 FROM public.pos_products pp
       JOIN public.pos_tenants pt ON pt.id = pp.tenant_id
       WHERE pp.merchant_product_id = NEW.id AND pt.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Produk tertaut POS hanya dapat mengubah nama, harga, deskripsi, gambar, dan status dari POS'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_core_edit_for_pos_product ON public.products;
CREATE TRIGGER trg_prevent_manual_core_edit_for_pos_product
BEFORE UPDATE OF name, price, description, image_url, is_active ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.prevent_manual_core_edit_for_pos_product();

REVOKE ALL ON FUNCTION public.sync_pos_product_to_merchant_catalog(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_product_to_merchant_catalog_trigger() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_manual_stock_edit_for_pos_product() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_manual_core_edit_for_pos_product() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_tenant record;
BEGIN
  FOR v_tenant IN SELECT id FROM public.pos_tenants WHERE is_active = true AND merchant_id IS NOT NULL LOOP
    PERFORM public.sync_pos_stock_to_marketplace_internal(v_tenant.id);
  END LOOP;
END $$;
