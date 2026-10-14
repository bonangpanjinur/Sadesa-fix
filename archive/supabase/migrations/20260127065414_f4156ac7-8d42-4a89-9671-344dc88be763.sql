-- Create notifications table for realtime notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info', -- info, success, warning, error, order, withdrawal, verification
  link TEXT, -- Optional link to navigate to
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  read_at TIMESTAMP WITH TIME ZONE
)$bootstrap_sql_1ce0873361b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ce0873361b5$;

DO $bootstrap_do_d30a30f197a4$
BEGIN
  EXECUTE $bootstrap_sql_d30a30f197a4$-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY$bootstrap_sql_d30a30f197a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d30a30f197a4$;

DO $bootstrap_do_345d44514531$
BEGIN
  EXECUTE $bootstrap_sql_345d44514531$-- RLS Policies
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications$bootstrap_sql_345d44514531$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_345d44514531$;

DO $bootstrap_do_7bb2b5308a29$
BEGIN
  EXECUTE $bootstrap_sql_7bb2b5308a29$CREATE POLICY "Users can view own notifications" ON public.notifications
FOR SELECT USING (auth.uid() = user_id)$bootstrap_sql_7bb2b5308a29$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7bb2b5308a29$;

DO $bootstrap_do_bba06ebc9c0d$
BEGIN
  EXECUTE $bootstrap_sql_bba06ebc9c0d$DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications$bootstrap_sql_bba06ebc9c0d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bba06ebc9c0d$;

DO $bootstrap_do_e6a96dc877cd$
BEGIN
  EXECUTE $bootstrap_sql_e6a96dc877cd$CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE USING (auth.uid() = user_id)$bootstrap_sql_e6a96dc877cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6a96dc877cd$;

DO $bootstrap_do_cf68ee8310a9$
BEGIN
  EXECUTE $bootstrap_sql_cf68ee8310a9$DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications$bootstrap_sql_cf68ee8310a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf68ee8310a9$;

DO $bootstrap_do_f3fed49d53ee$
BEGIN
  EXECUTE $bootstrap_sql_f3fed49d53ee$CREATE POLICY "System can insert notifications" ON public.notifications
FOR INSERT WITH CHECK (true)$bootstrap_sql_f3fed49d53ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3fed49d53ee$;

DO $bootstrap_do_9589734f224f$
BEGIN
  EXECUTE $bootstrap_sql_9589734f224f$DROP POLICY IF EXISTS "Admins can manage all notifications" ON public.notifications$bootstrap_sql_9589734f224f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9589734f224f$;

DO $bootstrap_do_2c7c58a22372$
BEGIN
  EXECUTE $bootstrap_sql_2c7c58a22372$CREATE POLICY "Admins can manage all notifications" ON public.notifications
FOR ALL USING (is_admin())$bootstrap_sql_2c7c58a22372$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c7c58a22372$;

DO $bootstrap_do_0fb0407b7ed5$
BEGIN
  EXECUTE $bootstrap_sql_0fb0407b7ed5$-- Enable realtime for notifications
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_0fb0407b7ed5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0fb0407b7ed5$;

DO $bootstrap_do_d00c113d4363$
BEGIN
  EXECUTE $bootstrap_sql_d00c113d4363$-- Create function to send notification
CREATE OR REPLACE FUNCTION public.send_notification(
  p_user_id UUID,
  p_title TEXT,
  p_message TEXT,
  p_type TEXT DEFAULT 'info',
  p_link TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  notification_id UUID;
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, link)
  VALUES (p_user_id, p_title, p_message, p_type, p_link)
  RETURNING id INTO notification_id;

  RETURN notification_id;
END;
$$$bootstrap_sql_d00c113d4363$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d00c113d4363$;

DO $bootstrap_do_0ebe4530ff05$
BEGIN
  EXECUTE $bootstrap_sql_0ebe4530ff05$-- Trigger to notify merchant when order status changes
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
  -- Get merchant user_id
  SELECT user_id INTO merchant_user_id
  FROM merchants
  WHERE id = NEW.merchant_id;

  -- Map status to readable text
  CASE NEW.status
    WHEN 'NEW' THEN order_status_text := 'Pesanan Baru';
    WHEN 'PENDING_CONFIRMATION' THEN order_status_text := 'Menunggu Konfirmasi';
    WHEN 'PROCESSED' THEN order_status_text := 'Sedang Diproses';
    WHEN 'SENT' THEN order_status_text := 'Sedang Dikirim';
    WHEN 'DONE' THEN order_status_text := 'Selesai';
    WHEN 'CANCELED' THEN order_status_text := 'Dibatalkan';
    ELSE order_status_text := NEW.status;
  END CASE;

  -- Notify buyer on status change
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM send_notification(
      NEW.buyer_id,
      'Status Pesanan Diperbarui',
      'Pesanan #' || LEFT(NEW.id::TEXT, 8) || ' ' || order_status_text,
      'order',
      '/orders/' || NEW.id
    );
  END IF;

  -- Notify merchant on new order
  IF TG_OP = 'INSERT' AND merchant_user_id IS NOT NULL THEN
    PERFORM send_notification(
      merchant_user_id,
      'Pesanan Baru',
      'Anda menerima pesanan baru senilai Rp ' || NEW.total::TEXT,
      'order',
      '/merchant/orders'
    );
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_0ebe4530ff05$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ebe4530ff05$;

DO $bootstrap_do_06fa0b0e16d5$
BEGIN
  EXECUTE $bootstrap_sql_06fa0b0e16d5$-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS order_notification_trigger ON orders$bootstrap_sql_06fa0b0e16d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06fa0b0e16d5$;

DO $bootstrap_do_ad74f923229e$
BEGIN
  EXECUTE $bootstrap_sql_ad74f923229e$-- Create trigger for order notifications
CREATE TRIGGER order_notification_trigger
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION notify_order_change()$bootstrap_sql_ad74f923229e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad74f923229e$;

DO $bootstrap_do_e9546ecea917$
BEGIN
  EXECUTE $bootstrap_sql_e9546ecea917$-- Trigger to notify merchant on withdrawal status change
CREATE OR REPLACE FUNCTION public.notify_withdrawal_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merchant_user_id UUID;
  status_text TEXT;
BEGIN
  -- Get merchant user_id
  SELECT user_id INTO merchant_user_id
  FROM merchants
  WHERE id = NEW.merchant_id;

  IF merchant_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Map status
  CASE NEW.status
    WHEN 'APPROVED' THEN status_text := 'disetujui';
    WHEN 'REJECTED' THEN status_text := 'ditolak';
    WHEN 'COMPLETED' THEN status_text := 'telah ditransfer';
    ELSE status_text := NEW.status;
  END CASE;

  -- Notify on status change
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status != 'PENDING' THEN
    PERFORM send_notification(
      merchant_user_id,
      'Penarikan Saldo ' || INITCAP(status_text),
      'Permintaan penarikan Rp ' || NEW.amount::TEXT || ' telah ' || status_text,
      'withdrawal',
      '/merchant/withdrawal'
    );
  END IF;

  RETURN NEW;
END;
$$$bootstrap_sql_e9546ecea917$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e9546ecea917$;

DO $bootstrap_do_8babca6405d5$
BEGIN
  EXECUTE $bootstrap_sql_8babca6405d5$-- Create trigger for withdrawal notifications
DROP TRIGGER IF EXISTS withdrawal_notification_trigger ON withdrawal_requests$bootstrap_sql_8babca6405d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8babca6405d5$;

DO $bootstrap_do_51f679edf78a$
BEGIN
  EXECUTE $bootstrap_sql_51f679edf78a$CREATE TRIGGER withdrawal_notification_trigger
AFTER UPDATE ON withdrawal_requests
FOR EACH ROW
EXECUTE FUNCTION notify_withdrawal_change()$bootstrap_sql_51f679edf78a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51f679edf78a$;

DO $bootstrap_do_44111de59433$
BEGIN
  EXECUTE $bootstrap_sql_44111de59433$-- Trigger to notify on merchant verification
CREATE OR REPLACE FUNCTION public.notify_merchant_verification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND TG_OP = 'UPDATE' AND OLD.registration_status IS DISTINCT FROM NEW.registration_status THEN
    IF NEW.registration_status = 'APPROVED' THEN
      PERFORM send_notification(
        NEW.user_id,
        'Pendaftaran Merchant Disetujui',
        'Selamat! Toko ' || NEW.name || ' telah diverifikasi. Anda dapat mulai berjualan.',
        'success',
        '/merchant'
      );
    ELSIF NEW.registration_status = 'REJECTED' THEN
      PERFORM send_notification(
        NEW.user_id,
        'Pendaftaran Merchant Ditolak',
        'Maaf, pendaftaran toko ' || NEW.name || ' ditolak. Alasan: ' || COALESCE(NEW.rejection_reason, 'Tidak memenuhi syarat'),
        'error',
        '/register/merchant'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_44111de59433$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44111de59433$;

DO $bootstrap_do_d367b829bf42$
BEGIN
  EXECUTE $bootstrap_sql_d367b829bf42$-- Create trigger for merchant verification notifications
DROP TRIGGER IF EXISTS merchant_verification_trigger ON merchants$bootstrap_sql_d367b829bf42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d367b829bf42$;

DO $bootstrap_do_a7cef934dc5f$
BEGIN
  EXECUTE $bootstrap_sql_a7cef934dc5f$CREATE TRIGGER merchant_verification_trigger
AFTER UPDATE ON merchants
FOR EACH ROW
EXECUTE FUNCTION notify_merchant_verification()$bootstrap_sql_a7cef934dc5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7cef934dc5f$;

DO $bootstrap_do_94e503b2eaa2$
BEGIN
  EXECUTE $bootstrap_sql_94e503b2eaa2$-- Trigger to notify admin on new withdrawal request
CREATE OR REPLACE FUNCTION public.notify_admin_new_withdrawal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_id UUID;
  merchant_name TEXT;
BEGIN
  -- Get merchant name
  SELECT name INTO merchant_name FROM merchants WHERE id = NEW.merchant_id;

  -- Notify all admins
  FOR admin_id IN SELECT user_id FROM user_roles WHERE role = 'admin'
  LOOP
    PERFORM send_notification(
      admin_id,
      'Permintaan Penarikan Baru',
      merchant_name || ' mengajukan penarikan Rp ' || NEW.amount::TEXT,
      'withdrawal',
      '/admin/withdrawals'
    );
  END LOOP;

  RETURN NEW;
END;
$$$bootstrap_sql_94e503b2eaa2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_94e503b2eaa2$;

DO $bootstrap_do_d93f16af99f3$
BEGIN
  EXECUTE $bootstrap_sql_d93f16af99f3$-- Create trigger for new withdrawal notifications to admin
DROP TRIGGER IF EXISTS admin_withdrawal_notification_trigger ON withdrawal_requests$bootstrap_sql_d93f16af99f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d93f16af99f3$;

DO $bootstrap_do_50f38612ba09$
BEGIN
  EXECUTE $bootstrap_sql_50f38612ba09$CREATE TRIGGER admin_withdrawal_notification_trigger
AFTER INSERT ON withdrawal_requests
FOR EACH ROW
EXECUTE FUNCTION notify_admin_new_withdrawal()$bootstrap_sql_50f38612ba09$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50f38612ba09$;

DO $bootstrap_do_cea914ffee17$
BEGIN
  EXECUTE $bootstrap_sql_cea914ffee17$
