-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_bc68ad0ac35c$
BEGIN
  EXECUTE $bootstrap_sql_bc68ad0ac35c$-- Ensure a newly created passenger ride reaches available couriers even when
-- the driver app is backgrounded. The existing in-app notification remains
-- the source of truth; this durable job is consumed by the notification worker.
CREATE OR REPLACE FUNCTION public.notify_couriers_new_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text := 'Pesanan Ojek Baru!';
  v_message text := 'Ada permintaan ojek baru. Buka aplikasi untuk melihat detail dan mengambil order.';
  v_courier record;
BEGIN
  FOR v_courier IN
    SELECT c.user_id
    FROM public.couriers c
    WHERE c.user_id IS NOT NULL
      AND c.registration_status = 'APPROVED'
      AND c.status = 'ACTIVE'
      AND c.is_available = true
      AND c.last_location_update >= now() - interval '90 seconds'
  LOOP
    INSERT INTO public.notifications (user_id, title, message, type, link)
    VALUES (v_courier.user_id, v_title, v_message, 'ride', '/courier/rides');

    INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
    VALUES (
      v_courier.user_id,
      'push',
      'new_ride_request',
      jsonb_build_object(
        'title', v_title,
        'body', v_message,
        'url', '/courier/rides',
        'data', jsonb_build_object(
          'type', 'new_ride_request',
          'ride_id', NEW.id::text
        )
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$$bootstrap_sql_bc68ad0ac35c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bc68ad0ac35c$;

DO $bootstrap_do_c2059fd0830d$
BEGIN
  EXECUTE $bootstrap_sql_c2059fd0830d$REVOKE ALL ON FUNCTION public.notify_couriers_new_ride() FROM PUBLIC, anon, authenticated$bootstrap_sql_c2059fd0830d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2059fd0830d$;

DO $bootstrap_do_09df42ce3f85$
BEGIN
  EXECUTE $bootstrap_sql_09df42ce3f85$GRANT EXECUTE ON FUNCTION public.notify_couriers_new_ride() TO service_role$bootstrap_sql_09df42ce3f85$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_09df42ce3f85$;

DO $bootstrap_do_f6fa61bc0073$
BEGIN
  EXECUTE $bootstrap_sql_f6fa61bc0073$COMMENT ON FUNCTION public.notify_couriers_new_ride() IS
  'Creates in-app and durable Web Push notifications for active, recently located couriers when a SEARCHING ride is inserted.'$bootstrap_sql_f6fa61bc0073$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f6fa61bc0073$;
