-- Queue buyer order-status pushes from the database so merchants do not need
-- permission to call the admin-only send-push-notification Edge Function.
CREATE OR REPLACE FUNCTION public.notify_buyer_order_status_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status_label text;
BEGIN
  CASE NEW.status
    WHEN 'NEW' THEN v_status_label := 'Pesanan baru';
    WHEN 'PENDING_CONFIRMATION' THEN v_status_label := 'Menunggu konfirmasi';
    WHEN 'PENDING_PAYMENT' THEN v_status_label := 'Menunggu pembayaran';
    WHEN 'PROCESSED' THEN v_status_label := 'Sedang diproses';
    WHEN 'READY' THEN v_status_label := 'Siap diambil';
    WHEN 'ASSIGNED' THEN v_status_label := 'Kurir ditugaskan';
    WHEN 'PICKED_UP' THEN v_status_label := 'Pesanan sudah diambil kurir';
    WHEN 'SENT' THEN v_status_label := 'Sedang dikirim';
    WHEN 'DELIVERING' THEN v_status_label := 'Sedang dikirim';
    WHEN 'DELIVERED' THEN v_status_label := 'Pesanan sudah tiba';
    WHEN 'DONE' THEN v_status_label := 'Pesanan selesai';
    WHEN 'CANCELED' THEN v_status_label := 'Pesanan dibatalkan';
    WHEN 'REJECTED' THEN v_status_label := 'Pesanan ditolak';
    WHEN 'REJECTED_BY_BUYER' THEN v_status_label := 'Pesanan dibatalkan pembeli';
    WHEN 'REFUNDED' THEN v_status_label := 'Dana pesanan dikembalikan';
    ELSE v_status_label := NEW.status;
  END CASE;

  INSERT INTO public.notification_delivery_jobs (
    recipient_id,
    channel,
    template_key,
    payload
  ) VALUES (
    NEW.buyer_id,
    'push',
    'order_status_update',
    jsonb_build_object(
      'title', 'Status Pesanan Diperbarui',
      'body', 'Pesanan #' || LEFT(NEW.id::TEXT, 8) || ' sekarang: ' || v_status_label || '. Ketuk untuk melihat detail.',
      'url', '/orders/' || NEW.id::TEXT,
      'data', jsonb_build_object(
        'type', 'order_status_update',
        'order_id', NEW.id::TEXT
      )
    )
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_buyer_order_status_push() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS buyer_order_status_push_trigger ON public.orders;
CREATE TRIGGER buyer_order_status_push_trigger
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.buyer_id IS NOT NULL)
EXECUTE FUNCTION public.notify_buyer_order_status_push();

-- A 30-second ride offer cannot rely only on the one-minute cron poll. Kick
-- the existing durable worker when a targeted ride-push job is enqueued; the
-- cron remains the fallback for retries and periods when Vault is unavailable.
CREATE OR REPLACE FUNCTION public.dispatch_urgent_ride_push_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.dispatch_notification_delivery_jobs();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_urgent_ride_push_job() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS dispatch_urgent_ride_push_job_trigger ON public.notification_delivery_jobs;
CREATE TRIGGER dispatch_urgent_ride_push_job_trigger
AFTER INSERT ON public.notification_delivery_jobs
FOR EACH ROW
WHEN (NEW.channel = 'push' AND NEW.template_key = 'new_ride_request')
EXECUTE FUNCTION public.dispatch_urgent_ride_push_job();
