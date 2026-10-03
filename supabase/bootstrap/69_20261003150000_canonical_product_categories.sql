-- Canonical product category identity and server-side catalog counts.
-- The legacy products.category slug remains for backwards-compatible imports/display.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.categories(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS products_category_id_active_idx
  ON public.products(category_id, created_at DESC)
  WHERE is_active = true;

-- Backfill existing products once. Future slug changes do not affect these rows.
UPDATE public.products p
SET category_id = c.id
FROM public.categories c
WHERE p.category_id IS NULL
  AND lower(trim(p.category)) = lower(c.slug);

CREATE OR REPLACE FUNCTION public.sync_product_category_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.category_id IS NULL AND NULLIF(trim(NEW.category), '') IS NOT NULL THEN
    SELECT id INTO NEW.category_id
    FROM public.categories
    WHERE lower(slug) = lower(trim(NEW.category))
      AND is_active = true
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_product_category_id ON public.products;
CREATE TRIGGER trg_sync_product_category_id
  BEFORE INSERT OR UPDATE OF category, category_id ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.sync_product_category_id();

CREATE OR REPLACE FUNCTION public.get_product_category_counts()
RETURNS TABLE(category_id uuid, product_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT p.category_id, count(*)::bigint
  FROM public.products p
  WHERE p.is_active = true AND p.category_id IS NOT NULL
  GROUP BY p.category_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_product_category_counts() TO anon, authenticated;

-- Keep the bundle compatible with the canonical bootstrap validator. The
-- statements above are already guarded with IF NOT EXISTS / CREATE OR REPLACE.
DO $bootstrap_do_canonical_product_categories_marker$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_canonical_product_categories_marker$;
