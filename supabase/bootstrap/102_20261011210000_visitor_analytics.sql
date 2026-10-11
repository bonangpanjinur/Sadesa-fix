-- Visitor analytics: server-captured network metadata and privacy-conscious aggregates.
CREATE TABLE IF NOT EXISTS public.visitor_analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  path text NOT NULL,
  page_title text,
  referrer text,
  visitor_key text NOT NULL,
  viewer_id uuid,
  ip_address inet,
  country_code text,
  country_name text,
  region_name text,
  city_name text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  user_agent text,
  device_type text NOT NULL DEFAULT 'unknown',
  browser_name text,
  os_name text
);

CREATE INDEX IF NOT EXISTS idx_visitor_analytics_occurred_at ON public.visitor_analytics_events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_visitor_analytics_path_time ON public.visitor_analytics_events (path, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_visitor_analytics_visitor_time ON public.visitor_analytics_events (visitor_key, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_visitor_analytics_location ON public.visitor_analytics_events (country_code, region_name, city_name, occurred_at DESC);

ALTER TABLE public.visitor_analytics_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read visitor analytics" ON public.visitor_analytics_events;
CREATE POLICY "Admins can read visitor analytics"
  ON public.visitor_analytics_events FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "No direct visitor analytics inserts" ON public.visitor_analytics_events;
CREATE POLICY "No direct visitor analytics inserts"
  ON public.visitor_analytics_events FOR INSERT TO authenticated, anon
  WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.purge_old_visitor_analytics_events()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE deleted_count bigint;
BEGIN
  DELETE FROM public.visitor_analytics_events
  WHERE occurred_at < now() - interval '90 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_old_visitor_analytics_events() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_old_visitor_analytics_events() TO service_role;

CREATE OR REPLACE FUNCTION public.get_visitor_analytics_summary(
  p_from timestamptz,
  p_to timestamptz
)
RETURNS TABLE (
  total_views bigint,
  unique_visitors bigint,
  today_views bigint,
  today_unique_visitors bigint,
  top_path text,
  top_path_views bigint,
  top_country text,
  top_country_views bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  RETURN QUERY
  WITH scoped AS (
    SELECT * FROM public.visitor_analytics_events
    WHERE occurred_at >= p_from AND occurred_at < p_to
  ), today AS (
    SELECT * FROM scoped WHERE occurred_at >= date_trunc('day', now())
  ), paths AS (
    SELECT path, count(*)::bigint AS views FROM scoped GROUP BY path ORDER BY views DESC LIMIT 1
  ), countries AS (
    SELECT COALESCE(country_name, 'Tidak diketahui') AS country, count(*)::bigint AS views
    FROM scoped GROUP BY 1 ORDER BY views DESC LIMIT 1
  )
  SELECT
    (SELECT count(*)::bigint FROM scoped),
    (SELECT count(DISTINCT visitor_key)::bigint FROM scoped),
    (SELECT count(*)::bigint FROM today),
    (SELECT count(DISTINCT visitor_key)::bigint FROM today),
    (SELECT path FROM paths), (SELECT views FROM paths),
    (SELECT country FROM countries), (SELECT views FROM countries);
END;
$$;
REVOKE ALL ON FUNCTION public.get_visitor_analytics_summary(timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_visitor_analytics_summary(timestamptz, timestamptz) TO authenticated;

DO $bootstrap_do_visitor_analytics_marker$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_visitor_analytics_marker$;
