-- Atomic admin operation for price-book header plus its first item.
CREATE OR REPLACE FUNCTION public.create_pos_price_book(
  p_tenant_id uuid,
  p_name text,
  p_customer_segment text,
  p_outlet_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_priority integer,
  p_product_id uuid,
  p_variant_id uuid,
  p_price numeric
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_book_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.pos_tenants WHERE id = p_tenant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Price book administration denied' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Invalid price book input' USING ERRCODE = '22023';
  END IF;
  IF p_customer_segment NOT IN ('retail','wholesale','reseller','member','outlet') THEN
    RAISE EXCEPTION 'Invalid customer segment' USING ERRCODE = '22023';
  END IF;
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at < p_starts_at THEN
    RAISE EXCEPTION 'Price book end date precedes start date' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pos_products WHERE id = p_product_id AND tenant_id = p_tenant_id AND is_active = true) THEN
    RAISE EXCEPTION 'Product does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  IF p_outlet_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.pos_outlets WHERE id = p_outlet_id AND tenant_id = p_tenant_id) THEN
    RAISE EXCEPTION 'Outlet does not belong to tenant' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.pos_price_books(tenant_id, name, customer_segment, outlet_id, starts_at, ends_at, priority, created_by)
  VALUES (p_tenant_id, trim(p_name), p_customer_segment, p_outlet_id, p_starts_at, p_ends_at, COALESCE(p_priority, 0), auth.uid())
  RETURNING id INTO v_book_id;
  INSERT INTO public.pos_price_book_items(price_book_id, product_id, variant_id, price)
  VALUES (v_book_id, p_product_id, p_variant_id, p_price);
  RETURN v_book_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_price_book(uuid, text, text, uuid, timestamptz, timestamptz, integer, uuid, uuid, numeric) TO authenticated;
