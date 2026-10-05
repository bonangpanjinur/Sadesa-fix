-- Repair product media dependencies that were present in source history but are
-- missing from some production projects. This migration is safe to re-run.
DO $bootstrap_do_product_media_repair$
BEGIN
  EXECUTE $bootstrap_sql_product_media_repair$

CREATE TABLE IF NOT EXISTS public.product_toppings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  topping_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_toppings_unique_pair UNIQUE (product_id, topping_product_id),
  CONSTRAINT product_toppings_not_self CHECK (product_id <> topping_product_id)
);

CREATE INDEX IF NOT EXISTS idx_product_toppings_product_id
  ON public.product_toppings(product_id, sort_order);

ALTER TABLE public.product_toppings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active product toppings" ON public.product_toppings;
CREATE POLICY "Anyone can read active product toppings"
  ON public.product_toppings FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_toppings.product_id AND p.is_active = true)
    AND EXISTS (SELECT 1 FROM public.products t WHERE t.id = product_toppings.topping_product_id AND t.is_active = true)
  );

DROP POLICY IF EXISTS "Merchant manages own product toppings" ON public.product_toppings;
CREATE POLICY "Merchant manages own product toppings"
  ON public.product_toppings FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id AND m.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id AND m.user_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.products t
      WHERE t.id = product_toppings.topping_product_id
        AND t.merchant_id = (SELECT parent.merchant_id FROM public.products parent WHERE parent.id = product_toppings.product_id)
    )
  );

GRANT SELECT ON public.product_toppings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_toppings TO authenticated;

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
$$;

DROP TRIGGER IF EXISTS trg_validate_product_topping_merchant ON public.product_toppings;
CREATE TRIGGER trg_validate_product_topping_merchant
  BEFORE INSERT OR UPDATE ON public.product_toppings
  FOR EACH ROW EXECUTE FUNCTION public.validate_product_topping_merchant();

REVOKE ALL ON FUNCTION public.validate_product_topping_merchant() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_product_topping_merchant() TO authenticated;

-- Keep PostgREST from serving a stale schema cache after the table is created.
NOTIFY pgrst, 'reload schema';
$bootstrap_sql_product_media_repair$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_product_media_repair$;
