-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 17_20260907030000_marketplace_pos_stock_ledger.sql .. 31_20260908180000_ride_status_transition.sql

-- ===== BEGIN BUNDLE: 17_20260907030000_marketplace_pos_stock_ledger.sql =====
-- Cross-channel stock ledger for marketplace reservations.
--
-- POS-linked products reserve physical stock per outlet instead of only
-- incrementing products.reserved_stock. The marketplace projection remains
-- products.stock, while this table is the durable allocation/audit record.

CREATE TABLE IF NOT EXISTS public.marketplace_stock_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.marketplace_stock_reservations(id) ON DELETE CASCADE,
  reservation_item_id uuid NOT NULL REFERENCES public.marketplace_stock_reservation_items(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  pos_product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE RESTRICT,
  quantity numeric NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released', 'consumed', 'expired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  consumed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_marketplace_allocations_reservation
  ON public.marketplace_stock_allocations(reservation_id, status);
CREATE INDEX IF NOT EXISTS idx_marketplace_allocations_outlet_product
  ON public.marketplace_stock_allocations(tenant_id, outlet_id, pos_product_id, status);

ALTER TABLE public.marketplace_stock_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own marketplace stock allocations" ON public.marketplace_stock_allocations;
CREATE POLICY "Users view own marketplace stock allocations"
  ON public.marketplace_stock_allocations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.marketplace_stock_reservations r
      JOIN public.orders o ON o.id = r.order_id
      WHERE r.id = reservation_id
        AND (
          r.buyer_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.merchants m
            WHERE m.id = o.merchant_id AND m.user_id = auth.uid()
          )
          OR public.is_admin()
        )
    )
  );

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reservation_id uuid;
  v_input jsonb;
  v_product public.products%ROWTYPE;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty integer;
  v_total integer := 0;
  v_existing public.marketplace_stock_reservations%ROWTYPE;
  v_tenant_id uuid;
  v_pos_product_id uuid;
  v_item_id uuid;
  v_remaining numeric;
  v_available numeric;
  v_allocated numeric;
  v_stock record;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND OR lower(COALESCE(v_order.status, '')) IN
     ('cancelled', 'canceled', 'rejected', 'refunded') THEN
    RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'reservation_id', v_existing.id,
      'status', v_existing.status,
      'duplicate', true
    );
  END IF;

  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at)
  VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute'))
  RETURNING id INTO v_reservation_id;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::integer, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_product_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not found' USING ERRCODE = '23503';
    END IF;

    INSERT INTO public.marketplace_stock_reservation_items(
      reservation_id, product_id, variant_id, quantity
    )
    VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty)
    RETURNING id INTO v_item_id;

    -- A POS-linked product with no variant uses outlet stock as its physical
    -- source. Allocate deterministically so concurrent buyers lock the same
    -- rows in the same order and cannot oversell an outlet.
    v_tenant_id := NULL;
    v_pos_product_id := NULL;
    IF v_variant_id IS NULL THEN
      SELECT pt.id, pp.id
      INTO v_tenant_id, v_pos_product_id
      FROM public.pos_tenants pt
      JOIN public.pos_products pp
        ON pp.tenant_id = pt.id
       AND pp.merchant_product_id = v_product_id
       AND pp.is_active = true
      WHERE pt.merchant_id = v_order.merchant_id
        AND pt.is_active = true
      ORDER BY pt.created_at, pp.created_at
      LIMIT 1;
    END IF;

    IF v_pos_product_id IS NOT NULL THEN
      v_remaining := v_qty;
      FOR v_stock IN
        SELECT ps.id, ps.outlet_id, ps.quantity, COALESCE(ps.reserved_quantity, 0) AS reserved_quantity
        FROM public.pos_stock ps
        JOIN public.pos_outlets po
          ON po.id = ps.outlet_id
         AND po.tenant_id = ps.tenant_id
         AND po.is_active = true
        WHERE ps.tenant_id = v_tenant_id
          AND ps.product_id = v_pos_product_id
          AND ps.variant_id IS NULL
        ORDER BY ps.outlet_id, ps.id
        FOR UPDATE
      LOOP
        EXIT WHEN v_remaining <= 0;
        v_available := GREATEST(v_stock.quantity - v_stock.reserved_quantity, 0);
        v_allocated := LEAST(v_available, v_remaining);
        IF v_allocated > 0 THEN
          UPDATE public.pos_stock
          SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_allocated,
              updated_at = now()
          WHERE id = v_stock.id;

          INSERT INTO public.marketplace_stock_allocations(
            reservation_id, reservation_item_id, tenant_id, pos_product_id,
            product_id, outlet_id, quantity
          )
          VALUES (
            v_reservation_id, v_item_id, v_tenant_id, v_pos_product_id,
            v_product_id, v_stock.outlet_id, v_allocated
          );
          v_remaining := v_remaining - v_allocated;
        END IF;
      END LOOP;

      IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Insufficient POS outlet stock' USING ERRCODE = '23514';
      END IF;
    ELSE
      -- Legacy marketplace-only products retain their existing reservation
      -- counter and continue to use the marketplace stock lifecycle.
      IF v_product.stock - v_product.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products
      SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_product_id;
    END IF;
    v_total := v_total + v_qty;
  END LOOP;

  RETURN jsonb_build_object(
    'reservation_id', v_reservation_id,
    'status', 'active',
    'quantity', v_total,
    'expires_at', p_expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(
  p_order_id uuid,
  p_status text DEFAULT 'released'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_res
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()
  ) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer
     AND NOT EXISTS (
       SELECT 1 FROM public.orders o
       JOIN public.merchants m ON m.id = o.merchant_id
       WHERE o.id = p_order_id AND m.user_id = auth.uid()
     )
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501';
  END IF;
  IF v_res.status <> 'active' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status);
  END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NULL;
    UPDATE public.marketplace_stock_allocations
    SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
        released_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.*
    FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (
        SELECT 1 FROM public.marketplace_stock_allocations a
        WHERE a.reservation_item_id = i.id
      )
  LOOP
    UPDATE public.products
    SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity),
        updated_at = now()
    WHERE id = v_item.product_id;
  END LOOP;

  UPDATE public.marketplace_stock_reservations
  SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
      released_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_product public.products%ROWTYPE;
BEGIN
  SELECT * INTO v_res
  FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true);
  END IF;
  IF v_res.status <> 'active' THEN
    RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status);
  END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_allocation.quantity, 0),
        reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NULL;
    UPDATE public.marketplace_stock_allocations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.*
    FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (
        SELECT 1 FROM public.marketplace_stock_allocations a
        WHERE a.reservation_item_id = i.id
      )
  LOOP
    SELECT * INTO v_product
    FROM public.products
    WHERE id = v_item.product_id
    FOR UPDATE;
    IF NOT FOUND OR v_product.reserved_stock < v_item.quantity
       OR v_product.stock < v_item.quantity THEN
      RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514';
    END IF;
    UPDATE public.products
    SET stock = stock - v_item.quantity,
        reserved_stock = reserved_stock - v_item.quantity,
        sold_count = COALESCE(sold_count, 0) + v_item.quantity,
        updated_at = now()
    WHERE id = v_item.product_id;
  END LOOP;

  UPDATE public.marketplace_stock_reservations
  SET status = 'consumed', consumed_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;
-- ===== END BUNDLE: 17_20260907030000_marketplace_pos_stock_ledger.sql =====

-- ===== BEGIN BUNDLE: 18_20260907040000_live_chat_realtime.sql =====
-- Live chat realtime foundation.
-- This is intentionally additive: legacy chat_messages columns and policies
-- remain available while clients are migrated to conversations.

CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  context_type text NOT NULL CHECK (context_type IN ('order', 'ride')),
  order_id uuid NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  ride_request_id uuid NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  conversation_type text NOT NULL CHECK (conversation_type IN (
    'buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier'
  )),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed', 'archived')),
  last_message_id uuid NULL,
  last_message_at timestamptz NULL,
  closed_at timestamptz NULL,
  retention_until timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_order_type_uidx
  ON public.chat_conversations(order_id, conversation_type)
  WHERE order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_ride_type_uidx
  ON public.chat_conversations(ride_request_id, conversation_type)
  WHERE ride_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS chat_conversations_last_message_idx
  ON public.chat_conversations(last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS public.chat_participants (
  conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('buyer', 'merchant', 'courier', 'passenger')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz NULL,
  last_read_at timestamptz NULL,
  last_read_message_id uuid NULL,
  muted_until timestamptz NULL,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_participants_user_idx
  ON public.chat_participants(user_id, left_at);

ALTER TABLE public.chat_messages
  ALTER COLUMN order_id DROP NOT NULL;
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS conversation_id uuid NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS body text NULL,
  ADD COLUMN IF NOT EXISTS attachment_path text NULL,
  ADD COLUMN IF NOT EXISTS client_message_id uuid NULL,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;

UPDATE public.chat_messages
SET body = message
WHERE body IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_body_length_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_body_length_check
      CHECK (length(trim(COALESCE(body, message))) BETWEEN 1 AND 4000);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_message_type_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_message_type_check
      CHECK (message_type IN ('text'));
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS chat_messages_sender_client_uidx
  ON public.chat_messages(sender_id, client_message_id)
  WHERE client_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS chat_messages_conversation_cursor_idx
  ON public.chat_messages(conversation_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS chat_messages_sender_created_idx
  ON public.chat_messages(sender_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_message_reads (
  message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS chat_message_reads_user_idx
  ON public.chat_message_reads(user_id, read_at DESC);

CREATE OR REPLACE FUNCTION public.chat_is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = p_user_id
      AND role IN ('admin', 'admin_desa')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_chat_conversation_participant(
  p_conversation_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_domain_participants(
  p_context_type text,
  p_order_id uuid,
  p_ride_request_id uuid,
  p_conversation_type text
)
RETURNS TABLE(user_id uuid, role text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_context_type = 'order' THEN
    RETURN QUERY
    SELECT o.buyer_id, 'buyer'::text
    FROM public.orders o
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_merchant'
    UNION ALL
    SELECT m.user_id, 'merchant'::text
    FROM public.orders o
    JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_merchant'
    UNION ALL
    SELECT o.buyer_id, 'buyer'::text
    FROM public.orders o
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_courier'
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.orders o
    JOIN public.couriers c ON c.id = o.courier_id
    WHERE o.id = p_order_id AND p_conversation_type = 'buyer_courier'
    UNION ALL
    SELECT m.user_id, 'merchant'::text
    FROM public.orders o
    JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND p_conversation_type = 'merchant_courier'
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.orders o
    JOIN public.couriers c ON c.id = o.courier_id
    WHERE o.id = p_order_id AND p_conversation_type = 'merchant_courier';
  ELSIF p_context_type = 'ride' AND p_conversation_type = 'passenger_courier' THEN
    RETURN QUERY
    SELECT r.passenger_id, 'passenger'::text
    FROM public.ride_requests r
    WHERE r.id = p_ride_request_id
    UNION ALL
    SELECT c.user_id, 'courier'::text
    FROM public.ride_requests r
    JOIN public.couriers c ON c.id = r.driver_id
    WHERE r.id = p_ride_request_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_or_create_chat_conversation(
  p_context_type text,
  p_order_id uuid DEFAULT NULL,
  p_ride_request_id uuid DEFAULT NULL,
  p_conversation_type text DEFAULT 'buyer_merchant'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_participant_count integer;
  v_caller_is_participant boolean;
BEGIN
  IF p_context_type NOT IN ('order', 'ride')
     OR (p_context_type = 'order' AND p_order_id IS NULL)
     OR (p_context_type = 'ride' AND p_ride_request_id IS NULL)
     OR (p_context_type = 'order' AND p_ride_request_id IS NOT NULL)
     OR (p_context_type = 'ride' AND p_order_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'invalid chat context' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.chat_domain_participants(
      p_context_type, p_order_id, p_ride_request_id, p_conversation_type
    )
  ) THEN
    RAISE EXCEPTION 'chat context or participants not found' USING ERRCODE = '42501';
  END IF;

  SELECT c.id INTO v_conversation_id
  FROM public.chat_conversations c
  WHERE ((p_context_type = 'order' AND c.order_id = p_order_id)
      OR (p_context_type = 'ride' AND c.ride_request_id = p_ride_request_id))
    AND c.conversation_type = p_conversation_type
  LIMIT 1;

  IF v_conversation_id IS NULL THEN
    INSERT INTO public.chat_conversations (
      context_type, order_id, ride_request_id, conversation_type
    )
    VALUES (p_context_type, p_order_id, p_ride_request_id, p_conversation_type)
    RETURNING id INTO v_conversation_id;
  END IF;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  SELECT v_conversation_id, p.user_id, p.role
  FROM public.chat_domain_participants(
    p_context_type, p_order_id, p_ride_request_id, p_conversation_type
  ) p
  WHERE p.user_id IS NOT NULL
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  SELECT count(*) INTO v_participant_count
  FROM public.chat_participants
  WHERE conversation_id = v_conversation_id AND left_at IS NULL;
  SELECT public.is_chat_conversation_participant(v_conversation_id, auth.uid())
    INTO v_caller_is_participant;

  IF NOT COALESCE(v_caller_is_participant, false) AND NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  RETURN v_conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_chat_conversation_read(
  p_conversation_id uuid,
  p_message_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_participants (
    conversation_id, user_id, role, last_read_at, last_read_message_id
  )
  SELECT p_conversation_id, auth.uid(), role, now(), p_message_id
  FROM public.chat_participants
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid()
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET last_read_at = now(), last_read_message_id = COALESCE(p_message_id, chat_participants.last_read_message_id);

  IF p_message_id IS NOT NULL THEN
    INSERT INTO public.chat_message_reads (message_id, user_id)
    SELECT p_message_id, auth.uid()
    WHERE EXISTS (
      SELECT 1 FROM public.chat_messages
      WHERE id = p_message_id AND conversation_id = p_conversation_id
    )
    ON CONFLICT (message_id, user_id) DO UPDATE SET read_at = now();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_chat_unread_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)
  FROM public.chat_messages m
  JOIN public.chat_participants p
    ON p.conversation_id = m.conversation_id
   AND p.user_id = auth.uid()
   AND p.left_at IS NULL
  WHERE m.sender_id <> auth.uid()
    AND m.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.chat_message_reads r
      WHERE r.message_id = m.id AND r.user_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public.chat_touch_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL THEN
    UPDATE public.chat_conversations
    SET last_message_id = NEW.id,
        last_message_at = NEW.created_at,
        updated_at = now()
    WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_chat_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL AND (
    SELECT count(*)
    FROM public.chat_messages m
    WHERE m.sender_id = NEW.sender_id
      AND m.conversation_id IS NOT NULL
      AND m.created_at > now() - interval '1 minute'
  ) >= 30 THEN
    RAISE EXCEPTION 'chat rate limit exceeded' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_touch_conversation ON public.chat_messages;
CREATE TRIGGER chat_messages_touch_conversation
AFTER INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.chat_touch_conversation();

DROP TRIGGER IF EXISTS chat_messages_rate_limit ON public.chat_messages;
CREATE TRIGGER chat_messages_rate_limit
BEFORE INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.enforce_chat_rate_limit();

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recipient record;
  sender_name text;
  preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(p.full_name, ''),
    NULLIF(m.name, ''),
    NULLIF(c.name, ''),
    'Pengguna'
  )
  INTO sender_name
  FROM public.profiles p
  FULL JOIN public.merchants m ON m.user_id = NEW.sender_id
  FULL JOIN public.couriers c ON c.user_id = NEW.sender_id
  WHERE p.user_id = NEW.sender_id
     OR m.user_id = NEW.sender_id
     OR c.user_id = NEW.sender_id
  LIMIT 1;

  preview := left(
    regexp_replace(trim(COALESCE(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
    120
  );

  FOR recipient IN
    SELECT p.user_id
    FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id
      AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL
      AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    PERFORM public.send_notification(
      recipient.user_id,
      COALESCE(sender_name, 'Pesan baru'),
      preview,
      'chat',
      '/buyer/chat'
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_notify_recipient ON public.chat_messages;
CREATE TRIGGER chat_messages_notify_recipient
AFTER INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Chat participants can view conversations" ON public.chat_conversations;
CREATE POLICY "Chat participants can view conversations"
ON public.chat_conversations FOR SELECT
USING (
  public.is_chat_conversation_participant(id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Chat participants can view participant rows" ON public.chat_participants;
CREATE POLICY "Chat participants can view participant rows"
ON public.chat_participants FOR SELECT
USING (
  public.is_chat_conversation_participant(conversation_id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Users can update own chat read state" ON public.chat_participants;
CREATE POLICY "Users can update own chat read state"
ON public.chat_participants FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Chat participants can view message reads" ON public.chat_message_reads;
CREATE POLICY "Chat participants can view message reads"
ON public.chat_message_reads FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.chat_messages m
    WHERE m.id = message_id
      AND public.is_chat_conversation_participant(m.conversation_id, auth.uid())
  )
  OR public.chat_is_admin(auth.uid())
);

DROP POLICY IF EXISTS "Users can insert own message reads" ON public.chat_message_reads;
CREATE POLICY "Users can insert own message reads"
ON public.chat_message_reads FOR INSERT
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Conversation participants can send messages" ON public.chat_messages;
CREATE POLICY "Conversation participants can send messages"
ON public.chat_messages FOR INSERT
WITH CHECK (
  auth.uid() = sender_id
  AND conversation_id IS NOT NULL
  AND public.is_chat_conversation_participant(conversation_id, auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.chat_conversations c
    WHERE c.id = conversation_id AND c.status = 'active'
  )
  AND COALESCE(body, message) IS NOT NULL
  AND length(trim(COALESCE(body, message))) BETWEEN 1 AND 4000
);

DROP POLICY IF EXISTS "Participants can view conversation messages" ON public.chat_messages;
CREATE POLICY "Participants can view conversation messages"
ON public.chat_messages FOR SELECT
USING (
  conversation_id IS NOT NULL
  AND (
    public.is_chat_conversation_participant(conversation_id, auth.uid())
    OR public.chat_is_admin(auth.uid())
  )
);

-- Canonical conversations use the conversation retention policy. Legacy
-- auto_delete_at stays untouched for the dual-read period.
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.chat_messages m
  USING public.chat_conversations c
  WHERE m.conversation_id = c.id
    AND c.retention_until IS NOT NULL
    AND c.retention_until <= now();

  DELETE FROM public.chat_messages
  WHERE conversation_id IS NULL
    AND auto_delete_at IS NOT NULL
    AND auto_delete_at <= now();
END;
$$;

-- Backfill order conversations and attach valid legacy messages.
DO $$
DECLARE
  r record;
  v_conversation_id uuid;
BEGIN
  FOR r IN
    SELECT DISTINCT
      m.order_id,
      COALESCE(m.chat_type, 'buyer_merchant') AS conversation_type
    FROM public.chat_messages m
    WHERE m.order_id IS NOT NULL
      AND COALESCE(m.chat_type, 'buyer_merchant') IN (
        'buyer_merchant', 'buyer_courier', 'merchant_courier'
      )
  LOOP
    SELECT c.id INTO v_conversation_id
    FROM public.chat_conversations c
    WHERE c.order_id = r.order_id
      AND c.conversation_type = r.conversation_type
    LIMIT 1;

    IF v_conversation_id IS NULL THEN
      INSERT INTO public.chat_conversations (
        context_type, order_id, conversation_type
      )
      SELECT 'order', r.order_id, r.conversation_type
      WHERE EXISTS (
        SELECT 1 FROM public.chat_domain_participants(
          'order', r.order_id, NULL, r.conversation_type
        )
      )
      RETURNING id INTO v_conversation_id;
    END IF;

    IF v_conversation_id IS NOT NULL THEN
      INSERT INTO public.chat_participants (conversation_id, user_id, role)
      SELECT v_conversation_id, p.user_id, p.role
      FROM public.chat_domain_participants(
        'order', r.order_id, NULL, r.conversation_type
      ) p
      WHERE p.user_id IS NOT NULL
      ON CONFLICT (conversation_id, user_id) DO NOTHING;

      UPDATE public.chat_messages
      SET conversation_id = v_conversation_id,
          body = COALESCE(body, message)
      WHERE order_id = r.order_id
        AND COALESCE(chat_type, 'buyer_merchant') = r.conversation_type
        AND conversation_id IS NULL;
    END IF;
  END LOOP;

  UPDATE public.chat_conversations c
  SET last_message_id = latest.id,
      last_message_at = latest.created_at,
      updated_at = now()
  FROM (
    SELECT DISTINCT ON (conversation_id)
      conversation_id, id, created_at
    FROM public.chat_messages
    WHERE conversation_id IS NOT NULL
    ORDER BY conversation_id, created_at DESC, id DESC
  ) latest
  WHERE c.id = latest.conversation_id;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_participants;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reads;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END;
$$;
-- ===== END BUNDLE: 18_20260907040000_live_chat_realtime.sql =====

-- ===== BEGIN BUNDLE: 19_20260907050000_pos_entitlement_lifecycle.sql =====
-- Phase 1: make POS entitlement time-aware and preserve a readable grace period.
-- Marketplace merchant access is intentionally not coupled to this lifecycle.

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS grace_ends_at timestamptz;

ALTER TABLE public.pos_tenants
  DROP CONSTRAINT IF EXISTS pos_tenants_status_check;

ALTER TABLE public.pos_tenants
  ADD CONSTRAINT pos_tenants_status_check
  CHECK (status IN ('inactive', 'setup_required', 'trial', 'active', 'grace', 'suspended', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_entitlement_lookup
  ON public.pos_subscriptions(merchant_id, status, expired_at, grace_ends_at);

-- This is the single read model for the current POS entitlement. It is safe
-- for the merchant subscription screen and keeps expiry/grace logic out of
-- browser-only checks.
CREATE OR REPLACE FUNCTION public.get_pos_entitlement(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_state text := 'none';
  v_operational boolean := false;
BEGIN
  IF auth.uid() IS NULL OR (
    NOT public.is_admin()
    AND NOT EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id = p_merchant_id
        AND m.user_id = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'Merchant entitlement access denied' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE merchant_id = p_merchant_id
    AND status IN ('ACTIVE', 'SUSPENDED', 'CANCELLED')
  ORDER BY
    CASE status WHEN 'ACTIVE' THEN 1 WHEN 'SUSPENDED' THEN 2 ELSE 3 END,
    created_at DESC
  LIMIT 1;

  IF v_subscription.id IS NULL THEN
    RETURN jsonb_build_object('state', v_state, 'operational', false);
  END IF;

  IF v_subscription.status = 'SUSPENDED' THEN
    v_state := 'suspended';
  ELSIF v_subscription.status = 'CANCELLED' THEN
    v_state := 'cancelled';
  ELSIF v_subscription.started_at IS NULL OR v_subscription.started_at > now() THEN
    v_state := 'pending';
  ELSIF v_subscription.expired_at > now() THEN
    v_state := CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END;
    v_operational := true;
  ELSIF v_subscription.grace_ends_at IS NOT NULL
    AND v_subscription.grace_ends_at > now() THEN
    v_state := 'grace';
    v_operational := true;
  ELSE
    v_state := 'expired';
  END IF;

  RETURN jsonb_build_object(
    'state', v_state,
    'operational', v_operational,
    'subscription_id', v_subscription.id,
    'package_id', v_subscription.package_id,
    'is_trial', v_subscription.is_trial,
    'started_at', v_subscription.started_at,
    'expired_at', v_subscription.expired_at,
    'grace_ends_at', v_subscription.grace_ends_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_entitlement(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_entitlement(uuid) TO authenticated;

-- Every operational mutation, including the atomic checkout trigger path,
-- must consult the subscription clock rather than trusting the tenant row.
CREATE OR REPLACE FUNCTION public.is_pos_tenant_active(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.pos_tenants t
    JOIN public.pos_subscriptions s ON s.merchant_id = t.merchant_id
    WHERE t.id = p_tenant_id
      AND t.is_active = true
      AND t.status IN ('trial', 'active', 'grace')
      AND s.status = 'ACTIVE'
      AND s.started_at IS NOT NULL
      AND s.started_at <= now()
      AND (
        s.expired_at > now()
        OR s.grace_ends_at > now()
      )
      AND (
        s.is_trial = true
        OR s.payment_status = 'PAID'
      )
  );
$$;

REVOKE ALL ON FUNCTION public.is_pos_tenant_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_pos_tenant_active(uuid) TO authenticated;

-- Admin approval/reactivation clears a previous grace window. A later
-- suspend/cancel remains explicit and does not delete merchant data.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_duration_months integer;
  v_started_at timestamptz;
  v_expired_at timestamptz;
  v_action text := upper(trim(p_action));
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;
  v_duration_months := COALESCE(v_duration_months, 1);

  IF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at
        + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
    ELSE
      v_started_at := now();
      v_expired_at := v_started_at + make_interval(months => CASE
        WHEN v_action = 'EXTEND' THEN GREATEST(1, COALESCE(p_extension_months, 1))
        ELSE v_duration_months
      END);
    END IF;

    UPDATE public.pos_subscriptions
    SET status = 'ACTIVE',
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        grace_ends_at = NULL,
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END,
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED', payment_status = 'UNPAID', updated_at = now()
    WHERE id = v_subscription.id;
    UPDATE public.pos_tenants
    SET status = 'suspended', is_active = false, suspended_at = now(), updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED', payment_status = 'CANCELLED', updated_at = now()
    WHERE id = v_subscription.id;
    UPDATE public.pos_tenants
    SET status = 'cancelled', is_active = false, updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(NULLIF(trim(p_rejection_reason), ''), 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object('subscription', to_jsonb(s), 'tenant', to_jsonb(t))
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;
-- ===== END BUNDLE: 19_20260907050000_pos_entitlement_lifecycle.sql =====

-- ===== BEGIN BUNDLE: 20_20260907060000_pos_subscription_history_export_audit.sql =====
-- Phase 1 completion slice:
-- package price history, subscription export, idempotent reactivation,
-- and auditable admin lifecycle actions.

CREATE TABLE IF NOT EXISTS public.pos_package_price_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid REFERENCES public.pos_packages(id) ON DELETE SET NULL,
  package_name text NOT NULL,
  description text,
  duration_months integer NOT NULL,
  price integer NOT NULL,
  is_active boolean NOT NULL,
  sort_order integer NOT NULL,
  change_type text NOT NULL CHECK (change_type IN ('INITIAL', 'UPDATE')),
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  change_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pos_package_price_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view POS package history" ON public.pos_package_price_history;
CREATE POLICY "Admins can view POS package history"
  ON public.pos_package_price_history FOR SELECT
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_pos_package_price_history_package
  ON public.pos_package_price_history(package_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.record_pos_package_price_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR OLD.name IS DISTINCT FROM NEW.name
     OR OLD.description IS DISTINCT FROM NEW.description
     OR OLD.duration_months IS DISTINCT FROM NEW.duration_months
     OR OLD.price IS DISTINCT FROM NEW.price
     OR OLD.is_active IS DISTINCT FROM NEW.is_active
     OR OLD.sort_order IS DISTINCT FROM NEW.sort_order THEN
    INSERT INTO public.pos_package_price_history (
      package_id,
      package_name,
      description,
      duration_months,
      price,
      is_active,
      sort_order,
      change_type,
       changed_by,
       change_reason
    )
    VALUES (
      NEW.id,
      NEW.name,
      NEW.description,
      NEW.duration_months,
      NEW.price,
      NEW.is_active,
      NEW.sort_order,
       CASE WHEN TG_OP = 'INSERT' THEN 'INITIAL' ELSE 'UPDATE' END,
       auth.uid(),
       NULLIF(current_setting('app.pos_package_change_reason', true), '')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_pos_package_price_history ON public.pos_packages;
CREATE TRIGGER trg_record_pos_package_price_history
AFTER INSERT OR UPDATE ON public.pos_packages
FOR EACH ROW
EXECUTE FUNCTION public.record_pos_package_price_history();

-- Backfill the current package state once for packages created before this
-- history table existed. The NOT EXISTS guard keeps the migration rerunnable.
INSERT INTO public.pos_package_price_history (
  package_id,
  package_name,
  description,
  duration_months,
  price,
  is_active,
  sort_order,
  change_type
)
SELECT p.id, p.name, p.description, p.duration_months, p.price, p.is_active, p.sort_order, 'INITIAL'
FROM public.pos_packages p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.pos_package_price_history h
  WHERE h.package_id = p.id
);

CREATE OR REPLACE FUNCTION public.get_pos_package_history(p_limit integer DEFAULT 200)
RETURNS TABLE (
  id uuid,
  package_id uuid,
  package_name text,
  description text,
  duration_months integer,
  price integer,
  is_active boolean,
  sort_order integer,
  change_type text,
  changed_by uuid,
  change_reason text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    h.id,
    h.package_id,
    h.package_name,
    h.description,
    h.duration_months,
    h.price,
    h.is_active,
    h.sort_order,
    h.change_type,
    h.changed_by,
    h.change_reason,
    h.created_at
  FROM public.pos_package_price_history h
  WHERE public.is_admin()
  ORDER BY h.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500);
$$;

REVOKE ALL ON FUNCTION public.get_pos_package_history(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_package_history(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_pos_package(
  p_package_id uuid,
  p_name text,
  p_description text,
  p_duration_months integer,
  p_price integer,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before public.pos_packages%ROWTYPE;
  v_after public.pos_packages%ROWTYPE;
  v_reason text := NULLIF(trim(p_reason), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can update POS packages' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION 'Package name and change reason are required' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_duration_months, 0) < 1 OR COALESCE(p_price, -1) < 0 THEN
    RAISE EXCEPTION 'Package duration and price are invalid' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_before
  FROM public.pos_packages
  WHERE id = p_package_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS package not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.pos_package_change_reason', v_reason, true);
  UPDATE public.pos_packages
  SET name = trim(p_name),
      description = NULLIF(trim(COALESCE(p_description, '')), ''),
      duration_months = p_duration_months,
      price = p_price
  WHERE id = p_package_id;

  SELECT * INTO v_after
  FROM public.pos_packages
  WHERE id = p_package_id;

  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  )
  VALUES (
    auth.uid(),
    'UPDATE_POS_PACKAGE',
    'pos_package',
    p_package_id,
    to_jsonb(v_before),
    to_jsonb(v_after) || jsonb_build_object('reason', v_reason)
  );

  RETURN to_jsonb(v_after);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_pos_package(uuid, text, text, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_pos_package(uuid, text, text, integer, integer, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.export_pos_subscription_data(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_owner boolean;
  v_is_admin boolean;
  v_subscriptions jsonb;
BEGIN
  v_is_owner := EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.id = p_merchant_id
      AND m.user_id = auth.uid()
  );
  v_is_admin := public.is_admin();

  IF auth.uid() IS NULL OR (NOT v_is_owner AND NOT v_is_admin) THEN
    RAISE EXCEPTION 'Subscription export access denied' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      to_jsonb(s) || jsonb_build_object(
        'package',
        CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'description', p.description,
          'duration_months', p.duration_months,
          'price', p.price
        ) END
      )
      ORDER BY s.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_subscriptions
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_packages p ON p.id = s.package_id
  WHERE s.merchant_id = p_merchant_id;

  RETURN jsonb_build_object(
    'export_version', 1,
    'exported_at', now(),
    'merchant_id', p_merchant_id,
    'subscriptions', v_subscriptions
  );
END;
$$;

REVOKE ALL ON FUNCTION public.export_pos_subscription_data(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_pos_subscription_data(uuid) TO authenticated;

-- Extend the existing lifecycle RPC without changing its call contract:
-- the new reason parameter is optional for existing clients.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_current public.pos_subscriptions%ROWTYPE;
  v_duration_months integer;
  v_started_at timestamptz;
  v_expired_at timestamptz;
  v_action text := upper(trim(p_action));
  v_reason text := NULLIF(trim(COALESCE(p_reason, p_rejection_reason)), '');
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;
  v_duration_months := COALESCE(v_duration_months, 1);

  -- Repeating approval/reactivation on an already operational subscription
  -- must not reset its clock or create a second workspace.
  IF v_action IN ('APPROVE', 'REACTIVATE')
     AND v_subscription.status = 'ACTIVE'
     AND v_subscription.started_at IS NOT NULL
     AND v_subscription.expired_at > now()
     AND (v_subscription.grace_ends_at IS NULL OR v_subscription.grace_ends_at > now()) THEN
    NULL;
  ELSIF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at
        + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
    ELSE
      v_started_at := now();
      v_expired_at := v_started_at + make_interval(months => CASE
        WHEN v_action = 'EXTEND' THEN GREATEST(1, COALESCE(p_extension_months, 1))
        ELSE v_duration_months
      END);
    END IF;

    UPDATE public.pos_subscriptions
    SET status = 'ACTIVE',
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        grace_ends_at = NULL,
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END,
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED', payment_status = 'UNPAID', updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'suspended', is_active = false, suspended_at = now(), updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED', payment_status = 'CANCELLED', updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'cancelled', is_active = false, updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(v_reason, 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_current
  FROM public.pos_subscriptions
  WHERE id = v_subscription.id;

  INSERT INTO public.admin_audit_logs (
    admin_id,
    action,
    entity_type,
    entity_id,
    old_value,
    new_value
  )
  VALUES (
    auth.uid(),
    'POS_SUBSCRIPTION_' || v_action,
    'pos_subscription',
    v_subscription.id,
    to_jsonb(v_subscription),
    to_jsonb(v_current) || jsonb_build_object('reason', v_reason)
  );

  SELECT jsonb_build_object('subscription', to_jsonb(s), 'tenant', to_jsonb(t))
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text, text) TO authenticated;

-- Preserve the four-argument RPC used by older clients while routing it
-- through the audited implementation above.
CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id uuid,
  p_action text,
  p_extension_months integer DEFAULT 1,
  p_rejection_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.admin_manage_pos_subscription(
    p_subscription_id,
    p_action,
    p_extension_months,
    p_rejection_reason,
    NULL
  );
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(uuid, text, integer, text) TO authenticated;
-- ===== END BUNDLE: 20_20260907060000_pos_subscription_history_export_audit.sql =====

-- ===== BEGIN BUNDLE: 21_20260907070000_pos_stock_reconciliation_alerts.sql =====
-- Phase 2: durable stock reconciliation and visible projection failures.

ALTER TABLE public.pos_marketplace_sync
  ADD COLUMN IF NOT EXISTS sync_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error_at timestamptz,
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_pos_marketplace_sync_retry
  ON public.pos_marketplace_sync(tenant_id, sync_status, next_retry_at);

CREATE TABLE IF NOT EXISTS public.pos_stock_sync_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  sync_id uuid NOT NULL REFERENCES public.pos_marketplace_sync(id) ON DELETE CASCADE,
  alert_code text NOT NULL,
  severity text NOT NULL DEFAULT 'error' CHECK (severity IN ('warning', 'error')),
  message text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE(sync_id, alert_code)
);

CREATE INDEX IF NOT EXISTS idx_pos_stock_sync_alerts_open
  ON public.pos_stock_sync_alerts(tenant_id, status, last_seen_at DESC);

ALTER TABLE public.pos_stock_sync_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view own stock sync alerts" ON public.pos_stock_sync_alerts;
CREATE POLICY "POS users view own stock sync alerts"
  ON public.pos_stock_sync_alerts
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.pos_tenants t
      WHERE t.id = tenant_id
        AND (t.user_id = auth.uid() OR public.is_admin())
    )
  );

CREATE OR REPLACE FUNCTION public.record_pos_stock_sync_failure(
  p_tenant_id uuid,
  p_pos_product_id uuid,
  p_message text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sync record;
  v_message text := left(COALESCE(NULLIF(trim(p_message), ''), 'Projection stok gagal'), 500);
  v_count integer := 0;
BEGIN
  FOR v_sync IN
    SELECT id, tenant_id
    FROM public.pos_marketplace_sync
    WHERE tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pos_product_id = p_pos_product_id)
      AND sync_stock = true
  LOOP
    UPDATE public.pos_marketplace_sync
    SET sync_status = 'error',
        error_message = v_message,
        sync_attempts = COALESCE(sync_attempts, 0) + 1,
        last_error_at = now(),
        next_retry_at = now() + interval '5 minutes',
        updated_at = now()
    WHERE id = v_sync.id;

    INSERT INTO public.pos_stock_sync_alerts (
      tenant_id, sync_id, alert_code, severity, message, status,
      first_seen_at, last_seen_at, resolved_at
    )
    VALUES (
      v_sync.tenant_id, v_sync.id, 'STOCK_PROJECTION_FAILED', 'error', v_message,
      'open', now(), now(), NULL
    )
    ON CONFLICT (sync_id, alert_code) DO UPDATE
    SET severity = 'error',
        message = EXCLUDED.message,
        status = 'open',
        last_seen_at = now(),
        resolved_at = NULL;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pos_stock_sync_alert(p_sync_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.pos_stock_sync_alerts
  SET status = 'resolved',
      resolved_at = now(),
      last_seen_at = now()
  WHERE sync_id = p_sync_id
    AND status = 'open';
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_safe(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  BEGIN
    v_result := public.sync_pos_stock_to_marketplace_internal(p_tenant_id, p_pos_product_id);
    RETURN v_result;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.record_pos_stock_sync_failure(p_tenant_id, p_pos_product_id, SQLERRM);
    RETURN jsonb_build_object(
      'tenant_id', p_tenant_id,
      'processed', 0,
      'updated', 0,
      'status', 'error',
      'error_message', SQLERRM
    );
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.pos_tenants t
      WHERE t.id = p_tenant_id AND t.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.pos_users u
      WHERE u.tenant_id = p_tenant_id
        AND u.user_id = auth.uid()
        AND u.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock synchronization access denied' USING ERRCODE = '42501';
  END IF;

  RETURN public.sync_pos_stock_to_marketplace_safe(p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
  v_product_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_id ELSE NEW.product_id END;
BEGIN
  PERFORM public.sync_pos_stock_to_marketplace_safe(v_tenant_id, v_product_id);
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE OR REPLACE FUNCTION public.pos_stock_sync_alert_on_success()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.sync_status = 'synced' THEN
    PERFORM public.resolve_pos_stock_sync_alert(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pos_stock_sync_alert_on_success ON public.pos_marketplace_sync;
CREATE TRIGGER trg_pos_stock_sync_alert_on_success
AFTER UPDATE OF sync_status ON public.pos_marketplace_sync
FOR EACH ROW
WHEN (NEW.sync_status = 'synced')
EXECUTE FUNCTION public.pos_stock_sync_alert_on_success();

CREATE OR REPLACE FUNCTION public.get_pos_stock_reconciliation(p_tenant_id uuid)
RETURNS TABLE (
  pos_product_id uuid,
  product_name text,
  sku text,
  merchant_product_id uuid,
  outlet_total numeric,
  reserved numeric,
  pos_available numeric,
  marketplace_stock integer,
  delta numeric,
  status text,
  sync_status text,
  last_synced_at timestamptz,
  error_message text,
  last_error_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    pp.id,
    pp.name,
    pp.sku,
    pp.merchant_product_id,
    COALESCE(stock.outlet_total, 0),
    COALESCE(stock.reserved, 0),
    GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0),
    marketplace.stock,
    CASE
      WHEN pp.merchant_product_id IS NULL OR marketplace.id IS NULL THEN NULL
      ELSE GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0) - marketplace.stock
    END,
    CASE
      WHEN pp.merchant_product_id IS NULL THEN 'unlinked'
      WHEN marketplace.id IS NULL THEN 'missing'
      WHEN GREATEST(COALESCE(stock.outlet_total, 0) - COALESCE(stock.reserved, 0), 0) <> marketplace.stock THEN 'mismatch'
      ELSE 'ok'
    END,
    COALESCE(ms.sync_status, 'unlinked'),
    ms.last_synced_at,
    ms.error_message,
    ms.last_error_at
  FROM public.pos_products pp
  LEFT JOIN public.pos_marketplace_sync ms
    ON ms.tenant_id = pp.tenant_id
   AND ms.pos_product_id = pp.id
  LEFT JOIN public.products marketplace
    ON marketplace.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
  LEFT JOIN LATERAL (
    SELECT
      SUM(ps.quantity) AS outlet_total,
      SUM(COALESCE(ps.reserved_quantity, 0)) AS reserved
    FROM public.pos_stock ps
    WHERE ps.tenant_id = pp.tenant_id
      AND ps.product_id = pp.id
      AND ps.variant_id IS NULL
  ) stock ON true
  WHERE pp.tenant_id = p_tenant_id
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.pos_tenants t
        WHERE t.id = p_tenant_id
          AND t.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM public.pos_users u
        WHERE u.tenant_id = p_tenant_id
          AND u.user_id = auth.uid()
          AND u.is_active = true
      )
    )
  ORDER BY pp.name;
$$;

REVOKE ALL ON FUNCTION public.record_pos_stock_sync_failure(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_pos_stock_sync_alert(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_safe(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pos_stock_reconciliation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_stock_reconciliation(uuid) TO authenticated;
-- ===== END BUNDLE: 21_20260907070000_pos_stock_reconciliation_alerts.sql =====

-- ===== BEGIN BUNDLE: 22_20260907080000_pos_catalog_identity_stale_projection.sql =====
-- Phase 2: enforce tenant-scoped catalog identities and detect stale projections.
--
-- SKU/barcode are operational identities, not display labels. They must be
-- unique within a tenant across both parent products and their variants.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.pos_products
    WHERE NULLIF(BTRIM(sku), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(sku))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_product_variants
    WHERE NULLIF(BTRIM(sku), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(sku))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_products p
    JOIN public.pos_product_variants v
      ON v.tenant_id = p.tenant_id
     AND LOWER(BTRIM(v.sku)) = LOWER(BTRIM(p.sku))
    WHERE NULLIF(BTRIM(p.sku), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Duplicate SKU values exist within a POS tenant; clean them before applying catalog identity constraints';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pos_products
    WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(barcode))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_product_variants
    WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL
    GROUP BY tenant_id, LOWER(BTRIM(barcode))
    HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM public.pos_products p
    JOIN public.pos_product_variants v
      ON v.tenant_id = p.tenant_id
     AND LOWER(BTRIM(v.barcode)) = LOWER(BTRIM(p.barcode))
    WHERE NULLIF(BTRIM(p.barcode), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Duplicate barcode values exist within a POS tenant; clean them before applying catalog identity constraints';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_tenant_sku_unique
  ON public.pos_products (tenant_id, LOWER(BTRIM(sku)))
  WHERE NULLIF(BTRIM(sku), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_product_variants_tenant_sku_unique
  ON public.pos_product_variants (tenant_id, LOWER(BTRIM(sku)))
  WHERE NULLIF(BTRIM(sku), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_products_tenant_barcode_unique
  ON public.pos_products (tenant_id, LOWER(BTRIM(barcode)))
  WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_product_variants_tenant_barcode_unique
  ON public.pos_product_variants (tenant_id, LOWER(BTRIM(barcode)))
  WHERE NULLIF(BTRIM(barcode), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.validate_pos_catalog_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sku text := NULLIF(LOWER(BTRIM(NEW.sku)), '');
  v_barcode text := NULLIF(LOWER(BTRIM(NEW.barcode)), '');
BEGIN
  IF TG_TABLE_NAME = 'pos_products' THEN
    IF v_sku IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(sku)) = v_sku
    ) THEN
      RAISE EXCEPTION 'SKU sudah digunakan oleh varian lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
    IF v_barcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(barcode)) = v_barcode
    ) THEN
      RAISE EXCEPTION 'Barcode sudah digunakan oleh varian lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
  ELSE
    IF v_sku IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_products
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(sku)) = v_sku
    ) THEN
      RAISE EXCEPTION 'SKU sudah digunakan oleh produk lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
    IF v_barcode IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.pos_products
      WHERE tenant_id = NEW.tenant_id
        AND LOWER(BTRIM(barcode)) = v_barcode
    ) THEN
      RAISE EXCEPTION 'Barcode sudah digunakan oleh produk lain dalam tenant ini' USING ERRCODE = '23505';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_product_identity ON public.pos_products;
CREATE TRIGGER trg_validate_pos_product_identity
BEFORE INSERT OR UPDATE OF tenant_id, sku, barcode ON public.pos_products
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_catalog_identity();

DROP TRIGGER IF EXISTS trg_validate_pos_variant_identity ON public.pos_product_variants;
CREATE TRIGGER trg_validate_pos_variant_identity
BEFORE INSERT OR UPDATE OF tenant_id, sku, barcode ON public.pos_product_variants
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_catalog_identity();

CREATE OR REPLACE FUNCTION public.validate_pos_variant_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian harus berada pada tenant dan produk POS yang sama' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_variant_scope ON public.pos_product_variants;
CREATE TRIGGER trg_validate_pos_variant_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id ON public.pos_product_variants
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_variant_scope();

CREATE OR REPLACE FUNCTION public.validate_pos_stock_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada tenant dan produk POS yang sama' USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada outlet tenant yang sama' USING ERRCODE = '23514';
  END IF;

  IF NEW.variant_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE id = NEW.variant_id
      AND product_id = NEW.product_id
      AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian stok tidak cocok dengan produk dan tenant' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_stock_scope ON public.pos_stock;
CREATE TRIGGER trg_validate_pos_stock_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id, variant_id, outlet_id ON public.pos_stock
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_stock_scope();

CREATE OR REPLACE FUNCTION public.detect_pos_stock_sync_stale(
  p_tenant_id uuid,
  p_stale_after_minutes integer DEFAULT 120
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sync record;
  v_cutoff timestamptz := now() - make_interval(mins => GREATEST(COALESCE(p_stale_after_minutes, 120), 15));
  v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.pos_tenants WHERE id = p_tenant_id AND user_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.pos_users
      WHERE tenant_id = p_tenant_id AND user_id = auth.uid() AND is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'POS stock stale detection access denied' USING ERRCODE = '42501';
  END IF;

  FOR v_sync IN
    SELECT ms.id, ms.tenant_id, pp.name, ms.last_synced_at
    FROM public.pos_marketplace_sync ms
    JOIN public.pos_products pp ON pp.id = ms.pos_product_id
    WHERE ms.tenant_id = p_tenant_id
      AND ms.sync_stock = true
      AND ms.sync_status = 'synced'
      AND (ms.last_synced_at IS NULL OR ms.last_synced_at < v_cutoff)
  LOOP
    INSERT INTO public.pos_stock_sync_alerts (
      tenant_id, sync_id, alert_code, severity, message, status,
      first_seen_at, last_seen_at, resolved_at
    )
    VALUES (
      v_sync.tenant_id,
      v_sync.id,
      'STOCK_PROJECTION_STALE',
      'warning',
      format('Projection stok "%s" belum diperbarui sejak %s.', v_sync.name,
        COALESCE(to_char(v_sync.last_synced_at AT TIME ZONE 'Asia/Jakarta', 'DD Mon YYYY HH24:MI'), 'belum pernah')),
      'open',
      now(), now(), NULL
    )
    ON CONFLICT (sync_id, alert_code) DO UPDATE
    SET severity = 'warning',
        message = EXCLUDED.message,
        status = 'open',
        last_seen_at = now(),
        resolved_at = NULL;
    v_count := v_count + 1;
  END LOOP;

  UPDATE public.pos_stock_sync_alerts alert
  SET status = 'resolved', resolved_at = now(), last_seen_at = now()
  WHERE alert.tenant_id = p_tenant_id
    AND alert.alert_code = 'STOCK_PROJECTION_STALE'
    AND alert.status = 'open'
    AND NOT EXISTS (
      SELECT 1
      FROM public.pos_marketplace_sync ms
      WHERE ms.id = alert.sync_id
        AND ms.sync_stock = true
        AND ms.sync_status = 'synced'
        AND (ms.last_synced_at IS NULL OR ms.last_synced_at < v_cutoff)
    );

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_pos_catalog_identity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_variant_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_stock_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detect_pos_stock_sync_stale(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detect_pos_stock_sync_stale(uuid, integer) TO authenticated;
-- ===== END BUNDLE: 22_20260907080000_pos_catalog_identity_stale_projection.sql =====

-- ===== BEGIN BUNDLE: 23_20260907100000_pos_variant_outlet_stock_contract.sql =====
-- Phase 2: one stock identity for every sellable unit.
--
-- A product without variants uses (pos_product, NULL, outlet).
-- A product with variants uses (pos_product, pos_variant, outlet).
-- Marketplace reservations and projection must never fall back from a variant
-- row to the parent product row.

ALTER TABLE public.pos_product_variants
  ADD COLUMN IF NOT EXISTS merchant_variant_id uuid
    REFERENCES public.product_variants(id) ON DELETE SET NULL;

ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS reserved_stock integer NOT NULL DEFAULT 0
    CHECK (reserved_stock >= 0);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_variants_tenant_merchant_variant
  ON public.pos_product_variants(tenant_id, merchant_variant_id)
  WHERE merchant_variant_id IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.pos_stock
    WHERE variant_id IS NULL
    GROUP BY product_id, outlet_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate base POS stock rows exist for a product and outlet';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pos_stock
    WHERE variant_id IS NOT NULL
    GROUP BY product_id, variant_id, outlet_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate variant POS stock rows exist for a product and outlet';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_stock_product_outlet_base_unique
  ON public.pos_stock(product_id, outlet_id)
  WHERE variant_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_stock_product_variant_outlet_unique
  ON public.pos_stock(product_id, variant_id, outlet_id)
  WHERE variant_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.validate_pos_stock_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.pos_products
    WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada tenant dan produk POS yang sama'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = NEW.outlet_id AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Stok harus berada pada outlet tenant yang sama'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.variant_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE id = NEW.variant_id
      AND product_id = NEW.product_id
      AND tenant_id = NEW.tenant_id
  ) THEN
    RAISE EXCEPTION 'Varian stok tidak cocok dengan produk dan tenant'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.quantity < 0 OR COALESCE(NEW.reserved_quantity, 0) < 0
     OR COALESCE(NEW.reserved_quantity, 0) > NEW.quantity THEN
    RAISE EXCEPTION 'Stok dan reservasi tidak boleh negatif atau melebihi stok fisik'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_pos_stock_scope ON public.pos_stock;
CREATE TRIGGER trg_validate_pos_stock_scope
BEFORE INSERT OR UPDATE OF tenant_id, product_id, variant_id, outlet_id, quantity, reserved_quantity
ON public.pos_stock
FOR EACH ROW EXECUTE FUNCTION public.validate_pos_stock_scope();

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variant_to_pos(
  p_variant_id uuid,
  p_tenant_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_variant public.product_variants%ROWTYPE;
  v_pos_product_id uuid;
  v_pos_variant_id uuid;
BEGIN
  SELECT pv.* INTO v_variant
  FROM public.product_variants pv
  JOIN public.products p ON p.id = pv.product_id
  WHERE pv.id = p_variant_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT pp.id INTO v_pos_product_id
  FROM public.pos_products pp
  WHERE pp.tenant_id = p_tenant_id
    AND pp.merchant_product_id = v_variant.product_id
  LIMIT 1;
  IF v_pos_product_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_pos_variant_id
  FROM public.pos_product_variants
  WHERE tenant_id = p_tenant_id
    AND merchant_variant_id = p_variant_id
  LIMIT 1;

  IF v_pos_variant_id IS NULL THEN
    INSERT INTO public.pos_product_variants (
      product_id, tenant_id, merchant_variant_id, name, sku, price,
      cost_price, is_active
    )
    SELECT
      v_pos_product_id, p_tenant_id, v_variant.id, v_variant.name, v_variant.sku,
      pp.price + COALESCE(v_variant.price_adjustment, 0), pp.cost_price, v_variant.is_active
    FROM public.pos_products pp
    WHERE pp.id = v_pos_product_id
    RETURNING id INTO v_pos_variant_id;
  ELSE
    UPDATE public.pos_product_variants ppv
    SET product_id = v_pos_product_id,
        name = v_variant.name,
        sku = v_variant.sku,
        price = (SELECT pp.price FROM public.pos_products pp WHERE pp.id = v_pos_product_id)
          + COALESCE(v_variant.price_adjustment, 0),
        is_active = v_variant.is_active,
        updated_at = now()
    WHERE ppv.id = v_pos_variant_id;
  END IF;

  UPDATE public.pos_products
  SET has_variants = true, updated_at = now()
  WHERE id = v_pos_product_id;

  RETURN v_pos_variant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_pos_stock_rows_for_product(
  p_product_id uuid,
  p_tenant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_outlet public.pos_outlets%ROWTYPE;
  v_variant public.pos_product_variants%ROWTYPE;
  v_has_active_variants boolean;
BEGIN
  IF p_product_id IS NULL THEN RETURN; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.pos_product_variants
    WHERE product_id = p_product_id AND tenant_id = p_tenant_id AND is_active = true
  ) INTO v_has_active_variants;

  FOR v_outlet IN
    SELECT * FROM public.pos_outlets
    WHERE tenant_id = p_tenant_id AND is_active = true
  LOOP
    IF v_has_active_variants THEN
      FOR v_variant IN
        SELECT * FROM public.pos_product_variants
        WHERE product_id = p_product_id AND tenant_id = p_tenant_id AND is_active = true
      LOOP
        INSERT INTO public.pos_stock (
          tenant_id, product_id, variant_id, outlet_id, quantity, min_stock
        )
        VALUES (p_tenant_id, p_product_id, v_variant.id, v_outlet.id, 0, 0)
        ON CONFLICT (product_id, variant_id, outlet_id)
        WHERE variant_id IS NOT NULL DO NOTHING;
      END LOOP;
    ELSE
      INSERT INTO public.pos_stock (
        tenant_id, product_id, variant_id, outlet_id, quantity, min_stock
      )
      VALUES (p_tenant_id, p_product_id, NULL, v_outlet.id, 0, 0)
      ON CONFLICT (product_id, outlet_id)
      WHERE variant_id IS NULL DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variants_for_product(
  p_product_id uuid,
  p_tenant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_variant public.product_variants%ROWTYPE;
  v_pos_product_id uuid;
BEGIN
  SELECT id INTO v_pos_product_id
  FROM public.pos_products
  WHERE tenant_id = p_tenant_id
    AND merchant_product_id = p_product_id
  LIMIT 1;
  IF v_pos_product_id IS NULL THEN RETURN; END IF;

  FOR v_variant IN
    SELECT * FROM public.product_variants
    WHERE product_id = p_product_id
  LOOP
    PERFORM public.sync_merchant_product_variant_to_pos(v_variant.id, p_tenant_id);
  END LOOP;

  UPDATE public.pos_products
  SET has_variants = EXISTS (
        SELECT 1 FROM public.pos_product_variants
        WHERE product_id = v_pos_product_id AND tenant_id = p_tenant_id AND is_active = true
      ),
      updated_at = now()
  WHERE id = v_pos_product_id;

  PERFORM public.ensure_pos_stock_rows_for_product(v_pos_product_id, p_tenant_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variants_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT pt.*
    FROM public.pos_tenants pt
    JOIN public.products p ON p.merchant_id = pt.merchant_id
    WHERE p.id = NEW.product_id AND pt.is_active = true
  LOOP
    PERFORM public.sync_merchant_product_variants_for_product(NEW.product_id, v_tenant.id);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_variants ON public.product_variants;
CREATE TRIGGER trg_sync_merchant_product_variants
AFTER INSERT OR UPDATE OF name, price_adjustment, sku, is_active, product_id
ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.sync_merchant_product_variants_trigger();

CREATE OR REPLACE FUNCTION public.sync_merchant_product_variant_delete_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
BEGIN
  FOR v_tenant IN
    SELECT pt.*
    FROM public.pos_tenants pt
    JOIN public.products p ON p.merchant_id = pt.merchant_id
    WHERE p.id = OLD.product_id AND pt.is_active = true
  LOOP
    UPDATE public.pos_product_variants
    SET is_active = false, updated_at = now()
    WHERE tenant_id = v_tenant.id
      AND merchant_variant_id = OLD.id;

    UPDATE public.pos_products pp
    SET has_variants = EXISTS (
      SELECT 1 FROM public.pos_product_variants
      WHERE product_id = pp.id AND tenant_id = v_tenant.id AND is_active = true
    ),
    updated_at = now()
    WHERE pp.tenant_id = v_tenant.id AND pp.merchant_product_id = OLD.product_id;
  END LOOP;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_merchant_product_variant_delete ON public.product_variants;
CREATE TRIGGER trg_sync_merchant_product_variant_delete
BEFORE DELETE ON public.product_variants
FOR EACH ROW EXECUTE FUNCTION public.sync_merchant_product_variant_delete_trigger();

ALTER TABLE public.marketplace_stock_allocations
  ADD COLUMN IF NOT EXISTS pos_variant_id uuid
    REFERENCES public.pos_product_variants(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.sync_pos_stock_to_marketplace_internal(
  p_tenant_id uuid,
  p_pos_product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_mapping record;
  v_variant record;
  v_available numeric;
  v_projected_stock integer;
  v_processed integer := 0;
  v_updated integer := 0;
BEGIN
  PERFORM set_config('app.pos_stock_projection', 'on', true);
  SELECT * INTO v_tenant FROM public.pos_tenants WHERE id = p_tenant_id;
  IF NOT FOUND OR v_tenant.merchant_id IS NULL THEN
    RETURN jsonb_build_object('tenant_id', p_tenant_id, 'processed', 0, 'updated', 0, 'status', 'unmapped');
  END IF;

  FOR v_mapping IN
    SELECT pp.id AS pos_product_id,
           COALESCE(ms.marketplace_product_id, pp.merchant_product_id) AS marketplace_product_id,
           ms.id AS sync_id,
           EXISTS (
             SELECT 1 FROM public.pos_product_variants ppv
             WHERE ppv.product_id = pp.id AND ppv.tenant_id = pp.tenant_id AND ppv.is_active = true
           ) AS has_active_variants
    FROM public.pos_products pp
    LEFT JOIN public.pos_marketplace_sync ms
      ON ms.tenant_id = pp.tenant_id AND ms.pos_product_id = pp.id
    JOIN public.products marketplace_product
      ON marketplace_product.id = COALESCE(ms.marketplace_product_id, pp.merchant_product_id)
      AND marketplace_product.merchant_id = v_tenant.merchant_id
    WHERE pp.tenant_id = p_tenant_id
      AND (p_pos_product_id IS NULL OR pp.id = p_pos_product_id)
      AND (ms.id IS NULL OR (ms.sync_stock = true AND ms.sync_status = 'synced'))
  LOOP
    v_processed := v_processed + 1;
    SELECT COALESCE(SUM(GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)), 0)
    INTO v_available
    FROM public.pos_stock ps
    JOIN public.pos_outlets po ON po.id = ps.outlet_id
      AND po.tenant_id = ps.tenant_id AND po.is_active = true
    WHERE ps.tenant_id = p_tenant_id
      AND ps.product_id = v_mapping.pos_product_id
      AND (
        (v_mapping.has_active_variants AND ps.variant_id IS NOT NULL)
        OR (NOT v_mapping.has_active_variants AND ps.variant_id IS NULL)
      );

    v_projected_stock := GREATEST(0, ROUND(v_available))::integer;
    UPDATE public.products
    SET stock = v_projected_stock, updated_at = now()
    WHERE id = v_mapping.marketplace_product_id
      AND merchant_id = v_tenant.merchant_id
      AND stock IS DISTINCT FROM v_projected_stock;
    IF FOUND THEN v_updated := v_updated + 1; END IF;

    IF v_mapping.sync_id IS NOT NULL THEN
      UPDATE public.pos_marketplace_sync
      SET last_synced_at = now(), sync_status = 'synced', error_message = NULL, updated_at = now()
      WHERE id = v_mapping.sync_id;
    END IF;

    FOR v_variant IN
      SELECT ppv.id AS pos_variant_id, ppv.merchant_variant_id
      FROM public.pos_product_variants ppv
      WHERE ppv.product_id = v_mapping.pos_product_id
        AND ppv.tenant_id = p_tenant_id
        AND ppv.is_active = true
        AND ppv.merchant_variant_id IS NOT NULL
    LOOP
      SELECT COALESCE(SUM(GREATEST(ps.quantity - COALESCE(ps.reserved_quantity, 0), 0)), 0)
      INTO v_available
      FROM public.pos_stock ps
      JOIN public.pos_outlets po ON po.id = ps.outlet_id
        AND po.tenant_id = ps.tenant_id AND po.is_active = true
      WHERE ps.tenant_id = p_tenant_id
        AND ps.product_id = v_mapping.pos_product_id
        AND ps.variant_id = v_variant.pos_variant_id;
      v_projected_stock := GREATEST(0, ROUND(v_available))::integer;
      UPDATE public.product_variants
      SET stock = v_projected_stock, updated_at = now()
      WHERE id = v_variant.merchant_variant_id
        AND stock IS DISTINCT FROM v_projected_stock;
      IF FOUND THEN v_updated := v_updated + 1; END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('tenant_id', p_tenant_id, 'processed', v_processed, 'updated', v_updated, 'status', 'success');
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_marketplace_stock(
  p_order_id uuid,
  p_items jsonb,
  p_expires_at timestamptz DEFAULT now() + interval '30 minutes'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reservation_id uuid;
  v_input jsonb;
  v_product public.products%ROWTYPE;
  v_variant public.product_variants%ROWTYPE;
  v_product_id uuid;
  v_variant_id uuid;
  v_qty numeric;
  v_total numeric := 0;
  v_existing public.marketplace_stock_reservations%ROWTYPE;
  v_tenant_id uuid;
  v_pos_product_id uuid;
  v_pos_variant_id uuid;
  v_item_id uuid;
  v_remaining numeric;
  v_available numeric;
  v_allocated numeric;
  v_stock record;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invalid marketplace reservation' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR lower(COALESCE(v_order.status, '')) IN ('cancelled', 'canceled', 'rejected', 'refunded') THEN
    RAISE EXCEPTION 'Order reservation access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_existing FROM public.marketplace_stock_reservations
  WHERE order_id = p_order_id FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('reservation_id', v_existing.id, 'status', v_existing.status, 'duplicate', true);
  END IF;

  INSERT INTO public.marketplace_stock_reservations(order_id, buyer_id, expires_at)
  VALUES (p_order_id, auth.uid(), GREATEST(p_expires_at, now() + interval '1 minute'))
  RETURNING id INTO v_reservation_id;

  FOR v_input IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_input->>'product_id', '')::uuid;
    v_variant_id := NULLIF(v_input->>'variant_id', '')::uuid;
    v_qty := COALESCE((v_input->>'quantity')::numeric, 0);
    IF v_product_id IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid marketplace reservation item' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_product FROM public.products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE = '23503'; END IF;
    IF v_variant_id IS NOT NULL THEN
      SELECT * INTO v_variant FROM public.product_variants
      WHERE id = v_variant_id AND product_id = v_product_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Variant does not belong to product' USING ERRCODE = '23514'; END IF;
    END IF;

    INSERT INTO public.marketplace_stock_reservation_items(reservation_id, product_id, variant_id, quantity)
    VALUES (v_reservation_id, v_product_id, v_variant_id, v_qty)
    RETURNING id INTO v_item_id;

    SELECT pt.id, pp.id, ppv.id
    INTO v_tenant_id, v_pos_product_id, v_pos_variant_id
    FROM public.pos_tenants pt
    JOIN public.pos_products pp ON pp.tenant_id = pt.id
      AND pp.merchant_product_id = v_product_id AND pp.is_active = true
    LEFT JOIN public.pos_product_variants ppv ON ppv.product_id = pp.id
      AND ppv.tenant_id = pp.tenant_id AND ppv.merchant_variant_id = v_variant_id
      AND ppv.is_active = true
    WHERE pt.merchant_id = v_order.merchant_id AND pt.is_active = true
      AND (v_variant_id IS NULL OR ppv.id IS NOT NULL)
    ORDER BY pt.created_at, pp.created_at
    LIMIT 1;

    IF v_pos_product_id IS NOT NULL AND (v_variant_id IS NULL OR v_pos_variant_id IS NOT NULL) THEN
      v_remaining := v_qty;
      FOR v_stock IN
        SELECT ps.id, ps.outlet_id, ps.quantity, COALESCE(ps.reserved_quantity, 0) AS reserved_quantity
        FROM public.pos_stock ps
        JOIN public.pos_outlets po ON po.id = ps.outlet_id
          AND po.tenant_id = ps.tenant_id AND po.is_active = true
        WHERE ps.tenant_id = v_tenant_id
          AND ps.product_id = v_pos_product_id
          AND ps.variant_id IS NOT DISTINCT FROM v_pos_variant_id
        ORDER BY ps.outlet_id, ps.id
        FOR UPDATE
      LOOP
        EXIT WHEN v_remaining <= 0;
        v_available := GREATEST(v_stock.quantity - v_stock.reserved_quantity, 0);
        v_allocated := LEAST(v_available, v_remaining);
        IF v_allocated > 0 THEN
          UPDATE public.pos_stock
          SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_allocated, updated_at = now()
          WHERE id = v_stock.id;
          INSERT INTO public.marketplace_stock_allocations(
            reservation_id, reservation_item_id, tenant_id, pos_product_id, pos_variant_id,
            product_id, outlet_id, quantity
          )
          VALUES (
            v_reservation_id, v_item_id, v_tenant_id, v_pos_product_id, v_pos_variant_id,
            v_product_id, v_stock.outlet_id, v_allocated
          );
          v_remaining := v_remaining - v_allocated;
        END IF;
      END LOOP;
      IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Insufficient POS outlet stock' USING ERRCODE = '23514';
      END IF;
    ELSIF v_variant_id IS NOT NULL THEN
      IF v_variant.stock - v_variant.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace variant stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.product_variants
      SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_variant_id;
    ELSE
      IF v_product.stock - v_product.reserved_stock < v_qty THEN
        RAISE EXCEPTION 'Insufficient marketplace stock' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products SET reserved_stock = reserved_stock + v_qty, updated_at = now()
      WHERE id = v_product_id;
    END IF;
    v_total := v_total + v_qty;
  END LOOP;

  RETURN jsonb_build_object('reservation_id', v_reservation_id, 'status', 'active', 'quantity', v_total, 'expires_at', p_expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_marketplace_stock_reservation(
  p_order_id uuid,
  p_status text DEFAULT 'released'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_user_is_buyer boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  SELECT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND buyer_id = auth.uid()) INTO v_user_is_buyer;
  IF NOT v_user_is_buyer AND NOT EXISTS (
    SELECT 1 FROM public.orders o JOIN public.merchants m ON m.id = o.merchant_id
    WHERE o.id = p_order_id AND m.user_id = auth.uid()
  ) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Reservation access denied' USING ERRCODE = '42501';
  END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active' FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NOT DISTINCT FROM v_allocation.pos_variant_id;
    UPDATE public.marketplace_stock_allocations
    SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
        released_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.* FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (SELECT 1 FROM public.marketplace_stock_allocations a WHERE a.reservation_item_id = i.id)
  LOOP
    IF v_item.variant_id IS NOT NULL THEN
      UPDATE public.product_variants
      SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
      WHERE id = v_item.variant_id;
    ELSE
      UPDATE public.products
      SET reserved_stock = GREATEST(0, reserved_stock - v_item.quantity), updated_at = now()
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  UPDATE public.marketplace_stock_reservations
  SET status = CASE WHEN p_status IN ('expired', 'released') THEN p_status ELSE 'released' END,
      released_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_marketplace_stock_reservation(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.marketplace_stock_reservations%ROWTYPE;
  v_item record;
  v_allocation record;
  v_product public.products%ROWTYPE;
  v_variant public.product_variants%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM public.marketplace_stock_reservations WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'not_found'); END IF;
  IF v_res.status = 'consumed' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed', 'duplicate', true); END IF;
  IF v_res.status <> 'active' THEN RETURN jsonb_build_object('order_id', p_order_id, 'status', v_res.status); END IF;

  FOR v_allocation IN
    SELECT * FROM public.marketplace_stock_allocations
    WHERE reservation_id = v_res.id AND status = 'active' FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_allocation.quantity, 0),
        reserved_quantity = GREATEST(COALESCE(reserved_quantity, 0) - v_allocation.quantity, 0),
        updated_at = now()
    WHERE tenant_id = v_allocation.tenant_id
      AND outlet_id = v_allocation.outlet_id
      AND product_id = v_allocation.pos_product_id
      AND variant_id IS NOT DISTINCT FROM v_allocation.pos_variant_id;
    UPDATE public.marketplace_stock_allocations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_allocation.id;
  END LOOP;

  FOR v_item IN
    SELECT i.* FROM public.marketplace_stock_reservation_items i
    WHERE i.reservation_id = v_res.id
      AND NOT EXISTS (SELECT 1 FROM public.marketplace_stock_allocations a WHERE a.reservation_item_id = i.id)
  LOOP
    IF v_item.variant_id IS NOT NULL THEN
      SELECT * INTO v_variant FROM public.product_variants WHERE id = v_item.variant_id FOR UPDATE;
      IF NOT FOUND OR v_variant.reserved_stock < v_item.quantity OR v_variant.stock < v_item.quantity THEN
        RAISE EXCEPTION 'Reserved marketplace variant stock is no longer available' USING ERRCODE = '23514';
      END IF;
      UPDATE public.product_variants
      SET stock = stock - v_item.quantity,
          reserved_stock = reserved_stock - v_item.quantity,
          updated_at = now()
      WHERE id = v_item.variant_id;
    ELSE
      SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
      IF NOT FOUND OR v_product.reserved_stock < v_item.quantity OR v_product.stock < v_item.quantity THEN
        RAISE EXCEPTION 'Reserved marketplace stock is no longer available' USING ERRCODE = '23514';
      END IF;
      UPDATE public.products
      SET stock = stock - v_item.quantity,
          reserved_stock = reserved_stock - v_item.quantity,
          sold_count = COALESCE(sold_count, 0) + v_item.quantity,
          updated_at = now()
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  UPDATE public.marketplace_stock_reservations SET status = 'consumed', consumed_at = now()
  WHERE id = v_res.id;
  RETURN jsonb_build_object('order_id', p_order_id, 'status', 'consumed');
END;
$$;

REVOKE ALL ON FUNCTION public.sync_merchant_product_variant_to_pos(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_merchant_product_variants_for_product(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_pos_stock_scope() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_stock_to_marketplace_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.consume_marketplace_stock_reservation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_pos_stock_to_marketplace(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_marketplace_stock(uuid, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_marketplace_stock_reservation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_stock_reservation(uuid) TO authenticated;
-- ===== END BUNDLE: 23_20260907100000_pos_variant_outlet_stock_contract.sql =====

-- ===== BEGIN BUNDLE: 24_20260907110000_phase4_canonical_reporting.sql =====
-- SaDesa manual bootstrap bundle; Phase 4 canonical reporting.
-- Apply after bundle 23 on a project that already has the POS bootstrap.
-- This bundle intentionally keeps reporting calculations server-side so every
-- report/export uses the same tenant, outlet, status, and date definitions.

CREATE OR REPLACE FUNCTION public.get_pos_canonical_report(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sales jsonb;
  v_returns jsonb;
  v_cash jsonb;
  v_cash_mutations jsonb;
  v_purchases jsonb;
  v_shifts jsonb;
  v_journal_summary jsonb;
  v_daily jsonb;
  v_top_products jsonb;
BEGIN
  IF auth.uid() IS NULL
     OR p_tenant_id IS NULL
     OR p_outlet_id IS NULL
     OR p_from IS NULL
     OR p_to IS NULL
     OR p_from > p_to
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid canonical report scope' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'transactions', COUNT(*)::integer,
    'gross_revenue', COALESCE(SUM(subtotal), 0),
    'discounts', COALESCE(SUM(discount_amount), 0),
    'tax', COALESCE(SUM(tax_amount), 0),
    'net_revenue', COALESCE(SUM(total), 0),
    'cash', COALESCE(SUM(total) FILTER (WHERE payment_method = 'cash'), 0),
    'qris', COALESCE(SUM(total) FILTER (WHERE payment_method = 'qris'), 0),
    'transfer', COALESCE(SUM(total) FILTER (WHERE payment_method = 'transfer'), 0),
    'debit', COALESCE(SUM(total) FILTER (WHERE payment_method = 'debit'), 0),
    'credit', COALESCE(SUM(total) FILTER (WHERE payment_method = 'credit'), 0),
    'split', COALESCE(SUM(total) FILTER (WHERE payment_method = 'split'), 0)
  )
  INTO v_sales
  FROM public.pos_sales
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status = 'completed'
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cogs', COALESCE(SUM(i.cost_price * i.qty), 0),
    'items', COALESCE(SUM(i.qty), 0)
  )
  INTO v_returns
  FROM public.pos_sale_items i
  JOIN public.pos_sales s ON s.id = i.sale_id
  WHERE s.tenant_id = p_tenant_id
    AND s.outlet_id = p_outlet_id
    AND s.status = 'completed'
    AND s.created_at >= p_from
    AND s.created_at <= p_to;

  SELECT jsonb_build_object(
    'count', COUNT(*)::integer,
    'total_refund', COALESCE(SUM(total_refund), 0),
    'cash_refund', COALESCE(SUM(total_refund) FILTER (WHERE refund_method = 'cash'), 0),
    'store_credit_refund', COALESCE(SUM(total_refund) FILTER (WHERE refund_method = 'store_credit'), 0)
  )
  INTO v_cash
  FROM public.pos_sale_returns
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status IN ('approved', 'processed')
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cash_in', COALESCE(SUM(amount) FILTER (WHERE type = 'in' AND COALESCE(category, 'other') <> 'sales_cash'), 0),
    'cash_out', COALESCE(SUM(amount) FILTER (WHERE type = 'out'), 0),
    'by_category', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('category', category, 'type', type, 'amount', amount))
      FROM (
        SELECT type, COALESCE(category, 'other') AS category, SUM(amount) AS amount
        FROM public.pos_cash_mutations
        WHERE tenant_id = p_tenant_id
          AND outlet_id = p_outlet_id
          AND created_at >= p_from
          AND created_at <= p_to
          AND NOT (type = 'in' AND category = 'sales_cash')
        GROUP BY type, COALESCE(category, 'other')
        ORDER BY type, amount DESC
      ) mutation_totals
    ), '[]'::jsonb)
  )
  INTO v_cash_mutations
  FROM public.pos_cash_mutations
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cash_paid', COALESCE(SUM(amount_paid), 0),
    'received_total', COALESCE(SUM(total), 0),
    'count', COUNT(*)::integer,
    'by_status', COALESCE(jsonb_agg(jsonb_build_object('status', status, 'amount_paid', amount_paid)), '[]'::jsonb)
  )
  INTO v_purchases
  FROM public.pos_purchase_orders
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status IN ('received', 'partial')
    AND COALESCE(received_date::timestamptz, created_at) >= p_from
    AND COALESCE(received_date::timestamptz, created_at) <= p_to;

  SELECT jsonb_build_object(
    'closed_count', COUNT(*) FILTER (WHERE status = 'closed')::integer,
    'open_count', COUNT(*) FILTER (WHERE status = 'open')::integer,
    'difference', COALESCE(SUM(difference) FILTER (WHERE status = 'closed'), 0),
    'absolute_difference', COALESCE(SUM(ABS(difference)) FILTER (WHERE status = 'closed'), 0),
    'unreconciled_count', COUNT(*) FILTER (WHERE status = 'closed' AND COALESCE(difference, 0) <> 0)::integer
  )
  INTO v_shifts
  FROM public.pos_cash_sessions
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND opened_at >= p_from
    AND opened_at <= p_to;

  SELECT jsonb_build_object(
    'entry_count', COUNT(DISTINCT e.id)::integer,
    'debit', COALESCE(SUM(l.debit), 0),
    'credit', COALESCE(SUM(l.credit), 0),
    'balanced', COALESCE(SUM(l.debit), 0) = COALESCE(SUM(l.credit), 0),
    'unbalanced_entries', COUNT(DISTINCT e.id) FILTER (WHERE e.id IN (
      SELECT entry_id
      FROM (
        SELECT e2.id AS entry_id, SUM(l2.debit) AS debit, SUM(l2.credit) AS credit
        FROM public.pos_journal_entries e2
        JOIN public.pos_journal_lines l2 ON l2.journal_entry_id = e2.id
        WHERE e2.tenant_id = p_tenant_id
          AND (e2.outlet_id = p_outlet_id OR e2.outlet_id IS NULL)
          AND e2.status = 'posted'
          AND e2.entry_date >= p_from::date
          AND e2.entry_date <= p_to::date
        GROUP BY e2.id
        HAVING SUM(l2.debit) <> SUM(l2.credit)
      ) unbalanced
    ))::integer
  )
  INTO v_journal_summary
  FROM public.pos_journal_entries e
  JOIN public.pos_journal_lines l ON l.journal_entry_id = e.id
  WHERE e.tenant_id = p_tenant_id
    AND (e.outlet_id = p_outlet_id OR e.outlet_id IS NULL)
    AND e.status = 'posted'
    AND e.entry_date >= p_from::date
    AND e.entry_date <= p_to::date;

  SELECT COALESCE(jsonb_agg(row_to_json(product_totals)::jsonb ORDER BY product_totals.profit DESC), '[]'::jsonb)
  INTO v_top_products
  FROM (
    SELECT
      i.product_name AS name,
      SUM(i.qty) AS qty,
      SUM(i.subtotal) AS revenue,
      SUM(i.cost_price * i.qty) AS cogs,
      SUM(i.subtotal - (i.cost_price * i.qty)) AS profit
    FROM public.pos_sale_items i
    JOIN public.pos_sales s ON s.id = i.sale_id
    WHERE s.tenant_id = p_tenant_id
      AND s.outlet_id = p_outlet_id
      AND s.status = 'completed'
      AND s.created_at >= p_from
      AND s.created_at <= p_to
    GROUP BY i.product_name
    ORDER BY profit DESC
    LIMIT 10
  ) product_totals;

  SELECT COALESCE(jsonb_agg(row_to_json(day_totals)::jsonb ORDER BY day_totals.period), '[]'::jsonb)
  INTO v_daily
  FROM (
    SELECT
      d.period::date AS period,
      COALESCE((
        SELECT SUM(s.total)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS revenue,
      COALESCE((
        SELECT SUM(s.discount_amount)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS discounts,
      COALESCE((
        SELECT SUM(si.cost_price * si.qty)
        FROM public.pos_sale_items si
        JOIN public.pos_sales s ON s.id = si.sale_id
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS cogs,
      (
        SELECT COUNT(*)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      )::integer AS transactions,
      COALESCE((
        SELECT SUM(amount)
        FROM public.pos_cash_mutations m
        WHERE m.tenant_id = p_tenant_id
          AND m.outlet_id = p_outlet_id
          AND m.type = 'in'
          AND m.category <> 'sales_cash'
          AND m.created_at >= d.period
          AND m.created_at < d.period + interval '1 day'
      ), 0) AS cash_in,
      COALESCE((
        SELECT SUM(amount)
        FROM public.pos_cash_mutations m
        WHERE m.tenant_id = p_tenant_id
          AND m.outlet_id = p_outlet_id
          AND m.type = 'out'
          AND m.created_at >= d.period
          AND m.created_at < d.period + interval '1 day'
      ), 0) AS cash_out,
      COALESCE((
        SELECT SUM(amount_paid)
        FROM public.pos_purchase_orders p
        WHERE p.tenant_id = p_tenant_id
          AND p.outlet_id = p_outlet_id
          AND p.status IN ('received', 'partial')
          AND COALESCE(p.received_date::timestamptz, p.created_at) >= d.period
          AND COALESCE(p.received_date::timestamptz, p.created_at) < d.period + interval '1 day'
      ), 0) AS purchase_cash
    FROM generate_series(p_from::date, p_to::date, interval '1 day') d(period)
  ) day_totals;

  RETURN jsonb_build_object(
    'scope', jsonb_build_object('tenant_id', p_tenant_id, 'outlet_id', p_outlet_id, 'from', p_from, 'to', p_to),
    'sales', v_sales,
    'costs', v_returns,
    'returns', v_cash,
    'cash_mutations', v_cash_mutations,
    'purchases', v_purchases,
    'shifts', v_shifts,
    'journal', v_journal_summary,
    'top_products', v_top_products,
    'daily', v_daily
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
IS 'Canonical tenant/outlet-scoped POS reporting contract. Uses completed sales, approved/processed returns, actual cash mutations, paid purchases, closed shifts, and posted journals.';
-- ===== END BUNDLE: 24_20260907110000_phase4_canonical_reporting.sql =====

-- ===== BEGIN BUNDLE: 25_20260907130000_phase4_debt_reconciliation.sql =====
-- SaDesa manual bootstrap bundle; Phase 4 debt payment and daily reconciliation.
-- Apply after bundle 24.

CREATE TABLE IF NOT EXISTS public.pos_debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('payable', 'receivable')),
  party_name text NOT NULL,
  phone text,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  remaining numeric(15,2) NOT NULL CHECK (remaining >= 0),
  due_date date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid')),
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.pos_debt_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id uuid NOT NULL REFERENCES public.pos_debts(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'transfer', 'debit', 'credit', 'other')),
  paid_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pos_debts_scope_status
  ON public.pos_debts(tenant_id, outlet_id, status, due_date);
CREATE INDEX IF NOT EXISTS idx_pos_debt_payments_scope_paid_at
  ON public.pos_debt_payments(tenant_id, outlet_id, paid_at DESC);

ALTER TABLE public.pos_debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_debt_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view debts" ON public.pos_debts;
CREATE POLICY "POS users view debts"
  ON public.pos_debts FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create debts" ON public.pos_debts;
CREATE POLICY "POS users create debts"
  ON public.pos_debts FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view debt payments" ON public.pos_debt_payments;
CREATE POLICY "POS users view debt payments"
  ON public.pos_debt_payments FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.record_pos_debt_payment(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_debt_id uuid,
  p_amount numeric,
  p_payment_method text DEFAULT 'cash',
  p_paid_at timestamptz DEFAULT now(),
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debt public.pos_debts%ROWTYPE;
  v_payment_id uuid;
  v_remaining numeric;
  v_status text;
  v_cash_type text;
  v_cash_category text;
BEGIN
  IF auth.uid() IS NULL
     OR p_amount IS NULL
     OR p_amount <= 0
     OR p_payment_method NOT IN ('cash', 'transfer', 'debit', 'credit', 'other')
     OR p_paid_at IS NULL
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid debt payment' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_debt
  FROM public.pos_debts
  WHERE id = p_debt_id
    AND tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
  FOR UPDATE;

  IF NOT FOUND OR v_debt.status = 'paid' THEN
    RAISE EXCEPTION 'Debt is not payable' USING ERRCODE = '55000';
  END IF;
  IF p_amount > v_debt.remaining THEN
    RAISE EXCEPTION 'Payment exceeds outstanding debt' USING ERRCODE = '23514';
  END IF;

  v_remaining := GREATEST(0, v_debt.remaining - p_amount);
  v_status := CASE WHEN v_remaining = 0 THEN 'paid' ELSE 'active' END;
  v_cash_type := CASE WHEN v_debt.type = 'receivable' THEN 'in' ELSE 'out' END;
  v_cash_category := CASE WHEN v_debt.type = 'receivable' THEN 'hutang_diterima' ELSE 'hutang_bayar' END;

  INSERT INTO public.pos_debt_payments(
    debt_id, tenant_id, outlet_id, amount, payment_method, paid_at, notes, created_by
  )
  VALUES (
    v_debt.id, p_tenant_id, p_outlet_id, p_amount, p_payment_method, p_paid_at,
    NULLIF(trim(p_notes), ''), auth.uid()
  )
  RETURNING id INTO v_payment_id;

  UPDATE public.pos_debts
  SET remaining = v_remaining,
      status = v_status,
      updated_at = now()
  WHERE id = v_debt.id;

  IF p_payment_method = 'cash' THEN
    INSERT INTO public.pos_cash_mutations(
      tenant_id, outlet_id, type, category, amount, description, reference, created_by, created_at
    )
    VALUES (
      p_tenant_id,
      p_outlet_id,
      v_cash_type,
      v_cash_category,
      p_amount,
      CASE WHEN v_debt.type = 'receivable' THEN 'Pembayaran piutang: ' ELSE 'Pembayaran hutang: ' END || v_debt.party_name,
      v_payment_id::text,
      auth.uid(),
      p_paid_at
    );
  END IF;

  RETURN jsonb_build_object(
    'payment_id', v_payment_id,
    'debt_id', v_debt.id,
    'type', v_debt.type,
    'amount', p_amount,
    'remaining', v_remaining,
    'status', v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_pos_debt_payment(uuid, uuid, uuid, numeric, text, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_pos_debt_payment(uuid, uuid, uuid, numeric, text, timestamptz, text)
  TO authenticated;

-- The first reporting bundle used purchase-order cumulative amount_paid, which
-- is not safe for a bounded cashflow period. Keep it as a private implementation
-- detail and expose a corrected wrapper based on actual supplier payments.
ALTER FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  RENAME TO get_pos_canonical_report_legacy;

CREATE OR REPLACE FUNCTION public.get_pos_canonical_report(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report jsonb;
  v_purchases jsonb;
  v_daily jsonb := '[]'::jsonb;
  v_day jsonb;
  v_day_date date;
  v_paid numeric;
BEGIN
  IF auth.uid() IS NULL
     OR p_tenant_id IS NULL
     OR p_outlet_id IS NULL
     OR p_from IS NULL
     OR p_to IS NULL
     OR p_from > p_to
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid canonical report scope' USING ERRCODE = '42501';
  END IF;

  v_report := public.get_pos_canonical_report_legacy(p_tenant_id, p_outlet_id, p_from, p_to);

  SELECT COALESCE(SUM(amount) FILTER (WHERE payment_method = 'cash'), 0)
  INTO v_paid
  FROM public.pos_supplier_payments
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND paid_at >= p_from
    AND paid_at <= p_to;

  v_purchases := jsonb_set(
    COALESCE(v_report->'purchases', '{}'::jsonb),
    '{cash_paid}',
    to_jsonb(v_paid),
    true
  );
  v_report := jsonb_set(v_report, '{purchases}', v_purchases, true);

  FOR v_day IN
    SELECT value FROM jsonb_array_elements(COALESCE(v_report->'daily', '[]'::jsonb))
  LOOP
    v_day_date := (v_day->>'period')::date;
    SELECT COALESCE(SUM(amount), 0)
    INTO v_paid
    FROM public.pos_supplier_payments
    WHERE tenant_id = p_tenant_id
      AND outlet_id = p_outlet_id
      AND paid_at >= v_day_date::timestamptz
      AND paid_at < (v_day_date + 1)::timestamptz;
    v_daily := v_daily || jsonb_build_array(
      jsonb_set(v_day, '{purchase_cash}', to_jsonb(v_paid), true)
    );
  END LOOP;

  RETURN jsonb_set(v_report, '{daily}', v_daily, true);
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_canonical_report_legacy(uuid, uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  TO authenticated;

CREATE TABLE IF NOT EXISTS public.pos_daily_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  reconciliation_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('balanced', 'attention', 'unbalanced')),
  sales_total numeric(15,2) NOT NULL DEFAULT 0,
  cash_sales numeric(15,2) NOT NULL DEFAULT 0,
  cash_refunds numeric(15,2) NOT NULL DEFAULT 0,
  cash_in numeric(15,2) NOT NULL DEFAULT 0,
  cash_out numeric(15,2) NOT NULL DEFAULT 0,
  supplier_payments numeric(15,2) NOT NULL DEFAULT 0,
  shift_difference numeric(15,2) NOT NULL DEFAULT 0,
  unreconciled_sessions integer NOT NULL DEFAULT 0,
  journal_debit numeric(15,2) NOT NULL DEFAULT 0,
  journal_credit numeric(15,2) NOT NULL DEFAULT 0,
  unbalanced_journals integer NOT NULL DEFAULT 0,
  report_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  reconciled_by uuid REFERENCES auth.users(id),
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, outlet_id, reconciliation_date)
);

CREATE INDEX IF NOT EXISTS idx_pos_daily_reconciliations_scope_date
  ON public.pos_daily_reconciliations(tenant_id, outlet_id, reconciliation_date DESC);

ALTER TABLE public.pos_daily_reconciliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view daily reconciliations" ON public.pos_daily_reconciliations;
CREATE POLICY "POS users view daily reconciliations"
  ON public.pos_daily_reconciliations FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.get_pos_daily_reconciliation(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_reconciliation_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report jsonb;
  v_shift_difference numeric;
  v_unreconciled_sessions integer;
  v_unbalanced_journals integer;
  v_status text;
BEGIN
  IF auth.uid() IS NULL
     OR p_reconciliation_date IS NULL
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid daily reconciliation scope' USING ERRCODE = '42501';
  END IF;

  v_report := public.get_pos_canonical_report(
    p_tenant_id,
    p_outlet_id,
    p_reconciliation_date::timestamptz,
    ((p_reconciliation_date + 1)::timestamptz - interval '1 microsecond')
  );
  v_shift_difference := COALESCE((v_report #>> '{shifts,difference}')::numeric, 0);
  v_unreconciled_sessions := COALESCE((v_report #>> '{shifts,unreconciled_count}')::integer, 0);
  v_unbalanced_journals := COALESCE((v_report #>> '{journal,unbalanced_entries}')::integer, 0);
  v_status := CASE
    WHEN v_unbalanced_journals > 0 THEN 'unbalanced'
    WHEN v_unreconciled_sessions > 0 OR ABS(v_shift_difference) > 0.01 THEN 'attention'
    ELSE 'balanced'
  END;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'outlet_id', p_outlet_id,
    'reconciliation_date', p_reconciliation_date,
    'status', v_status,
    'sales_total', COALESCE((v_report #>> '{sales,net_revenue}')::numeric, 0),
    'cash_sales', COALESCE((v_report #>> '{sales,cash}')::numeric, 0),
    'cash_refunds', COALESCE((v_report #>> '{returns,cash_refund}')::numeric, 0),
    'cash_in', COALESCE((v_report #>> '{cash_mutations,cash_in}')::numeric, 0),
    'cash_out', COALESCE((v_report #>> '{cash_mutations,cash_out}')::numeric, 0),
    'supplier_payments', COALESCE((v_report #>> '{purchases,cash_paid}')::numeric, 0),
    'shift_difference', v_shift_difference,
    'unreconciled_sessions', v_unreconciled_sessions,
    'journal_debit', COALESCE((v_report #>> '{journal,debit}')::numeric, 0),
    'journal_credit', COALESCE((v_report #>> '{journal,credit}')::numeric, 0),
    'unbalanced_journals', v_unbalanced_journals,
    'report_snapshot', v_report
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_pos_daily(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_reconciliation_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Daily reconciliation denied' USING ERRCODE = '42501';
  END IF;

  v_result := public.get_pos_daily_reconciliation(p_tenant_id, p_outlet_id, p_reconciliation_date);
  INSERT INTO public.pos_daily_reconciliations(
    tenant_id, outlet_id, reconciliation_date, status, sales_total, cash_sales,
    cash_refunds, cash_in, cash_out, supplier_payments, shift_difference,
    unreconciled_sessions, journal_debit, journal_credit, unbalanced_journals,
    report_snapshot, reconciled_by, reconciled_at, updated_at
  )
  VALUES (
    p_tenant_id, p_outlet_id, p_reconciliation_date,
    v_result->>'status',
    (v_result->>'sales_total')::numeric,
    (v_result->>'cash_sales')::numeric,
    (v_result->>'cash_refunds')::numeric,
    (v_result->>'cash_in')::numeric,
    (v_result->>'cash_out')::numeric,
    (v_result->>'supplier_payments')::numeric,
    (v_result->>'shift_difference')::numeric,
    (v_result->>'unreconciled_sessions')::integer,
    (v_result->>'journal_debit')::numeric,
    (v_result->>'journal_credit')::numeric,
    (v_result->>'unbalanced_journals')::integer,
    v_result->'report_snapshot',
    auth.uid(),
    now(),
    now()
  )
  ON CONFLICT (tenant_id, outlet_id, reconciliation_date) DO UPDATE SET
    status = EXCLUDED.status,
    sales_total = EXCLUDED.sales_total,
    cash_sales = EXCLUDED.cash_sales,
    cash_refunds = EXCLUDED.cash_refunds,
    cash_in = EXCLUDED.cash_in,
    cash_out = EXCLUDED.cash_out,
    supplier_payments = EXCLUDED.supplier_payments,
    shift_difference = EXCLUDED.shift_difference,
    unreconciled_sessions = EXCLUDED.unreconciled_sessions,
    journal_debit = EXCLUDED.journal_debit,
    journal_credit = EXCLUDED.journal_credit,
    unbalanced_journals = EXCLUDED.unbalanced_journals,
    report_snapshot = EXCLUDED.report_snapshot,
    reconciled_by = EXCLUDED.reconciled_by,
    reconciled_at = EXCLUDED.reconciled_at,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_result || jsonb_build_object('reconciliation_id', v_id, 'reconciled_at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_daily_reconciliation(uuid, uuid, date)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reconcile_pos_daily(uuid, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_daily_reconciliation(uuid, uuid, date)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_pos_daily(uuid, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pos_posted_journal(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_from date,
  p_to date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entries jsonb;
  v_total_debit numeric;
  v_total_credit numeric;
  v_entry_count integer;
BEGIN
  IF auth.uid() IS NULL
     OR p_from IS NULL
     OR p_to IS NULL
     OR p_from > p_to
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid posted journal scope' USING ERRCODE = '42501';
  END IF;

  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'date', to_char(e.entry_date, 'DD/MM/YYYY'),
      'ref', e.entry_number,
      'description', e.memo,
      'account_code', l.account_code,
      'account_name', l.account_name,
      'debit', l.debit,
      'credit', l.credit
    ) ORDER BY e.entry_date, e.entry_number, l.id), '[]'::jsonb),
    COALESCE(SUM(l.debit), 0),
    COALESCE(SUM(l.credit), 0),
    COUNT(DISTINCT e.id)::integer
  INTO v_entries, v_total_debit, v_total_credit, v_entry_count
  FROM public.pos_journal_entries e
  JOIN public.pos_journal_lines l ON l.journal_entry_id = e.id
  WHERE e.tenant_id = p_tenant_id
    AND e.outlet_id = p_outlet_id
    AND e.status = 'posted'
    AND e.entry_date BETWEEN p_from AND p_to;

  RETURN jsonb_build_object(
    'entries', v_entries,
    'entry_count', v_entry_count,
    'total_debit', v_total_debit,
    'total_credit', v_total_credit,
    'balanced', v_total_debit = v_total_credit
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_posted_journal(uuid, uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_posted_journal(uuid, uuid, date, date)
  TO authenticated;
-- ===== END BUNDLE: 25_20260907130000_phase4_debt_reconciliation.sql =====

-- ===== BEGIN BUNDLE: 26_20260908100000_phase5_commercial_entitlements.sql =====
-- Fase 5: pertumbuhan dan monetisasi lanjutan.
-- Paket tetap menjadi sumber konfigurasi limit POS; transaksi tetap
-- divalidasi oleh guard server-side, bukan hanya oleh UI.

ALTER TABLE public.pos_packages
  ADD COLUMN IF NOT EXISTS max_outlets INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_users INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS add_on_user_price INTEGER NOT NULL DEFAULT 25000,
  ADD COLUMN IF NOT EXISTS priority_support BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_discount_percent INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS onboarding_discount_expires_at TIMESTAMPTZ;

ALTER TABLE public.pos_packages
  DROP CONSTRAINT IF EXISTS pos_packages_limits_check;
ALTER TABLE public.pos_packages
  ADD CONSTRAINT pos_packages_limits_check CHECK (
    max_outlets > 0
    AND max_users > 0
    AND add_on_user_price >= 0
    AND onboarding_discount_percent BETWEEN 0 AND 100
  );

UPDATE public.pos_packages
SET
  max_outlets = CASE
    WHEN lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%' THEN 99
    WHEN lower(name) LIKE '%pro%' OR lower(name) LIKE '%growth%' THEN 3
    ELSE 1
  END,
  max_users = CASE
    WHEN lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%' THEN 20
    WHEN lower(name) LIKE '%pro%' OR lower(name) LIKE '%growth%' THEN 5
    ELSE 2
  END,
  priority_support = lower(name) LIKE '%enterprise%' OR lower(name) LIKE '%business%';

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  partner_type TEXT,
  discount_percent INTEGER NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  max_redemptions INTEGER,
  redeemed_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pos_onboarding_promotions_discount_check CHECK (discount_percent BETWEEN 0 AND 100),
  CONSTRAINT pos_onboarding_promotions_redemption_check CHECK (
    max_redemptions IS NULL OR max_redemptions > 0
  )
);

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotion_redemptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  promotion_id UUID NOT NULL REFERENCES public.pos_onboarding_promotions(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, merchant_id)
);

ALTER TABLE public.pos_onboarding_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_onboarding_promotion_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Anyone can view active onboarding promotions"
  ON public.pos_onboarding_promotions FOR SELECT TO authenticated
  USING (is_active AND starts_at <= now() AND expires_at > now());

DROP POLICY IF EXISTS "Admins manage onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Admins manage onboarding promotions"
  ON public.pos_onboarding_promotions FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Merchants view own promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Merchants view own promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = merchant_id AND m.user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Admins view promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Admins view promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (is_admin());

CREATE OR REPLACE FUNCTION public.get_pos_commercial_entitlement(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_outlet_count INTEGER;
  v_user_count INTEGER;
BEGIN
  SELECT * INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id;

  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'POS tenant tidak ditemukan';
  END IF;

  IF v_tenant.user_id <> auth.uid() AND NOT is_admin() THEN
    RAISE EXCEPTION 'Tidak berwenang melihat entitlement tenant ini';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status IN ('ACTIVE', 'PENDING')
  ORDER BY ps.created_at DESC
  LIMIT 1;

  IF v_subscription.package_id IS NOT NULL THEN
    SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  END IF;

  SELECT count(*)::INTEGER INTO v_outlet_count
  FROM public.pos_outlets WHERE tenant_id = p_tenant_id AND is_active;

  SELECT count(*)::INTEGER INTO v_user_count
  FROM public.pos_users WHERE tenant_id = p_tenant_id AND is_active;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'subscription_status', COALESCE(v_subscription.status, 'NONE'),
    'package_id', v_package.id,
    'package_name', COALESCE(v_package.name, 'Trial / legacy'),
    'max_outlets', COALESCE(v_package.max_outlets, 1),
    'max_users', COALESCE(v_package.max_users, 2),
    'add_on_user_price', COALESCE(v_package.add_on_user_price, 25000),
    'priority_support', COALESCE(v_package.priority_support, false),
    'active_outlets', v_outlet_count,
    'active_users', v_user_count,
    'outlets_remaining', GREATEST(COALESCE(v_package.max_outlets, 1) - v_outlet_count, 0),
    'users_remaining', GREATEST(COALESCE(v_package.max_users, 2) - v_user_count, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pos_outlet_with_entitlement_guard(
  p_tenant_id UUID,
  p_name TEXT,
  p_address TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
)
RETURNS public.pos_outlets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_outlet_count INTEGER;
  v_outlet public.pos_outlets%ROWTYPE;
BEGIN
  SELECT * INTO v_tenant FROM public.pos_tenants
  WHERE id = p_tenant_id AND user_id = auth.uid();
  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'Tidak berwenang menambah outlet pada tenant ini';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;
  IF v_subscription.id IS NULL THEN
    RAISE EXCEPTION 'Subscription POS aktif diperlukan untuk menambah outlet';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  SELECT count(*)::INTEGER INTO v_outlet_count
  FROM public.pos_outlets WHERE tenant_id = p_tenant_id AND is_active;
  IF v_outlet_count >= COALESCE(v_package.max_outlets, 1) THEN
    RAISE EXCEPTION 'Batas outlet paket % tercapai (% outlet)', COALESCE(v_package.name, 'POS'), COALESCE(v_package.max_outlets, 1);
  END IF;

  INSERT INTO public.pos_outlets (tenant_id, name, address, phone)
  VALUES (p_tenant_id, NULLIF(trim(p_name), ''), NULLIF(trim(p_address), ''), NULLIF(trim(p_phone), ''))
  RETURNING * INTO v_outlet;
  RETURN v_outlet;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pos_commercial_entitlement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pos_outlet_with_entitlement_guard(UUID, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_pos_package(
  p_package_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_duration_months INTEGER,
  p_price INTEGER,
  p_max_outlets INTEGER,
  p_max_users INTEGER,
  p_add_on_user_price INTEGER,
  p_priority_support BOOLEAN,
  p_onboarding_discount_percent INTEGER,
  p_onboarding_discount_expires_at TIMESTAMPTZ,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before public.pos_packages%ROWTYPE;
  v_after public.pos_packages%ROWTYPE;
  v_reason TEXT := NULLIF(trim(p_reason), '');
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can update POS packages' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(p_name), '') IS NULL OR v_reason IS NULL
    OR COALESCE(p_duration_months, 0) < 1 OR COALESCE(p_price, -1) < 0
    OR COALESCE(p_max_outlets, 0) < 1 OR COALESCE(p_max_users, 0) < 1
    OR COALESCE(p_add_on_user_price, -1) < 0
    OR COALESCE(p_onboarding_discount_percent, -1) NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'Data paket atau alasan perubahan tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.pos_packages WHERE id = p_package_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS package not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.pos_packages
  SET name = trim(p_name),
      description = NULLIF(trim(COALESCE(p_description, '')), ''),
      duration_months = p_duration_months,
      price = p_price,
      max_outlets = p_max_outlets,
      max_users = p_max_users,
      add_on_user_price = p_add_on_user_price,
      priority_support = COALESCE(p_priority_support, false),
      onboarding_discount_percent = p_onboarding_discount_percent,
      onboarding_discount_expires_at = p_onboarding_discount_expires_at
  WHERE id = p_package_id;

  SELECT * INTO v_after FROM public.pos_packages WHERE id = p_package_id;
  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  ) VALUES (
    auth.uid(), 'UPDATE_POS_PACKAGE_LIMITS', 'pos_package', p_package_id,
    to_jsonb(v_before), to_jsonb(v_after) || jsonb_build_object('reason', v_reason)
  );
  RETURN to_jsonb(v_after);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_pos_package(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, BOOLEAN, INTEGER, TIMESTAMPTZ, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_pos_package(
  UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, BOOLEAN, INTEGER, TIMESTAMPTZ, TEXT
) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pos_user_with_entitlement_guard(
  p_tenant_id UUID,
  p_name TEXT,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'kasir',
  p_outlet_id UUID DEFAULT NULL,
  p_pin TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true
)
RETURNS public.pos_users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_user_count INTEGER;
  v_user public.pos_users%ROWTYPE;
BEGIN
  SELECT * INTO v_tenant FROM public.pos_tenants
  WHERE id = p_tenant_id AND user_id = auth.uid();
  IF v_tenant.id IS NULL THEN
    RAISE EXCEPTION 'Tidak berwenang menambah pengguna pada tenant ini';
  END IF;
  IF p_role NOT IN ('owner', 'manager', 'kasir', 'staff_gudang', 'purchasing', 'finance', 'auditor') THEN
    RAISE EXCEPTION 'Role pengguna tidak valid';
  END IF;
  IF p_outlet_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.pos_outlets
    WHERE id = p_outlet_id AND tenant_id = p_tenant_id AND is_active
  ) THEN
    RAISE EXCEPTION 'Outlet pengguna tidak valid';
  END IF;

  SELECT ps.* INTO v_subscription
  FROM public.pos_subscriptions ps
  WHERE ps.merchant_id = v_tenant.merchant_id
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;
  IF v_subscription.id IS NULL THEN
    RAISE EXCEPTION 'Subscription POS aktif diperlukan untuk menambah pengguna';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages WHERE id = v_subscription.package_id;
  SELECT count(*)::INTEGER INTO v_user_count
  FROM public.pos_users WHERE tenant_id = p_tenant_id AND is_active;
  IF v_user_count >= COALESCE(v_package.max_users, 2) THEN
    RAISE EXCEPTION 'Batas pengguna paket % tercapai (% pengguna)', COALESCE(v_package.name, 'POS'), COALESCE(v_package.max_users, 2);
  END IF;

  INSERT INTO public.pos_users (tenant_id, name, email, phone, role, outlet_id, pin, is_active)
  VALUES (p_tenant_id, NULLIF(trim(p_name), ''), NULLIF(trim(p_email), ''), NULLIF(trim(p_phone), ''), p_role, p_outlet_id, NULLIF(trim(p_pin), ''), COALESCE(p_is_active, true))
  RETURNING * INTO v_user;
  RETURN v_user;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pos_user_with_entitlement_guard(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_user_with_entitlement_guard(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN) TO authenticated;
-- ===== END BUNDLE: 26_20260908100000_phase5_commercial_entitlements.sql =====

-- ===== BEGIN BUNDLE: 27_20260908120000_partner_promotions_priority_support.sql =====
-- Fase 5: partner desa/koperasi, promo onboarding yang benar-benar ditebus,
-- dan SLA dukungan prioritas.

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS original_amount INTEGER,
  ADD COLUMN IF NOT EXISTS discount_amount INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promotion_id UUID REFERENCES public.pos_onboarding_promotions(id),
  ADD COLUMN IF NOT EXISTS promotion_code TEXT;

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_promotion_id
  ON public.pos_subscriptions(promotion_id);

DROP FUNCTION IF EXISTS public.preview_pos_onboarding_promotion(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.preview_pos_onboarding_promotion(
  p_code TEXT,
  p_package_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id UUID;
  v_promotion public.pos_onboarding_promotions%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_discount_amount INTEGER;
  v_final_amount INTEGER;
BEGIN
  SELECT id INTO v_merchant_id FROM public.merchants WHERE user_id = auth.uid();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan';
  END IF;

  SELECT * INTO v_promotion
  FROM public.pos_onboarding_promotions
  WHERE code = upper(trim(p_code))
    AND is_active
    AND starts_at <= now()
    AND expires_at > now();
  IF v_promotion.id IS NULL THEN
    RAISE EXCEPTION 'Kode promo tidak ditemukan atau sudah kedaluwarsa';
  END IF;
  IF v_promotion.max_redemptions IS NOT NULL
    AND v_promotion.redeemed_count >= v_promotion.max_redemptions THEN
    RAISE EXCEPTION 'Kuota kode promo sudah habis';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.pos_onboarding_promotion_redemptions
    WHERE promotion_id = v_promotion.id AND merchant_id = v_merchant_id
  ) THEN
    RAISE EXCEPTION 'Kode promo ini sudah digunakan oleh merchant Anda';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages
  WHERE id = p_package_id AND is_active;
  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket POS tidak ditemukan';
  END IF;

  v_discount_amount := floor(v_package.price * v_promotion.discount_percent / 100.0);
  v_final_amount := greatest(v_package.price - v_discount_amount, 0);
  RETURN jsonb_build_object(
    'promotion_id', v_promotion.id,
    'code', v_promotion.code,
    'name', v_promotion.name,
    'partner_type', v_promotion.partner_type,
    'discount_percent', v_promotion.discount_percent,
    'discount_amount', v_discount_amount,
    'original_amount', v_package.price,
    'final_amount', v_final_amount,
    'expires_at', v_promotion.expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pos_subscription_with_promotion(
  p_package_id UUID,
  p_payment_proof_url TEXT DEFAULT NULL,
  p_promo_code TEXT DEFAULT NULL
)
RETURNS public.pos_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id UUID;
  v_package public.pos_packages%ROWTYPE;
  v_promotion public.pos_onboarding_promotions%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_discount_amount INTEGER := 0;
  v_original_amount INTEGER;
  v_final_amount INTEGER;
  v_code TEXT := NULLIF(upper(trim(p_promo_code)), '');
BEGIN
  SELECT id INTO v_merchant_id FROM public.merchants WHERE user_id = auth.uid();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages
  WHERE id = p_package_id AND is_active;
  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket POS tidak ditemukan';
  END IF;

  v_original_amount := v_package.price;
  IF v_code IS NOT NULL THEN
    SELECT * INTO v_promotion
    FROM public.pos_onboarding_promotions
    WHERE code = v_code
    FOR UPDATE;
    IF v_promotion.id IS NULL
      OR NOT v_promotion.is_active
      OR v_promotion.starts_at > now()
      OR v_promotion.expires_at <= now() THEN
      RAISE EXCEPTION 'Kode promo tidak ditemukan atau sudah kedaluwarsa';
    END IF;
    IF v_promotion.max_redemptions IS NOT NULL
      AND v_promotion.redeemed_count >= v_promotion.max_redemptions THEN
      RAISE EXCEPTION 'Kuota kode promo sudah habis';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.pos_onboarding_promotion_redemptions
      WHERE promotion_id = v_promotion.id AND merchant_id = v_merchant_id
    ) THEN
      RAISE EXCEPTION 'Kode promo ini sudah digunakan oleh merchant Anda';
    END IF;
    v_discount_amount := floor(v_original_amount * v_promotion.discount_percent / 100.0);
  END IF;
  v_final_amount := greatest(v_original_amount - v_discount_amount, 0);

  INSERT INTO public.pos_subscriptions (
    merchant_id, package_id, status, payment_amount, original_amount,
    discount_amount, promotion_id, promotion_code, payment_proof_url,
    payment_status, started_at, expired_at
  ) VALUES (
    v_merchant_id, p_package_id, 'PENDING', v_final_amount, v_original_amount,
    v_discount_amount, v_promotion.id, v_promotion.code, p_payment_proof_url,
    CASE WHEN v_final_amount = 0 THEN 'FREE' ELSE 'PENDING' END, NULL, NULL
  )
  RETURNING * INTO v_subscription;

  IF v_promotion.id IS NOT NULL THEN
    INSERT INTO public.pos_onboarding_promotion_redemptions (promotion_id, merchant_id)
    VALUES (v_promotion.id, v_merchant_id);
    UPDATE public.pos_onboarding_promotions
    SET redeemed_count = redeemed_count + 1, updated_at = now()
    WHERE id = v_promotion.id;
  END IF;
  RETURN v_subscription;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_pos_onboarding_promotion(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_pos_onboarding_promotion(TEXT, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_pos_subscription_with_promotion(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_subscription_with_promotion(UUID, TEXT, TEXT) TO authenticated;

-- Support tables were historically used by the UI without a canonical
-- bootstrap. IF NOT EXISTS keeps this safe for projects that already have them.
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  priority_source TEXT NOT NULL DEFAULT 'standard',
  status TEXT NOT NULL DEFAULT 'open',
  sla_due_at TIMESTAMPTZ,
  first_response_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_message_at TIMESTAMPTZ,
  message_count INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS priority_source TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS sla_due_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS first_response_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('user', 'admin')),
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_sla
  ON public.support_tickets(status, sla_due_at);
CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket
  ON public.support_ticket_messages(ticket_id, created_at);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own support tickets" ON public.support_tickets;
CREATE POLICY "Users view own support tickets" ON public.support_tickets
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "Users create own support tickets" ON public.support_tickets;
CREATE POLICY "Users create own support tickets" ON public.support_tickets
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "Users update own support tickets" ON public.support_tickets;
CREATE POLICY "Users update own support tickets" ON public.support_tickets
  FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Users view permitted support messages" ON public.support_ticket_messages;
CREATE POLICY "Users view permitted support messages" ON public.support_ticket_messages
  FOR SELECT TO authenticated USING (
    is_admin() OR EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Users create permitted support messages" ON public.support_ticket_messages;
CREATE POLICY "Users create permitted support messages" ON public.support_ticket_messages
  FOR INSERT TO authenticated WITH CHECK (
    sender_id = auth.uid() AND (
      is_admin() OR EXISTS (
        SELECT 1 FROM public.support_tickets t
        WHERE t.id = ticket_id AND t.user_id = auth.uid()
      )
    )
  );

CREATE OR REPLACE FUNCTION public.create_support_ticket(
  p_subject TEXT,
  p_category TEXT,
  p_message TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket_id UUID;
  v_priority_support BOOLEAN := false;
  v_priority TEXT := 'medium';
  v_priority_source TEXT := 'standard';
  v_sla_due_at TIMESTAMPTZ := now() + interval '24 hours';
BEGIN
  IF NULLIF(trim(p_subject), '') IS NULL OR NULLIF(trim(p_message), '') IS NULL THEN
    RAISE EXCEPTION 'Subjek dan pesan tiket wajib diisi';
  END IF;

  SELECT COALESCE(pp.priority_support, false) INTO v_priority_support
  FROM public.merchants m
  JOIN public.pos_subscriptions ps ON ps.merchant_id = m.id
  JOIN public.pos_packages pp ON pp.id = ps.package_id
  WHERE m.user_id = auth.uid()
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;

  IF v_priority_support THEN
    v_priority := 'high';
    v_priority_source := 'pos_priority_support';
    v_sla_due_at := now() + interval '4 hours';
  END IF;

  INSERT INTO public.support_tickets (
    user_id, subject, category, priority, priority_source, status,
    sla_due_at, created_at, updated_at, last_message_at, message_count
  ) VALUES (
    auth.uid(), trim(p_subject), trim(p_category), v_priority, v_priority_source, 'open',
    v_sla_due_at, now(), now(), now(), 1
  ) RETURNING id INTO v_ticket_id;

  INSERT INTO public.support_ticket_messages (
    ticket_id, sender_id, sender_role, message
  ) VALUES (v_ticket_id, auth.uid(), 'user', trim(p_message));
  RETURN v_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_support_ticket(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_support_ticket(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_support_first_response(p_ticket_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can mark support response';
  END IF;
  UPDATE public.support_tickets
  SET first_response_at = COALESCE(first_response_at, now()),
      updated_at = now()
  WHERE id = p_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_support_first_response(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_support_first_response(UUID) TO authenticated;
-- ===== END BUNDLE: 27_20260908120000_partner_promotions_priority_support.sql =====

-- ===== BEGIN BUNDLE: 28_20260908140000_public_qr_menu_table_order.sql =====
-- Public QR menu and table-order contract.
-- Customer-facing reads/writes are deliberately exposed through scoped
-- SECURITY DEFINER RPCs instead of the tenant RLS tables.

ALTER TABLE public.pos_table_orders
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'internal';

ALTER TABLE public.pos_table_orders
  DROP CONSTRAINT IF EXISTS pos_table_orders_source_check;

ALTER TABLE public.pos_table_orders
  ADD CONSTRAINT pos_table_orders_source_check
  CHECK (source IN ('internal', 'table_qr'));

CREATE INDEX IF NOT EXISTS idx_pos_table_orders_public_status
  ON public.pos_table_orders(tenant_id, id, status);

CREATE TABLE IF NOT EXISTS public.pos_table_order_stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.pos_table_orders(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.pos_products(id) ON DELETE RESTRICT,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE RESTRICT,
  quantity numeric(15,3) NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'consumed', 'released')),
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz,
  released_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_pos_table_order_stock_reservations_order
  ON public.pos_table_order_stock_reservations(order_id, status);

ALTER TABLE public.pos_table_order_stock_reservations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view table order stock reservations"
  ON public.pos_table_order_stock_reservations;
CREATE POLICY "POS users view table order stock reservations"
  ON public.pos_table_order_stock_reservations
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (SELECT id FROM public.pos_tenants WHERE user_id = auth.uid())
    OR tenant_id IN (
      SELECT tenant_id
      FROM public.pos_users
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE OR REPLACE FUNCTION public.reserve_pos_table_order_stock(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty numeric;
  v_stock_id uuid;
BEGIN
  SELECT *
  INTO v_order
  FROM public.pos_table_orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order meja tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_order.items)
  LOOP
    SELECT *
    INTO v_product
    FROM public.pos_products
    WHERE id = (v_item->>'product_id')::uuid
      AND tenant_id = v_order.tenant_id
      AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk order tidak tersedia' USING ERRCODE = '22023';
    END IF;

    v_qty := (v_item->>'qty')::numeric;
    IF v_product.is_stock_tracked THEN
      UPDATE public.pos_stock
      SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_qty,
          updated_at = now()
      WHERE tenant_id = v_order.tenant_id
        AND product_id = v_product.id
        AND outlet_id = v_order.outlet_id
        AND GREATEST(quantity - COALESCE(reserved_quantity, 0), 0) >= v_qty
      RETURNING id INTO v_stock_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Stok produk % tidak mencukupi', v_product.name
          USING ERRCODE = '55000';
      END IF;

      INSERT INTO public.pos_table_order_stock_reservations(
        order_id, tenant_id, product_id, outlet_id, quantity
      )
      VALUES (
        v_order.id, v_order.tenant_id, v_product.id, v_order.outlet_id, v_qty
      );
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_pos_table_order_stock(
  p_order_id uuid,
  p_status text DEFAULT 'released'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation public.pos_table_order_stock_reservations%ROWTYPE;
BEGIN
  FOR v_reservation IN
    SELECT *
    FROM public.pos_table_order_stock_reservations
    WHERE order_id = p_order_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET reserved_quantity = GREATEST(
          COALESCE(reserved_quantity, 0) - v_reservation.quantity, 0
        ),
        updated_at = now()
    WHERE tenant_id = v_reservation.tenant_id
      AND product_id = v_reservation.product_id
      AND outlet_id = v_reservation.outlet_id;

    UPDATE public.pos_table_order_stock_reservations
    SET status = CASE WHEN p_status = 'expired' THEN 'released' ELSE 'released' END,
        released_at = now()
    WHERE id = v_reservation.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_pos_table_order_stock(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reservation public.pos_table_order_stock_reservations%ROWTYPE;
BEGIN
  FOR v_reservation IN
    SELECT *
    FROM public.pos_table_order_stock_reservations
    WHERE order_id = p_order_id AND status = 'active'
    FOR UPDATE
  LOOP
    UPDATE public.pos_stock
    SET quantity = GREATEST(quantity - v_reservation.quantity, 0),
        reserved_quantity = GREATEST(
          COALESCE(reserved_quantity, 0) - v_reservation.quantity, 0
        ),
        updated_at = now()
    WHERE tenant_id = v_reservation.tenant_id
      AND product_id = v_reservation.product_id
      AND outlet_id = v_reservation.outlet_id;

    UPDATE public.pos_table_order_stock_reservations
    SET status = 'consumed', consumed_at = now()
    WHERE id = v_reservation.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_pos_table_order_stock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'cancelled' THEN
    PERFORM public.release_pos_table_order_stock(NEW.id, 'released');
  ELSIF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('served', 'paid') THEN
    PERFORM public.consume_pos_table_order_stock(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pos_table_order_stock_lifecycle
  ON public.pos_table_orders;
CREATE TRIGGER trg_pos_table_order_stock_lifecycle
  AFTER UPDATE OF status ON public.pos_table_orders
  FOR EACH ROW EXECUTE FUNCTION public.sync_pos_table_order_stock();

REVOKE ALL ON FUNCTION public.reserve_pos_table_order_stock(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_pos_table_order_stock(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.consume_pos_table_order_stock(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_pos_table_order_stock()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_pos_menu(
  p_tenant_id uuid,
  p_table_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant public.pos_tenants%ROWTYPE;
  v_table public.pos_tables%ROWTYPE;
  v_outlet_id uuid;
BEGIN
  IF NOT public.is_pos_tenant_active(p_tenant_id) THEN
    RAISE EXCEPTION 'Menu POS sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;

  SELECT *
  INTO v_tenant
  FROM public.pos_tenants
  WHERE id = p_tenant_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Toko tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  IF p_table_id IS NOT NULL THEN
    SELECT *
    INTO v_table
    FROM public.pos_tables
    WHERE id = p_table_id
      AND tenant_id = p_tenant_id
      AND is_active = true
      AND status <> 'cleaning';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Meja tidak valid atau sudah tidak aktif' USING ERRCODE = 'P0002';
    END IF;

    v_outlet_id := v_table.outlet_id;
  END IF;

  RETURN jsonb_build_object(
    'tenant', jsonb_build_object(
      'id', v_tenant.id,
      'name', v_tenant.name,
      'logo_url', v_tenant.logo_url,
      'address', v_tenant.address,
      'phone', v_tenant.phone,
      'currency', v_tenant.currency
    ),
    'table', CASE WHEN p_table_id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_table.id,
      'name', v_table.name,
      'outlet_id', v_table.outlet_id,
      'status', v_table.status
    ) END,
    'categories', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'sort_order', c.sort_order
        )
        ORDER BY c.sort_order, c.name
      )
      FROM public.pos_categories c
      WHERE c.tenant_id = p_tenant_id
        AND c.is_active = true
    ), '[]'::jsonb),
    'products', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'name', p.name,
          'price', p.price,
          'original_price', NULL,
          'category_id', p.category_id,
          'description', p.description,
          'image_url', p.image_url,
          'unit', p.unit,
          'is_available',
            CASE
              WHEN NOT p.is_stock_tracked THEN true
              ELSE COALESCE((
                SELECT SUM(GREATEST(s.quantity - COALESCE(s.reserved_quantity, 0), 0))
                FROM public.pos_stock s
                WHERE s.tenant_id = p_tenant_id
                  AND s.product_id = p.id
                  AND (v_outlet_id IS NULL OR s.outlet_id = v_outlet_id)
              ), 0) > 0
            END
        )
        ORDER BY COALESCE(c.sort_order, 2147483647), p.name
      )
      FROM public.pos_products p
      LEFT JOIN public.pos_categories c
        ON c.id = p.category_id
       AND c.tenant_id = p_tenant_id
       AND c.is_active = true
      WHERE p.tenant_id = p_tenant_id
        AND p.is_active = true
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_public_pos_table_order(
  p_tenant_id uuid,
  p_table_id uuid,
  p_customer_name text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_table public.pos_tables%ROWTYPE;
  v_order public.pos_table_orders%ROWTYPE;
  v_item jsonb;
  v_product public.pos_products%ROWTYPE;
  v_qty integer;
  v_notes text;
  v_items jsonb := '[]'::jsonb;
  v_order_number text;
BEGIN
  IF NOT public.is_pos_tenant_active(p_tenant_id) THEN
    RAISE EXCEPTION 'POS sedang tidak tersedia' USING ERRCODE = '55000';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'Item pesanan tidak valid' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_table
  FROM public.pos_tables
  WHERE id = p_table_id
    AND tenant_id = p_tenant_id
    AND is_active = true
    AND status <> 'cleaning'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Meja tidak valid atau sudah tidak aktif' USING ERRCODE = 'P0002';
  END IF;

  IF v_table.outlet_id IS NULL THEN
    RAISE EXCEPTION 'QR meja belum terhubung ke outlet' USING ERRCODE = '55000';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF jsonb_typeof(v_item) <> 'object'
       OR NULLIF(v_item->>'product_id', '') IS NULL
       OR (v_item ? 'qty') IS FALSE THEN
      RAISE EXCEPTION 'Format item pesanan tidak valid' USING ERRCODE = '22023';
    END IF;

    v_qty := (v_item->>'qty')::integer;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
      RAISE EXCEPTION 'Jumlah item pesanan tidak valid' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_product
    FROM public.pos_products
    WHERE id = (v_item->>'product_id')::uuid
      AND tenant_id = p_tenant_id
      AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk tidak tersedia' USING ERRCODE = '22023';
    END IF;

    IF v_product.is_stock_tracked AND NOT EXISTS (
      SELECT 1
      FROM public.pos_stock s
      WHERE s.tenant_id = p_tenant_id
        AND s.product_id = v_product.id
        AND (v_table.outlet_id IS NULL OR s.outlet_id = v_table.outlet_id)
        AND GREATEST(s.quantity - COALESCE(s.reserved_quantity, 0), 0) >= v_qty
    ) THEN
      RAISE EXCEPTION 'Stok produk % tidak mencukupi', v_product.name USING ERRCODE = '55000';
    END IF;

    v_notes := NULLIF(left(COALESCE(v_item->>'notes', ''), 500), '');
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'qty', v_qty,
      'price', v_product.price,
      'subtotal', v_product.price * v_qty,
      'notes', v_notes
    ));
  END LOOP;

  v_order_number := 'QR-' ||
    to_char(now(), 'YYMMDDHH24MISS') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));

  INSERT INTO public.pos_table_orders(
    tenant_id, outlet_id, table_id, table_name, order_number, status,
    items, customer_name, notes, source
  )
  VALUES (
    p_tenant_id, v_table.outlet_id, v_table.id, v_table.name, v_order_number,
    'pending', v_items, NULLIF(left(COALESCE(p_customer_name, 'Tamu'), 120), ''),
    NULLIF(left(COALESCE(p_notes, ''), 1000), ''), 'table_qr'
  )
  RETURNING * INTO v_order;

  PERFORM public.reserve_pos_table_order_stock(v_order.id);

  IF v_table.status = 'available' OR v_table.status = 'reserved' THEN
    UPDATE public.pos_tables
    SET status = 'occupied', updated_at = now()
    WHERE id = v_table.id;
  END IF;

  RETURN jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'table_id', v_order.table_id,
    'table_name', v_order.table_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_public_pos_table_order(
  p_tenant_id uuid,
  p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.pos_table_orders%ROWTYPE;
BEGIN
  SELECT *
  INTO v_order
  FROM public.pos_table_orders
  WHERE id = p_order_id
    AND tenant_id = p_tenant_id
    AND source = 'table_qr';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pesanan tidak ditemukan' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'items', v_order.items,
    'notes', v_order.notes,
    'customer_name', v_order.customer_name,
    'table_id', v_order.table_id,
    'table_name', v_order.table_name,
    'source', v_order.source,
    'cooking_started_at', v_order.cooking_started_at,
    'ready_at', v_order.ready_at,
    'served_at', v_order.served_at,
    'created_at', v_order.created_at,
    'updated_at', v_order.updated_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_pos_menu(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_public_pos_table_order(uuid, uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_pos_table_order(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_pos_menu(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_public_pos_table_order(uuid, uuid, text, text, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_pos_table_order(uuid, uuid) TO anon, authenticated;
-- ===== END BUNDLE: 28_20260908140000_public_qr_menu_table_order.sql =====

-- ===== BEGIN BUNDLE: 29_20260908160000_admin_pos_schema_repair.sql =====
-- Safe repair bundle for the Admin POS subscription and partner-promotion flows.
-- Apply after the base POS bootstrap (bundles 13-19). Every statement is
-- idempotent so this file can be pasted into the Supabase SQL editor again.

ALTER TABLE public.pos_packages
  ADD COLUMN IF NOT EXISTS max_outlets INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_users INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS add_on_user_price INTEGER NOT NULL DEFAULT 25000,
  ADD COLUMN IF NOT EXISTS priority_support BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_discount_percent INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS onboarding_discount_expires_at TIMESTAMPTZ;

ALTER TABLE public.pos_packages
  DROP CONSTRAINT IF EXISTS pos_packages_limits_check;
ALTER TABLE public.pos_packages
  ADD CONSTRAINT pos_packages_limits_check CHECK (
    max_outlets > 0
    AND max_users > 0
    AND add_on_user_price >= 0
    AND onboarding_discount_percent BETWEEN 0 AND 100
  );

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  partner_type TEXT,
  discount_percent INTEGER NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  max_redemptions INTEGER,
  redeemed_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pos_onboarding_promotions_discount_check CHECK (discount_percent BETWEEN 0 AND 100),
  CONSTRAINT pos_onboarding_promotions_redemption_check CHECK (
    max_redemptions IS NULL OR max_redemptions > 0
  )
);

CREATE TABLE IF NOT EXISTS public.pos_onboarding_promotion_redemptions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  promotion_id UUID NOT NULL REFERENCES public.pos_onboarding_promotions(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, merchant_id)
);

ALTER TABLE public.pos_onboarding_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_onboarding_promotion_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Anyone can view active onboarding promotions"
  ON public.pos_onboarding_promotions FOR SELECT TO authenticated
  USING (is_active AND starts_at <= now() AND expires_at > now());

DROP POLICY IF EXISTS "Admins manage onboarding promotions" ON public.pos_onboarding_promotions;
CREATE POLICY "Admins manage onboarding promotions"
  ON public.pos_onboarding_promotions FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Merchants view own promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Merchants view own promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.id = merchant_id AND m.user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Admins view promotion redemptions" ON public.pos_onboarding_promotion_redemptions;
CREATE POLICY "Admins view promotion redemptions"
  ON public.pos_onboarding_promotion_redemptions FOR SELECT TO authenticated
  USING (is_admin());

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS original_amount INTEGER,
  ADD COLUMN IF NOT EXISTS discount_amount INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promotion_id UUID,
  ADD COLUMN IF NOT EXISTS promotion_code TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.pos_subscriptions'::regclass
      AND conname = 'pos_subscriptions_promotion_id_fkey'
  ) THEN
    ALTER TABLE public.pos_subscriptions
      ADD CONSTRAINT pos_subscriptions_promotion_id_fkey
      FOREIGN KEY (promotion_id)
      REFERENCES public.pos_onboarding_promotions(id)
      ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_promotion_id
  ON public.pos_subscriptions(promotion_id);

CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id UUID,
  p_action TEXT,
  p_extension_months INTEGER DEFAULT 1,
  p_rejection_reason TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_current public.pos_subscriptions%ROWTYPE;
  v_duration_months INTEGER;
  v_started_at TIMESTAMPTZ;
  v_expired_at TIMESTAMPTZ;
  v_action TEXT := upper(trim(p_action));
  v_reason TEXT := NULLIF(trim(COALESCE(p_reason, p_rejection_reason)), '');
  v_result JSONB;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only admins can manage POS subscriptions' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_subscription
  FROM public.pos_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'POS subscription not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT GREATEST(1, COALESCE(duration_months, 1))
  INTO v_duration_months
  FROM public.pos_packages
  WHERE id = v_subscription.package_id;
  v_duration_months := COALESCE(v_duration_months, 1);

  IF v_action IN ('APPROVE', 'REACTIVATE')
     AND v_subscription.status = 'ACTIVE'
     AND v_subscription.started_at IS NOT NULL
     AND v_subscription.expired_at > now()
     AND (v_subscription.grace_ends_at IS NULL OR v_subscription.grace_ends_at > now()) THEN
    NULL;
  ELSIF v_action IN ('APPROVE', 'REACTIVATE', 'EXTEND') THEN
    IF v_action = 'EXTEND' AND v_subscription.expired_at > now() THEN
      v_started_at := COALESCE(v_subscription.started_at, now());
      v_expired_at := v_subscription.expired_at
        + make_interval(months => GREATEST(1, COALESCE(p_extension_months, 1)));
    ELSE
      v_started_at := now();
      v_expired_at := v_started_at + make_interval(months => CASE
        WHEN v_action = 'EXTEND' THEN GREATEST(1, COALESCE(p_extension_months, 1))
        ELSE v_duration_months
      END);
    END IF;

    UPDATE public.pos_subscriptions
    SET status = 'ACTIVE',
        payment_status = 'PAID',
        started_at = v_started_at,
        expired_at = v_expired_at,
        grace_ends_at = NULL,
        approved_at = COALESCE(approved_at, now()),
        approved_by = auth.uid(),
        rejection_reason = NULL,
        updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = CASE WHEN v_subscription.is_trial THEN 'trial' ELSE 'active' END,
        is_active = true,
        activated_at = COALESCE(activated_at, now()),
        suspended_at = NULL,
        updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'SUSPEND' THEN
    UPDATE public.pos_subscriptions
    SET status = 'SUSPENDED', payment_status = 'UNPAID', updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'suspended', is_active = false, suspended_at = now(), updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'CANCEL' THEN
    UPDATE public.pos_subscriptions
    SET status = 'CANCELLED', payment_status = 'CANCELLED', updated_at = now()
    WHERE id = v_subscription.id;

    UPDATE public.pos_tenants
    SET status = 'cancelled', is_active = false, updated_at = now()
    WHERE merchant_id = v_subscription.merchant_id;
  ELSIF v_action = 'REJECT' THEN
    UPDATE public.pos_subscriptions
    SET status = 'REJECTED',
        payment_status = 'REJECTED',
        rejection_reason = COALESCE(v_reason, 'Permintaan ditolak oleh admin.'),
        updated_at = now()
    WHERE id = v_subscription.id;
  ELSE
    RAISE EXCEPTION 'Unsupported POS subscription action: %', v_action USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_current
  FROM public.pos_subscriptions
  WHERE id = v_subscription.id;

  INSERT INTO public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, old_value, new_value
  ) VALUES (
    auth.uid(),
    'POS_SUBSCRIPTION_' || v_action,
    'pos_subscription',
    v_subscription.id,
    to_jsonb(v_subscription),
    to_jsonb(v_current) || jsonb_build_object('reason', v_reason)
  );

  SELECT jsonb_build_object('subscription', to_jsonb(s), 'tenant', to_jsonb(t))
  INTO v_result
  FROM public.pos_subscriptions s
  LEFT JOIN public.pos_tenants t ON t.merchant_id = s.merchant_id
  WHERE s.id = p_subscription_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_manage_pos_subscription(
  p_subscription_id UUID,
  p_action TEXT,
  p_extension_months INTEGER DEFAULT 1,
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.admin_manage_pos_subscription(
    p_subscription_id,
    p_action,
    p_extension_months,
    p_rejection_reason,
    NULL
  );
$$;

REVOKE ALL ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_pos_subscription(UUID, TEXT, INTEGER, TEXT)
  TO authenticated;

-- Supabase/PostgREST normally reloads after DDL; this makes the refresh
-- explicit so the new table and RPC are immediately visible to the SPA.
NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 29_20260908160000_admin_pos_schema_repair.sql =====

-- ===== BEGIN BUNDLE: 30_20260908170000_dispute_schema_repair.sql =====
-- Repair the dispute/refund contract used by buyer, merchant, and admin pages.
-- The original refund_requests table predates the dispute workflow. This
-- bundle is safe to rerun on projects that already have some of these columns.

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS title TEXT,
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS dispute_status TEXT DEFAULT 'OPEN',
  ADD COLUMN IF NOT EXISTS merchant_response TEXT,
  ADD COLUMN IF NOT EXISTS merchant_responded_at TIMESTAMPTZ;

UPDATE public.refund_requests
SET title = 'Komplain Pesanan'
WHERE title IS NULL;

UPDATE public.refund_requests
SET category = 'Lainnya'
WHERE category IS NULL;

UPDATE public.refund_requests
SET dispute_status = CASE
  WHEN upper(COALESCE(status, '')) = 'APPROVED' THEN 'RESOLVED_REFUND'
  WHEN upper(COALESCE(status, '')) = 'REJECTED' THEN 'RESOLVED_REJECTED'
  ELSE 'OPEN'
END
WHERE dispute_status IS NULL
   OR dispute_status NOT IN (
     'OPEN',
     'IN_MEDIATION',
     'MERCHANT_RESPONDED',
     'RESOLVED_REFUND',
     'RESOLVED_REJECTED',
     'CLOSED'
   );

ALTER TABLE public.refund_requests
  ALTER COLUMN title SET DEFAULT 'Komplain Pesanan',
  ALTER COLUMN title SET NOT NULL,
  ALTER COLUMN category SET DEFAULT 'Lainnya',
  ALTER COLUMN category SET NOT NULL,
  ALTER COLUMN dispute_status SET DEFAULT 'OPEN',
  ALTER COLUMN dispute_status SET NOT NULL;

ALTER TABLE public.refund_requests
  DROP CONSTRAINT IF EXISTS refund_requests_dispute_status_check;
ALTER TABLE public.refund_requests
  ADD CONSTRAINT refund_requests_dispute_status_check CHECK (
    dispute_status IN (
      'OPEN',
      'IN_MEDIATION',
      'MERCHANT_RESPONDED',
      'RESOLVED_REFUND',
      'RESOLVED_REJECTED',
      'CLOSED'
    )
  );

CREATE INDEX IF NOT EXISTS idx_refund_requests_dispute_status
  ON public.refund_requests(dispute_status, created_at DESC);

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 30_20260908170000_dispute_schema_repair.sql =====

-- ===== BEGIN BUNDLE: 31_20260908180000_ride_status_transition.sql =====
-- Validate driver ride transitions on the server.
-- This is intentionally idempotent so it can be replayed with the bootstrap set.
-- PostgreSQL cannot replace an existing function when its return type differs.
DROP FUNCTION IF EXISTS public.transition_ride_status(uuid, text);

CREATE OR REPLACE FUNCTION public.transition_ride_status(
  p_ride_id uuid,
  p_to_status text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ride public.ride_requests%ROWTYPE;
  v_courier_id uuid;
BEGIN
  SELECT id INTO v_courier_id
  FROM public.couriers
  WHERE user_id = auth.uid()
    AND registration_status = 'APPROVED'
    AND status = 'ACTIVE'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'Kurir tidak aktif atau belum disetujui';
  END IF;

  SELECT * INTO v_ride
  FROM public.ride_requests
  WHERE id = p_ride_id
    AND driver_id = v_courier_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Perjalanan tidak ditemukan atau bukan milik kurir ini';
  END IF;

  IF (v_ride.status, p_to_status) NOT IN (
    ('ACCEPTED', 'PICKED_UP'),
    ('PICKED_UP', 'IN_TRANSIT'),
    ('IN_TRANSIT', 'COMPLETED')
  ) THEN
    RAISE EXCEPTION 'Perubahan status perjalanan tidak valid';
  END IF;

  UPDATE public.ride_requests
  SET status = p_to_status,
      picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
      completed_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completed_at END
  WHERE id = p_ride_id;

  RETURN p_to_status;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;
-- ===== END BUNDLE: 31_20260908180000_ride_status_transition.sql =====

