-- DesaMart checkout repair bundle.
-- Source: 20261014093000_repair_checkout_item_normalizer.sql
-- Safe to re-run: CREATE OR REPLACE and REVOKE are idempotent.

-- Repair checkout databases where the item-normalization migration was skipped
-- or the function was removed while newer quote RPCs already depend on it.
CREATE OR REPLACE FUNCTION public.normalize_marketplace_checkout_items(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_normalized jsonb;
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Cart is empty' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
    WHERE i.product_id IS NULL
       OR i.quantity IS NULL
       OR i.quantity <= 0
       OR i.quantity <> trunc(i.quantity)
  ) THEN
    RAISE EXCEPTION 'Invalid checkout item' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT i.product_id, i.variant_id, sum(i.quantity) AS quantity
      FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
      GROUP BY i.product_id, i.variant_id
      HAVING sum(i.quantity) > 1000
    ) invalid_groups
  ) THEN
    RAISE EXCEPTION 'Combined product quantity exceeds the checkout limit' USING ERRCODE = '22023';
  END IF;
  SELECT jsonb_agg(
    jsonb_build_object(
      'product_id', grouped.product_id,
      'variant_id', grouped.variant_id,
      'quantity', grouped.quantity::integer
    ) ORDER BY grouped.product_id, grouped.variant_id NULLS FIRST
  )
  INTO v_normalized
  FROM (
    SELECT i.product_id, i.variant_id, sum(i.quantity) AS quantity
    FROM jsonb_to_recordset(p_items) AS i(product_id uuid, variant_id uuid, quantity numeric)
    GROUP BY i.product_id, i.variant_id
  ) grouped;
  RETURN v_normalized;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_marketplace_checkout_items(jsonb) FROM PUBLIC, anon, authenticated;
