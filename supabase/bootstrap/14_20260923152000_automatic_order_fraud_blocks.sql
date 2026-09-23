-- Automatic, auditable order fraud controls.
-- A block is a risk signal with expiry, not proof of fraud.
CREATE TABLE IF NOT EXISTS public.order_fraud_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  block_type text NOT NULL CHECK (block_type IN ('user', 'device', 'ip')),
  block_value text NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reason text NOT NULL,
  failed_order_count integer NOT NULL DEFAULT 0,
  distinct_user_count integer NOT NULL DEFAULT 1,
  blocked_until timestamptz NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (block_type, block_value)
);

CREATE INDEX IF NOT EXISTS idx_order_fraud_blocks_active
  ON public.order_fraud_blocks(blocked_until, block_type);
CREATE INDEX IF NOT EXISTS idx_order_fraud_blocks_user
  ON public.order_fraud_blocks(user_id, blocked_until);

ALTER TABLE public.order_fraud_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_fraud_blocks FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS "Admins view order fraud blocks" ON public.order_fraud_blocks;
CREATE POLICY "Admins view order fraud blocks"
  ON public.order_fraud_blocks FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.enforce_automatic_order_fraud_blocks()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_device_id text;
  v_ip_address inet;
  v_user_failed integer := 0;
  v_device_failed integer := 0;
  v_ip_failed integer := 0;
  v_ip_users integer := 0;
  v_reason text;
  v_block_type text;
  v_block_value text;
  v_existing_block public.order_fraud_blocks%ROWTYPE;
BEGIN
  -- Do not apply buyer fraud heuristics to admin/service-role imports or
  -- server-side payment/webhook operations.
  IF v_user_id IS NULL OR auth.role() = 'service_role' OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.buyer_id IS DISTINCT FROM v_user_id THEN
    RETURN NEW;
  END IF;

  SELECT p.device_id, p.ip_address
  INTO v_device_id, v_ip_address
  FROM public.pwa_device_sessions p
  WHERE p.user_id = v_user_id AND p.status = 'active'
  ORDER BY p.last_seen_at DESC
  LIMIT 1;

  SELECT * INTO v_existing_block
  FROM public.order_fraud_blocks b
  WHERE b.blocked_until > now()
    AND ((b.block_type = 'user' AND b.block_value = v_user_id::text)
      OR (b.block_type = 'device' AND v_device_id IS NOT NULL AND b.block_value = v_device_id)
      OR (b.block_type = 'ip' AND v_ip_address IS NOT NULL AND b.block_value = v_ip_address::text))
  ORDER BY b.blocked_until DESC
  LIMIT 1;

  IF FOUND THEN
    v_reason := v_existing_block.reason;
  ELSE
    SELECT count(*)::integer INTO v_user_failed
    FROM public.orders o
    WHERE o.buyer_id = v_user_id
      AND COALESCE(o.payment_status, 'UNPAID') IN ('UNPAID', 'EXPIRED', 'FAILED')
      AND o.created_at >= now() - interval '24 hours';

    IF v_device_id IS NOT NULL THEN
      SELECT count(*)::integer INTO v_device_failed
      FROM public.orders o
      WHERE o.buyer_id IN (
        SELECT DISTINCT p.user_id FROM public.pwa_device_sessions p WHERE p.device_id = v_device_id
      )
        AND COALESCE(o.payment_status, 'UNPAID') IN ('UNPAID', 'EXPIRED', 'FAILED')
        AND o.created_at >= now() - interval '24 hours';
    END IF;

    IF v_ip_address IS NOT NULL THEN
      SELECT count(*)::integer, count(DISTINCT o.buyer_id)::integer
      INTO v_ip_failed, v_ip_users
      FROM public.orders o
      WHERE o.buyer_id IN (
        SELECT DISTINCT p.user_id FROM public.pwa_device_sessions p WHERE p.ip_address = v_ip_address
      )
        AND COALESCE(o.payment_status, 'UNPAID') IN ('UNPAID', 'EXPIRED', 'FAILED')
        AND o.created_at >= now() - interval '24 hours';
    END IF;

    IF v_user_failed >= 2 THEN
      v_block_type := 'user';
      v_block_value := v_user_id::text;
      v_reason := '3+ unpaid or failed orders by user in 24 hours';
    ELSIF v_device_failed >= 2 AND v_device_id IS NOT NULL THEN
      v_block_type := 'device';
      v_block_value := v_device_id;
      v_reason := '3+ unpaid or failed orders associated with device in 24 hours';
    ELSIF v_ip_failed >= 11 AND v_ip_users >= 3 AND v_ip_address IS NOT NULL THEN
      v_block_type := 'ip';
      v_block_value := v_ip_address::text;
      v_reason := '12+ unpaid or failed orders from IP across 3+ users in 24 hours';
    END IF;

    IF v_reason IS NOT NULL AND v_block_type IS NOT NULL THEN
      INSERT INTO public.order_fraud_blocks(
        block_type, block_value, user_id, reason, failed_order_count,
        distinct_user_count, blocked_until, metadata, updated_at
      ) VALUES (
        v_block_type, v_block_value, v_user_id, v_reason,
        GREATEST(v_user_failed, v_device_failed, v_ip_failed),
        GREATEST(1, v_ip_users), now() + interval '24 hours',
        jsonb_build_object('user_id', v_user_id, 'device_id', v_device_id, 'ip_address', v_ip_address::text, 'window', '24 hours'), now()
      )
      ON CONFLICT (block_type, block_value) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        reason = EXCLUDED.reason,
        failed_order_count = EXCLUDED.failed_order_count,
        distinct_user_count = EXCLUDED.distinct_user_count,
        blocked_until = EXCLUDED.blocked_until,
        metadata = EXCLUDED.metadata,
        updated_at = now();
    END IF;
  END IF;

  IF v_reason IS NOT NULL THEN
    NEW.status := 'CANCELED';
    NEW.payment_status := 'EXPIRED';
    NEW.cancellation_reason := 'AUTOMATIC_FRAUD_BLOCK: ' || v_reason;
    NEW.cancelled_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_automatic_order_fraud_blocks ON public.orders;
CREATE TRIGGER trg_automatic_order_fraud_blocks
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_automatic_order_fraud_blocks();

REVOKE ALL ON FUNCTION public.enforce_automatic_order_fraud_blocks() FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.order_fraud_blocks IS
  'Expiring, auditable automatic blocks based on repeated unpaid or failed orders; not a definitive fraud finding.';
