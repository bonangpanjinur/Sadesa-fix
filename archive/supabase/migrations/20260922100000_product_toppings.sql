-- Product toppings: a merchant can offer existing products as add-ons for another product.
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
  );

DROP POLICY IF EXISTS "Merchant manages own product toppings" ON public.product_toppings;
CREATE POLICY "Merchant manages own product toppings"
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
  );

GRANT SELECT ON public.product_toppings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_toppings TO authenticated;
COMMENT ON TABLE public.product_toppings IS 'Existing products offered as toppings/add-ons for another product.';
COMMENT ON COLUMN public.product_toppings.topping_product_id IS 'The existing product whose own price and stock are used at checkout.';

-- Keep merchant ownership checks simple and avoid relying on client-supplied prices.
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

-- The checkout RPC remains authoritative: selected topping products are submitted as
-- regular p_items, so their live price, active state, and stock are revalidated there.
COMMENT ON FUNCTION public.validate_product_topping_merchant() IS 'Ensures topping and parent product belong to the same merchant.';

NOTIFY pgrst, 'reload schema';
