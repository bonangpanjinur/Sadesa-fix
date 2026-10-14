-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: queues at most one push alert per incomplete payment-setup cycle.
-- ===== BEGIN SOURCE: 20261010150000_merchant_payment_setup_push_alert.sql =====
DO $bootstrap_do_merchant_payment_setup_push_alert$
BEGIN
  EXECUTE $bootstrap_sql_merchant_payment_setup_alert$
-- Alert approved merchants who have not configured a complete bank account or a QRIS image.
-- Push is queued only after the owner has at least one registered browser subscription.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS payment_setup_push_alerted_at timestamptz;

COMMENT ON COLUMN public.merchants.payment_setup_push_alerted_at IS
  'Prevents duplicate payment-setup push alerts until the merchant completes bank or QRIS settings.';

CREATE OR REPLACE FUNCTION public.enqueue_merchant_payment_setup_alert(p_merchant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_status text;
  v_registration_status text;
  v_bank_name text;
  v_bank_account_number text;
  v_bank_account_name text;
  v_qris_image_url text;
  v_alerted_at timestamptz;
  v_title text := 'Lengkapi pembayaran toko';
  v_message text := 'Tambahkan rekening bank lengkap atau unggah QRIS agar pelanggan dapat membayar langsung ke toko Anda.';
BEGIN
  SELECT m.user_id, m.status, m.registration_status,
         m.bank_name, m.bank_account_number, m.bank_account_name,
         m.qris_image_url, m.payment_setup_push_alerted_at
    INTO v_user_id, v_status, v_registration_status,
         v_bank_name, v_bank_account_number, v_bank_account_name,
         v_qris_image_url, v_alerted_at
  FROM public.merchants m
  WHERE m.id = p_merchant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF (NULLIF(trim(v_bank_name), '') IS NOT NULL
      AND NULLIF(trim(v_bank_account_number), '') IS NOT NULL
      AND NULLIF(trim(v_bank_account_name), '') IS NOT NULL)
     OR NULLIF(trim(v_qris_image_url), '') IS NOT NULL THEN
    IF v_alerted_at IS NOT NULL THEN
      UPDATE public.merchants SET payment_setup_push_alerted_at = NULL WHERE id = p_merchant_id;
    END IF;
    RETURN;
  END IF;

  IF v_status IS DISTINCT FROM 'ACTIVE'
     OR v_registration_status IS DISTINCT FROM 'APPROVED'
     OR v_user_id IS NULL
     OR v_alerted_at IS NOT NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.push_subscriptions ps WHERE ps.user_id = v_user_id
     ) THEN
    RETURN;
  END IF;

  -- Lock + nullable marker make the alert once-per-incomplete-configuration cycle.
  UPDATE public.merchants
  SET payment_setup_push_alerted_at = now()
  WHERE id = p_merchant_id AND payment_setup_push_alerted_at IS NULL;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  BEGIN
    PERFORM public.send_notification(
      v_user_id,
      v_title,
      v_message,
      'warning',
      '/merchant/settings'
    );
    INSERT INTO public.notification_delivery_jobs (
      recipient_id, channel, template_key, payload
    ) VALUES (
      v_user_id,
      'push',
      'merchant_payment_setup_required',
      jsonb_build_object(
        'title', v_title,
        'body', v_message,
        'url', '/merchant/settings',
        'data', jsonb_build_object(
          'type', 'merchant_payment_setup_required',
          'merchant_id', p_merchant_id::text
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.merchants SET payment_setup_push_alerted_at = NULL WHERE id = p_merchant_id;
    RAISE WARNING 'Merchant payment setup alert could not be queued for merchant %: %', p_merchant_id, SQLERRM;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_merchant_payment_setup_alert(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_merchant_payment_setup_alert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.enqueue_merchant_payment_setup_alert(NEW.id);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_payment_setup_alert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS merchant_payment_setup_alert_sync ON public.merchants;
CREATE TRIGGER merchant_payment_setup_alert_sync
AFTER INSERT OR UPDATE OF user_id, status, registration_status,
  bank_name, bank_account_number, bank_account_name, qris_image_url
ON public.merchants
FOR EACH ROW
EXECUTE FUNCTION public.sync_merchant_payment_setup_alert();

CREATE OR REPLACE FUNCTION public.notify_merchant_payment_setup_on_push_subscription()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_merchant_id uuid;
BEGIN
  FOR v_merchant_id IN
    SELECT m.id
    FROM public.merchants m
    WHERE m.user_id = NEW.user_id
      AND m.status = 'ACTIVE'
      AND m.registration_status = 'APPROVED'
  LOOP
    PERFORM public.enqueue_merchant_payment_setup_alert(v_merchant_id);
  END LOOP;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_merchant_payment_setup_on_push_subscription() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS push_subscription_merchant_payment_setup_alert ON public.push_subscriptions;
CREATE TRIGGER push_subscription_merchant_payment_setup_alert
AFTER INSERT OR UPDATE ON public.push_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.notify_merchant_payment_setup_on_push_subscription();

-- Notify existing approved stores that already have an active push subscription.
DO $$
DECLARE
  v_merchant_id uuid;
BEGIN
  FOR v_merchant_id IN
    SELECT m.id
    FROM public.merchants m
    WHERE m.status = 'ACTIVE'
      AND m.registration_status = 'APPROVED'
  LOOP
    PERFORM public.enqueue_merchant_payment_setup_alert(v_merchant_id);
  END LOOP;
END;
$$;
  $bootstrap_sql_merchant_payment_setup_alert$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_merchant_payment_setup_alert$;

-- ===== END SOURCE: 20261010150000_merchant_payment_setup_push_alert.sql =====
