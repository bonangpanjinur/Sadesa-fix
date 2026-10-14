-- Manual refund settlement queue for the current legacy invoice checkout.
-- This bundle intentionally does not send funds or call a provider API.
-- Legacy Xendit invoice records do not contain the Payment Request ID required
-- by the current Refunds API, so approved refunds must be paid and evidenced by
-- an administrator until checkout is migrated in a separately approved change.

ALTER TABLE public.refund_settlements
  ADD COLUMN IF NOT EXISTS manual_evidence_path text,
  ADD COLUMN IF NOT EXISTS manual_verified_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS manual_verified_at timestamptz;

-- Private proof bucket: only admins can upload/read/delete settlement receipts.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'refund-settlement-evidence',
  'refund-settlement-evidence',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[];

DROP POLICY IF EXISTS "Admins can upload refund settlement evidence" ON storage.objects;
CREATE POLICY "Admins can upload refund settlement evidence"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'refund-settlement-evidence'
  AND public.is_admin()
  AND name ~ '^settlements/[0-9a-fA-F-]{36}/[A-Za-z0-9_.-]{1,200}$'
);

DROP POLICY IF EXISTS "Admins can read refund settlement evidence" ON storage.objects;
CREATE POLICY "Admins can read refund settlement evidence"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'refund-settlement-evidence' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete refund settlement evidence" ON storage.objects;
CREATE POLICY "Admins can delete refund settlement evidence"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'refund-settlement-evidence' AND public.is_admin());

CREATE OR REPLACE FUNCTION public.route_legacy_refund_settlement_to_manual()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'PENDING' AND NEW.provider_reference IS NULL THEN
    NEW.provider := 'MANUAL';
    NEW.provider_status := 'MANUAL_REQUIRED';
    NEW.last_error := 'Legacy checkout does not store a Payment Request ID; verify the payout destination and complete this refund manually.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.route_legacy_refund_settlement_to_manual() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS route_legacy_refund_settlement_to_manual ON public.refund_settlements;
CREATE TRIGGER route_legacy_refund_settlement_to_manual
BEFORE INSERT ON public.refund_settlements
FOR EACH ROW EXECUTE FUNCTION public.route_legacy_refund_settlement_to_manual();

-- Idempotent worker for approved settlements created before this routing rule.
-- Existing provider references are deliberately excluded: those could represent
-- a live provider refund, and must not be double-paid manually.
CREATE OR REPLACE FUNCTION public.queue_legacy_refund_settlements(p_limit integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  WITH candidates AS (
    SELECT id, refund_request_id
    FROM public.refund_settlements
    WHERE status = 'PENDING'
      AND lower(provider) = 'xendit'
      AND provider_reference IS NULL
    ORDER BY created_at, id
    FOR UPDATE SKIP LOCKED
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ), routed AS (
    UPDATE public.refund_settlements AS s
    SET provider = 'MANUAL',
        provider_status = 'MANUAL_REQUIRED',
        last_error = 'Legacy checkout does not store a Payment Request ID; verify the payout destination and complete this refund manually.',
        updated_at = now()
    FROM candidates AS c
    WHERE s.id = c.id
    RETURNING s.refund_request_id
  )
  UPDATE public.refund_requests AS r
  SET settlement_status = 'PENDING', updated_at = now()
  WHERE r.id IN (SELECT refund_request_id FROM routed);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.queue_legacy_refund_settlements(integer) FROM PUBLIC, anon, authenticated, service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
DO $schedule_manual_refund_queue$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job WHERE jobname = 'route-legacy-refunds-to-manual-queue'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;
  PERFORM cron.schedule(
    'route-legacy-refunds-to-manual-queue',
    '* * * * *',
    'SELECT public.queue_legacy_refund_settlements(100);'
  );
END;
$schedule_manual_refund_queue$;

-- Keep provider/service-role completion intact. Admin completion is allowed only
-- when the manual queue has an uploaded private receipt bound to this settlement
-- and verified by the same admin in the current transaction.
CREATE OR REPLACE FUNCTION public.complete_refund_settlement(
  p_settlement_id uuid, p_success boolean, p_provider_reference text,
  p_provider_amount integer, p_provider_status text, p_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_balance numeric := 0;
  v_deducted numeric := 0;
  v_shortfall numeric := 0;
  v_commission_reversed bigint := 0;
  v_reference text := NULLIF(btrim(p_provider_reference), '');
  v_status text := upper(COALESCE(NULLIF(btrim(p_provider_status), ''), ''));
BEGIN
  SELECT * INTO v_settlement
  FROM public.refund_settlements
  WHERE id = p_settlement_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Settlement not found' USING ERRCODE = 'P0002'; END IF;

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       auth.uid() IS NOT NULL
       AND public.is_admin()
       AND v_settlement.provider = 'MANUAL'
       AND v_settlement.manual_evidence_path IS NOT NULL
       AND v_settlement.manual_verified_by = auth.uid()
     ) THEN
    RAISE EXCEPTION 'Settlement worker or evidenced manual admin completion required' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(auth.role(), '') = 'service_role'
     AND v_settlement.provider = 'MANUAL'
     AND (v_settlement.manual_evidence_path IS NULL
          OR v_settlement.manual_verified_by IS NULL
          OR v_settlement.manual_verified_at IS NULL) THEN
    RAISE EXCEPTION 'Manual settlement requires an administrator-uploaded receipt' USING ERRCODE = '42501';
  END IF;
  IF v_settlement.status = 'COMPLETED' THEN
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'COMPLETED', 'duplicate', true);
  END IF;
  IF v_settlement.status NOT IN ('PENDING', 'FAILED', 'PROCESSING') THEN
    RAISE EXCEPTION 'Refund settlement state does not allow provider result' USING ERRCODE = '55000';
  END IF;
  IF v_reference IS NOT NULL AND length(v_reference) > 200 THEN
    RAISE EXCEPTION 'Provider reference exceeds the supported length' USING ERRCODE = '22023';
  END IF;
  IF p_success IS TRUE THEN
    IF v_reference IS NULL OR v_status <> 'SUCCEEDED'
       OR p_provider_amount IS NULL OR p_provider_amount <> v_settlement.amount THEN
      RAISE EXCEPTION 'Successful refund requires a unique provider reference, SUCCEEDED status, and exact amount' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.refund_settlements
      WHERE btrim(provider_reference) = v_reference AND id <> p_settlement_id
    ) THEN
      RAISE EXCEPTION 'Provider reference has already been used' USING ERRCODE = '23505';
    END IF;
  ELSIF v_status NOT IN ('FAILED', 'REJECTED') THEN
    RAISE EXCEPTION 'Failed refund requires a FAILED or REJECTED provider status' USING ERRCODE = '22023';
  END IF;

  IF NOT p_success THEN
    UPDATE public.refund_settlements
    SET status = 'FAILED', provider_reference = v_reference,
        provider_status = v_status, provider_amount = p_provider_amount,
        last_error = left(COALESCE(p_error, 'Provider refund failed'), 500), updated_at = now()
    WHERE id = p_settlement_id;
    UPDATE public.refund_requests
    SET settlement_status = 'FAILED', updated_at = now()
    WHERE id = v_settlement.refund_request_id;
    RETURN jsonb_build_object('id', p_settlement_id, 'status', 'FAILED');
  END IF;

  SELECT COALESCE(m.available_balance, 0) INTO v_balance
  FROM public.merchants AS m
  WHERE m.id = v_settlement.merchant_id
  FOR UPDATE;
  v_deducted := LEAST(GREATEST(v_balance, 0), v_settlement.amount);
  v_shortfall := GREATEST(v_settlement.amount - v_deducted, 0);

  UPDATE public.refund_settlements
  SET status = 'COMPLETED', provider_reference = v_reference,
      provider_status = v_status, provider_amount = p_provider_amount,
      updated_at = now(), completed_at = now()
  WHERE id = p_settlement_id;
  UPDATE public.refund_requests
  SET settlement_status = 'COMPLETED', updated_at = now()
  WHERE id = v_settlement.refund_request_id;
  UPDATE public.orders
  SET status = 'REFUNDED', payment_status = 'REFUNDED', updated_at = now()
  WHERE id = v_settlement.order_id;
  UPDATE public.merchants
  SET available_balance = COALESCE(available_balance, 0) - v_deducted, updated_at = now()
  WHERE id = v_settlement.merchant_id;

  IF v_shortfall > 0 THEN
    INSERT INTO public.merchant_refund_shortfalls(
      settlement_id, merchant_id, order_id, refund_request_id, amount,
      deducted_amount, outstanding_amount, status
    ) VALUES (
      v_settlement.id, v_settlement.merchant_id, v_settlement.order_id,
      v_settlement.refund_request_id, v_settlement.amount, v_deducted, v_shortfall, 'OPEN'
    ) ON CONFLICT (settlement_id) DO NOTHING;
  END IF;
  v_commission_reversed := public.reverse_commission_for_refund(
    v_settlement.refund_request_id, v_settlement.order_id, v_settlement.amount
  );
  RETURN jsonb_build_object(
    'id', p_settlement_id, 'status', 'COMPLETED', 'provider_reference', v_reference,
    'provider_amount', p_provider_amount, 'provider_status', v_status,
    'deducted_amount', v_deducted, 'shortfall_amount', v_shortfall,
    'shortfall_status', CASE WHEN v_shortfall > 0 THEN 'OPEN' ELSE 'NONE' END,
    'commission_reversed_rupiah', v_commission_reversed
  );
END;
$$;
REVOKE ALL ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_refund_settlement(uuid, boolean, text, integer, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_manual_refund_settlement(
  p_settlement_id uuid,
  p_provider_reference text,
  p_provider_amount integer,
  p_evidence_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settlement public.refund_settlements%ROWTYPE;
  v_reference text := NULLIF(btrim(p_provider_reference), '');
  v_path text := NULLIF(btrim(p_evidence_path), '');
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required' USING ERRCODE = '42501';
  END IF;
  IF v_reference IS NULL OR length(v_reference) > 200 THEN
    RAISE EXCEPTION 'Bank/provider transfer reference is required' USING ERRCODE = '22023';
  END IF;
  IF v_path IS NULL OR v_path !~ (
    '^settlements/' || p_settlement_id::text || '/[A-Za-z0-9_.-]{1,200}$'
  ) THEN
    RAISE EXCEPTION 'Manual refund receipt path is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_settlement
  FROM public.refund_settlements
  WHERE id = p_settlement_id
  FOR UPDATE;
  IF NOT FOUND OR v_settlement.provider <> 'MANUAL' THEN
    RAISE EXCEPTION 'Manual refund settlement not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_settlement.status NOT IN ('PENDING', 'FAILED') THEN
    RAISE EXCEPTION 'Manual settlement is not awaiting payout confirmation' USING ERRCODE = '55000';
  END IF;
  IF p_provider_amount IS NULL OR p_provider_amount <> v_settlement.amount THEN
    RAISE EXCEPTION 'Manual payout amount must exactly match the approved refund' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'refund-settlement-evidence' AND name = v_path
  ) THEN
    RAISE EXCEPTION 'Uploaded manual refund receipt was not found' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.refund_settlements
    WHERE btrim(provider_reference) = v_reference AND id <> p_settlement_id
  ) THEN
    RAISE EXCEPTION 'Transfer reference has already been used' USING ERRCODE = '23505';
  END IF;

  UPDATE public.refund_settlements
  SET manual_evidence_path = v_path,
      manual_verified_by = auth.uid(),
      manual_verified_at = now(),
      provider_reference = v_reference,
      provider_status = 'SUCCEEDED',
      provider_amount = p_provider_amount,
      last_error = NULL,
      updated_at = now()
  WHERE id = p_settlement_id;

  v_result := public.complete_refund_settlement(
    p_settlement_id, true, v_reference, p_provider_amount, 'SUCCEEDED', NULL
  );
  RETURN v_result || jsonb_build_object('manual', true, 'evidence_path', v_path);
END;
$$;
REVOKE ALL ON FUNCTION public.complete_manual_refund_settlement(uuid, text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_manual_refund_settlement(uuid, text, integer, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
