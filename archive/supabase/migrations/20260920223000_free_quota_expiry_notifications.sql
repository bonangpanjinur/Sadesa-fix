-- Daily reminder for merchants whose free quota subscription expires in 7 days.
-- The delivery ledger makes the operation idempotent across repeated cron runs.

CREATE TABLE IF NOT EXISTS public.merchant_quota_expiry_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  reminder_days integer NOT NULL DEFAULT 7,
  sent_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, reminder_days)
);

ALTER TABLE public.merchant_quota_expiry_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view quota expiry notification ledger"
  ON public.merchant_quota_expiry_notifications;
CREATE POLICY "Admins can view quota expiry notification ledger"
ON public.merchant_quota_expiry_notifications
FOR SELECT
USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.notify_free_quota_expiring_merchants()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription record;
  v_claimed_id uuid;
  v_sent_count integer := 0;
  v_remaining_quota integer;
BEGIN
  FOR v_subscription IN
    SELECT
      ms.id,
      ms.merchant_id,
      ms.transaction_quota,
      ms.used_quota,
      ms.expired_at,
      m.user_id,
      m.name AS merchant_name
    FROM public.merchant_subscriptions ms
    JOIN public.transaction_packages tp ON tp.id = ms.package_id
    JOIN public.merchants m ON m.id = ms.merchant_id
    WHERE ms.status = 'ACTIVE'
      AND tp.name = 'Paket Gratis 2 Bulan'
      AND ms.expired_at > now() + interval '6 days'
      AND ms.expired_at <= now() + interval '7 days'
      AND m.user_id IS NOT NULL
  LOOP
    v_claimed_id := NULL;

    INSERT INTO public.merchant_quota_expiry_notifications (subscription_id, reminder_days)
    VALUES (v_subscription.id, 7)
    ON CONFLICT (subscription_id, reminder_days) DO NOTHING
    RETURNING id INTO v_claimed_id;

    IF v_claimed_id IS NOT NULL THEN
      v_remaining_quota := GREATEST(0, v_subscription.transaction_quota - v_subscription.used_quota);

      PERFORM public.send_notification(
        v_subscription.user_id,
        'Kuota gratis segera berakhir',
        format(
          'Paket gratis toko %s akan berakhir dalam 7 hari pada %s. Sisa kuota Anda %s transaksi. Segera pilih paket lanjutan agar penjualan tetap berjalan.',
          v_subscription.merchant_name,
          to_char(v_subscription.expired_at AT TIME ZONE 'Asia/Jakarta', 'DD FMMonth YYYY'),
          v_remaining_quota
        ),
        'warning',
        '/merchant/subscription'
      );

      v_sent_count := v_sent_count + 1;
    END IF;
  END LOOP;

  RETURN v_sent_count;
END;
$$;

COMMENT ON FUNCTION public.notify_free_quota_expiring_merchants() IS
  'Sends one in-app reminder per free merchant subscription when it enters the 7-day expiry window.';

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'free-quota-expiry-reminders') THEN
    PERFORM cron.unschedule('free-quota-expiry-reminders');
  END IF;
END
$$;

SELECT cron.schedule(
  'free-quota-expiry-reminders',
  '15 0 * * *',
  $$SELECT public.notify_free_quota_expiring_merchants()$$
);
