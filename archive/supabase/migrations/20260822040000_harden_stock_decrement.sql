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
$$;

REVOKE ALL ON FUNCTION public.decrement_stock(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decrement_stock(uuid, integer) TO authenticated;
