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
$$$bootstrap_sql_dbe55949d4b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dbe55949d4b4$;

DO $bootstrap_do_cde68d6609b9$
BEGIN
  EXECUTE $bootstrap_sql_cde68d6609b9$REVOKE ALL ON FUNCTION public.pos_user_has_role(uuid, text[]) FROM PUBLIC, anon$bootstrap_sql_cde68d6609b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cde68d6609b9$;

DO $bootstrap_do_a2bcfb680ce3$
BEGIN
  EXECUTE $bootstrap_sql_a2bcfb680ce3$GRANT EXECUTE ON FUNCTION public.pos_user_has_role(uuid, text[]) TO authenticated$bootstrap_sql_a2bcfb680ce3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2bcfb680ce3$;

DO $bootstrap_do_75195ada0d09$
BEGIN
  EXECUTE $bootstrap_sql_75195ada0d09$-- Sale item visibility must follow the parent sale's assigned outlet.
DROP POLICY IF EXISTS "tenant_users_select_sale_items" ON public.pos_sale_items$bootstrap_sql_75195ada0d09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_75195ada0d09$;

DO $bootstrap_do_f8863bb36676$
BEGIN
  EXECUTE $bootstrap_sql_f8863bb36676$DROP POLICY IF EXISTS "POS users can view assigned sale items" ON public.pos_sale_items$bootstrap_sql_f8863bb36676$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8863bb36676$;

DO $bootstrap_do_4e2b24ec307e$
BEGIN
  EXECUTE $bootstrap_sql_4e2b24ec307e$CREATE POLICY "POS users can view assigned sale items"
  ON public.pos_sale_items
  FOR SELECT TO authenticated
  USING (
    sale_id IN (
      SELECT s.id
      FROM public.pos_sales s
      WHERE public.pos_user_can_access_outlet(s.tenant_id, s.outlet_id)
    )
  )$bootstrap_sql_4e2b24ec307e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e2b24ec307e$;

DO $bootstrap_do_f929d9a7f641$
BEGIN
  EXECUTE $bootstrap_sql_f929d9a7f641$-- Reject malformed financial line values regardless of whether they came from
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
$$$bootstrap_sql_f929d9a7f641$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f929d9a7f641$;

DO $bootstrap_do_67290281fe4e$
BEGIN
  EXECUTE $bootstrap_sql_67290281fe4e$DROP TRIGGER IF EXISTS trg_validate_pos_sale_item_values ON public.pos_sale_items$bootstrap_sql_67290281fe4e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_67290281fe4e$;

DO $bootstrap_do_b6e904b9681b$
BEGIN
  EXECUTE $bootstrap_sql_b6e904b9681b$CREATE TRIGGER trg_validate_pos_sale_item_values
BEFORE INSERT OR UPDATE OF qty, price, discount, tax_amount, subtotal
ON public.pos_sale_items
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_item_values()$bootstrap_sql_b6e904b9681b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6e904b9681b$;

DO $bootstrap_do_9450f9f7313d$
BEGIN
  EXECUTE $bootstrap_sql_9450f9f7313d$REVOKE ALL ON FUNCTION public.validate_pos_sale_item_values() FROM PUBLIC, anon, authenticated$bootstrap_sql_9450f9f7313d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9450f9f7313d$;

DO $bootstrap_do_2bd971946c51$
BEGIN
  EXECUTE $bootstrap_sql_2bd971946c51$GRANT EXECUTE ON FUNCTION public.validate_pos_sale_item_values() TO service_role$bootstrap_sql_2bd971946c51$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2bd971946c51$;

DO $bootstrap_do_c3bd64d2c3ec$
BEGIN
  EXECUTE $bootstrap_sql_c3bd64d2c3ec$
