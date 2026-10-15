-- Admin-only hourly aggregation for the push delivery monitoring dashboard.
CREATE OR REPLACE FUNCTION public.get_push_delivery_hourly_stats(
  p_since timestamptz,
  p_until timestamptz
)
RETURNS TABLE (
  hour_bucket timestamptz,
  status text,
  attempt_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_since IS NULL OR p_until IS NULL OR p_until <= p_since
     OR p_until - p_since > interval '31 days' THEN
    RAISE EXCEPTION 'Invalid push delivery statistics range' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT
    date_trunc('hour', log.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS hour_bucket,
    log.status,
    count(*) AS attempt_count
  FROM public.push_delivery_logs AS log
  WHERE log.created_at >= p_since
    AND log.created_at < p_until
  GROUP BY 1, log.status
  ORDER BY 1, log.status;
END;
$$;

REVOKE ALL ON FUNCTION public.get_push_delivery_hourly_stats(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_push_delivery_hourly_stats(timestamptz, timestamptz) TO authenticated;
COMMENT ON FUNCTION public.get_push_delivery_hourly_stats(timestamptz, timestamptz) IS
  'Returns hourly push delivery attempt counts for admins only; bounds the scan window to 31 days.';

NOTIFY pgrst, 'reload schema';
