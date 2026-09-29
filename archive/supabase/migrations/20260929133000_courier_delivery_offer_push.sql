-- Ensure direct delivery offers also reach the courier when the app is in the
-- background or closed. The notification worker consumes this durable job.
CREATE OR REPLACE FUNCTION public.notify_courier_delivery_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_order record;
BEGIN
  IF NEW.status <> 'OFFERED' THEN
    RETURN NEW;
  END IF;

  SELECT c.user_id INTO v_user_id
  FROM public.couriers c
  WHERE c.id = NEW.courier_id;

  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT o.delivery_name, o.pickup_address, o.delivery_address
  INTO v_order
  FROM public.orders o
  WHERE o.id = NEW.order_id;

  INSERT INTO public.notifications (user_id, title, message, type, link)
  VALUES (
    v_user_id,
    'Tawaran Kirim Barang Baru!',
    left('Ada tawaran pengiriman baru. Pickup: ' || coalesce(v_order.pickup_address, 'lokasi pickup') || '. Terima atau tolak sebelum waktu habis.', 240),
    'order',
    '/courier/deliveries'
  );

  INSERT INTO public.notification_delivery_jobs (recipient_id, channel, template_key, payload)
  VALUES (
    v_user_id,
    'push',
    'new_delivery_offer',
    jsonb_build_object(
      'title', 'Tawaran Kirim Barang Baru!',
      'body', left('Pickup: ' || coalesce(v_order.pickup_address, 'lokasi pickup') || '. Buka aplikasi untuk menerima atau menolak tawaran.', 4000),
      'url', '/courier/deliveries',
      'data', jsonb_build_object(
        'type', 'new_delivery_offer',
        'assignment_id', NEW.id::text,
        'order_id', NEW.order_id::text
      )
    )
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_courier_delivery_offer() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_courier_delivery_offer() TO service_role;

DROP TRIGGER IF EXISTS trg_notify_courier_delivery_offer ON public.delivery_assignments;
CREATE TRIGGER trg_notify_courier_delivery_offer
AFTER INSERT ON public.delivery_assignments
FOR EACH ROW
EXECUTE FUNCTION public.notify_courier_delivery_offer();

COMMENT ON FUNCTION public.notify_courier_delivery_offer() IS
  'Queues in-app and Web Push notification for a newly created direct delivery offer.';
