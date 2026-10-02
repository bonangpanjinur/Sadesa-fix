-- Guest checkout hardening: keep guest payment transfer-only and bind proof URLs to the guest token path.
-- This migration is trigger-based so it also hardens databases where phase 1 is already applied.

CREATE OR REPLACE FUNCTION public.enforce_guest_checkout_payment_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.buyer_id IS NULL AND NEW.guest_access_token_hash IS NOT NULL THEN
    IF NEW.payment_method <> 'TRANSFER' THEN
      RAISE EXCEPTION 'Guest payment method is unavailable' USING ERRCODE = '22023';
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.payment_proof_url IS DISTINCT FROM OLD.payment_proof_url
       AND NEW.payment_proof_url IS NOT NULL
       AND position(
         ('/payment-proofs/orders/' || NEW.id::text || '/' || NEW.guest_access_token_hash || '/')
         IN NEW.payment_proof_url
       ) = 0 THEN
      RAISE EXCEPTION 'Guest payment proof is invalid' USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_guest_checkout_payment_contract ON public.orders;
CREATE TRIGGER enforce_guest_checkout_payment_contract
  BEFORE INSERT OR UPDATE OF payment_method, payment_proof_url ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_guest_checkout_payment_contract();

REVOKE ALL ON FUNCTION public.enforce_guest_checkout_payment_contract() FROM PUBLIC, anon, authenticated;

DO $bootstrap_do_guest_checkout_hardening$
BEGIN
  EXECUTE $bootstrap_sql_guest_checkout_hardening$COMMENT ON FUNCTION public.enforce_guest_checkout_payment_contract() IS 'Guest orders accept transfer only and payment proof URLs must be scoped to the order guest token hash.'$bootstrap_sql_guest_checkout_hardening$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_guest_checkout_hardening$;
