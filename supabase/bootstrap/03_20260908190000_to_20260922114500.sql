-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 32_20260908190000_chat_notification_trigger_repair.sql .. 43_20260922114500_chat_image_attachments.sql

-- ===== BEGIN BUNDLE: 32_20260908190000_chat_notification_trigger_repair.sql =====
-- Repair the chat notification trigger for PostgreSQL compatibility.
-- The previous implementation used FULL JOIN with OR conditions, which
-- PostgreSQL rejects at INSERT time with SQLSTATE 0A000.

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
    (SELECT NULLIF(p.full_name, '')
     FROM public.profiles p
     WHERE p.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(m.name, '')
     FROM public.merchants m
     WHERE m.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(c.name, '')
     FROM public.couriers c
     WHERE c.user_id = NEW.sender_id
     LIMIT 1),
    'Pengguna'
  )
  INTO sender_name;

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
-- ===== END BUNDLE: 32_20260908190000_chat_notification_trigger_repair.sql =====

-- ===== BEGIN BUNDLE: 33_20260908190000_ride_history_earnings_contract.sql =====
-- Keep courier ride history and earnings connected to the ride lifecycle.
-- This bundle is safe to replay and does not trust client-provided money fields.

ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS ride_request_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'courier_earnings_ride_request_id_fkey'
      AND conrelid = 'public.courier_earnings'::regclass
  ) THEN
    ALTER TABLE public.courier_earnings
      ADD CONSTRAINT courier_earnings_ride_request_id_fkey
      FOREIGN KEY (ride_request_id)
      REFERENCES public.ride_requests(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_courier_earnings_ride_request
  ON public.courier_earnings(ride_request_id)
  WHERE type = 'RIDE' AND ride_request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ride_requests_driver_history
  ON public.ride_requests(driver_id, created_at DESC);

-- Backfill completed rides that predate the lifecycle ledger.
INSERT INTO public.courier_earnings (
  courier_id,
  ride_request_id,
  amount,
  type,
  status,
  distance_km,
  base_amount,
  created_at
)
SELECT
  r.driver_id,
  r.id,
  COALESCE(r.final_fare, r.estimated_fare),
  'RIDE',
  'PENDING',
  r.distance_km,
  COALESCE(r.final_fare, r.estimated_fare),
  COALESCE(r.completed_at, r.created_at)
FROM public.ride_requests AS r
WHERE r.status = 'COMPLETED'
  AND r.driver_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.courier_earnings AS e
    WHERE e.ride_request_id = r.id
      AND e.type = 'RIDE'
  );

-- Assignment must only be performed by the authenticated, active courier
-- represented by p_courier_id.
CREATE OR REPLACE FUNCTION public.accept_ride(p_ride_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_updated integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.couriers
    WHERE id = p_courier_id
      AND user_id = auth.uid()
      AND registration_status = 'APPROVED'
      AND status = 'ACTIVE'
      AND is_available = true
  ) THEN
    RAISE EXCEPTION 'Kurir tidak aktif, belum disetujui, atau bukan milik akun ini';
  END IF;

  UPDATE public.ride_requests
  SET driver_id = p_courier_id,
      status = 'ACCEPTED',
      accepted_at = now()
  WHERE id = p_ride_id
    AND status = 'SEARCHING'
    AND driver_id IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN false;
  END IF;

  PERFORM public.send_notification(
    passenger_id,
    'Driver Ditemukan! 🏍️',
    'Driver sedang menuju lokasi jemput Anda',
    'ride',
    '/ride/' || p_ride_id::text
  )
  FROM public.ride_requests
  WHERE id = p_ride_id;

  RETURN true;
END;
$$;

-- Completion updates the ride and creates exactly one pending earning together.
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
  v_final_fare integer;
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

  SELECT *
  INTO v_ride
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

  v_final_fare := COALESCE(v_ride.final_fare, v_ride.estimated_fare);

  UPDATE public.ride_requests
  SET status = p_to_status,
      final_fare = CASE WHEN p_to_status = 'COMPLETED' THEN v_final_fare ELSE final_fare END,
      picked_up_at = CASE WHEN p_to_status = 'PICKED_UP' THEN now() ELSE picked_up_at END,
      completed_at = CASE WHEN p_to_status = 'COMPLETED' THEN now() ELSE completed_at END
  WHERE id = p_ride_id;

  IF p_to_status = 'COMPLETED' THEN
    INSERT INTO public.courier_earnings (
      courier_id,
      ride_request_id,
      amount,
      type,
      status,
      distance_km,
      base_amount,
      created_at
    )
    SELECT
      v_courier_id,
      p_ride_id,
      v_final_fare,
      'RIDE',
      'PENDING',
      v_ride.distance_km,
      v_final_fare,
      now()
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.courier_earnings
      WHERE ride_request_id = p_ride_id
        AND type = 'RIDE'
    );
  END IF;

  RETURN p_to_status;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_ride(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_ride(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.transition_ride_status(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_ride_status(uuid, text) TO authenticated;
-- ===== END BUNDLE: 33_20260908190000_ride_history_earnings_contract.sql =====

-- ===== BEGIN BUNDLE: 33_20260909100000_direct_chat_realtime.sql =====
-- Direct in-app buyer/merchant chat.
-- This extends the canonical conversation model without changing order/ride chat.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE;

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'));

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_one_context;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL)
    OR
    (context_type = 'direct' AND merchant_id IS NOT NULL AND order_id IS NULL AND ride_request_id IS NULL)
  );

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_direct_merchant_uidx
  ON public.chat_conversations(merchant_id, conversation_type)
  WHERE context_type = 'direct' AND merchant_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_merchant_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat participant' USING ERRCODE = '42501';
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.user_id IS NOT NULL
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, merchant_id, conversation_type
  )
  VALUES ('direct', p_merchant_id, 'buyer_merchant')
  ON CONFLICT (merchant_id, conversation_type)
    WHERE context_type = 'direct' AND merchant_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  IF NOT public.is_chat_conversation_participant(v_conversation_id, auth.uid())
     AND NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  RETURN v_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END;
$$;
-- ===== END BUNDLE: 33_20260909100000_direct_chat_realtime.sql =====

-- ===== BEGIN BUNDLE: 34_20260909110000_chat_security_pair_isolation.sql =====
-- Chat security hardening: pair-scoped direct conversations and immutable messages.
-- Apply after 33_20260909100000_direct_chat_realtime.sql.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS buyer_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

-- Existing direct conversations must have exactly one buyer before the new
-- pair-scoped key can be enabled. Ambiguous rows fail closed for manual repair.
DO $$
DECLARE
  ambiguous_count integer;
BEGIN
  UPDATE public.chat_conversations c
  SET buyer_user_id = buyers.user_id
  FROM (
    SELECT cp.conversation_id, (array_agg(cp.user_id ORDER BY cp.user_id))[1] AS user_id
    FROM public.chat_participants cp
    JOIN public.chat_conversations dc ON dc.id = cp.conversation_id
    WHERE dc.context_type = 'direct'
      AND cp.role = 'buyer'
      AND cp.left_at IS NULL
    GROUP BY cp.conversation_id
    HAVING count(*) = 1
  ) buyers
  WHERE c.id = buyers.conversation_id
    AND c.context_type = 'direct'
    AND c.buyer_user_id IS NULL;

  SELECT count(*)
  INTO ambiguous_count
  FROM public.chat_conversations c
  WHERE c.context_type = 'direct'
    AND c.buyer_user_id IS NULL;

  IF ambiguous_count > 0 THEN
    RAISE EXCEPTION 'direct chat migration blocked: % conversation(s) have no unique buyer participant', ambiguous_count
      USING ERRCODE = '23514';
  END IF;
END;
$$;

ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_one_context;

ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_one_context CHECK (
    (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND buyer_user_id IS NULL)
    OR
    (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND buyer_user_id IS NULL)
    OR
    (context_type = 'direct' AND merchant_id IS NOT NULL AND buyer_user_id IS NOT NULL AND order_id IS NULL AND ride_request_id IS NULL)
  );

DROP INDEX IF EXISTS public.chat_conversations_direct_merchant_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_direct_pair_uidx
  ON public.chat_conversations(buyer_user_id, merchant_id, conversation_type)
  WHERE context_type = 'direct'
    AND buyer_user_id IS NOT NULL
    AND merchant_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS chat_conversations_direct_buyer_idx
  ON public.chat_conversations(buyer_user_id, merchant_id)
  WHERE context_type = 'direct';

CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_merchant_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat participant' USING ERRCODE = '42501';
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.user_id IS NOT NULL
    AND m.user_id <> auth.uid()
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, merchant_id, buyer_user_id, conversation_type
  )
  VALUES ('direct', p_merchant_id, auth.uid(), 'buyer_merchant')
  ON CONFLICT (buyer_user_id, merchant_id, conversation_type)
    WHERE context_type = 'direct'
      AND buyer_user_id IS NOT NULL
      AND merchant_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  IF NOT public.is_chat_conversation_participant(v_conversation_id, auth.uid())
     AND NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  RETURN v_conversation_id;
END;
$$;

-- Users must not mutate message rows to mark read. Read state is written only
-- through mark_chat_conversation_read, while admin/service jobs retain access.
DROP POLICY IF EXISTS "Users can update own messages read status" ON public.chat_messages;
DROP POLICY IF EXISTS "Users can update own chat messages read status" ON public.chat_messages;

CREATE OR REPLACE FUNCTION public.validate_chat_message_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.is_chat_conversation_participant(NEW.conversation_id, NEW.sender_id)
     OR NEW.sender_id <> auth.uid() THEN
    RAISE EXCEPTION 'sender is not an active conversation participant' USING ERRCODE = '42501';
  END IF;

  IF NEW.receiver_id IS NULL
     OR NOT public.is_chat_conversation_participant(NEW.conversation_id, NEW.receiver_id)
     OR NEW.receiver_id = NEW.sender_id THEN
    RAISE EXCEPTION 'receiver is not a different active conversation participant' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_validate_participants ON public.chat_messages;
CREATE TRIGGER chat_messages_validate_participants
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.validate_chat_message_participants();

REVOKE UPDATE ON public.chat_messages FROM authenticated;
GRANT UPDATE ON public.chat_messages TO authenticated;
-- ===== END BUNDLE: 34_20260909110000_chat_security_pair_isolation.sql =====

-- ===== BEGIN BUNDLE: 35_20260909120000_chat_message_retention.sql =====
-- Chat message retention: soft delete at day 14, hard delete at day 30.
-- Apply after 34_20260909110000_chat_security_pair_isolation.sql.

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS soft_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS hard_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

-- Existing messages receive deterministic expiry dates based on created_at.
UPDATE public.chat_messages
SET soft_delete_at = created_at + interval '14 days',
    hard_delete_at = created_at + interval '30 days'
WHERE soft_delete_at IS NULL OR hard_delete_at IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_messages_retention_order_check'
  ) THEN
    ALTER TABLE public.chat_messages
      ADD CONSTRAINT chat_messages_retention_order_check
      CHECK (hard_delete_at > soft_delete_at);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS chat_messages_soft_delete_idx
  ON public.chat_messages(soft_delete_at, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS chat_messages_hard_delete_idx
  ON public.chat_messages(hard_delete_at, id);

CREATE OR REPLACE FUNCTION public.set_chat_message_retention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.created_at IS NULL THEN
    NEW.created_at := now();
  END IF;
  IF NEW.soft_delete_at IS NULL THEN
    NEW.soft_delete_at := NEW.created_at + interval '14 days';
  END IF;
  IF NEW.hard_delete_at IS NULL THEN
    NEW.hard_delete_at := NEW.created_at + interval '30 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_set_retention ON public.chat_messages;
CREATE TRIGGER chat_messages_set_retention
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.set_chat_message_retention();

CREATE OR REPLACE FUNCTION public.soft_delete_expired_chat_messages(
  p_limit integer DEFAULT 500
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 5000 THEN
    RAISE EXCEPTION 'retention batch limit must be between 1 and 5000' USING ERRCODE = '22023';
  END IF;

  WITH candidates AS (
    SELECT id
    FROM public.chat_messages
    WHERE deleted_at IS NULL
      AND soft_delete_at <= now()
      AND hard_delete_at > now()
    ORDER BY soft_delete_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE public.chat_messages m
  SET deleted_at = now(),
      deleted_reason = 'retention_14_days'
  FROM candidates c
  WHERE m.id = c.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_hard_expired_chat_messages(
  p_limit integer DEFAULT 500
)
RETURNS TABLE(id uuid, attachment_path text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.id, m.attachment_path
  FROM public.chat_messages m
  WHERE m.hard_delete_at <= now()
  ORDER BY m.hard_delete_at, m.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000);
$$;

CREATE OR REPLACE FUNCTION public.hard_delete_chat_messages(
  p_message_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF p_message_ids IS NULL OR cardinality(p_message_ids) = 0 THEN
    RETURN 0;
  END IF;

  DELETE FROM public.chat_messages
  WHERE id = ANY(p_message_ids)
    AND hard_delete_at <= now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.soft_delete_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_hard_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hard_delete_chat_messages(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.soft_delete_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_hard_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.hard_delete_chat_messages(uuid[]) TO service_role;

-- Canonical cleanup is now delegated to the retention worker. Keep the legacy
-- function name as a compatibility wrapper for existing operational tooling.
CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.soft_delete_expired_chat_messages(5000);
  DELETE FROM public.chat_messages
  WHERE conversation_id IS NULL
    AND auto_delete_at IS NOT NULL
    AND auto_delete_at <= now();
END;
$$;
-- ===== END BUNDLE: 35_20260909120000_chat_message_retention.sql =====

-- ===== BEGIN BUNDLE: 36_20260909130000_chat_rls_rpc_abuse_control.sql =====
-- Chat phase 3: database-owned authorization, canonical writes, and abuse control.
-- Apply after 35_20260909120000_chat_message_retention.sql.
--
-- Authenticated clients may read rows allowed by RLS, but all chat writes go
-- through SECURITY DEFINER RPCs. Message identity and content are immutable;
-- retention is the only supported message update.

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reads ENABLE ROW LEVEL SECURITY;

-- Remove legacy policies that allowed broad row mutation. The policies below
-- are recreated explicitly so older database states fail closed as well.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN (
        'chat_conversations',
        'chat_participants',
        'chat_messages',
        'chat_message_reads'
      )
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  END LOOP;
END;
$$;

REVOKE ALL ON public.chat_conversations FROM anon, authenticated;
REVOKE ALL ON public.chat_participants FROM anon, authenticated;
REVOKE ALL ON public.chat_messages FROM anon, authenticated;
REVOKE ALL ON public.chat_message_reads FROM anon, authenticated;

GRANT SELECT ON public.chat_conversations TO authenticated;
GRANT SELECT ON public.chat_participants TO authenticated;
GRANT SELECT ON public.chat_messages TO authenticated;
GRANT SELECT ON public.chat_message_reads TO authenticated;

CREATE POLICY "Chat participants can view conversations"
ON public.chat_conversations FOR SELECT
USING (
  public.is_chat_conversation_participant(id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

CREATE POLICY "Chat participants can view participant rows"
ON public.chat_participants FOR SELECT
USING (
  public.is_chat_conversation_participant(conversation_id, auth.uid())
  OR public.chat_is_admin(auth.uid())
);

CREATE POLICY "Participants can view conversation messages"
ON public.chat_messages FOR SELECT
USING (
  conversation_id IS NOT NULL
  AND (
    public.is_chat_conversation_participant(conversation_id, auth.uid())
    OR public.chat_is_admin(auth.uid())
  )
);

CREATE POLICY "Chat participants can view message reads"
ON public.chat_message_reads FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.chat_messages m
    WHERE m.id = message_id
      AND public.is_chat_conversation_participant(m.conversation_id, auth.uid())
  )
  OR public.chat_is_admin(auth.uid())
);

-- Keep the old function name, but validate the caller before creating or
-- reactivating any participant rows.
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
  v_caller_is_participant boolean;
BEGIN
  IF auth.uid() IS NULL
     OR p_context_type NOT IN ('order', 'ride')
     OR (p_context_type = 'order' AND p_order_id IS NULL)
     OR (p_context_type = 'ride' AND p_ride_request_id IS NULL)
     OR (p_context_type = 'order' AND p_ride_request_id IS NOT NULL)
     OR (p_context_type = 'ride' AND p_order_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'invalid chat context' USING ERRCODE = '22023';
  END IF;

  IF p_context_type = 'order'
     AND p_conversation_type NOT IN (
       'buyer_merchant', 'buyer_courier', 'merchant_courier'
     )
  THEN
    RAISE EXCEPTION 'invalid order conversation type' USING ERRCODE = '22023';
  END IF;

  IF p_context_type = 'ride'
     AND p_conversation_type <> 'passenger_courier'
  THEN
    RAISE EXCEPTION 'invalid ride conversation type' USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.chat_domain_participants(
      p_context_type,
      p_order_id,
      p_ride_request_id,
      p_conversation_type
    ) domain_participant
    WHERE domain_participant.user_id = auth.uid()
  )
  INTO v_caller_is_participant;

  IF NOT COALESCE(v_caller_is_participant, false)
     AND NOT public.chat_is_admin(auth.uid())
  THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  SELECT c.id
  INTO v_conversation_id
  FROM public.chat_conversations c
  WHERE (
    (
      p_context_type = 'order'
      AND c.order_id = p_order_id
      AND c.conversation_type = p_conversation_type
    )
    OR (
      p_context_type = 'ride'
      AND c.ride_request_id = p_ride_request_id
      AND c.conversation_type = p_conversation_type
    )
  )
  ORDER BY c.created_at
  LIMIT 1;

  IF v_conversation_id IS NULL THEN
    INSERT INTO public.chat_conversations (
      context_type,
      order_id,
      ride_request_id,
      conversation_type
    )
    VALUES (p_context_type, p_order_id, p_ride_request_id, p_conversation_type)
    RETURNING id INTO v_conversation_id;
  END IF;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  SELECT v_conversation_id, p.user_id, p.role
  FROM public.chat_domain_participants(
    p_context_type,
    p_order_id,
    p_ride_request_id,
    p_conversation_type
  ) p
  WHERE p.user_id IS NOT NULL
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$;

-- Direct chat remains pair-scoped and can only be opened by a buyer account.
CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_merchant_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat participant' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.id = p_merchant_id
      AND m.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.merchants m
    WHERE m.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'merchant cannot open buyer direct chat' USING ERRCODE = '42501';
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.user_id IS NOT NULL
    AND m.user_id <> auth.uid()
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type,
    merchant_id,
    buyer_user_id,
    conversation_type
  )
  VALUES ('direct', p_merchant_id, auth.uid(), 'buyer_merchant')
  ON CONFLICT (buyer_user_id, merchant_id, conversation_type)
    WHERE context_type = 'direct'
      AND buyer_user_id IS NOT NULL
      AND merchant_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$;

-- The read RPC is the only user write path for read cursors. A cursor may not
-- point at a different conversation or at a message the caller cannot read.
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
  IF auth.uid() IS NULL
     OR NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
  THEN
    RAISE EXCEPTION 'not a chat participant' USING ERRCODE = '42501';
  END IF;

  IF p_message_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.chat_messages m
       WHERE m.id = p_message_id
         AND m.conversation_id = p_conversation_id
         AND m.deleted_at IS NULL
     )
  THEN
    RAISE EXCEPTION 'message does not belong to conversation' USING ERRCODE = '22023';
  END IF;

  UPDATE public.chat_participants
  SET last_read_at = now(),
      last_read_message_id = COALESCE(
        p_message_id,
        last_read_message_id
      )
  WHERE conversation_id = p_conversation_id
    AND user_id = auth.uid()
    AND left_at IS NULL;

  IF p_message_id IS NOT NULL THEN
    INSERT INTO public.chat_message_reads (message_id, user_id)
    VALUES (p_message_id, auth.uid())
    ON CONFLICT (message_id, user_id) DO UPDATE
    SET read_at = now();
  END IF;
END;
$$;

-- Canonical, idempotent message write. Sender, order context, message type,
-- and participant membership are derived or checked in the database.
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_conversation_id uuid,
  p_receiver_id uuid,
  p_body text,
  p_client_message_id uuid
)
RETURNS public.chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.chat_messages%ROWTYPE;
  v_conversation public.chat_conversations%ROWTYPE;
  v_body text;
BEGIN
  IF auth.uid() IS NULL
     OR p_conversation_id IS NULL
     OR p_receiver_id IS NULL
     OR p_client_message_id IS NULL
  THEN
    RAISE EXCEPTION 'invalid chat message request' USING ERRCODE = '22023';
  END IF;

  v_body := btrim(COALESCE(p_body, ''));
  IF length(v_body) < 1 OR length(v_body) > 4000 THEN
    RAISE EXCEPTION 'chat message must contain 1 to 4000 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_conversation
  FROM public.chat_conversations c
  WHERE c.id = p_conversation_id
    AND c.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'conversation is not active' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
     OR NOT public.is_chat_conversation_participant(p_conversation_id, p_receiver_id)
     OR p_receiver_id = auth.uid()
  THEN
    RAISE EXCEPTION 'sender or receiver is not an active participant'
      USING ERRCODE = '42501';
  END IF;

  -- A retry with the same client ID returns the original row, but reusing it
  -- for a different conversation, recipient, or body is rejected.
  SELECT *
  INTO v_message
  FROM public.chat_messages m
  WHERE m.sender_id = auth.uid()
    AND m.client_message_id = p_client_message_id
  LIMIT 1;

  IF FOUND THEN
    IF v_message.conversation_id <> p_conversation_id
       OR v_message.receiver_id <> p_receiver_id
       OR btrim(COALESCE(v_message.body, v_message.message)) <> v_body
    THEN
      RAISE EXCEPTION 'client message ID was already used with different data'
        USING ERRCODE = '23505';
    END IF;
    RETURN v_message;
  END IF;

  INSERT INTO public.chat_messages (
    conversation_id,
    order_id,
    sender_id,
    receiver_id,
    message,
    body,
    message_type,
    client_message_id,
    chat_type
  )
  VALUES (
    p_conversation_id,
    v_conversation.order_id,
    auth.uid(),
    p_receiver_id,
    v_body,
    v_body,
    'text',
    p_client_message_id,
    v_conversation.conversation_type
  )
  ON CONFLICT (sender_id, client_message_id)
    WHERE client_message_id IS NOT NULL
  DO NOTHING
  RETURNING * INTO v_message;

  IF NOT FOUND THEN
    SELECT *
    INTO v_message
    FROM public.chat_messages m
    WHERE m.sender_id = auth.uid()
      AND m.client_message_id = p_client_message_id
    LIMIT 1;
  END IF;

  RETURN v_message;
END;
$$;

-- Prevent any future grant/policy regression from making messages mutable.
CREATE OR REPLACE FUNCTION public.protect_chat_message_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
     OR NEW.order_id IS DISTINCT FROM OLD.order_id
     OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.receiver_id IS DISTINCT FROM OLD.receiver_id
     OR NEW.message IS DISTINCT FROM OLD.message
     OR NEW.body IS DISTINCT FROM OLD.body
     OR NEW.message_type IS DISTINCT FROM OLD.message_type
     OR NEW.client_message_id IS DISTINCT FROM OLD.client_message_id
     OR NEW.chat_type IS DISTINCT FROM OLD.chat_type
     OR NEW.is_read IS DISTINCT FROM OLD.is_read
     OR NEW.image_url IS DISTINCT FROM OLD.image_url
     OR NEW.attachment_path IS DISTINCT FROM OLD.attachment_path
     OR NEW.auto_delete_at IS DISTINCT FROM OLD.auto_delete_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.soft_delete_at IS DISTINCT FROM OLD.soft_delete_at
     OR NEW.hard_delete_at IS DISTINCT FROM OLD.hard_delete_at
  THEN
    RAISE EXCEPTION 'chat messages are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_protect_immutability ON public.chat_messages;
CREATE TRIGGER chat_messages_protect_immutability
BEFORE UPDATE ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.protect_chat_message_immutability();

-- Re-check payload rules at the trigger boundary, including direct inserts
-- from trusted server jobs or a future privileged integration.
CREATE OR REPLACE FUNCTION public.validate_chat_message_payload()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NULL
     OR NEW.sender_id IS NULL
     OR NEW.receiver_id IS NULL
     OR NEW.client_message_id IS NULL
     OR length(btrim(COALESCE(NEW.body, NEW.message, ''))) NOT BETWEEN 1 AND 4000
  THEN
    RAISE EXCEPTION 'invalid chat message payload' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_validate_payload ON public.chat_messages;
CREATE TRIGGER chat_messages_validate_payload
BEFORE INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.validate_chat_message_payload();

-- Explicit grants keep PostgREST from exposing the RPCs to anonymous callers.
REVOKE ALL ON FUNCTION public.get_or_create_chat_conversation(text, uuid, uuid, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_or_create_direct_chat(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_chat_conversation_read(uuid, uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_chat_message(uuid, uuid, text, uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_or_create_chat_conversation(text, uuid, uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_chat_conversation_read(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_chat_message(uuid, uuid, text, uuid)
  TO authenticated;

-- Unread count is read-only, but must not be callable anonymously.
REVOKE ALL ON FUNCTION public.get_chat_unread_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_unread_count() TO authenticated;
-- ===== END BUNDLE: 36_20260909130000_chat_rls_rpc_abuse_control.sql =====

-- ===== BEGIN BUNDLE: 37_20260909140000_chat_retention_operations.sql =====
-- Chat retention operations: idempotent redaction, hard-delete claims, and metrics.
-- Apply after 36_20260909130000_chat_rls_rpc_abuse_control.sql.

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS soft_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS hard_delete_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_reason text;

CREATE TABLE IF NOT EXISTS public.chat_retention_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  status text NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
  soft_deleted integer NOT NULL DEFAULT 0,
  hard_delete_candidates integer NOT NULL DEFAULT 0,
  hard_deleted integer NOT NULL DEFAULT 0,
  attachment_objects_removed integer NOT NULL DEFAULT 0,
  error_code text,
  error_message text
);

CREATE INDEX IF NOT EXISTS chat_retention_runs_started_idx
  ON public.chat_retention_runs(started_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_retention_claims (
  message_id uuid PRIMARY KEY REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  claimed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chat_retention_claims_claimed_idx
  ON public.chat_retention_claims(claimed_at);

CREATE OR REPLACE FUNCTION public.soft_delete_expired_chat_messages(p_limit integer DEFAULT 500)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 5000 THEN
    RAISE EXCEPTION 'retention batch limit must be between 1 and 5000' USING ERRCODE = '22023';
  END IF;

  WITH candidates AS (
    SELECT id FROM public.chat_messages
    WHERE deleted_at IS NULL
      AND soft_delete_at <= now()
      AND hard_delete_at > now()
    ORDER BY soft_delete_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  )
  UPDATE public.chat_messages m
  SET deleted_at = COALESCE(m.deleted_at, now()),
      deleted_reason = COALESCE(m.deleted_reason, 'retention_14_days'),
      body = '[Pesan dihapus otomatis]',
      message = '[Pesan dihapus otomatis]'
  FROM candidates c
  WHERE m.id = c.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_hard_expired_chat_messages(p_limit integer DEFAULT 500)
RETURNS TABLE(id uuid, attachment_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.chat_retention_claims(message_id)
  SELECT m.id FROM public.chat_messages m
  LEFT JOIN public.chat_retention_claims c ON c.message_id = m.id
  WHERE m.hard_delete_at <= now()
    AND (c.message_id IS NULL OR c.claimed_at < now() - interval '15 minutes')
  ORDER BY m.hard_delete_at, m.id
  FOR UPDATE OF m SKIP LOCKED
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000)
  ON CONFLICT (message_id) DO UPDATE SET claimed_at = now();

  RETURN QUERY
  SELECT m.id, m.attachment_path
  FROM public.chat_messages m
  JOIN public.chat_retention_claims c ON c.message_id = m.id
  WHERE m.hard_delete_at <= now()
    AND c.claimed_at >= now() - interval '15 minutes'
  ORDER BY m.hard_delete_at, m.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000);
END;
$$;

CREATE OR REPLACE FUNCTION public.hard_delete_chat_messages(p_message_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  IF p_message_ids IS NULL OR cardinality(p_message_ids) = 0 THEN RETURN 0; END IF;
  DELETE FROM public.chat_message_reads WHERE message_id = ANY(p_message_ids);
  DELETE FROM public.chat_messages m
  WHERE m.id = ANY(p_message_ids)
    AND m.hard_delete_at <= now()
    AND EXISTS (SELECT 1 FROM public.chat_retention_claims c WHERE c.message_id = m.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM public.chat_retention_claims WHERE message_id = ANY(p_message_ids);
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_chat_retention_run(
  p_run_id uuid, p_status text, p_soft_deleted integer DEFAULT 0,
  p_hard_delete_candidates integer DEFAULT 0, p_hard_deleted integer DEFAULT 0,
  p_attachment_objects_removed integer DEFAULT 0, p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.chat_retention_runs
  SET status = p_status,
      completed_at = CASE WHEN p_status IN ('completed', 'failed') THEN now() ELSE completed_at END,
      soft_deleted = p_soft_deleted,
      hard_delete_candidates = p_hard_delete_candidates,
      hard_deleted = p_hard_deleted,
      attachment_objects_removed = p_attachment_objects_removed,
      error_code = p_error_code,
      error_message = left(p_error_message, 500)
  WHERE id = p_run_id;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_expired_chats()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- The legacy three-hour auto_delete_at policy is intentionally disabled.
  PERFORM public.soft_delete_expired_chat_messages(5000);
END;
$$;

REVOKE ALL ON TABLE public.chat_retention_runs, public.chat_retention_claims FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.soft_delete_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_hard_expired_chat_messages(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.hard_delete_chat_messages(uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_chat_retention_run(uuid, text, integer, integer, integer, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.chat_retention_runs TO service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.list_hard_expired_chat_messages(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.hard_delete_chat_messages(uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_chat_retention_run(uuid, text, integer, integer, integer, integer, text, text) TO service_role;
-- ===== END BUNDLE: 37_20260909140000_chat_retention_operations.sql =====

-- ===== BEGIN BUNDLE: 38_20260909150000_chat_notification_observability.sql =====
-- Fase 7: chat notification contract, idempotency, and safe operations metrics.
-- Backward-compatible: legacy notifications remain readable and send_notification is unchanged.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES public.chat_conversations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS message_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sender_display_name text,
  ADD COLUMN IF NOT EXISTS preview text,
  ADD COLUMN IF NOT EXISTS deep_link text,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_chat_idempotency_uidx
  ON public.notifications (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS notifications_chat_conversation_idx
  ON public.notifications (conversation_id, created_at DESC)
  WHERE conversation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.chat_observability_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_name text NOT NULL CHECK (metric_name IN (
    'event_delivery_latency_ms', 'channel_subscribed', 'channel_timeout',
    'channel_closed', 'channel_error', 'reconnect_success',
    'duplicate_retry_recovered', 'inbox_query_latency_ms',
    'history_query_latency_ms', 'unread_notification_delivery',
    'retention_cleanup_success', 'retention_cleanup_failure',
    'retention_cleanup_lag_seconds', 'active_conversations'
  )),
  metric_value numeric NOT NULL DEFAULT 1,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'worker', 'database')),
  CONSTRAINT chat_observability_context_object CHECK (jsonb_typeof(context) = 'object')
);
CREATE INDEX IF NOT EXISTS chat_observability_metric_time_idx
  ON public.chat_observability_events (metric_name, occurred_at DESC);
ALTER TABLE public.chat_observability_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_observability_events FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.chat_observability_events TO authenticated, service_role;
GRANT SELECT ON public.chat_observability_events TO service_role;

CREATE OR REPLACE FUNCTION public.record_chat_observability(
  p_metric_name text,
  p_metric_value numeric DEFAULT 1,
  p_context jsonb DEFAULT '{}'::jsonb,
  p_source text DEFAULT 'app'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  IF p_metric_name NOT IN (
    'event_delivery_latency_ms', 'channel_subscribed', 'channel_timeout',
    'channel_closed', 'channel_error', 'reconnect_success',
    'duplicate_retry_recovered', 'inbox_query_latency_ms',
    'history_query_latency_ms', 'unread_notification_delivery',
    'retention_cleanup_success', 'retention_cleanup_failure',
    'retention_cleanup_lag_seconds', 'active_conversations'
  ) THEN
    RAISE EXCEPTION 'Unsupported chat metric' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.chat_observability_events(metric_name, metric_value, context, source)
  VALUES (
    p_metric_name,
    greatest(least(coalesce(p_metric_value, 1), 2147483647), -2147483647),
    CASE WHEN jsonb_typeof(coalesce(p_context, '{}'::jsonb)) = 'object' THEN coalesce(p_context, '{}'::jsonb) ELSE '{}'::jsonb END,
    CASE WHEN p_source IN ('app', 'worker', 'database') THEN p_source ELSE 'app' END
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_chat_observability(text, numeric, jsonb, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(p_user_id uuid, p_conversation_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE COALESCE((SELECT role FROM public.chat_participants WHERE conversation_id = p_conversation_id AND user_id = p_user_id AND left_at IS NULL LIMIT 1), '')
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN '/courier/chat?conversationId=' || p_conversation_id::text
    WHEN 'passenger' THEN '/ride/tracking?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.send_chat_notification(
  p_recipient_id uuid,
  p_conversation_id uuid,
  p_message_id uuid,
  p_sender_display_name text,
  p_preview text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_key text := 'chat:' || p_message_id::text || ':' || p_recipient_id::text;
BEGIN
  INSERT INTO public.notifications(
    user_id, title, message, type, link, conversation_id, message_id,
    sender_display_name, preview, deep_link, idempotency_key
  ) VALUES (
    p_recipient_id, left(coalesce(p_sender_display_name, 'Pesan baru'), 120),
    left(coalesce(p_preview, 'Pesan baru'), 120), 'chat',
    public.chat_notification_deep_link(p_recipient_id, p_conversation_id),
    p_conversation_id, p_message_id, left(coalesce(p_sender_display_name, 'Pengguna'), 120),
    left(coalesce(p_preview, ''), 120),
    public.chat_notification_deep_link(p_recipient_id, p_conversation_id), v_key
  )
  ON CONFLICT (user_id, idempotency_key) DO UPDATE SET
    conversation_id = EXCLUDED.conversation_id,
    message_id = EXCLUDED.message_id,
    deep_link = EXCLUDED.deep_link
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE recipient record; sender_name text; message_preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(m.name, '') FROM public.merchants m WHERE m.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = NEW.sender_id LIMIT 1), 'Pengguna')
  INTO sender_name;
  message_preview := left(regexp_replace(trim(coalesce(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'), 120);
  FOR recipient IN SELECT p.user_id FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    PERFORM public.send_chat_notification(recipient.user_id, NEW.conversation_id, NEW.id, sender_name, message_preview);
  END LOOP;
  RETURN NEW;
END;
$$;

COMMENT ON TABLE public.chat_observability_events IS 'Safe chat metrics only; never store message bodies, tokens, signed URLs, or location.';
-- ===== END BUNDLE: 38_20260909150000_chat_notification_observability.sql =====

-- ===== BEGIN BUNDLE: 39_20260909143000_chat_participant_names.sql =====
-- Expose participant names only inside conversations the caller may access.
-- Profiles remain private; chat inboxes use this narrow SECURITY DEFINER RPC.

CREATE OR REPLACE FUNCTION public.get_chat_participant_profiles(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, full_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    target.user_id,
    COALESCE(
      NULLIF(trim(p.full_name), ''),
      NULLIF(trim(m.name), ''),
      NULLIF(trim(c.name), '')
    ) AS full_name
  FROM public.chat_participants target
  LEFT JOIN public.profiles p ON p.user_id = target.user_id
  LEFT JOIN public.merchants m ON m.user_id = target.user_id AND m.status = 'ACTIVE'
  LEFT JOIN public.couriers c ON c.user_id = target.user_id
  WHERE target.user_id = ANY(COALESCE(p_user_ids, ARRAY[]::uuid[]))
    AND target.left_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.chat_participants caller_membership
      JOIN public.chat_participants target_membership
        ON target_membership.conversation_id = caller_membership.conversation_id
       AND target_membership.user_id = target.user_id
       AND target_membership.left_at IS NULL
      WHERE caller_membership.user_id = auth.uid()
        AND caller_membership.left_at IS NULL
    );
$$;

REVOKE ALL ON FUNCTION public.get_chat_participant_profiles(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_participant_profiles(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.get_chat_participant_profiles(uuid[]) IS
  'Returns participant profile names only for conversations visible to the authenticated caller.';

GRANT EXECUTE ON FUNCTION public.get_chat_participant_profiles(uuid[]) TO service_role;
-- ===== END BUNDLE: 39_20260909143000_chat_participant_names.sql =====

-- ===== BEGIN BUNDLE: 40_20260909150000_dual_role_chat_context.sql =====
-- Dual-role accounts may act as buyer and merchant in separate chat contexts.
-- A merchant user is blocked only from opening a chat with their own store.

CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_merchant_user_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'invalid chat participant' USING ERRCODE = '42501';
  END IF;

  SELECT m.user_id
  INTO v_merchant_user_id
  FROM public.merchants m
  WHERE m.id = p_merchant_id
    AND m.user_id IS NOT NULL
    AND m.user_id <> auth.uid()
    AND m.status = 'ACTIVE'
  LIMIT 1;

  IF v_merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'merchant chat account not found' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type,
    merchant_id,
    buyer_user_id,
    conversation_type
  )
  VALUES ('direct', p_merchant_id, auth.uid(), 'buyer_merchant')
  ON CONFLICT (buyer_user_id, merchant_id, conversation_type)
    WHERE context_type = 'direct'
      AND buyer_user_id IS NOT NULL
      AND merchant_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'buyer'),
    (v_conversation_id, v_merchant_user_id, 'merchant')
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_or_create_direct_chat(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(uuid) TO authenticated;
-- ===== END BUNDLE: 40_20260909150000_dual_role_chat_context.sql =====

-- ===== BEGIN BUNDLE: 41_20260909152000_role_aware_chat_notifications.sql =====
-- Role-aware chat badges and notification destinations for dual-role accounts.

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
   AND p.role = 'buyer'
   AND p.left_at IS NULL
  WHERE m.sender_id <> auth.uid()
    AND m.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.chat_message_reads r
      WHERE r.message_id = m.id
        AND r.user_id = auth.uid()
    );
$$;

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

  -- Resolve display names with independent lookups. PostgreSQL rejects
  -- disjunctive outer-join plans in this trigger path (SQLSTATE 0A000),
  -- which rolls back the message INSERT and surfaces as an RPC 400.
  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '')
     FROM public.profiles p
     WHERE p.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(m.name, '')
     FROM public.merchants m
     WHERE m.user_id = NEW.sender_id
     LIMIT 1),
    (SELECT NULLIF(c.name, '')
     FROM public.couriers c
     WHERE c.user_id = NEW.sender_id
     LIMIT 1),
    'Pengguna'
  )
  INTO sender_name;

  preview := left(
    regexp_replace(trim(COALESCE(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
    120
  );

  FOR recipient IN
    SELECT p.user_id, p.role
    FROM public.chat_participants p
    WHERE p.conversation_id = NEW.conversation_id
      AND p.user_id <> NEW.sender_id
      AND p.left_at IS NULL
      AND (p.muted_until IS NULL OR p.muted_until <= now())
  LOOP
    BEGIN
      PERFORM public.send_chat_notification(
        recipient.user_id,
        NEW.conversation_id,
        NEW.id,
        COALESCE(sender_name, 'Pesan baru'),
        preview
      );
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        PERFORM public.send_notification(
          recipient.user_id,
          COALESCE(sender_name, 'Pesan baru'),
          COALESCE(preview, 'Pesan baru'),
          'chat',
          '/buyer/chat?conversationId=' || NEW.conversation_id::text
        );
      EXCEPTION WHEN OTHERS THEN
        -- Notification failures must never roll back the chat message.
        RAISE WARNING 'chat notification failed for message %: % (%)', NEW.id, SQLERRM, SQLSTATE;
      END;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.get_chat_unread_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_unread_count() TO authenticated;
-- ===== END BUNDLE: 41_20260909152000_role_aware_chat_notifications.sql =====

-- ===== BEGIN BUNDLE: 42_20260909170000_chat_notification_final_repair.sql =====
-- Final chat notification repair.
-- This migration is self-contained so deploying only the latest chat patch still
-- creates an in-app notification for every incoming chat message.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES public.chat_conversations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS message_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sender_display_name text,
  ADD COLUMN IF NOT EXISTS preview text,
  ADD COLUMN IF NOT EXISTS deep_link text,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_chat_idempotency_uidx
  ON public.notifications (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS notifications_chat_conversation_idx
  ON public.notifications (conversation_id, created_at DESC)
  WHERE conversation_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(
  p_user_id uuid,
  p_conversation_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE COALESCE((
    SELECT role
    FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
    LIMIT 1
  ), '')
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN '/courier/chat?conversationId=' || p_conversation_id::text
    WHEN 'passenger' THEN '/ride/tracking?conversationId=' || p_conversation_id::text
    WHEN 'admin_desa' THEN '/desa/chat?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.send_chat_notification(
  p_recipient_id uuid,
  p_conversation_id uuid,
  p_message_id uuid,
  p_sender_display_name text,
  p_preview text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_key text := 'chat:' || p_message_id::text || ':' || p_recipient_id::text;
  v_link text := public.chat_notification_deep_link(p_recipient_id, p_conversation_id);
BEGIN
  INSERT INTO public.notifications (
    user_id,
    title,
    message,
    type,
    link,
    conversation_id,
    message_id,
    sender_display_name,
    preview,
    deep_link,
    idempotency_key
  )
  VALUES (
    p_recipient_id,
    left(coalesce(nullif(trim(p_sender_display_name), ''), 'Pesan baru'), 120),
    left(coalesce(nullif(trim(p_preview), ''), 'Pesan baru'), 120),
    'chat',
    v_link,
    p_conversation_id,
    p_message_id,
    left(coalesce(p_sender_display_name, 'Pengguna'), 120),
    left(coalesce(p_preview, ''), 120),
    v_link,
    v_key
  )
  ON CONFLICT (user_id, idempotency_key) DO UPDATE SET
    conversation_id = EXCLUDED.conversation_id,
    message_id = EXCLUDED.message_id,
    link = EXCLUDED.link,
    deep_link = EXCLUDED.deep_link
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_chat_notification(uuid, uuid, uuid, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recipient record;
  sender_name text;
  message_preview text;
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(m.name, '') FROM public.merchants m WHERE m.user_id = NEW.sender_id LIMIT 1),
    (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = NEW.sender_id LIMIT 1),
    'Pengguna'
  ) INTO sender_name;

  message_preview := left(
    regexp_replace(trim(coalesce(NEW.body, NEW.message)), E'[\\n\\r]+', ' ', 'g'),
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
    BEGIN
      PERFORM public.send_chat_notification(
        recipient.user_id,
        NEW.conversation_id,
        NEW.id,
        sender_name,
        message_preview
      );
    EXCEPTION WHEN OTHERS THEN
      -- Keep compatibility with databases where one of the newer chat
      -- notification columns/functions was not deployed yet. The legacy
      -- function writes the core notification columns used by the UI.
      BEGIN
        PERFORM public.send_notification(
          recipient.user_id,
          coalesce(sender_name, 'Pesan baru'),
          coalesce(message_preview, 'Pesan baru'),
          'chat',
          public.chat_notification_deep_link(recipient.user_id, NEW.conversation_id)
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'chat notification failed for message %: % (%)', NEW.id, SQLERRM, SQLSTATE;
      END;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_notify_recipient ON public.chat_messages;
CREATE TRIGGER chat_messages_notify_recipient
AFTER INSERT ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.notify_chat_message();

COMMENT ON FUNCTION public.notify_chat_message() IS
  'Creates one idempotent in-app notification per active chat recipient without rolling back the message.';

-- Backfill recent messages created while the notification trigger was broken.
-- This is intentionally limited to one day and is idempotent for canonical
-- notifications; legacy fallback rows are guarded by a message preview check.
DO $$
DECLARE
  message_row record;
  sender_name text;
  message_preview text;
BEGIN
  FOR message_row IN
    SELECT m.id, m.conversation_id, m.sender_id, m.receiver_id, m.body, m.message
    FROM public.chat_messages m
    WHERE m.conversation_id IS NOT NULL
      AND m.created_at > now() - interval '1 day'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.message_id = m.id
      )
  LOOP
    SELECT COALESCE(
      (SELECT NULLIF(p.full_name, '') FROM public.profiles p WHERE p.user_id = message_row.sender_id LIMIT 1),
      (SELECT NULLIF(mm.name, '') FROM public.merchants mm WHERE mm.user_id = message_row.sender_id LIMIT 1),
      (SELECT NULLIF(c.name, '') FROM public.couriers c WHERE c.user_id = message_row.sender_id LIMIT 1),
      'Pengguna'
    ) INTO sender_name;
    message_preview := left(regexp_replace(trim(coalesce(message_row.body, message_row.message)), E'[\\n\\r]+', ' ', 'g'), 120);
    BEGIN
      PERFORM public.send_chat_notification(message_row.receiver_id, message_row.conversation_id, message_row.id, sender_name, message_preview);
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.send_notification(
        message_row.receiver_id,
        coalesce(sender_name, 'Pesan baru'),
        coalesce(message_preview, 'Pesan baru'),
        'chat',
        public.chat_notification_deep_link(message_row.receiver_id, message_row.conversation_id)
      );
    END;
  END LOOP;
END;
$$;
-- ===== END BUNDLE: 42_20260909170000_chat_notification_final_repair.sql =====

-- ===== BEGIN BUNDLE: 43_20260909180000_order_fulfillment_flow.sql =====
-- Order fulfillment flow repair
-- Keeps legacy statuses readable while allowing the complete merchant/buyer lifecycle.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'NEW',
    'PENDING_CONFIRMATION',
    'PENDING_PAYMENT',
    'PROCESSED',
    'READY',
    'ASSIGNED',
    'COURIER_ASSIGNED',
    'COURIER_ACCEPTED',
    'COURIER_REJECTED',
    'PICKED_UP',
    'SENT',
    'DELIVERING',
    'DELIVERED',
    'DONE',
    'CANCELED',
    'REJECTED',
    'REJECTED_BY_BUYER',
    'REFUNDED'
  ));

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_notes text,
  ADD COLUMN IF NOT EXISTS courier_rejected_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS courier_assigned_at timestamptz,
  ADD COLUMN IF NOT EXISTS courier_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_orders_fulfillment_status
  ON public.orders (merchant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_courier_queue
  ON public.orders (status, delivery_type, created_at DESC)
  WHERE delivery_type = 'INTERNAL';

COMMENT ON COLUMN public.orders.status IS
  'Lifecycle: NEW/PENDING_PAYMENT -> PROCESSED -> READY -> ASSIGNED/COURIER_ACCEPTED -> PICKED_UP -> DELIVERING -> DELIVERED -> DONE';
COMMENT ON COLUMN public.orders.courier_rejected_ids IS
  'Kurir yang menolak order ini dan tidak boleh ditawarkan ulang untuk order yang sama.';
-- ===== END BUNDLE: 43_20260909180000_order_fulfillment_flow.sql =====

-- ===== BEGIN BUNDLE: 43_20260910200000_fix_chat_ride_deep_link.sql =====
-- Fix passenger chat notifications to target the registered ride route.
-- The route is /ride/:id; conversation_id remains a query parameter for
-- opening the exact chat after the ride is loaded.
CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(
  p_user_id uuid,
  p_conversation_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE COALESCE((
    SELECT role
    FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
    LIMIT 1
  ), '')
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN CASE
      WHEN c.context_type = 'ride' AND c.ride_request_id IS NOT NULL
        THEN '/courier/rides?conversationId=' || p_conversation_id::text
      ELSE '/courier/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'passenger' THEN CASE
      WHEN c.ride_request_id IS NOT NULL
        THEN '/ride/' || c.ride_request_id::text || '?conversationId=' || p_conversation_id::text
      ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'admin_desa' THEN '/desa/chat?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END
  FROM public.chat_conversations c
  WHERE c.id = p_conversation_id);
$$;

GRANT EXECUTE ON FUNCTION public.chat_notification_deep_link(uuid, uuid)
  TO service_role;
-- ===== END BUNDLE: 43_20260910200000_fix_chat_ride_deep_link.sql =====

-- ===== BEGIN BUNDLE: 43_20260922114500_chat_image_attachments.sql =====
-- Chat image attachments: private storage + atomic message write.
-- Files are stored under <conversation_id>/<sender_id>/<uuid>.<ext>.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-attachments',
  'chat-attachments',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[];

DROP POLICY IF EXISTS "Chat participants upload attachments" ON storage.objects;
CREATE POLICY "Chat participants upload attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments'
  AND public.is_chat_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
  AND (storage.foldername(name))[2] = auth.uid()::text
);

DROP POLICY IF EXISTS "Chat participants read attachments" ON storage.objects;
CREATE POLICY "Chat participants read attachments"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND public.is_chat_conversation_participant((storage.foldername(name))[1]::uuid, auth.uid())
);

DROP POLICY IF EXISTS "Users delete own chat attachments" ON storage.objects;
CREATE POLICY "Users delete own chat attachments"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'chat-attachments'
  AND (storage.foldername(name))[2] = auth.uid()::text
);

ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_attachment_path_check
  CHECK (attachment_path IS NULL OR attachment_path LIKE '%/%/%') NOT VALID;

-- Five-argument variant keeps the existing four-argument RPC backwards compatible.
CREATE OR REPLACE FUNCTION public.send_chat_message_with_attachment(
  p_conversation_id uuid,
  p_receiver_id uuid,
  p_body text,
  p_client_message_id uuid,
  p_attachment_path text DEFAULT NULL
)
RETURNS public.chat_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.chat_messages%ROWTYPE;
  v_conversation public.chat_conversations%ROWTYPE;
  v_body text;
BEGIN
  IF auth.uid() IS NULL
     OR p_conversation_id IS NULL
     OR p_receiver_id IS NULL
     OR p_client_message_id IS NULL
  THEN
    RAISE EXCEPTION 'invalid chat message request' USING ERRCODE = '22023';
  END IF;

  v_body := btrim(COALESCE(p_body, ''));
  IF length(v_body) > 4000 THEN
    RAISE EXCEPTION 'chat message must contain at most 4000 characters' USING ERRCODE = '22023';
  END IF;
  IF length(v_body) = 0 AND p_attachment_path IS NULL THEN
    RAISE EXCEPTION 'chat message must contain text or an image' USING ERRCODE = '22023';
  END IF;
  IF p_attachment_path IS NOT NULL AND (
    p_attachment_path !~ '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]+$'
    OR p_attachment_path LIKE '%..%'
  ) THEN
    RAISE EXCEPTION 'invalid chat attachment path' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_conversation
  FROM public.chat_conversations
  WHERE id = p_conversation_id AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'conversation is not active' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_chat_conversation_participant(p_conversation_id, auth.uid())
     OR NOT public.is_chat_conversation_participant(p_conversation_id, p_receiver_id)
     OR p_receiver_id = auth.uid()
  THEN
    RAISE EXCEPTION 'sender or receiver is not an active participant' USING ERRCODE = '42501';
  END IF;
  IF p_attachment_path IS NOT NULL
     AND split_part(p_attachment_path, '/', 1) <> p_conversation_id::text
  THEN
    RAISE EXCEPTION 'attachment does not belong to conversation' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_message
  FROM public.chat_messages
  WHERE sender_id = auth.uid() AND client_message_id = p_client_message_id
  LIMIT 1;
  IF FOUND THEN
    IF v_message.conversation_id <> p_conversation_id
       OR v_message.receiver_id <> p_receiver_id
       OR btrim(COALESCE(v_message.body, v_message.message)) <> COALESCE(v_body, '')
       OR v_message.attachment_path IS DISTINCT FROM p_attachment_path
    THEN
      RAISE EXCEPTION 'client message ID was already used with different data' USING ERRCODE = '23505';
    END IF;
    RETURN v_message;
  END IF;

  INSERT INTO public.chat_messages (
    conversation_id, order_id, sender_id, receiver_id, message, body,
    message_type, client_message_id, chat_type, attachment_path
  ) VALUES (
    p_conversation_id, v_conversation.order_id, auth.uid(), p_receiver_id,
    COALESCE(NULLIF(v_body, ''), 'Gambar'), v_body,
    CASE WHEN p_attachment_path IS NULL THEN 'text' ELSE 'image' END,
    p_client_message_id, v_conversation.conversation_type, p_attachment_path
  )
  RETURNING * INTO v_message;
  RETURN v_message;
END;
$$;

REVOKE ALL ON FUNCTION public.send_chat_message_with_attachment(uuid, uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_chat_message_with_attachment(uuid, uuid, text, uuid, text) TO authenticated;

COMMENT ON FUNCTION public.send_chat_message_with_attachment IS
  'Atomically writes a chat text/image message after validating conversation membership and attachment path.';

NOTIFY pgrst, 'reload schema';

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;
ALTER TABLE public.chat_messages ADD CONSTRAINT chat_messages_message_type_check
  CHECK (message_type IN ('text', 'image')) NOT VALID;
-- ===== END BUNDLE: 43_20260922114500_chat_image_attachments.sql =====

