-- Prevent overselling: update only when enough stock exists and fail atomically.
CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_quantity integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_product_id IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Invalid stock decrement request';
  END IF;

  UPDATE public.products
  SET stock = stock - p_quantity,
      updated_at = now()
  WHERE id = p_product_id
    AND stock >= p_quantity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient stock or product not found';
  END IF;
END;
$$$bootstrap_sql_fcef8adf1a7b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fcef8adf1a7b$;

DO $bootstrap_do_0c6a075948e3$
BEGIN
  EXECUTE $bootstrap_sql_0c6a075948e3$REVOKE ALL ON FUNCTION public.decrement_stock(uuid, integer) FROM PUBLIC, anon$bootstrap_sql_0c6a075948e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c6a075948e3$;

DO $bootstrap_do_9a031b0d067f$
BEGIN
  EXECUTE $bootstrap_sql_9a031b0d067f$GRANT EXECUTE ON FUNCTION public.decrement_stock(uuid, integer) TO authenticated$bootstrap_sql_9a031b0d067f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9a031b0d067f$;

DO $bootstrap_do_c7ca0c1f1526$
BEGIN
  EXECUTE $bootstrap_sql_c7ca0c1f1526$
