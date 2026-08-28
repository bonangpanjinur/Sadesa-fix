-- POS authorization and checkout invariants.
-- This migration is safe to re-run and keeps enforcement in the database.

CREATE OR REPLACE FUNCTION public.pos_user_has_role(
  p_tenant_id uuid,
  p_roles text[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    WHERE t.id = p_tenant_id
      AND t.user_id = auth.uid()
      AND 'owner' = ANY(p_roles)
  )
  OR EXISTS (
    SELECT 1
    FROM public.pos_users u
    WHERE u.tenant_id = p_tenant_id
      AND u.user_id = auth.uid()
      AND u.is_active = true
      AND u.role = ANY(p_roles)
  );
$$;

REVOKE ALL ON FUNCTION public.pos_user_has_role(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pos_user_has_role(uuid, text[]) TO authenticated;

-- Sale item visibility must follow the parent sale's assigned outlet.
DROP POLICY IF EXISTS "tenant_users_select_sale_items" ON public.pos_sale_items;
DROP POLICY IF EXISTS "POS users can view assigned sale items" ON public.pos_sale_items;
CREATE POLICY "POS users can view assigned sale items"
  ON public.pos_sale_items
  FOR SELECT TO authenticated
  USING (
    sale_id IN (
      SELECT s.id
      FROM public.pos_sales s
      WHERE public.pos_user_can_access_outlet(s.tenant_id, s.outlet_id)
    )
  );

-- Reject malformed financial line values regardless of whether they came from
-- the checkout RPC or an administrative write path.
CREATE OR REPLACE FUNCTION public.validate_pos_sale_item_values()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.qty IS NULL OR NEW.qty <= 0 THEN
    RAISE EXCEPTION 'POS sale item quantity must be positive' USING ERRCODE = '22023';
  END IF;
  IF NEW.price IS NULL OR NEW.price < 0 THEN
    RAISE EXCEPTION 'POS sale item price must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(NEW.discount, 0) < 0 OR COALESCE(NEW.tax_amount, 0) < 0 THEN
    RAISE EXCEPTION 'POS sale item discount and tax must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.subtotal IS NULL OR NEW.subtotal < 0 THEN
    RAISE EXCEPTION 'POS sale item subtotal must be non-negative' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_item_values ON public.pos_sale_items;
CREATE TRIGGER trg_validate_pos_sale_item_values
BEFORE INSERT OR UPDATE OF qty, price, discount, tax_amount, subtotal
ON public.pos_sale_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_item_values();

REVOKE ALL ON FUNCTION public.validate_pos_sale_item_values() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_item_values() TO service_role;
