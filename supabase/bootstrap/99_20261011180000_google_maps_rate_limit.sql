-- Shared, privacy-preserving rate limits for billable Google Maps Edge calls.
DO $bootstrap_do_google_maps_rate_limit$
BEGIN
  EXECUTE $bootstrap_sql_google_maps_table$
    CREATE TABLE IF NOT EXISTS public.google_maps_rate_limits (
      bucket_key text PRIMARY KEY CHECK (length(bucket_key) = 64),
      window_started_at timestamptz NOT NULL,
      request_count integer NOT NULL CHECK (request_count >= 0),
      updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
    )
  $bootstrap_sql_google_maps_table$;

  EXECUTE $bootstrap_sql_google_maps_index$
    CREATE INDEX IF NOT EXISTS google_maps_rate_limits_updated_at_idx
      ON public.google_maps_rate_limits (updated_at)
  $bootstrap_sql_google_maps_index$;

  EXECUTE $bootstrap_sql_google_maps_table_revoke$
    REVOKE ALL ON TABLE public.google_maps_rate_limits FROM PUBLIC, anon, authenticated
  $bootstrap_sql_google_maps_table_revoke$;
  EXECUTE $bootstrap_sql_google_maps_table_grant$
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.google_maps_rate_limits TO service_role
  $bootstrap_sql_google_maps_table_grant$;

  EXECUTE $bootstrap_sql_google_maps_function$
    CREATE OR REPLACE FUNCTION public.consume_google_maps_rate_limit(
      p_bucket_key text,
      p_limit integer,
      p_window_seconds integer
    )
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_catalog, public
    AS $function$
    DECLARE
      v_now timestamptz := clock_timestamp();
      v_allowed boolean;
    BEGIN
      IF p_bucket_key IS NULL OR length(p_bucket_key) <> 64
        OR p_bucket_key !~ '^[0-9a-f]{64}$'
        OR p_limit < 1 OR p_limit > 100000
        OR p_window_seconds < 1 OR p_window_seconds > 86400 THEN
        RAISE EXCEPTION 'Invalid Google Maps rate-limit request';
      END IF;

      INSERT INTO public.google_maps_rate_limits AS current_bucket (
        bucket_key, window_started_at, request_count, updated_at
      )
      VALUES (p_bucket_key, v_now, 1, v_now)
      ON CONFLICT (bucket_key) DO UPDATE
      SET window_started_at = CASE
            WHEN current_bucket.window_started_at
              + make_interval(secs => p_window_seconds) <= v_now THEN v_now
            ELSE current_bucket.window_started_at
          END,
          request_count = CASE
            WHEN current_bucket.window_started_at
              + make_interval(secs => p_window_seconds) <= v_now THEN 1
            ELSE current_bucket.request_count + 1
          END,
          updated_at = v_now
      RETURNING request_count <= p_limit INTO v_allowed;

      DELETE FROM public.google_maps_rate_limits
      WHERE updated_at < v_now - interval '2 days'
        AND bucket_key <> p_bucket_key;

      RETURN v_allowed;
    END;
    $function$
  $bootstrap_sql_google_maps_function$;

  EXECUTE $bootstrap_sql_google_maps_function_revoke$
    REVOKE ALL ON FUNCTION public.consume_google_maps_rate_limit(text, integer, integer)
      FROM PUBLIC, anon, authenticated
  $bootstrap_sql_google_maps_function_revoke$;
  EXECUTE $bootstrap_sql_google_maps_function_grant$
    GRANT EXECUTE ON FUNCTION public.consume_google_maps_rate_limit(text, integer, integer)
      TO service_role
  $bootstrap_sql_google_maps_function_grant$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema
    OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_google_maps_rate_limit$;
