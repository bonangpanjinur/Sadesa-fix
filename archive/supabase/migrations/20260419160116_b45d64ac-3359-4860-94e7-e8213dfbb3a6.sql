ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_check$bootstrap_sql_b93b1087e1d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b93b1087e1d4$;

DO $bootstrap_do_138a7a491d4a$
BEGIN
  EXECUTE $bootstrap_sql_138a7a491d4a$-- Use a trigger-based validation instead of CHECK so we can reference categories table
CREATE OR REPLACE FUNCTION public.validate_product_category()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.category IS NULL OR NEW.category = '' THEN
    RAISE EXCEPTION 'Kategori produk wajib diisi';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE slug = NEW.category AND is_active = true) THEN
    RAISE EXCEPTION 'Kategori "%" tidak valid atau tidak aktif', NEW.category;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_138a7a491d4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_138a7a491d4a$;

DO $bootstrap_do_5adef2f21e8a$
BEGIN
  EXECUTE $bootstrap_sql_5adef2f21e8a$DROP TRIGGER IF EXISTS trg_validate_product_category ON public.products$bootstrap_sql_5adef2f21e8a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5adef2f21e8a$;

DO $bootstrap_do_09322853ca8a$
BEGIN
  EXECUTE $bootstrap_sql_09322853ca8a$CREATE TRIGGER trg_validate_product_category
BEFORE INSERT OR UPDATE OF category ON public.products
FOR EACH ROW EXECUTE FUNCTION public.validate_product_category()$bootstrap_sql_09322853ca8a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09322853ca8a$;

DO $bootstrap_do_b11386b87a3f$
BEGIN
  EXECUTE $bootstrap_sql_b11386b87a3f$
