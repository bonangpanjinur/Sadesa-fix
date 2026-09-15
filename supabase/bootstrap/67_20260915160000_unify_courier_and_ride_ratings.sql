-- Keep courier rating statistics consistent across marketplace deliveries and Ojek Desa rides.
-- Both flows represent feedback for the same courier profile, but historically maintained
-- separate storage paths.

CREATE OR REPLACE FUNCTION public.refresh_courier_rating(p_courier_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg numeric;
  v_count integer;
BEGIN
  SELECT
    COALESCE(round(avg(r.rating)::numeric, 2), 0),
    count(*)::integer
  INTO v_avg, v_count
  FROM (
    SELECT rating
    FROM public.courier_ratings
    WHERE courier_id = p_courier_id
    UNION ALL
    SELECT rating
    FROM public.ride_requests
    WHERE driver_id = p_courier_id
      AND status = 'COMPLETED'
      AND rating IS NOT NULL
  ) AS r;

  UPDATE public.couriers
  SET rating_avg = v_avg,
      rating_count = v_count,
      updated_at = now()
  WHERE id = p_courier_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_courier_rating_from_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.driver_id IS NOT NULL THEN
      PERFORM public.refresh_courier_rating(OLD.driver_id);
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.driver_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.rating IS DISTINCT FROM OLD.rating OR NEW.driver_id IS DISTINCT FROM OLD.driver_id) THEN
    PERFORM public.refresh_courier_rating(NEW.driver_id);
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.driver_id IS NOT NULL
     AND OLD.driver_id IS DISTINCT FROM NEW.driver_id THEN
    PERFORM public.refresh_courier_rating(OLD.driver_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_courier_rating_from_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_courier_rating(OLD.courier_id);
    RETURN OLD;
  END IF;

  PERFORM public.refresh_courier_rating(NEW.courier_id);
  IF TG_OP = 'UPDATE' AND OLD.courier_id IS DISTINCT FROM NEW.courier_id THEN
    PERFORM public.refresh_courier_rating(OLD.courier_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_courier_rating_after_ride ON public.ride_requests;
CREATE TRIGGER sync_courier_rating_after_ride
AFTER INSERT OR UPDATE OF driver_id, rating OR DELETE ON public.ride_requests
FOR EACH ROW
EXECUTE FUNCTION public.sync_courier_rating_from_ride();

DROP TRIGGER IF EXISTS sync_courier_rating_after_delivery ON public.courier_ratings;
CREATE TRIGGER sync_courier_rating_after_delivery
AFTER INSERT OR UPDATE OF courier_id, rating OR DELETE ON public.courier_ratings
FOR EACH ROW
EXECUTE FUNCTION public.sync_courier_rating_from_delivery();

-- Backfill profiles created before the unified aggregation existed.
UPDATE public.couriers AS c
SET rating_avg = stats.rating_avg,
    rating_count = stats.rating_count,
    updated_at = now()
FROM (
  SELECT
    c2.id,
    COALESCE(round(avg(r.rating)::numeric, 2), 0) AS rating_avg,
    count(r.rating)::integer AS rating_count
  FROM public.couriers AS c2
  LEFT JOIN (
    SELECT courier_id, rating
    FROM public.courier_ratings
    UNION ALL
    SELECT driver_id AS courier_id, rating
    FROM public.ride_requests
    WHERE status = 'COMPLETED' AND rating IS NOT NULL
  ) AS r ON r.courier_id = c2.id
  GROUP BY c2.id
) AS stats
WHERE c.id = stats.id;

REVOKE ALL ON FUNCTION public.refresh_courier_rating(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_courier_rating_from_ride() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_courier_rating_from_delivery() FROM PUBLIC, anon, authenticated;
NOTIFY pgrst, 'reload schema';