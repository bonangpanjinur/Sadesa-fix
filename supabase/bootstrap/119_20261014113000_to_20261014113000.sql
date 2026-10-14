-- DesaMart canonical bootstrap bundle; manual addition beyond the archived source set.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20261014113000_enforce_marketplace_checkout_payment_and_phone.sql .. 20261014113000_enforce_marketplace_checkout_payment_and_phone.sql

-- ===== BEGIN SOURCE: 20261014113000_enforce_marketplace_checkout_payment_and_phone.sql =====
-- Enforce marketplace checkout contracts at the database boundary.
-- Keep POS, table-order, and ride order types outside this trigger.
CREATE OR REPLACE FUNCTION public.enforce_marketplace_checkout_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone_digits text;
  v_transfer_enabled boolean;
  v_xendit_enabled boolean;
BEGIN
  IF NEW.buyer_id IS NULL AND NEW.guest_access_token_hash IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.delivery_type NOT IN ('PICKUP', 'INTERNAL', 'EXPEDITION') THEN
    RETURN NEW;
  END IF;

  v_phone_digits := regexp_replace(COALESCE(NEW.delivery_phone, ''), '[^0-9]', '', 'g');
  IF length(v_phone_digits) < 8 OR length(v_phone_digits) > 15 THEN
    RAISE EXCEPTION 'Invalid delivery phone number' USING ERRCODE = '22023';
  END IF;

  IF NEW.payment_method = 'TRANSFER' THEN
    SELECT COALESCE(m.payment_transfer_enabled, true)
      INTO v_transfer_enabled
    FROM public.merchants m
    WHERE m.id = NEW.merchant_id;

    IF COALESCE(v_transfer_enabled, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Transfer payment is unavailable for this merchant' USING ERRCODE = '22023';
    END IF;
  ELSIF NEW.payment_method = 'ONLINE' THEN
    SELECT COALESCE((s.value->>'enabled')::boolean, false)
      INTO v_xendit_enabled
    FROM public.app_settings s
    WHERE s.key = 'payment_xendit';

    IF COALESCE(v_xendit_enabled, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Online payment is currently unavailable' USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_marketplace_checkout_contract ON public.orders;
CREATE TRIGGER enforce_marketplace_checkout_contract
  BEFORE INSERT OR UPDATE OF merchant_id, payment_method, delivery_phone, delivery_type
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_marketplace_checkout_contract();

REVOKE ALL ON FUNCTION public.enforce_marketplace_checkout_contract() FROM PUBLIC, anon, authenticated;

-- ===== END SOURCE: 20261014113000_enforce_marketplace_checkout_payment_and_phone.sql =====
