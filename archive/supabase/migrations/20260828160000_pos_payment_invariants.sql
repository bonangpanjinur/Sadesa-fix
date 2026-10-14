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
$$$bootstrap_sql_95e782adf6b1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95e782adf6b1$;

DO $bootstrap_do_9fcad0bfc258$
BEGIN
  EXECUTE $bootstrap_sql_9fcad0bfc258$DROP TRIGGER IF EXISTS trg_validate_pos_sale_payment ON public.pos_sales$bootstrap_sql_9fcad0bfc258$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9fcad0bfc258$;

DO $bootstrap_do_d08278f4c4fe$
BEGIN
  EXECUTE $bootstrap_sql_d08278f4c4fe$CREATE TRIGGER trg_validate_pos_sale_payment
BEFORE INSERT OR UPDATE OF total, payment_method, payment_amount, change_amount
ON public.pos_sales
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_sale_payment()$bootstrap_sql_d08278f4c4fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d08278f4c4fe$;

DO $bootstrap_do_03652810a0da$
BEGIN
  EXECUTE $bootstrap_sql_03652810a0da$REVOKE ALL ON FUNCTION public.validate_pos_sale_payment() FROM PUBLIC, anon, authenticated$bootstrap_sql_03652810a0da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_03652810a0da$;

DO $bootstrap_do_d5328e6f38c4$
BEGIN
  EXECUTE $bootstrap_sql_d5328e6f38c4$GRANT EXECUTE ON FUNCTION public.validate_pos_sale_payment() TO service_role$bootstrap_sql_d5328e6f38c4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5328e6f38c4$;

DO $bootstrap_do_dbe55949d4b4$
BEGIN
  EXECUTE $bootstrap_sql_dbe55949d4b4$
