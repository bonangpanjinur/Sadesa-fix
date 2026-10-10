-- Sadesa Ojek pickup landmark; forward-only and safe to re-run.
-- Source: archive/supabase/migrations/20261010150000_ride_pickup_landmark.sql
DO $bootstrap_do_20261010150000_ride_pickup_landmark$
BEGIN
  EXECUTE $bootstrap_sql_add_pickup_landmark$
    ALTER TABLE public.ride_requests
      ADD COLUMN IF NOT EXISTS pickup_landmark text
  $bootstrap_sql_add_pickup_landmark$;

  EXECUTE $bootstrap_sql_create_ride_request_with_landmark$
    CREATE OR REPLACE FUNCTION public.create_ride_request_with_landmark(
      p_pickup_lat numeric,
      p_pickup_lng numeric,
      p_pickup_address text,
      p_destination_lat numeric,
      p_destination_lng numeric,
      p_destination_address text,
      p_pickup_landmark text
    )
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_catalog, public
    AS $ride_function$
    DECLARE
      v_ride_id uuid;
      v_landmark text := regexp_replace(COALESCE(p_pickup_landmark, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
    BEGIN
      IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
      END IF;
      IF char_length(v_landmark) NOT BETWEEN 3 AND 240 THEN
        RAISE EXCEPTION 'Pickup landmark must contain between 3 and 240 characters' USING ERRCODE = '22023';
      END IF;

      v_ride_id := public.create_ride_request(
        p_pickup_lat,
        p_pickup_lng,
        p_pickup_address,
        p_destination_lat,
        p_destination_lng,
        p_destination_address
      );

      UPDATE public.ride_requests
      SET pickup_landmark = v_landmark
      WHERE id = v_ride_id
        AND passenger_id = auth.uid();

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Created ride could not be updated with pickup landmark';
      END IF;

      RETURN v_ride_id;
    END;
    $ride_function$
  $bootstrap_sql_create_ride_request_with_landmark$;

  REVOKE ALL ON FUNCTION public.create_ride_request_with_landmark(numeric, numeric, text, numeric, numeric, text, text) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.create_ride_request_with_landmark(numeric, numeric, text, numeric, numeric, text, text) TO authenticated;
  COMMENT ON FUNCTION public.create_ride_request_with_landmark(numeric, numeric, text, numeric, numeric, text, text) IS
    'Creates a ride using canonical server fare rules and atomically stores its required pickup landmark.';
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20261010150000_ride_pickup_landmark$;
