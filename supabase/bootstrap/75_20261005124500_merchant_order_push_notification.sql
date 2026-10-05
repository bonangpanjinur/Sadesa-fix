-- DesaMart canonical bootstrap bundle; generated from archive/supabase/migrations/20261005124500_merchant_order_push_notification.sql.
-- SAFE TO RE-RUN: the function definition is replaced idempotently.
DO $bootstrap_do_merchant_order_push$
BEGIN
  EXECUTE $bootstrap_sql_merchant_order_push$-- Queue a durable Web Push notification when a new order reaches a merchant.
-- The notification worker delivers the banner even when the merchant app is closed.
CREATE OR REPLACE FUNCTION public.notify_order_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merchant_user_id UUID;
  order_status_text TEXT;
BEGIN
  SELECT user_id INTO merchant_user_id
  FROM merchants
  WHERE id = NEW.merchant_id;

  CASE NEW.status
    WHEN 'NEW' THEN order_status_text := 'Pesanan Baru';
    WHEN 'PENDING_CONFIRMATION' THEN order_status_text := 'Menunggu Konfirmasi';
    WHEN 'PROCESSED' THEN order_status_text := 'Sedang Diproses';
    WHEN 'SENT' THEN order_status_text := 'Sedang Dikirim';
    WHEN 'DONE' THEN order_status_text := 'Selesai';
    WHEN 'CANCELED' THEN order_status_text := 'Dibatalkan';
    ELSE order_status_text := NEW.status;
  END CASE;

  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM send_notification(
      NEW.buyer_id,
      'Status Pesanan Diperbarui',
      'Pesanan #' || LEFT(NEW.id::TEXT, 8) || ' ' || order_status_text,
      'order',
      '/orders/' || NEW.id
    );
  END IF;

  IF TG_OP = 'INSERT' AND merchant_user_id IS NOT NULL THEN
    PERFORM send_notification(
      merchant_user_id,
      'Pesanan Baru',
      'Anda menerima pesanan baru senilai Rp ' || NEW.total::TEXT,
      'order',
      '/merchant/orders?orderId=' || NEW.id::TEXT
    );

    INSERT INTO public.notification_delivery_jobs (
      recipient_id,
      channel,
      template_key,
      payload
    ) VALUES (
      merchant_user_id,
      'push',
      'new_merchant_order',
      jsonb_build_object(
        'title', 'Pesanan Baru',
        'body', 'Anda menerima pesanan baru senilai Rp ' || NEW.total::TEXT || '. Buka aplikasi untuk memproses pesanan.',
        'url', '/merchant/orders?orderId=' || NEW.id::TEXT,
        'data', jsonb_build_object(
          'type', 'new_merchant_order',
          'order_id', NEW.id::TEXT
        )
      )
    );
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS order_notification_trigger ON public.orders;
CREATE TRIGGER order_notification_trigger
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.notify_order_change();
$bootstrap_sql_merchant_order_push$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_merchant_order_push$;
