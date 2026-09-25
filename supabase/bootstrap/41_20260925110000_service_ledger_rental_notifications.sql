-- Penyempurnaan marketplace jasa: ledger immutable, domain status, rental, notifikasi, dan SLA.

ALTER TABLE public.service_requests
  ADD COLUMN IF NOT EXISTS service_type text NOT NULL DEFAULT 'JOB',
  ADD COLUMN IF NOT EXISTS rental_start_at timestamptz,
  ADD COLUMN IF NOT EXISTS rental_end_at timestamptz,
  ADD COLUMN IF NOT EXISTS rental_deposit numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rental_late_fee_per_day numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS handover_condition text,
  ADD COLUMN IF NOT EXISTS return_condition text,
  ADD COLUMN IF NOT EXISTS handover_at timestamptz,
  ADD COLUMN IF NOT EXISTS returned_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'NOT_STARTED',
  ADD COLUMN IF NOT EXISTS work_status text NOT NULL DEFAULT 'NOT_STARTED',
  ADD COLUMN IF NOT EXISTS dispute_status text NOT NULL DEFAULT 'NONE',
  ADD COLUMN IF NOT EXISTS payout_status text NOT NULL DEFAULT 'NOT_CREATED',
  ADD COLUMN IF NOT EXISTS negotiation_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS completion_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text;

ALTER TABLE public.service_requests
  DROP CONSTRAINT IF EXISTS service_requests_service_type_check;
ALTER TABLE public.service_requests
  ADD CONSTRAINT service_requests_service_type_check CHECK (service_type IN ('JOB','RENTAL'));
ALTER TABLE public.service_requests
  DROP CONSTRAINT IF EXISTS service_requests_rental_amounts_check;
ALTER TABLE public.service_requests
  ADD CONSTRAINT service_requests_rental_amounts_check CHECK (rental_deposit >= 0 AND rental_late_fee_per_day >= 0);
ALTER TABLE public.service_requests
  DROP CONSTRAINT IF EXISTS service_requests_rental_dates_check;
ALTER TABLE public.service_requests
  ADD CONSTRAINT service_requests_rental_dates_check CHECK (service_type = 'JOB' OR (rental_start_at IS NOT NULL AND rental_end_at IS NOT NULL AND rental_end_at > rental_start_at));

CREATE INDEX IF NOT EXISTS idx_service_requests_sla
  ON public.service_requests(status, negotiation_due_at, payment_due_at, completion_due_at);
CREATE INDEX IF NOT EXISTS idx_service_requests_domain_status
  ON public.service_requests(payment_status, work_status, dispute_status, payout_status);

CREATE TABLE IF NOT EXISTS public.service_transaction_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.service_requests(id) ON DELETE RESTRICT,
  event_type text NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  amount numeric(14,2),
  currency text NOT NULL DEFAULT 'IDR',
  external_reference text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_service_ledger_request_time
  ON public.service_transaction_ledger(request_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_ledger_type_time
  ON public.service_transaction_ledger(event_type, created_at DESC);
ALTER TABLE public.service_transaction_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "participants read service ledger" ON public.service_transaction_ledger;
CREATE POLICY "participants read service ledger" ON public.service_transaction_ledger FOR SELECT USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.service_requests r
    WHERE r.id = request_id AND (r.requester_id = auth.uid() OR r.provider_id = auth.uid())
  )
);
REVOKE INSERT, UPDATE, DELETE ON public.service_transaction_ledger FROM anon, authenticated;

CREATE TABLE IF NOT EXISTS public.service_sla_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.service_requests(id) ON DELETE RESTRICT,
  event_type text NOT NULL,
  previous_status text,
  resulting_status text,
  due_at timestamptz,
  executed_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_service_sla_events_request ON public.service_sla_events(request_id, executed_at DESC);
ALTER TABLE public.service_sla_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "participants read service sla events" ON public.service_sla_events;
CREATE POLICY "participants read service sla events" ON public.service_sla_events FOR SELECT USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.service_requests r
    WHERE r.id = request_id AND (r.requester_id = auth.uid() OR r.provider_id = auth.uid())
  )
);
REVOKE INSERT, UPDATE, DELETE ON public.service_sla_events FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.service_sync_domain_status()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.payment_status := CASE NEW.status
    WHEN 'WAITING_PAYMENT' THEN 'AWAITING_TRANSFER'
    WHEN 'PAID_TO_ADMIN' THEN 'VERIFIED'
    WHEN 'APPROVED_TO_START' THEN 'VERIFIED'
    WHEN 'IN_PROGRESS' THEN 'VERIFIED'
    WHEN 'WAITING_CONFIRMATION' THEN 'VERIFIED'
    WHEN 'COMPLETED' THEN 'SETTLED'
    WHEN 'REFUNDED' THEN 'REFUNDED'
    WHEN 'CANCELLED' THEN 'CANCELLED'
    ELSE 'NOT_STARTED' END;
  NEW.work_status := CASE NEW.status
    WHEN 'APPROVED_TO_START' THEN 'READY'
    WHEN 'IN_PROGRESS' THEN 'IN_PROGRESS'
    WHEN 'WAITING_CONFIRMATION' THEN 'WAITING_CONFIRMATION'
    WHEN 'COMPLETED' THEN 'COMPLETED'
    WHEN 'DISPUTED' THEN 'DISPUTED'
    WHEN 'REFUNDED' THEN 'REFUNDED'
    WHEN 'CANCELLED' THEN 'CANCELLED'
    ELSE 'NOT_STARTED' END;
  NEW.dispute_status := CASE
    WHEN NEW.status = 'DISPUTED' THEN 'OPEN'
    WHEN NEW.status = 'REFUNDED' THEN 'REFUNDED'
    ELSE COALESCE(NEW.dispute_status, 'NONE') END;
  NEW.payout_status := CASE
    WHEN NEW.status = 'COMPLETED' THEN 'RELEASED'
    WHEN NEW.status = 'REFUNDED' THEN 'REFUNDED'
    WHEN NEW.status IN ('WAITING_CONFIRMATION','DISPUTED') THEN 'PENDING'
    ELSE COALESCE(NEW.payout_status, 'NOT_CREATED') END;
  IF TG_OP = 'INSERT' THEN
    NEW.negotiation_due_at := COALESCE(NEW.negotiation_due_at, now() + interval '48 hours');
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    IF NEW.status = 'WAITING_PAYMENT' THEN NEW.payment_due_at := COALESCE(NEW.payment_due_at, now() + interval '24 hours'); END IF;
    IF NEW.status IN ('APPROVED_TO_START','IN_PROGRESS') THEN NEW.completion_due_at := COALESCE(NEW.completion_due_at, now() + interval '14 days'); END IF;
    IF NEW.status = 'CANCELLED' THEN NEW.cancelled_at := COALESCE(NEW.cancelled_at, now()); END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_service_sync_domain_status ON public.service_requests;
CREATE TRIGGER trg_service_sync_domain_status
BEFORE INSERT OR UPDATE OF status ON public.service_requests
FOR EACH ROW EXECUTE FUNCTION public.service_sync_domain_status();

CREATE OR REPLACE FUNCTION public.service_emit_notification(
  p_user_id uuid, p_title text, p_message text, p_type text DEFAULT 'info', p_link text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.notifications(user_id, title, message, type, link)
  VALUES (p_user_id, left(p_title, 160), left(p_message, 1000), p_type, p_link);
END;
$$;
REVOKE ALL ON FUNCTION public.service_emit_notification(uuid,text,text,text,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.service_record_ledger(
  p_request_id uuid, p_event_type text, p_actor_id uuid DEFAULT NULL, p_amount numeric DEFAULT NULL,
  p_external_reference text DEFAULT NULL, p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.service_transaction_ledger(request_id, event_type, actor_id, amount, external_reference, metadata)
  VALUES (p_request_id, p_event_type, p_actor_id, p_amount, nullif(trim(p_external_reference), ''), COALESCE(p_metadata, '{}'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.service_record_ledger(uuid,text,uuid,numeric,text,jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.service_request_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_message text; v_event text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.service_record_ledger(NEW.id, 'REQUEST_CREATED', NEW.requester_id, NEW.requester_budget, NULL, jsonb_build_object('service_type', NEW.service_type));
    PERFORM public.service_emit_notification(NEW.provider_id, 'Permintaan jasa baru', 'Ada permintaan jasa baru yang perlu Anda tinjau.', 'order', '/services/provider-history');
    RETURN NEW;
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    v_event := 'STATUS_' || OLD.status || '_TO_' || NEW.status;
    v_message := CASE NEW.status
      WHEN 'WAITING_PAYMENT' THEN 'Harga disetujui. Silakan lakukan transfer dan unggah bukti pembayaran.'
      WHEN 'APPROVED_TO_START' THEN 'Pembayaran telah diverifikasi. Penyedia dapat mulai bekerja.'
      WHEN 'IN_PROGRESS' THEN 'Pekerjaan telah dimulai oleh penyedia jasa.'
      WHEN 'WAITING_CONFIRMATION' THEN 'Pekerjaan menunggu konfirmasi selesai dari pihak terkait.'
      WHEN 'COMPLETED' THEN 'Transaksi jasa selesai dan payout telah diproses.'
      WHEN 'DISPUTED' THEN 'Transaksi masuk proses sengketa dan sedang ditinjau admin.'
      WHEN 'REFUNDED' THEN 'Refund transaksi telah dicatat selesai.'
      WHEN 'CANCELLED' THEN 'Transaksi jasa dibatalkan karena melewati batas waktu.'
      ELSE 'Status request jasa berubah menjadi ' || NEW.status || '.' END;
    PERFORM public.service_record_ledger(NEW.id, v_event, auth.uid(), NEW.agreed_price, NULL, jsonb_build_object('from', OLD.status, 'to', NEW.status));
    PERFORM public.service_emit_notification(NEW.requester_id, 'Pembaruan request jasa', v_message, CASE WHEN NEW.status IN ('DISPUTED','CANCELLED') THEN 'warning' ELSE 'info' END, '/services/requests');
    PERFORM public.service_emit_notification(NEW.provider_id, 'Pembaruan request jasa', v_message, CASE WHEN NEW.status IN ('DISPUTED','CANCELLED') THEN 'warning' ELSE 'info' END, '/services/provider-history');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_service_request_events ON public.service_requests;
CREATE TRIGGER trg_service_request_events
AFTER INSERT OR UPDATE OF status ON public.service_requests
FOR EACH ROW EXECUTE FUNCTION public.service_request_events();

CREATE OR REPLACE FUNCTION public.service_payment_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.service_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request FROM public.service_requests WHERE id = COALESCE(NEW.request_id, OLD.request_id);
  IF TG_OP = 'INSERT' THEN
    PERFORM public.service_record_ledger(v_request.id, 'PAYMENT_PROOF_SUBMITTED', NEW.uploaded_by, NEW.amount, NEW.transfer_reference, jsonb_build_object('proof_id', NEW.id));
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.service_record_ledger(v_request.id, 'PAYMENT_PROOF_' || NEW.status, auth.uid(), NEW.amount, NEW.transfer_reference, jsonb_build_object('proof_id', NEW.id));
    PERFORM public.service_emit_notification(v_request.requester_id, 'Status bukti pembayaran', 'Bukti pembayaran Anda berstatus ' || NEW.status || '.', CASE WHEN NEW.status = 'REJECTED' THEN 'warning' ELSE 'success' END, '/services/requests');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_service_payment_events ON public.service_payment_proofs;
CREATE TRIGGER trg_service_payment_events
AFTER INSERT OR UPDATE OF status ON public.service_payment_proofs
FOR EACH ROW EXECUTE FUNCTION public.service_payment_events();

CREATE OR REPLACE FUNCTION public.service_dispute_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.service_record_ledger(NEW.request_id, 'DISPUTE_' || NEW.status, COALESCE(NEW.resolved_by, NEW.opened_by), NEW.amount, NULL, jsonb_build_object('dispute_id', NEW.id));
    PERFORM public.service_emit_notification(NEW.requester_id, 'Pembaruan sengketa jasa', 'Status sengketa berubah menjadi ' || NEW.status || '.', 'warning', '/services/requests');
    PERFORM public.service_emit_notification(NEW.provider_id, 'Pembaruan sengketa jasa', 'Status sengketa berubah menjadi ' || NEW.status || '.', 'warning', '/services/provider-history');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_service_dispute_events ON public.service_disputes;
CREATE TRIGGER trg_service_dispute_events
AFTER INSERT OR UPDATE OF status ON public.service_disputes
FOR EACH ROW EXECUTE FUNCTION public.service_dispute_events();

CREATE OR REPLACE FUNCTION public.service_payout_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.service_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request FROM public.service_requests WHERE id = NEW.request_id;
  IF OLD IS NULL OR OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.service_record_ledger(NEW.request_id, 'PAYOUT_' || NEW.status, NEW.released_by, NEW.net_amount, NEW.external_transfer_reference, jsonb_build_object('payout_id', NEW.id));
    IF NEW.status = 'RELEASED' THEN
      PERFORM public.service_emit_notification(v_request.requester_id, 'Payout jasa selesai', 'Payout penyedia telah dicatat oleh admin.', 'success', '/services/requests');
      PERFORM public.service_emit_notification(v_request.provider_id, 'Payout jasa selesai', 'Payout Anda telah dicatat ditransfer oleh admin.', 'success', '/services/provider-history');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_service_payout_events ON public.service_payouts;
CREATE TRIGGER trg_service_payout_events
AFTER INSERT OR UPDATE OF status ON public.service_payouts
FOR EACH ROW EXECUTE FUNCTION public.service_payout_events();

CREATE OR REPLACE FUNCTION public.service_create_request_v2(
  p_provider_id uuid, p_profile_id uuid, p_subcategory_id uuid, p_title text, p_description text,
  p_location text, p_budget numeric DEFAULT NULL, p_service_type text DEFAULT 'JOB',
  p_rental_start_at timestamptz DEFAULT NULL, p_rental_end_at timestamptz DEFAULT NULL,
  p_rental_deposit numeric DEFAULT 0, p_rental_late_fee_per_day numeric DEFAULT 0,
  p_handover_condition text DEFAULT NULL
)
RETURNS public.service_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.service_requests;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'buyer') THEN RAISE EXCEPTION 'Buyer role is required'; END IF;
  IF p_service_type NOT IN ('JOB','RENTAL') THEN RAISE EXCEPTION 'Invalid service type'; END IF;
  IF length(trim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120 OR length(trim(coalesce(p_description, ''))) NOT BETWEEN 10 AND 4000 OR length(trim(coalesce(p_location, ''))) NOT BETWEEN 3 AND 250 THEN RAISE EXCEPTION 'Request data is incomplete or too long'; END IF;
  IF p_budget IS NOT NULL AND p_budget < 0 THEN RAISE EXCEPTION 'Budget cannot be negative'; END IF;
  IF p_service_type = 'RENTAL' AND (p_rental_start_at IS NULL OR p_rental_end_at IS NULL OR p_rental_end_at <= p_rental_start_at) THEN RAISE EXCEPTION 'Rental dates are invalid'; END IF;
  IF p_rental_deposit < 0 OR p_rental_late_fee_per_day < 0 THEN RAISE EXCEPTION 'Rental charges cannot be negative'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_profiles WHERE id = p_profile_id AND provider_id = p_provider_id AND is_active = true AND verification_status = 'VERIFIED') THEN RAISE EXCEPTION 'Verified provider profile is required'; END IF;
  INSERT INTO public.service_requests(requester_id, provider_id, profile_id, subcategory_id, title, description, location, requester_budget, agreed_price, service_type, rental_start_at, rental_end_at, rental_deposit, rental_late_fee_per_day, handover_condition, status)
  VALUES (auth.uid(), p_provider_id, p_profile_id, p_subcategory_id, trim(p_title), trim(p_description), trim(p_location), p_budget, NULL, p_service_type, p_rental_start_at, p_rental_end_at, round(p_rental_deposit, 2), round(p_rental_late_fee_per_day, 2), nullif(trim(p_handover_condition), ''), 'NEGOTIATING')
  RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;
REVOKE ALL ON FUNCTION public.service_create_request_v2(uuid,uuid,uuid,text,text,text,numeric,text,timestamptz,timestamptz,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_create_request_v2(uuid,uuid,uuid,text,text,text,numeric,text,timestamptz,timestamptz,numeric,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.service_run_sla_sweep(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer := 0; r public.service_requests%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN RAISE EXCEPTION 'SLA sweep requires worker or admin access'; END IF;
  FOR r IN SELECT * FROM public.service_requests WHERE status = 'NEGOTIATING' AND negotiation_due_at IS NOT NULL AND negotiation_due_at < now() ORDER BY negotiation_due_at LIMIT greatest(1, least(p_limit, 1000)) FOR UPDATE LOOP
    UPDATE public.service_requests SET status = 'CANCELLED', cancellation_reason = 'Negotiation timeout', updated_at = now() WHERE id = r.id;
    INSERT INTO public.service_sla_events(request_id, event_type, previous_status, resulting_status, due_at) VALUES (r.id, 'NEGOTIATION_TIMEOUT', r.status, 'CANCELLED', r.negotiation_due_at);
    v_count := v_count + 1;
  END LOOP;
  FOR r IN SELECT * FROM public.service_requests WHERE status = 'WAITING_PAYMENT' AND payment_due_at IS NOT NULL AND payment_due_at < now() ORDER BY payment_due_at LIMIT greatest(1, least(p_limit, 1000)) FOR UPDATE LOOP
    UPDATE public.service_requests SET status = 'CANCELLED', cancellation_reason = 'Payment timeout', updated_at = now() WHERE id = r.id;
    INSERT INTO public.service_sla_events(request_id, event_type, previous_status, resulting_status, due_at) VALUES (r.id, 'PAYMENT_TIMEOUT', r.status, 'CANCELLED', r.payment_due_at);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.service_run_sla_sweep(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.service_run_sla_sweep(integer) TO service_role;

-- Prevent direct mutation of the financial audit trail.
CREATE OR REPLACE FUNCTION public.service_ledger_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Service transaction ledger is immutable'; END;
$$;
DROP TRIGGER IF EXISTS trg_service_ledger_immutable ON public.service_transaction_ledger;
CREATE TRIGGER trg_service_ledger_immutable BEFORE UPDATE OR DELETE ON public.service_transaction_ledger FOR EACH ROW EXECUTE FUNCTION public.service_ledger_immutable();
