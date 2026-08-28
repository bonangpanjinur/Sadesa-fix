-- Enforce payment invariants for every POS sale, including writes outside the checkout RPC.
CREATE OR REPLACE FUNCTION public.validate_pos_sale_payment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.total IS NULL OR NEW.total < 0 THEN
    RAISE EXCEPTION 'POS sale total must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.payment_amount IS NULL OR NEW.payment_amount < 0 THEN
    RAISE EXCEPTION 'POS payment amount must be non-negative' USING ERRCODE = '22023';
  END IF;
  IF NEW.change_amount IS NULL OR NEW.change_amount < 0 THEN
    RAISE EXCEPTION 'POS change amount must be non-negative' USING ERRCODE = '22023';
  END IF;

  IF NEW.payment_method = 'cash' THEN
    IF NEW.payment_amount < NEW.total OR NEW.change_amount <> NEW.payment_amount - NEW.total THEN
      RAISE EXCEPTION 'Cash payment and change do not match sale total' USING ERRCODE = '22023';
    END IF;
  ELSIF NEW.payment_method IN ('qris', 'transfer', 'debit', 'credit', 'split') THEN
    IF NEW.payment_amount <> NEW.total OR NEW.change_amount <> 0 THEN
      RAISE EXCEPTION 'Non-cash payment must equal sale total with zero change' USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported POS payment method' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_sale_payment ON public.pos_sales;
CREATE TRIGGER trg_validate_pos_sale_payment
BEFORE INSERT OR UPDATE OF total, payment_method, payment_amount, change_amount
ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_payment();

REVOKE ALL ON FUNCTION public.validate_pos_sale_payment() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_pos_sale_payment() TO service_role;
