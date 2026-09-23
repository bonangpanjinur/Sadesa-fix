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
