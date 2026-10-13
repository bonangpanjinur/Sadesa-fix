-- Local courier pricing: distance formula plus an optional zone surcharge.
-- The existing shipping_zones.fee is interpreted as a flat surcharge for
-- difficult-road zones, not as a replacement for the distance-based fare.
CREATE OR REPLACE FUNCTION public.marketplace_shipping_contract_quote(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_subtotal integer,
  p_distance_km numeric,
  p_merchant_id uuid,
  p_rate_card_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings jsonb;
  v_zones jsonb;
  v_zone jsonb;
  v_shipping integer := 0;
  v_distance numeric := GREATEST(COALESCE(p_distance_km, 0), 0);
  v_zone_fee integer := 0;
  v_zone_name text;
  v_zone_max_distance numeric;
  v_free_shipping_min_order integer;
BEGIN
  IF p_delivery_type = 'PICKUP' THEN
    RETURN jsonb_build_object('contract', 'PICKUP_FREE_V1', 'shipping_cost', 0);
  ELSIF p_delivery_type = 'EXPEDITION' THEN
    RETURN public.marketplace_expedition_shipping_quote(
      p_items, p_delivery, p_subtotal, p_merchant_id, p_rate_card_id
    );
  ELSIF p_delivery_type <> 'INTERNAL' THEN
    RAISE EXCEPTION 'Unsupported delivery pricing contract' USING ERRCODE = '22023';
  END IF;

  SELECT value INTO v_settings
  FROM public.app_settings
  WHERE key = 'shipping_base_fee';

  SELECT value INTO v_zones
  FROM public.app_settings
  WHERE key = 'shipping_zones';

  v_free_shipping_min_order := COALESCE((v_settings->>'free_shipping_min_order')::integer, 100000);

  IF p_subtotal < v_free_shipping_min_order THEN
    -- Pick the nearest configured zone that contains the distance. If the
    -- distance exceeds all configured zones, use the farthest configured zone
    -- as a deterministic fallback; the separate local-distance restriction
    -- remains responsible for rejecting out-of-area INTERNAL orders.
    SELECT zone
      INTO v_zone
    FROM (
      SELECT value AS zone
      FROM jsonb_array_elements(COALESCE(v_zones->'zones', '[]'::jsonb))
      WHERE COALESCE((value->>'max_distance_km')::numeric, -1) >= v_distance
      ORDER BY (value->>'max_distance_km')::numeric ASC
      LIMIT 1
    ) matched;

    IF v_zone IS NULL THEN
      SELECT zone
        INTO v_zone
      FROM (
        SELECT value AS zone
        FROM jsonb_array_elements(COALESCE(v_zones->'zones', '[]'::jsonb))
        ORDER BY (value->>'max_distance_km')::numeric DESC
        LIMIT 1
      ) fallback;
    END IF;

    v_zone_fee := GREATEST(COALESCE((v_zone->>'fee')::integer, 0), 0);
    v_zone_name := NULLIF(btrim(v_zone->>'name'), '');
    v_zone_max_distance := NULLIF(v_zone->>'max_distance_km', '')::numeric;

    v_shipping := COALESCE((v_settings->>'base_fee')::integer, 5000)
      + round(v_distance * COALESCE((v_settings->>'per_km_fee')::integer, 2000))
      + v_zone_fee;
    v_shipping := LEAST(COALESCE((v_settings->>'max_fee')::integer, 50000),
      GREATEST(COALESCE((v_settings->>'min_fee')::integer, 5000), v_shipping));
  END IF;

  RETURN jsonb_build_object(
    'contract', 'LOCAL_COURIER_DISTANCE_ZONE_V1',
    'distance_km', round(v_distance::numeric, 2),
    'zone_name', v_zone_name,
    'zone_max_distance_km', v_zone_max_distance,
    'zone_surcharge', v_zone_fee,
    'shipping_cost', v_shipping
  );
END;
$$;

REVOKE ALL ON FUNCTION public.marketplace_shipping_contract_quote(jsonb, jsonb, text, integer, numeric, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
NOTIFY pgrst, 'reload schema';
