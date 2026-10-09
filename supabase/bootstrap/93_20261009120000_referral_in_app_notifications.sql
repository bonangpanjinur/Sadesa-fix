-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_dc10e965ac11$
BEGIN
  EXECUTE $bootstrap_sql_dc10e965ac11$-- Notify referral owners about new commissions and payout status transitions.
-- Notifications are inserted transactionally with the source ledger/status update.

CREATE OR REPLACE FUNCTION public.notify_referral_commission_earned()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_link text;
  v_message text;
BEGIN
  IF NEW.entry_type <> 'EARNING' OR NEW.amount_rupiah <= 0 THEN
    RETURN NEW;
  END IF;

  v_link := CASE NEW.owner_role
    WHEN 'VERIFIKATOR' THEN '/verifikator/earnings?tab=referral'
    WHEN 'ADMIN_DESA' THEN '/desa/komisi-referral'
    ELSE NULL
  END;
  IF v_link IS NULL THEN
    RETURN NEW;
  END IF;

  v_message := format(
    'Komisi referral Rp%s tercatat dari fee merchant Rp%s. Nilai ini menunggu masa refund sampai %s sebelum tersedia untuk payout.',
    NEW.amount_rupiah::text,
    NEW.fee_collected_base_rupiah::text,
    to_char(NEW.release_at AT TIME ZONE 'Asia/Jakarta', 'DD-MM-YYYY HH24:MI')
  );

  INSERT INTO public.notifications (user_id, title, message, type, link, idempotency_key)
  VALUES (
    NEW.owner_user_id,
    'Komisi referral baru',
    left(v_message, 1000),
    'success',
    v_link,
    'referral:earning:' || NEW.id::text
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$$bootstrap_sql_dc10e965ac11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc10e965ac11$;

DO $bootstrap_do_b51688f1ef89$
BEGIN
  EXECUTE $bootstrap_sql_b51688f1ef89$REVOKE ALL ON FUNCTION public.notify_referral_commission_earned() FROM PUBLIC, anon, authenticated$bootstrap_sql_b51688f1ef89$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b51688f1ef89$;

DO $bootstrap_do_91de308e6e11$
BEGIN
  EXECUTE $bootstrap_sql_91de308e6e11$DROP TRIGGER IF EXISTS notify_referral_commission_earned ON public.merchant_referral_commission_ledger$bootstrap_sql_91de308e6e11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_91de308e6e11$;

DO $bootstrap_do_6808bb63b1a3$
BEGIN
  EXECUTE $bootstrap_sql_6808bb63b1a3$CREATE TRIGGER notify_referral_commission_earned
AFTER INSERT ON public.merchant_referral_commission_ledger
FOR EACH ROW
EXECUTE FUNCTION public.notify_referral_commission_earned()$bootstrap_sql_6808bb63b1a3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6808bb63b1a3$;

DO $bootstrap_do_d9cbd13080fe$
BEGIN
  EXECUTE $bootstrap_sql_d9cbd13080fe$CREATE OR REPLACE FUNCTION public.notify_referral_payout_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_title text;
  v_message text;
  v_link text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('APPROVED', 'REJECTED', 'PAID') THEN
    RETURN NEW;
  END IF;

  v_link := CASE NEW.owner_role
    WHEN 'VERIFIKATOR' THEN '/verifikator/earnings?tab=referral'
    WHEN 'ADMIN_DESA' THEN '/desa/komisi-referral'
    ELSE NULL
  END;
  IF v_link IS NULL THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'APPROVED' THEN
      v_title := 'Payout referral disetujui';
      v_message := format('Permintaan payout Rp%s disetujui. Admin akan melakukan transfer manual.', NEW.amount_rupiah::text);
    WHEN 'REJECTED' THEN
      v_title := 'Payout referral ditolak';
      v_message := format('Permintaan payout Rp%s ditolak.%s', NEW.amount_rupiah::text,
        CASE WHEN NULLIF(trim(COALESCE(NEW.admin_notes, '')), '') IS NULL THEN ''
          ELSE ' Catatan admin: ' || left(trim(NEW.admin_notes), 500) END);
    WHEN 'PAID' THEN
      v_title := 'Payout referral dibayar';
      v_message := format('Payout referral Rp%s telah dicatat dibayar. Referensi transfer: %s.',
        NEW.amount_rupiah::text, COALESCE(NULLIF(trim(NEW.payout_reference), ''), 'tidak tersedia'));
  END CASE;

  INSERT INTO public.notifications (user_id, title, message, type, link, idempotency_key)
  VALUES (
    NEW.owner_user_id,
    v_title,
    left(v_message, 1000),
    'withdrawal',
    v_link,
    'referral:payout:' || NEW.id::text || ':' || NEW.status
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$$bootstrap_sql_d9cbd13080fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9cbd13080fe$;

DO $bootstrap_do_fd6df38569e4$
BEGIN
  EXECUTE $bootstrap_sql_fd6df38569e4$REVOKE ALL ON FUNCTION public.notify_referral_payout_status_change() FROM PUBLIC, anon, authenticated$bootstrap_sql_fd6df38569e4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd6df38569e4$;

DO $bootstrap_do_535fe44bf9b2$
BEGIN
  EXECUTE $bootstrap_sql_535fe44bf9b2$DROP TRIGGER IF EXISTS notify_referral_payout_status_change ON public.merchant_referral_payout_requests$bootstrap_sql_535fe44bf9b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_535fe44bf9b2$;

DO $bootstrap_do_e91fbf1dd1fd$
BEGIN
  EXECUTE $bootstrap_sql_e91fbf1dd1fd$CREATE TRIGGER notify_referral_payout_status_change
AFTER UPDATE OF status ON public.merchant_referral_payout_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_referral_payout_status_change()$bootstrap_sql_e91fbf1dd1fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e91fbf1dd1fd$;
