-- SaDesa canonical bootstrap bundle.
-- SAFE TO RE-RUN: functions and triggers are replaced idempotently.

DO $bootstrap_do_product_engagement_favorites$
BEGIN
  EXECUTE $bootstrap_sql_product_engagement_favorites$
-- Return favorite counts only for products owned by the authenticated merchant.
CREATE OR REPLACE FUNCTION public.get_merchant_product_favorite_counts(p_merchant_id uuid)
RETURNS TABLE(product_id uuid, favorite_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.merchants
    WHERE id = p_merchant_id
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Merchant access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id, COUNT(w.id)::bigint
  FROM public.products p
  LEFT JOIN public.wishlists w ON w.product_id = p.id
  WHERE p.merchant_id = p_merchant_id
  GROUP BY p.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_merchant_product_favorite_counts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_merchant_product_favorite_counts(uuid) TO authenticated;

-- Notify the merchant in-app (and queue Web Push when enabled) whenever a buyer
-- adds one of the merchant's products to their wishlist.
CREATE OR REPLACE FUNCTION public.notify_merchant_product_favorite()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merchant_user_id uuid;
  product_name text;
  merchant_id uuid;
BEGIN
  SELECT p.name, p.merchant_id, m.user_id
    INTO product_name, merchant_id, merchant_user_id
  FROM public.products p
  JOIN public.merchants m ON m.id = p.merchant_id
  WHERE p.id = NEW.product_id;

  -- Do not notify a merchant about their own wishlist action.
  IF merchant_user_id IS NULL OR merchant_user_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  PERFORM public.send_notification(
    merchant_user_id,
    'Produk ditambahkan ke favorit',
    'Produk "' || COALESCE(product_name, 'Anda') || '" baru saja difavoritkan.',
    'favorite',
    '/merchant/visitor-stats'
  );

  INSERT INTO public.notification_delivery_jobs (
    recipient_id,
    channel,
    template_key,
    payload
  ) VALUES (
    merchant_user_id,
    'push',
    'product_favorite',
    jsonb_build_object(
      'title', 'Produk ditambahkan ke favorit',
      'body', 'Produk "' || COALESCE(product_name, 'Anda') || '" baru saja difavoritkan.',
      'url', '/merchant/visitor-stats',
      'data', jsonb_build_object(
        'type', 'product_favorite',
        'product_id', NEW.product_id::text,
        'merchant_id', merchant_id::text
      )
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS merchant_product_favorite_notification_trigger ON public.wishlists;
CREATE TRIGGER merchant_product_favorite_notification_trigger
AFTER INSERT ON public.wishlists
FOR EACH ROW
EXECUTE FUNCTION public.notify_merchant_product_favorite();
$bootstrap_sql_product_engagement_favorites$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_product_engagement_favorites$;
