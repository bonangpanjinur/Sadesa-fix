-- Notify the ride passenger once when the assigned courier enters the pickup radius.
-- The durable marker prevents duplicate notifications when GPS updates arrive frequently.

ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS pickup_approach_notified_at timestamptz;

CREATE TABLE IF NOT EXISTS public.ride_pickup_approach_notifications (
  ride_id uuid PRIMARY KEY REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ride_pickup_approach_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ride_pickup_approach_notifications FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_ride_pickup_approach_notification(
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
$$;

REVOKE ALL ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.trigger_ride_pickup_approach_notification()
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
$$;

DROP TRIGGER IF EXISTS trg_ride_pickup_approach_notification ON public.couriers;
CREATE TRIGGER trg_ride_pickup_approach_notification
AFTER UPDATE OF current_lat, current_lng ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.trigger_ride_pickup_approach_notification();

COMMENT ON COLUMN public.ride_requests.pickup_approach_notified_at IS
  'Set once when the assigned courier first enters the 500m pickup radius.';
COMMENT ON FUNCTION public.enqueue_ride_pickup_approach_notification(uuid, numeric, numeric) IS
  'Queues one Web Push notification for an ACCEPTED ride when its courier is within 500m of pickup.';
