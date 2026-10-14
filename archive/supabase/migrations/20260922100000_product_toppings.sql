-- Product toppings: a merchant can offer existing products as add-ons for another product.
CREATE TABLE IF NOT EXISTS public.product_toppings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  topping_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_toppings_unique_pair UNIQUE (product_id, topping_product_id),
  CONSTRAINT product_toppings_not_self CHECK (product_id <> topping_product_id)
)$bootstrap_sql_623fe5280103$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_623fe5280103$;

DO $bootstrap_do_f09c94594e0f$
BEGIN
  EXECUTE $bootstrap_sql_f09c94594e0f$CREATE INDEX IF NOT EXISTS idx_product_toppings_product_id
  ON public.product_toppings(product_id, sort_order)$bootstrap_sql_f09c94594e0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f09c94594e0f$;

DO $bootstrap_do_8a653a01ac27$
BEGIN
  EXECUTE $bootstrap_sql_8a653a01ac27$ALTER TABLE public.product_toppings ENABLE ROW LEVEL SECURITY$bootstrap_sql_8a653a01ac27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a653a01ac27$;

DO $bootstrap_do_d7661bb942ee$
BEGIN
  EXECUTE $bootstrap_sql_d7661bb942ee$DROP POLICY IF EXISTS "Anyone can read active product toppings" ON public.product_toppings$bootstrap_sql_d7661bb942ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7661bb942ee$;

DO $bootstrap_do_a07e2faabf75$
BEGIN
  EXECUTE $bootstrap_sql_a07e2faabf75$CREATE POLICY "Anyone can read active product toppings"
  ON public.product_toppings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_toppings.product_id
        AND p.is_active = true
    )
    AND EXISTS (
      SELECT 1 FROM public.products t
      WHERE t.id = product_toppings.topping_product_id
        AND t.is_active = true
    )
  )$bootstrap_sql_a07e2faabf75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a07e2faabf75$;

DO $bootstrap_do_0d30bd90e779$
BEGIN
  EXECUTE $bootstrap_sql_0d30bd90e779$DROP POLICY IF EXISTS "Merchant manages own product toppings" ON public.product_toppings$bootstrap_sql_0d30bd90e779$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d30bd90e779$;

DO $bootstrap_do_49b125360a35$
BEGIN
  EXECUTE $bootstrap_sql_49b125360a35$CREATE POLICY "Merchant manages own product toppings"
  ON public.product_toppings FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id
        AND m.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id
        AND m.user_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.products t
      WHERE t.id = product_toppings.topping_product_id
        AND t.merchant_id = (SELECT parent.merchant_id FROM public.products parent WHERE parent.id = product_toppings.product_id)
    )
  )$bootstrap_sql_49b125360a35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49b125360a35$;

DO $bootstrap_do_850bee2581ab$
BEGIN
  EXECUTE $bootstrap_sql_850bee2581ab$GRANT SELECT ON public.product_toppings TO anon, authenticated$bootstrap_sql_850bee2581ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_850bee2581ab$;

DO $bootstrap_do_9ad70e126e53$
BEGIN
  EXECUTE $bootstrap_sql_9ad70e126e53$GRANT INSERT, UPDATE, DELETE ON public.product_toppings TO authenticated$bootstrap_sql_9ad70e126e53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ad70e126e53$;

DO $bootstrap_do_e50d56deed71$
BEGIN
  EXECUTE $bootstrap_sql_e50d56deed71$COMMENT ON TABLE public.product_toppings IS 'Existing products offered as toppings/add-ons for another product.'$bootstrap_sql_e50d56deed71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e50d56deed71$;

DO $bootstrap_do_f4ad322c9b83$
BEGIN
  EXECUTE $bootstrap_sql_f4ad322c9b83$COMMENT ON COLUMN public.product_toppings.topping_product_id IS 'The existing product whose own price and stock are used at checkout.'$bootstrap_sql_f4ad322c9b83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4ad322c9b83$;

DO $bootstrap_do_31be05e6b515$
BEGIN
  EXECUTE $bootstrap_sql_31be05e6b515$-- Keep merchant ownership checks simple and avoid relying on client-supplied prices.
CREATE OR REPLACE FUNCTION public.validate_product_topping_merchant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  parent_merchant uuid;
  topping_merchant uuid;
BEGIN
  SELECT merchant_id INTO parent_merchant FROM public.products WHERE id = NEW.product_id;
  SELECT merchant_id INTO topping_merchant FROM public.products WHERE id = NEW.topping_product_id;
  IF parent_merchant IS NULL OR topping_merchant IS NULL OR parent_merchant <> topping_merchant THEN
    RAISE EXCEPTION 'Topping harus berasal dari merchant yang sama';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_31be05e6b515$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31be05e6b515$;

DO $bootstrap_do_bd0a3d9da3a1$
BEGIN
  EXECUTE $bootstrap_sql_bd0a3d9da3a1$DROP TRIGGER IF EXISTS trg_validate_product_topping_merchant ON public.product_toppings$bootstrap_sql_bd0a3d9da3a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd0a3d9da3a1$;

DO $bootstrap_do_580be85499f3$
BEGIN
  EXECUTE $bootstrap_sql_580be85499f3$CREATE TRIGGER trg_validate_product_topping_merchant
  BEFORE INSERT OR UPDATE ON public.product_toppings
  FOR EACH ROW EXECUTE FUNCTION public.validate_product_topping_merchant()$bootstrap_sql_580be85499f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_580be85499f3$;

DO $bootstrap_do_0ce041a0eb55$
BEGIN
  EXECUTE $bootstrap_sql_0ce041a0eb55$REVOKE ALL ON FUNCTION public.validate_product_topping_merchant() FROM PUBLIC$bootstrap_sql_0ce041a0eb55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ce041a0eb55$;

DO $bootstrap_do_b40b009d5221$
BEGIN
  EXECUTE $bootstrap_sql_b40b009d5221$GRANT EXECUTE ON FUNCTION public.validate_product_topping_merchant() TO authenticated$bootstrap_sql_b40b009d5221$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b40b009d5221$;

DO $bootstrap_do_2d7c864cb2e2$
BEGIN
  EXECUTE $bootstrap_sql_2d7c864cb2e2$-- The checkout RPC remains authoritative: selected topping products are submitted as
-- regular p_items, so their live price, active state, and stock are revalidated there.
COMMENT ON FUNCTION public.validate_product_topping_merchant() IS 'Ensures topping and parent product belong to the same merchant.'$bootstrap_sql_2d7c864cb2e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d7c864cb2e2$;

DO $bootstrap_do_c7cf52d5935b$
BEGIN
  EXECUTE $bootstrap_sql_c7cf52d5935b$NOTIFY pgrst, 'reload schema'$bootstrap_sql_c7cf52d5935b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7cf52d5935b$;

DO $bootstrap_do_c83d50398738$
BEGIN
  EXECUTE $bootstrap_sql_c83d50398738$
