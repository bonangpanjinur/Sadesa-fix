-- DesaMart canonical bootstrap bundle; generated from archive source migrations.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260929140000_auto_cancel_unanswered_transport_orders.sql .. 20260929140000_auto_cancel_unanswered_transport_orders.sql

-- ===== BEGIN SOURCE: 20260929140000_auto_cancel_unanswered_transport_orders.sql =====
-- Automatically close passenger rides and direct courier bookings that remain
-- unaccepted for five minutes. Runs independently of buyer/courier browser sessions.
CREATE OR REPLACE FUNCTION public.auto_cancel_unanswered_transport_orders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride record;
  v_order_id uuid;
  v_order public.orders%ROWTYPE;
  v_buyer_id uuid;
  v_cancelled integer := 0;
BEGIN
  -- Serialize against sequential ride dispatch and acceptance so a driver
  -- cannot accept a ride while the timeout worker is closing it.
  IF pg_try_advisory_xact_lock(7210953184926001) THEN
    UPDATE public.ride_request_offers offer
    SET status = 'EXPIRED',
        responded_at = COALESCE(offer.responded_at, now())
    WHERE offer.status = 'PENDING'
      AND EXISTS (
        SELECT 1
        FROM public.ride_requests ride
        WHERE ride.id = offer.ride_id
          AND (ride.status <> 'SEARCHING' OR ride.driver_id IS NOT NULL)
      );

    FOR v_ride IN
      SELECT r.id, r.passenger_id
      FROM public.ride_requests r
      WHERE r.status = 'SEARCHING'
        AND r.driver_id IS NULL
        AND r.created_at <= now() - interval '5 minutes'
      ORDER BY r.created_at ASC
      LIMIT 100
      FOR UPDATE SKIP LOCKED
    LOOP
      UPDATE public.ride_request_offers
      SET status = 'EXPIRED',
          responded_at = COALESCE(responded_at, now())
      WHERE ride_id = v_ride.id
        AND status = 'PENDING';

      UPDATE public.ride_requests
      SET status = 'CANCELLED',
          cancelled_at = now(),
          cancellation_reason = 'Tidak ada driver yang merespons dalam 5 menit.',
          updated_at = now()
      WHERE id = v_ride.id
        AND status = 'SEARCHING'
        AND driver_id IS NULL;

      IF FOUND THEN
        BEGIN
          PERFORM public.send_notification(
            v_ride.passenger_id,
            'Pesanan ojek dibatalkan otomatis',
            'Tidak ada driver yang merespons dalam 5 menit. Silakan buat pesanan baru.',
            'ride',
            '/ride/' || v_ride.id::text
          );
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ride timeout notification failed for %: %', v_ride.id, SQLERRM;
        END;
        v_cancelled := v_cancelled + 1;
      END IF;
    END LOOP;
  END IF;

  -- Process direct package-courier orders only. Lock the order and its offers
  -- with NOWAIT inside a savepoint: if an acceptance/dispatch is in flight,
  -- skip this order and let the next minute's run retry instead of racing it.
  FOR v_order_id IN
    SELECT o.id
    FROM public.orders o
    WHERE o.service_type = 'COURIER_DELIVERY'
      AND o.status = 'ASSIGNED'
      AND o.courier_id IS NULL
      AND COALESCE(o.scheduled_pickup, false) = false
      AND o.created_at <= now() - interval '5 minutes'
      AND NOT EXISTS (
        SELECT 1
        FROM public.delivery_assignments accepted
        WHERE accepted.order_id = o.id
          AND accepted.status = 'ACCEPTED'
      )
    ORDER BY o.created_at ASC
    LIMIT 100
  LOOP
    BEGIN
      SELECT * INTO v_order
      FROM public.orders
      WHERE id = v_order_id
      FOR UPDATE NOWAIT;

      IF NOT FOUND
         OR v_order.service_type <> 'COURIER_DELIVERY'
         OR v_order.status <> 'ASSIGNED'
         OR v_order.courier_id IS NOT NULL
         OR COALESCE(v_order.scheduled_pickup, false)
         OR v_order.created_at > now() - interval '5 minutes' THEN
        CONTINUE;
      END IF;

      -- Prevent a courier response from being committed while this order is
      -- canceled. NOWAIT avoids deadlock with a response already in progress.
      PERFORM 1
      FROM public.delivery_assignments da
      WHERE da.order_id = v_order_id
        AND da.status IN ('OFFERED', 'ACCEPTED')
      FOR UPDATE NOWAIT;

      IF EXISTS (
        SELECT 1
        FROM public.delivery_assignments accepted
        WHERE accepted.order_id = v_order_id
          AND accepted.status = 'ACCEPTED'
      ) THEN
        CONTINUE;
      END IF;

      UPDATE public.orders
      SET status = 'CANCELED',
          courier_id = NULL,
          cancelled_at = now(),
          cancelled_by = NULL,
          cancellation_reason = 'Tidak ada kurir yang merespons dalam 5 menit.',
          cancellation_type = 'SYSTEM',
          status_updated_at = now(),
          updated_at = now()
      WHERE id = v_order_id
        AND service_type = 'COURIER_DELIVERY'
        AND status = 'ASSIGNED'
        AND courier_id IS NULL
      RETURNING buyer_id INTO v_buyer_id;

      IF FOUND THEN
        UPDATE public.delivery_assignments
        SET status = 'CANCELED',
            responded_at = COALESCE(responded_at, now()),
            rejection_reason = 'Order dibatalkan otomatis karena tidak ada respons dalam 5 menit.',
            updated_at = now()
        WHERE order_id = v_order_id
          AND status = 'OFFERED';

        INSERT INTO public.order_status_history(order_id, from_status, to_status, actor_id, reason)
        VALUES (
          v_order_id,
          'ASSIGNED',
          'CANCELED',
          NULL,
          'Sistem membatalkan otomatis: tidak ada kurir yang merespons dalam 5 menit.'
        );

        BEGIN
          PERFORM public.send_notification(
            v_buyer_id,
            'Pesanan kurir dibatalkan otomatis',
            'Tidak ada kurir yang merespons dalam 5 menit. Silakan buat pesanan baru.',
            'order',
            '/orders/' || v_order_id::text || '/tracking'
          );
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'courier timeout notification failed for %: %', v_order_id, SQLERRM;
        END;
        v_cancelled := v_cancelled + 1;
      END IF;
    EXCEPTION
      WHEN lock_not_available THEN
        -- Another transaction is accepting or dispatching this order. Retry on
        -- the next scheduled run; no state changes from this block are kept.
        NULL;
    END;
  END LOOP;

  RETURN v_cancelled;
END;
$$;

REVOKE ALL ON FUNCTION public.auto_cancel_unanswered_transport_orders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_cancel_unanswered_transport_orders() TO service_role;
COMMENT ON FUNCTION public.auto_cancel_unanswered_transport_orders() IS
  'Cancels unaccepted passenger rides and unscheduled direct-courier bookings after five minutes; scheduled every minute by pg_cron.';

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $bootstrap_do_auto_cancel_unanswered_transport_orders$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'auto-cancel-unanswered-transport-orders'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'auto-cancel-unanswered-transport-orders',
    '* * * * *',
    'SELECT public.auto_cancel_unanswered_transport_orders();'
  );
END;
$bootstrap_do_auto_cancel_unanswered_transport_orders$;

NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260929140000_auto_cancel_unanswered_transport_orders.sql =====
