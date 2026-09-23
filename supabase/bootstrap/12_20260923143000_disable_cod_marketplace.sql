-- Temporarily disable cash-on-delivery for marketplace orders.
-- POS cash payments remain available because they use payment_method = 'cash'.
CREATE OR REPLACE FUNCTION public.reject_cod_marketplace_orders()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.payment_method = 'COD' THEN
    RAISE EXCEPTION 'COD sementara dinonaktifkan. Gunakan transfer bank, QRIS, atau pembayaran online.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_cod_marketplace_orders ON public.orders;
CREATE TRIGGER trg_reject_cod_marketplace_orders
  BEFORE INSERT OR UPDATE OF payment_method ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_cod_marketplace_orders();

COMMENT ON FUNCTION public.reject_cod_marketplace_orders() IS
  'Temporarily blocks COD for marketplace orders while retaining POS cash payments.';

-- Limit authenticated buyers to ten new orders per ten-minute window. The
-- idempotent checkout wrapper prevents retries from creating extra rows, while
-- this trigger protects the database from scripted order floods.
CREATE OR REPLACE FUNCTION public.enforce_marketplace_order_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recent_order_count integer;
BEGIN
  IF auth.uid() IS NULL OR NEW.buyer_id IS NULL OR NEW.buyer_id <> auth.uid() THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO recent_order_count
  FROM public.orders
  WHERE buyer_id = NEW.buyer_id
    AND created_at >= now() - interval '10 minutes'
    AND status <> 'CANCELLED';

  IF recent_order_count >= 10 THEN
    RAISE EXCEPTION 'Terlalu banyak pesanan dalam waktu singkat. Coba lagi beberapa menit.'
      USING ERRCODE = '42901';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_order_rate_limit ON public.orders;
CREATE TRIGGER trg_marketplace_order_rate_limit
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_marketplace_order_rate_limit();

-- Keep a minimal, append-only security trail for order creation and status or
-- payment changes. It is intentionally separate from admin_audit_logs because
-- buyer-created orders do not have an admin actor.
CREATE TABLE IF NOT EXISTS public.order_security_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid,
  actor_id uuid,
  event_type text NOT NULL,
  old_status text,
  new_status text,
  old_payment_status text,
  new_payment_status text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_security_audit_order_created
  ON public.order_security_audit_log(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_security_audit_actor_created
  ON public.order_security_audit_log(actor_id, created_at DESC);

ALTER TABLE public.order_security_audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_security_audit_log FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.write_order_security_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  event_name text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    event_name := 'created';
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    event_name := 'status_changed';
  ELSIF OLD.payment_status IS DISTINCT FROM NEW.payment_status THEN
    event_name := 'payment_status_changed';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO public.order_security_audit_log (
    order_id, actor_id, event_type, old_status, new_status,
    old_payment_status, new_payment_status, metadata
  ) VALUES (
    NEW.id,
    auth.uid(),
    event_name,
    CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
    NEW.status,
    CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.payment_status END,
    NEW.payment_status,
    jsonb_build_object('operation', TG_OP, 'buyer_id', NEW.buyer_id, 'merchant_id', NEW.merchant_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_security_audit_log ON public.orders;
CREATE TRIGGER trg_order_security_audit_log
  AFTER INSERT OR UPDATE OF status, payment_status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.write_order_security_audit_log();

REVOKE ALL ON FUNCTION public.enforce_marketplace_order_rate_limit() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.write_order_security_audit_log() FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.order_security_audit_log IS
  'Append-only security events for marketplace order and payment status changes.';
