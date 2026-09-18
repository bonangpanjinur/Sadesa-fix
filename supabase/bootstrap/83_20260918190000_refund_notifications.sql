-- Refund notification coverage.
-- Every persisted refund lifecycle transition produces an in-app notification
-- for the parties that need to act or be informed.

CREATE OR REPLACE FUNCTION public.notify_refund_request_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_user_id uuid;
  v_order_link text := '/orders/' || COALESCE(NEW.order_id, OLD.order_id)::text || '/dispute';
  v_admin_link text := '/admin/disputes';
  v_merchant_link text := '/merchant/refunds';
  v_title text;
  v_message text;
  v_type text := 'refund';
BEGIN
  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = COALESCE(NEW.merchant_id, OLD.merchant_id);

  -- A new request needs action from the merchant and admin team.
  IF TG_OP = 'INSERT' THEN
    v_title := 'Pengajuan Refund Baru';
    v_message := 'Pembeli mengajukan refund untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '. Silakan tinjau pengajuan ini.';
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    INSERT INTO public.notifications (user_id, title, message, type, link)
    SELECT ur.user_id, v_title, v_message, v_type, v_admin_link
    FROM public.user_roles ur
    WHERE ur.role::text = 'admin';
    RETURN NEW;
  END IF;

  -- Merchant response is a distinct event and must reach the buyer and admins.
  IF OLD.merchant_response IS DISTINCT FROM NEW.merchant_response
     AND NEW.merchant_response IS NOT NULL THEN
    v_title := 'Respons Merchant atas Refund';
    v_message := 'Merchant telah memberikan respons untuk refund pesanan #' || LEFT(NEW.order_id::text, 8) || '. Silakan lihat detailnya.';
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    INSERT INTO public.notifications (user_id, title, message, type, link)
    SELECT ur.user_id, v_title, v_message, v_type, v_admin_link
    FROM public.user_roles ur
    WHERE ur.role::text = 'admin' AND ur.user_id <> NEW.buyer_id;
    RETURN NEW;
  END IF;

  -- A decision notification includes the initial settlement state so the buyer
  -- does not mistake approval for completed payout.
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.status = 'APPROVED' THEN
      v_title := 'Refund Disetujui';
      v_message := 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' disetujui dan sedang menunggu pencairan.';
    ELSIF NEW.status = 'REJECTED' THEN
      v_title := 'Refund Ditolak';
      v_message := 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' ditolak. Silakan buka detail untuk melihat catatan admin.';
    ELSE
      v_title := 'Status Refund Diperbarui';
      v_message := 'Status refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.status || '.';
    END IF;
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  -- Mediation and closure transitions are informative even when the refund
  -- decision itself has not changed.
  IF OLD.dispute_status IS DISTINCT FROM NEW.dispute_status THEN
    v_title := 'Status Penanganan Refund Diperbarui';
    v_message := 'Penanganan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.dispute_status || '.';
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  -- Settlement status can change independently through the provider callback.
  IF OLD.settlement_status IS DISTINCT FROM NEW.settlement_status THEN
    v_title := 'Status Pencairan Refund Diperbarui';
    v_message := CASE NEW.settlement_status
      WHEN 'PROCESSING' THEN 'Pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' sedang diproses.'
      WHEN 'COMPLETED' THEN 'Refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berhasil dicairkan.'
      WHEN 'FAILED' THEN 'Pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' gagal dan perlu ditindaklanjuti.'
      ELSE 'Status pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || COALESCE(NEW.settlement_status, 'UNKNOWN') || '.'
    END;
    PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, v_type, v_order_link);
    IF v_merchant_user_id IS NOT NULL THEN
      PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, v_type, v_merchant_link);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_request_notification_trigger ON public.refund_requests;
CREATE TRIGGER refund_request_notification_trigger
AFTER INSERT OR UPDATE OF status, dispute_status, merchant_response, settlement_status
ON public.refund_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_request_change();

CREATE OR REPLACE FUNCTION public.notify_refund_settlement_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_user_id uuid;
  v_title text;
  v_message text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = NEW.merchant_id;

  v_title := 'Status Pencairan Refund Diperbarui';
  v_message := CASE NEW.status
    WHEN 'PROCESSING' THEN 'Pencairan refund sedang diproses untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '.'
    WHEN 'COMPLETED' THEN 'Refund berhasil dicairkan untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '.'
    WHEN 'FAILED' THEN 'Pencairan refund gagal untuk pesanan #' || LEFT(NEW.order_id::text, 8) || '; perlu ditindaklanjuti.'
    ELSE 'Status pencairan refund pesanan #' || LEFT(NEW.order_id::text, 8) || ' berubah menjadi ' || NEW.status || '.'
  END;
  PERFORM public.send_notification(NEW.buyer_id, v_title, v_message, 'refund', '/orders/' || NEW.order_id::text || '/dispute');
  IF v_merchant_user_id IS NOT NULL THEN
    PERFORM public.send_notification(v_merchant_user_id, v_title, v_message, 'refund', '/merchant/refunds');
  END IF;
  INSERT INTO public.notifications (user_id, title, message, type, link)
  SELECT ur.user_id, v_title, v_message, 'refund', '/admin/disputes'
  FROM public.user_roles ur
  WHERE ur.role::text = 'admin' AND ur.user_id <> NEW.buyer_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS refund_settlement_notification_trigger ON public.refund_settlements;
CREATE TRIGGER refund_settlement_notification_trigger
AFTER UPDATE OF status ON public.refund_settlements
FOR EACH ROW
EXECUTE FUNCTION public.notify_refund_settlement_change();

REVOKE ALL ON FUNCTION public.notify_refund_request_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_refund_settlement_change() FROM PUBLIC, anon, authenticated;
