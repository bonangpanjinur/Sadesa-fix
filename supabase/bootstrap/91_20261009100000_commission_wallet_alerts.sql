-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Sends one in-app warning per low-balance/debt cycle; recovery resets the alert gate.

DO $bootstrap_do_commission_wallet_alerts$
BEGIN
  EXECUTE $bootstrap_sql_commission_wallet_alerts$
ALTER TABLE public.commission_wallets
  ADD COLUMN IF NOT EXISTS low_balance_alerted_at timestamptz;

CREATE OR REPLACE FUNCTION public.notify_commission_wallet_low_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_threshold bigint := 10000;
  v_fee_enabled boolean := false;
  v_user_id uuid;
  v_link text;
  v_title text;
  v_message text;
BEGIN
  SELECT p.low_balance_threshold_rupiah
    INTO v_threshold
  FROM public.commission_wallet_policy_settings p
  WHERE p.id = true;
  v_threshold := COALESCE(v_threshold, 10000);

  SELECT COALESCE(s.is_enabled AND s.fee_percent > 0, false)
    INTO v_fee_enabled
  FROM public.commission_fee_settings s
  WHERE s.owner_type = NEW.owner_type;
  v_fee_enabled := COALESCE(v_fee_enabled, false);

  -- Clear the alert gate when fees are off or the wallet has recovered. A later
  -- low-balance cycle can notify again after commission is enabled.
  IF NEW.is_active IS NOT TRUE
     OR NOT v_fee_enabled
     OR (NEW.balance_rupiah > v_threshold AND NEW.debt_rupiah = 0) THEN
    NEW.low_balance_alerted_at := NULL;
    RETURN NEW;
  END IF;

  IF NEW.low_balance_alerted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.owner_type = 'MERCHANT' THEN
    SELECT m.user_id INTO v_user_id
    FROM public.merchants m
    WHERE m.id = NEW.merchant_id;
    v_link := '/merchant/wallet';
  ELSIF NEW.owner_type = 'COURIER' THEN
    SELECT c.user_id INTO v_user_id
    FROM public.couriers c
    WHERE c.id = NEW.courier_id;
    v_link := '/courier/commission-wallet';
  ELSE
    RETURN NEW;
  END IF;

  -- Orphaned profiles cannot receive a notification; leave the gate unset so a
  -- later owner/profile repair can still deliver the first alert.
  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.debt_rupiah > 0 THEN
    v_title := 'Komisi tertunggak';
    v_message := 'Tagihan komisi Anda Rp ' || NEW.debt_rupiah::text
      || '. Top-up akan melunasi tagihan terlebih dahulu sebelum menambah saldo.';
  ELSE
    v_title := 'Saldo komisi rendah';
    v_message := 'Saldo wallet komisi Anda Rp ' || NEW.balance_rupiah::text
      || ' dan sudah mencapai ambang Rp ' || v_threshold::text
      || '. Top-up agar transaksi berikutnya dapat diproses.';
  END IF;

  BEGIN
    INSERT INTO public.notifications (user_id, title, message, type, link)
    VALUES (v_user_id, v_title, v_message, 'warning', v_link);
    NEW.low_balance_alerted_at := now();
  EXCEPTION WHEN OTHERS THEN
    -- Notification delivery must never roll back a completed commission charge/top-up.
    RAISE WARNING 'Commission wallet alert insert failed for wallet %: %', NEW.id, SQLERRM;
    NEW.low_balance_alerted_at := NULL;
  END;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_commission_wallet_low_balance() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS commission_wallet_low_balance_notification ON public.commission_wallets;
CREATE TRIGGER commission_wallet_low_balance_notification
BEFORE UPDATE OF balance_rupiah, debt_rupiah, is_active ON public.commission_wallets
FOR EACH ROW EXECUTE FUNCTION public.notify_commission_wallet_low_balance();

CREATE OR REPLACE FUNCTION public.recheck_commission_wallet_alerts_on_policy_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF NEW.low_balance_threshold_rupiah IS DISTINCT FROM OLD.low_balance_threshold_rupiah THEN
    -- Re-evaluate existing wallets immediately against the newly configured threshold.
    UPDATE public.commission_wallets
    SET balance_rupiah = balance_rupiah
    WHERE is_active = true;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.recheck_commission_wallet_alerts_on_policy_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS commission_wallet_policy_threshold_alert_check ON public.commission_wallet_policy_settings;
CREATE TRIGGER commission_wallet_policy_threshold_alert_check
AFTER UPDATE OF low_balance_threshold_rupiah ON public.commission_wallet_policy_settings
FOR EACH ROW EXECUTE FUNCTION public.recheck_commission_wallet_alerts_on_policy_change();

CREATE OR REPLACE FUNCTION public.recheck_commission_wallet_alerts_on_fee_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF NEW.is_enabled IS DISTINCT FROM OLD.is_enabled
     OR NEW.fee_percent IS DISTINCT FROM OLD.fee_percent THEN
    UPDATE public.commission_wallets
    SET balance_rupiah = balance_rupiah
    WHERE owner_type = NEW.owner_type AND is_active = true;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.recheck_commission_wallet_alerts_on_fee_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS commission_wallet_fee_alert_check ON public.commission_fee_settings;
CREATE TRIGGER commission_wallet_fee_alert_check
AFTER UPDATE OF is_enabled, fee_percent ON public.commission_fee_settings
FOR EACH ROW EXECUTE FUNCTION public.recheck_commission_wallet_alerts_on_fee_change();

-- Backfill one alert for active wallets already below threshold when this bundle is first applied.
UPDATE public.commission_wallets
SET balance_rupiah = balance_rupiah
WHERE is_active = true
  AND low_balance_alerted_at IS NULL
  AND (
    debt_rupiah > 0
    OR balance_rupiah <= COALESCE((
      SELECT p.low_balance_threshold_rupiah
      FROM public.commission_wallet_policy_settings p
      WHERE p.id = true
    ), 10000)
  );

NOTIFY pgrst, 'reload schema';
$bootstrap_sql_commission_wallet_alerts$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_commission_wallet_alerts$;
