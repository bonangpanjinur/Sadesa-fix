-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_c20a8a8d59d7$
BEGIN
  EXECUTE $bootstrap_sql_c20a8a8d59d7$-- Notify the ride passenger once when the assigned courier enters the pickup radius.
-- The durable marker prevents duplicate notifications when GPS updates arrive frequently.

ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS pickup_approach_notified_at timestamptz$bootstrap_sql_c20a8a8d59d7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c20a8a8d59d7$;

DO $bootstrap_do_fe93e14d75e5$
BEGIN
  EXECUTE $bootstrap_sql_fe93e14d75e5$CREATE TABLE IF NOT EXISTS public.ride_pickup_approach_notifications (
  ride_id uuid PRIMARY KEY REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_fe93e14d75e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe93e14d75e5$;

DO $bootstrap_do_77bb90ceaea2$
BEGIN
  EXECUTE $bootstrap_sql_77bb90ceaea2$ALTER TABLE public.ride_pickup_approach_notifications ENABLE ROW LEVEL SECURITY$bootstrap_sql_77bb90ceaea2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_77bb90ceaea2$;

DO $bootstrap_do_1db1d32e6226$
BEGIN
  EXECUTE $bootstrap_sql_1db1d32e6226$REVOKE ALL ON public.ride_pickup_approach_notifications FROM PUBLIC, anon, authenticated$bootstrap_sql_1db1d32e6226$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1db1d32e6226$;

DO $bootstrap_do_f5be8d034f16$
BEGIN
  EXECUTE $bootstrap_sql_f5be8d034f16$CREATE OR REPLACE FUNCTION public.enqueue_ride_pickup_approach_notification(
  p_courier_id uuid,
  p_lat numeric,
  p_lng numeric
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride record;
  v_queued integer := 0;
  v_marker_inserted boolean;
BEGIN
  IF p_courier_id IS NULL OR p_lat IS NULL OR p_lng IS NULL
     OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN
    RETURN 0;
  END IF;

  FOR v_ride IN
    SELECT r.id, r.passenger_id, r.pickup_address
    FROM public.ride_requests r
    WHERE r.driver_id = p_courier_id
      AND r.status = 'ACCEPTED'
      AND r.pickup_approach_notified_at IS NULL
      AND 6371 * 2 * asin(sqrt(
        power(sin(radians(p_lat - r.pickup_lat) / 2), 2)
        + cos(radians(p_lat)) * cos(radians(r.pickup_lat))
        * power(sin(radians(p_lng - r.pickup_lng) / 2), 2)
      )) <= 0.5
    FOR UPDATE OF r
  LOOP
    INSERT INTO public.ride_pickup_approach_notifications(ride_id)
    VALUES (v_ride.id)
    ON CONFLICT (ride_id) DO NOTHING;
    v_marker_inserted := FOUND;

    IF v_marker_inserted THEN
      UPDATE public.ride_requests
      SET pickup_approach_notified_at = now(), updated_at = now()
      WHERE id = v_ride.id;

      INSERT INTO public.notification_delivery_jobs(
        recipient_id, channel, template_key, payload
      ) VALUES (
        v_ride.passenger_id,
        'push',
        'ride_pickup_approaching',
        jsonb_build_object(
          'title', 'Kurir sudah dekat',
          'body', 'Kurir Anda sudah mendekati titik jemput. Silakan bersiap.',
          'url', '/ride/' || v_ride.id::text,
          'data', jsonb_build_object(
            'type', 'ride_pickup_approaching',
            'ride_id', v_ride.id::text,
            'pickup_address', left(coalesce(v_ride.pickup_address, ''), 240)
          )
        )
      );
      v_queued := v_queued + 1;
    END IF;
  END LOOP;

  RETURN v_queued;
END;
$$$bootstrap_sql_f5be8d034f16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f5be8d034f16$;

DO $bootstrap_do_daeed8e8f63e$
BEGIN
  EXECUTE $bootstrap_sql_daeed8e8f63e$REVOKE ALL ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated$bootstrap_sql_daeed8e8f63e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_daeed8e8f63e$;

DO $bootstrap_do_21b11d1dfa18$
BEGIN
  EXECUTE $bootstrap_sql_21b11d1dfa18$GRANT EXECUTE ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) TO service_role$bootstrap_sql_21b11d1dfa18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_21b11d1dfa18$;

DO $bootstrap_do_9f771df8ea19$
BEGIN
  EXECUTE $bootstrap_sql_9f771df8ea19$CREATE OR REPLACE FUNCTION public.trigger_ride_pickup_approach_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.current_lat IS DISTINCT FROM OLD.current_lat
     OR NEW.current_lng IS DISTINCT FROM OLD.current_lng THEN
    PERFORM public.enqueue_ride_pickup_approach_notification(NEW.id, NEW.current_lat, NEW.current_lng);
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_9f771df8ea19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f771df8ea19$;

DO $bootstrap_do_0f92bd8ace23$
BEGIN
  EXECUTE $bootstrap_sql_0f92bd8ace23$DROP TRIGGER IF EXISTS trg_ride_pickup_approach_notification ON public.couriers$bootstrap_sql_0f92bd8ace23$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f92bd8ace23$;

DO $bootstrap_do_39883d511052$
BEGIN
  EXECUTE $bootstrap_sql_39883d511052$CREATE TRIGGER trg_ride_pickup_approach_notification
AFTER UPDATE OF current_lat, current_lng ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.trigger_ride_pickup_approach_notification()$bootstrap_sql_39883d511052$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39883d511052$;

DO $bootstrap_do_b381d8128f8c$
BEGIN
  EXECUTE $bootstrap_sql_b381d8128f8c$COMMENT ON COLUMN public.ride_requests.pickup_approach_notified_at IS
  'Set once when the assigned courier first enters the 500m pickup radius.'$bootstrap_sql_b381d8128f8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b381d8128f8c$;

DO $bootstrap_do_31fe74cf3bc1$
BEGIN
  EXECUTE $bootstrap_sql_31fe74cf3bc1$COMMENT ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) IS
  'Queues one Web Push notification for an ACCEPTED ride when its courier is within 500m of pickup.'$bootstrap_sql_31fe74cf3bc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31fe74cf3bc1$;
