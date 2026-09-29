-- Recover unaccepted transport offers when a courier connection disappears.
-- Courier location updates are a server-verifiable heartbeat (30s client cadence,
-- 90s freshness window). The minute worker advances rides and reassigns direct
-- courier delivery offers without requiring a buyer or courier page to stay open.

CREATE OR REPLACE FUNCTION public.dispatch_courier_order_internal(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_courier record;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_assignment_id uuid;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'NOT_FOUND');
  END IF;

  IF v_order.status <> 'ASSIGNED' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  IF v_order.pickup_lat IS NULL OR v_order.pickup_lng IS NULL THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'NOT_APPLICABLE');
  END IF;

  -- The five-minute deadline is measured from order creation for direct courier
  -- orders, not reset each time the buyer tracking page retries dispatch.
  IF v_order.service_type = 'COURIER_DELIVERY'
     AND v_order.created_at <= now() - interval '5 minutes' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_order.status, 'dispatch_status', 'TIMED_OUT');
  END IF;

  SELECT da.* INTO v_assignment
  FROM public.delivery_assignments da
  WHERE da.order_id = p_order_id
    AND da.status = 'OFFERED'
  ORDER BY da.offered_at DESC
  LIMIT 1
  FOR UPDATE NOWAIT;

  IF FOUND AND v_assignment.expires_at > now() THEN
    UPDATE public.orders
    SET courier_id = v_assignment.courier_id,
        assigned_at = COALESCE(assigned_at, now()),
        status_updated_at = now(),
        updated_at = now()
    WHERE id = p_order_id;
    RETURN jsonb_build_object('order_id', p_order_id, 'assignment_id', v_assignment.id, 'dispatch_status', 'OFFERED');
  END IF;

  IF FOUND THEN
    UPDATE public.delivery_assignments
    SET status = 'EXPIRED',
        responded_at = COALESCE(responded_at, now()),
        rejection_reason = 'Tawaran kedaluwarsa sebelum kurir merespons.',
        updated_at = now()
    WHERE id = v_assignment.id
      AND status = 'OFFERED';

    UPDATE public.orders
    SET courier_rejected_ids = CASE
          WHEN v_assignment.courier_id = ANY(COALESCE(courier_rejected_ids, '{}'::uuid[]))
            THEN COALESCE(courier_rejected_ids, '{}'::uuid[])
          ELSE array_append(COALESCE(courier_rejected_ids, '{}'::uuid[]), v_assignment.courier_id)
        END,
        courier_id = NULL,
        assigned_at = NULL,
        status_updated_at = now(),
        updated_at = now()
    WHERE id = p_order_id
    RETURNING * INTO v_order;
  END IF;

  SELECT
    c.id,
    c.user_id,
    6371 * 2 * asin(sqrt(LEAST(1::double precision, GREATEST(0::double precision,
      power(sin(radians(c.current_lat::double precision - v_order.pickup_lat::double precision) / 2), 2)
      + cos(radians(v_order.pickup_lat::double precision))
        * cos(radians(c.current_lat::double precision))
        * power(sin(radians(c.current_lng::double precision - v_order.pickup_lng::double precision) / 2), 2)
    )))) AS distance_km
  INTO v_courier
  FROM public.couriers c
  WHERE c.user_id IS NOT NULL
    AND c.status = 'ACTIVE'
    AND c.registration_status = 'APPROVED'
    AND c.is_available IS TRUE
    AND c.current_lat IS NOT NULL
    AND c.current_lng IS NOT NULL
    AND c.last_location_update >= now() - interval '90 seconds'
    AND NOT (c.id = ANY(COALESCE(v_order.courier_rejected_ids, '{}'::uuid[])))
    AND NOT EXISTS (
      SELECT 1
      FROM public.delivery_assignments attempted
      WHERE attempted.order_id = p_order_id
        AND attempted.courier_id = c.id
    )
  ORDER BY distance_km ASC, c.id ASC
  LIMIT 1;

  IF NOT FOUND THEN
    IF v_order.courier_id IS NOT NULL OR v_order.assigned_at IS NOT NULL THEN
      UPDATE public.orders
      SET courier_id = NULL,
          assigned_at = NULL,
          status_updated_at = now(),
          updated_at = now()
      WHERE id = p_order_id;
    END IF;
    RETURN jsonb_build_object('order_id', p_order_id, 'dispatch_status', 'WAITING_FOR_COURIER');
  END IF;

  INSERT INTO public.delivery_assignments(order_id, courier_id, offered_at, expires_at)
  VALUES (p_order_id, v_courier.id, now(), now() + interval '5 minutes')
  RETURNING id INTO v_assignment_id;

  UPDATE public.orders
  SET courier_id = v_courier.id,
      assigned_at = now(),
      status_updated_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  BEGIN
    PERFORM public.send_notification(
      v_courier.user_id,
      'Pesanan Kurir Baru',
      'Ada pesanan kurir baru di sekitar lokasi Anda. Terima atau tolak melalui aplikasi.',
      'order',
      '/courier/deliveries'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'courier offer notification failed for order %: %', p_order_id, SQLERRM;
  END;

  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'assignment_id', v_assignment_id,
    'courier_id', v_courier.id,
    'dispatch_status', 'OFFERED'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.dispatch_courier_order_internal(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order_internal(uuid) TO service_role;

-- Keep the existing buyer/admin RPC contract, but ensure its candidate list is
-- filtered by a fresh GPS heartbeat and delegate all offer logic to the same
-- server-only dispatcher used by the background worker.
CREATE OR REPLACE FUNCTION public.dispatch_courier_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (buyer_id = auth.uid() OR public.is_admin())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order access denied' USING ERRCODE = '42501';
  END IF;

  RETURN public.dispatch_courier_order_internal(p_order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.dispatch_courier_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_courier_order(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.process_unresponsive_transport_offers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride_id uuid;
  v_ride_offer_id uuid;
  v_order_id uuid;
  v_order public.orders%ROWTYPE;
  v_assignment public.delivery_assignments%ROWTYPE;
  v_courier public.couriers%ROWTYPE;
  v_courier_stale boolean;
  v_order_timed_out boolean;
  v_dispatch_result jsonb;
  v_processed integer := 0;
BEGIN
  -- Move unanswered ride offers to the next fresh, nearest courier even when
  -- every courier browser is disconnected. A live offer is left untouched.
  IF pg_try_advisory_xact_lock(7210953184926001) THEN
    FOR v_ride_id IN
      SELECT r.id
      FROM public.ride_requests r
      WHERE r.status = 'SEARCHING'
        AND r.driver_id IS NULL
        AND r.created_at > now() - interval '5 minutes'
        AND NOT EXISTS (
          SELECT 1
          FROM public.ride_request_offers pending_offer
          WHERE pending_offer.ride_id = r.id
            AND pending_offer.status = 'PENDING'
            AND pending_offer.expires_at > now()
        )
      ORDER BY r.created_at ASC
      LIMIT 100
    LOOP
      v_ride_offer_id := public.dispatch_next_ride_offer(v_ride_id);
      IF v_ride_offer_id IS NOT NULL THEN
        v_processed := v_processed + 1;
      END IF;
    END LOOP;
  END IF;

  -- Retry direct package orders with no live offer, and promptly release a
  -- courier whose availability/GPS heartbeat went stale. Do not touch accepted
  -- assignments. The 5-minute order deadline is enforced by the following
  -- auto-cancel call in the same cron transaction.
  FOR v_order_id IN
    SELECT o.id
    FROM public.orders o
    WHERE o.service_type = 'COURIER_DELIVERY'
      AND o.status = 'ASSIGNED'
      AND NOT EXISTS (
        SELECT 1
        FROM public.delivery_assignments accepted
        WHERE accepted.order_id = o.id
          AND accepted.status = 'ACCEPTED'
      )
      AND (
        o.created_at <= now() - interval '5 minutes'
        OR NOT EXISTS (
          SELECT 1
          FROM public.delivery_assignments live_offer
          WHERE live_offer.order_id = o.id
            AND live_offer.status = 'OFFERED'
            AND live_offer.expires_at > now()
        )
        OR EXISTS (
          SELECT 1
          FROM public.delivery_assignments stale_offer
          LEFT JOIN public.couriers c ON c.id = stale_offer.courier_id
          WHERE stale_offer.order_id = o.id
            AND stale_offer.status = 'OFFERED'
            AND (
              stale_offer.expires_at <= now()
              OR c.id IS NULL
              OR c.status <> 'ACTIVE'
              OR c.registration_status <> 'APPROVED'
              OR c.is_available IS DISTINCT FROM true
              OR c.current_lat IS NULL
              OR c.current_lng IS NULL
              OR c.last_location_update IS NULL
              OR c.last_location_update < now() - interval '90 seconds'
            )
        )
      )
    ORDER BY o.created_at ASC
    LIMIT 100
  LOOP
    BEGIN
      SELECT * INTO v_order
      FROM public.orders
      WHERE id = v_order_id
      AND service_type = 'COURIER_DELIVERY'
        AND status = 'ASSIGNED'
      FOR UPDATE NOWAIT;

      IF NOT FOUND THEN
        CONTINUE;
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.delivery_assignments accepted
        WHERE accepted.order_id = v_order_id
          AND accepted.status = 'ACCEPTED'
      ) THEN
        CONTINUE;
      END IF;

      v_order_timed_out := v_order.created_at <= now() - interval '5 minutes';
      v_assignment := NULL;
      v_courier := NULL;

      SELECT * INTO v_assignment
      FROM public.delivery_assignments da
      WHERE da.order_id = v_order_id
        AND da.status = 'OFFERED'
      ORDER BY da.offered_at DESC
      LIMIT 1
      FOR UPDATE NOWAIT;

      IF FOUND THEN
        SELECT * INTO v_courier
        FROM public.couriers c
        WHERE c.id = v_assignment.courier_id;

        v_courier_stale := NOT FOUND
          OR v_courier.status <> 'ACTIVE'
          OR v_courier.registration_status <> 'APPROVED'
          OR v_courier.is_available IS DISTINCT FROM true
          OR v_courier.current_lat IS NULL
          OR v_courier.current_lng IS NULL
          OR v_courier.last_location_update IS NULL
          OR v_courier.last_location_update < now() - interval '90 seconds';

        IF NOT v_order_timed_out
           AND v_assignment.expires_at > now()
           AND NOT v_courier_stale THEN
          CONTINUE;
        END IF;

        UPDATE public.delivery_assignments
        SET status = 'EXPIRED',
            responded_at = COALESCE(responded_at, now()),
            rejection_reason = CASE
              WHEN v_order_timed_out THEN 'Batas respons pesanan 5 menit tercapai.'
              WHEN v_courier_stale THEN 'Offer dilepas otomatis karena koneksi driver atau heartbeat lokasi terputus.'
              ELSE 'Offer kedaluwarsa sebelum kurir merespons.'
            END,
            updated_at = now()
        WHERE id = v_assignment.id
          AND status = 'OFFERED';

        UPDATE public.orders
        SET courier_rejected_ids = CASE
              WHEN v_assignment.courier_id = ANY(COALESCE(courier_rejected_ids, '{}'::uuid[]))
                THEN COALESCE(courier_rejected_ids, '{}'::uuid[])
              ELSE array_append(COALESCE(courier_rejected_ids, '{}'::uuid[]), v_assignment.courier_id)
            END,
            courier_id = NULL,
            assigned_at = NULL,
            status_updated_at = now(),
            updated_at = now()
        WHERE id = v_order_id
          AND status = 'ASSIGNED'
        RETURNING * INTO v_order;
      ELSIF v_order.courier_id IS NOT NULL OR v_order.assigned_at IS NOT NULL THEN
        -- Repair legacy/orphaned assignment pointers so the normal dispatcher
        -- can select a different courier and the timeout worker can close it.
        UPDATE public.orders
        SET courier_id = NULL,
            assigned_at = NULL,
            status_updated_at = now(),
            updated_at = now()
        WHERE id = v_order_id
          AND status = 'ASSIGNED'
        RETURNING * INTO v_order;
      END IF;

      IF v_order_timed_out THEN
        CONTINUE;
      END IF;

      v_dispatch_result := public.dispatch_courier_order_internal(v_order_id);
      IF v_dispatch_result ->> 'dispatch_status' = 'OFFERED' THEN
        v_processed := v_processed + 1;
      END IF;
    EXCEPTION
      WHEN lock_not_available THEN
        -- An accept/dispatch transaction owns a row lock. Let it finish and
        -- retry on the next minute instead of racing or deadlocking.
        NULL;
    END;
  END LOOP;

  RETURN v_processed;
END;
$$;
REVOKE ALL ON FUNCTION public.process_unresponsive_transport_offers() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_unresponsive_transport_offers() TO service_role;
COMMENT ON FUNCTION public.process_unresponsive_transport_offers() IS
  'Advances expired ride offers and reassigns direct courier offers when the targeted courier is unavailable or has no location heartbeat for 90 seconds. Scheduled before the five-minute auto-cancel worker.';

-- Run retry before cancellation in the same cron execution: disconnected couriers
-- are replaced first; orders that remain unaccepted after five minutes are then
-- canceled by the existing authoritative timeout function.
DO $bootstrap_do_transport_connection_drop_offer_recovery$
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
    'DO $transport_offer_timeout_pipeline$ BEGIN PERFORM public.process_unresponsive_transport_offers(); PERFORM public.auto_cancel_unanswered_transport_orders(); END $transport_offer_timeout_pipeline$;'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE;
END
$bootstrap_do_transport_connection_drop_offer_recovery$;

NOTIFY pgrst, 'reload schema';
