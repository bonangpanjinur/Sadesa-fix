-- Linked products must receive stock from POS outlet stock, not from a
-- merchant's manual marketplace edit. The projection function in migration 15
-- opts into the internal transaction setting before it updates products.stock.

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

REVOKE ALL ON FUNCTION public.prevent_manual_stock_edit_for_pos_product() FROM PUBLIC, anon, authenticated;