-- Concurrency hardening for POS voucher redemption, cash sessions, and returns.

CREATE OR REPLACE FUNCTION public.validate_pos_cash_session_actor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Keep service-role/batch imports compatible while enforcing browser actors.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.cashier_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cash session cashier identity mismatch' USING ERRCODE = '42501';
  END IF;
  IF NOT public.pos_user_has_role(NEW.tenant_id, ARRAY['owner', 'manager', 'kasir']::text[]) THEN
    RAISE EXCEPTION 'POS role cannot open cash session' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_cash_session_actor ON public.pos_cash_sessions;
CREATE TRIGGER trg_validate_pos_cash_session_actor
BEFORE INSERT ON public.pos_cash_sessions
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_cash_session_actor();

REVOKE ALL ON FUNCTION public.validate_pos_cash_session_actor() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_cash_session_actor() TO service_role;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_voucher_usage_sale_once
  ON public.pos_voucher_usages(voucher_id, sale_id)
  WHERE sale_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_returns_total_refund_nonnegative') THEN
    ALTER TABLE public.pos_sale_returns ADD CONSTRAINT pos_sale_returns_total_refund_nonnegative CHECK (total_refund >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_qty_positive') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_qty_positive CHECK (qty > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pos_sale_return_items_values_nonnegative') THEN
    ALTER TABLE public.pos_sale_return_items ADD CONSTRAINT pos_sale_return_items_values_nonnegative CHECK (price >= 0 AND subtotal >= 0);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale public.pos_sales%ROWTYPE;
BEGIN
  SELECT * INTO v_sale
  FROM public.pos_sales
  WHERE id = NEW.sale_id
    AND tenant_id = NEW.tenant_id
    AND outlet_id = NEW.outlet_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Return sale does not belong to tenant and outlet' USING ERRCODE = '42501';
  END IF;
  IF v_sale.status NOT IN ('completed', 'refunded', 'partially_refunded') THEN
    RAISE EXCEPTION 'Only completed POS sales can be returned' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_context ON public.pos_sale_returns;
CREATE TRIGGER trg_validate_pos_sale_return_context
BEFORE INSERT OR UPDATE OF sale_id, tenant_id, outlet_id
ON public.pos_sale_returns
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_context();

CREATE OR REPLACE FUNCTION public.validate_pos_sale_return_item_quantity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed numeric;
  v_returned numeric;
BEGIN
  SELECT si.qty INTO v_allowed
  FROM public.pos_sale_items si
  WHERE si.id = NEW.sale_item_id
    AND si.sale_id = (SELECT sale_id FROM public.pos_sale_returns WHERE id = NEW.return_id)
  FOR UPDATE;
  IF v_allowed IS NULL THEN
    RAISE EXCEPTION 'Return item does not belong to original sale' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(ri.qty), 0) INTO v_returned
  FROM public.pos_sale_return_items ri
  WHERE ri.sale_item_id = NEW.sale_item_id
    AND ri.return_id <> NEW.return_id;
  IF NEW.qty > v_allowed - v_returned THEN
    RAISE EXCEPTION 'Return quantity exceeds purchased quantity' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_return_item_quantity ON public.pos_sale_return_items;
CREATE TRIGGER trg_validate_pos_sale_return_item_quantity
BEFORE INSERT OR UPDATE OF return_id, sale_item_id, qty
ON public.pos_sale_return_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_return_item_quantity();

REVOKE ALL ON FUNCTION public.validate_pos_sale_return_context() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_sale_return_item_quantity() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_context() TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_return_item_quantity() TO service_role;
