-- Unified verifier referral for merchants and couriers.
-- One active verifikator_codes row is the source of truth for both registration forms.

ALTER TABLE public.couriers
  ADD COLUMN IF NOT EXISTS verifikator_id uuid;

ALTER TABLE public.verifikator_earnings
  ADD COLUMN IF NOT EXISTS courier_earning_id uuid,
  ADD COLUMN IF NOT EXISTS buyer_role text,
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'QUOTA_SALE';

CREATE INDEX IF NOT EXISTS idx_couriers_verifikator_id
  ON public.couriers(verifikator_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_verifikator_earnings_courier_once
  ON public.verifikator_earnings(courier_earning_id)
  WHERE courier_earning_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_merchant_verifikator_referral()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code public.verifikator_codes%ROWTYPE;
  v_group public.trade_groups%ROWTYPE;
BEGIN
  IF NEW.verifikator_code IS NULL OR (TG_OP = 'UPDATE' AND NEW.verifikator_code IS NOT DISTINCT FROM OLD.verifikator_code) THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_code
  FROM public.verifikator_codes
  WHERE code = upper(trim(NEW.verifikator_code))
    AND is_active = true
  LIMIT 1;

  IF v_code.id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_group
  FROM public.trade_groups
  WHERE verifikator_id = v_code.verifikator_id
    AND is_active = true
  LIMIT 1;

  NEW.verifikator_code := upper(trim(NEW.verifikator_code));
  NEW.verifikator_id := v_code.verifikator_id;
  NEW.trade_group := v_code.trade_group;
  IF v_group.id IS NOT NULL THEN
    NEW.group_id := v_group.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_merchant_verifikator_referral ON public.merchants;
CREATE TRIGGER assign_merchant_verifikator_referral
  BEFORE INSERT OR UPDATE OF verifikator_code ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_merchant_verifikator_referral();

CREATE OR REPLACE FUNCTION public.assign_courier_verifikator_referral()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_verifikator_id uuid;
BEGIN
  IF NEW.verifikator_code IS NULL OR (TG_OP = 'UPDATE' AND NEW.verifikator_code IS NOT DISTINCT FROM OLD.verifikator_code) THEN
    RETURN NEW;
  END IF;

  SELECT verifikator_id INTO v_verifikator_id
  FROM public.verifikator_codes
  WHERE code = upper(trim(NEW.verifikator_code))
    AND is_active = true
  LIMIT 1;

  IF v_verifikator_id IS NOT NULL THEN
    NEW.verifikator_code := upper(trim(NEW.verifikator_code));
    NEW.verifikator_id := v_verifikator_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_courier_verifikator_referral ON public.couriers;
CREATE TRIGGER assign_courier_verifikator_referral
  BEFORE INSERT OR UPDATE OF verifikator_code ON public.couriers
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_courier_verifikator_referral();

CREATE OR REPLACE FUNCTION public.record_verifikator_courier_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier public.couriers%ROWTYPE;
  v_verifikator_id uuid;
  v_percent numeric;
  v_commission integer;
BEGIN
  IF NEW.status NOT IN ('PENDING', 'PAID') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_courier
  FROM public.couriers
  WHERE id = NEW.courier_id;

  v_verifikator_id := v_courier.verifikator_id;
  IF v_verifikator_id IS NULL AND v_courier.verifikator_code IS NOT NULL THEN
    SELECT verifikator_id INTO v_verifikator_id
    FROM public.verifikator_codes
    WHERE code = upper(v_courier.verifikator_code)
      AND is_active = true
    LIMIT 1;
  END IF;

  IF v_verifikator_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT commission_percent INTO v_percent
  FROM public.verifikator_commission_rules
  WHERE source_type = 'TRANSACTION'
    AND is_active = true;

  v_percent := COALESCE(v_percent, 0);
  v_commission := floor(COALESCE(NEW.amount, 0) * v_percent / 100);
  IF v_commission <= 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.verifikator_earnings (
    verifikator_id, merchant_id, subscription_id, package_id,
    package_amount, commission_percent, commission_amount, status,
    source_type, courier_earning_id, buyer_role, description
  )
  VALUES (
    v_verifikator_id, NULL, NULL, NULL,
    NEW.amount, v_percent, v_commission, 'PENDING',
    'TRANSACTION', NEW.id, 'DRIVER', 'Komisi referral transaksi ojek'
  )
  ON CONFLICT (courier_earning_id) WHERE courier_earning_id IS NOT NULL
  DO UPDATE SET
    verifikator_id = EXCLUDED.verifikator_id,
    package_amount = EXCLUDED.package_amount,
    commission_percent = EXCLUDED.commission_percent,
    commission_amount = EXCLUDED.commission_amount;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS record_verifikator_courier_commission ON public.courier_earnings;
CREATE TRIGGER record_verifikator_courier_commission
  AFTER INSERT OR UPDATE OF amount, status, courier_id ON public.courier_earnings
  FOR EACH ROW
  EXECUTE FUNCTION public.record_verifikator_courier_commission();

REVOKE ALL ON FUNCTION public.assign_merchant_verifikator_referral() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assign_courier_verifikator_referral() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_verifikator_courier_commission() FROM PUBLIC;

COMMENT ON COLUMN public.verifikator_earnings.courier_earning_id IS
  'Idempotency key linking a verifier commission to one courier earning row.';
COMMENT ON FUNCTION public.record_verifikator_courier_commission() IS
  'Creates one pending verifier referral earning for a completed courier earning using the TRANSACTION rule.';
