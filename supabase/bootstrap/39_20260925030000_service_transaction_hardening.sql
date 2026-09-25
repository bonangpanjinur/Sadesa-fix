-- Hardening transaksi marketplace jasa.
-- Semua mutation sensitif dipindahkan ke RPC atomic dengan row lock.

ALTER TABLE public.service_payment_proofs
  ADD COLUMN IF NOT EXISTS payment_reference text;

CREATE INDEX IF NOT EXISTS idx_service_payment_proofs_request_status
  ON public.service_payment_proofs(request_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION public.service_create_request(
  p_provider_id uuid,
  p_profile_id uuid,
  p_subcategory_id uuid,
  p_title text,
  p_description text,
  p_location text,
  p_budget numeric DEFAULT NULL
)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'buyer') THEN
    RAISE EXCEPTION 'Buyer role is required';
  END IF;
  IF p_provider_id IS NULL OR p_profile_id IS NULL OR length(trim(coalesce(p_title, ''))) < 3
     OR length(trim(coalesce(p_description, ''))) < 10 OR length(trim(coalesce(p_location, ''))) < 3 THEN
    RAISE EXCEPTION 'Request data is incomplete';
  END IF;
  IF p_budget IS NOT NULL AND p_budget < 0 THEN
    RAISE EXCEPTION 'Budget cannot be negative';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_profiles
    WHERE id = p_profile_id AND provider_id = p_provider_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Provider profile is not available';
  END IF;

  INSERT INTO public.service_requests (
    requester_id, provider_id, profile_id, subcategory_id,
    title, description, location, agreed_price, status
  ) VALUES (
    auth.uid(), p_provider_id, p_profile_id, p_subcategory_id,
    trim(p_title), trim(p_description), trim(p_location), p_budget, 'NEGOTIATING'
  ) RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_submit_payment_proof(
  p_request_id uuid,
  p_amount numeric,
  p_transfer_reference text,
  p_proof_url text
)
RETURNS public.service_payment_proofs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
  v_proof public.service_payment_proofs;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND requester_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status <> 'WAITING_PAYMENT' OR v_request.agreed_price IS NULL THEN
    RAISE EXCEPTION 'Request is not ready for payment';
  END IF;
  IF p_amount IS NULL OR p_amount <> v_request.agreed_price THEN
    RAISE EXCEPTION 'Payment amount must match agreed price';
  END IF;
  IF EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'PENDING') THEN
    RAISE EXCEPTION 'A payment proof is already under review';
  END IF;

  INSERT INTO public.service_payment_proofs (
    request_id, uploaded_by, amount, transfer_reference, payment_reference, proof_url, status
  ) VALUES (
    p_request_id, auth.uid(), p_amount, nullif(trim(p_transfer_reference), ''),
    encode(gen_random_bytes(12), 'hex'), nullif(trim(p_proof_url), ''), 'PENDING'
  ) RETURNING * INTO v_proof;
  RETURN v_proof;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_provider_propose_price(
  p_request_id uuid,
  p_agreed_price numeric
)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND provider_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status <> 'NEGOTIATING' OR p_agreed_price IS NULL OR p_agreed_price <= 0 THEN
    RAISE EXCEPTION 'Request is not ready for a price proposal';
  END IF;
  UPDATE public.service_requests SET
    agreed_price = round(p_agreed_price, 2),
    platform_fee = round(p_agreed_price * 0.05, 2),
    transfer_fee = 0,
    provider_payout = round(p_agreed_price * 0.95, 2),
    provider_approved = true,
    updated_at = now()
  WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_requester_accept_price(p_request_id uuid)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND requester_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status <> 'NEGOTIATING' OR v_request.agreed_price IS NULL OR v_request.agreed_price <= 0 THEN
    RAISE EXCEPTION 'A provider price proposal is required';
  END IF;
  UPDATE public.service_requests SET requester_approved = true, status = 'WAITING_PAYMENT', updated_at = now()
    WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_admin_review_payment(
  p_proof_id uuid,
  p_approved boolean,
  p_note text DEFAULT NULL
)
RETURNS public.service_payment_proofs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proof public.service_payment_proofs;
  v_request public.service_requests;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  SELECT * INTO v_proof FROM public.service_payment_proofs WHERE id = p_proof_id FOR UPDATE;
  IF NOT FOUND OR v_proof.status <> 'PENDING' THEN RAISE EXCEPTION 'Payment proof is not pending'; END IF;
  SELECT * INTO v_request FROM public.service_requests WHERE id = v_proof.request_id FOR UPDATE;
  IF NOT FOUND OR v_request.agreed_price IS NULL OR v_proof.amount <> v_request.agreed_price THEN
    RAISE EXCEPTION 'Payment amount does not match request';
  END IF;

  UPDATE public.service_payment_proofs SET
    status = CASE WHEN p_approved THEN 'VERIFIED' ELSE 'REJECTED' END,
    admin_note = nullif(trim(p_note), ''),
    verified_at = CASE WHEN p_approved THEN now() ELSE NULL END
  WHERE id = p_proof_id RETURNING * INTO v_proof;

  UPDATE public.service_requests SET status = CASE WHEN p_approved THEN 'APPROVED_TO_START' ELSE 'WAITING_PAYMENT' END,
    updated_at = now() WHERE id = v_request.id;
  RETURN v_proof;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_mark_completed(p_request_id uuid)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND (requester_id = auth.uid() OR provider_id = auth.uid()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status NOT IN ('APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION') THEN
    RAISE EXCEPTION 'Request cannot be completed in its current state';
  END IF;

  UPDATE public.service_requests SET
    requester_completed = requester_completed OR requester_id = auth.uid(),
    provider_completed = provider_completed OR provider_id = auth.uid(),
    status = CASE WHEN (requester_completed OR requester_id = auth.uid())
                       AND (provider_completed OR provider_id = auth.uid())
                  THEN 'WAITING_CONFIRMATION' ELSE 'IN_PROGRESS' END,
    updated_at = now()
  WHERE id = v_request.id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_open_dispute(
  p_request_id uuid,
  p_reason text,
  p_amount numeric DEFAULT NULL
)
RETURNS public.service_disputes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
  v_dispute public.service_disputes;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND (requester_id = auth.uid() OR provider_id = auth.uid()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status IN ('CANCELLED','REFUNDED','COMPLETED') THEN RAISE EXCEPTION 'Request cannot be disputed'; END IF;
  IF length(trim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'Dispute reason is too short'; END IF;
  IF EXISTS (SELECT 1 FROM public.service_disputes WHERE request_id = p_request_id AND status NOT IN ('CLOSED','REJECTED')) THEN
    RAISE EXCEPTION 'An active dispute already exists';
  END IF;

  INSERT INTO public.service_disputes (request_id, opened_by, requester_id, provider_id, reason, amount, status)
  VALUES (p_request_id, auth.uid(), v_request.requester_id, v_request.provider_id,
          trim(p_reason), coalesce(p_amount, v_request.agreed_price), 'OPEN')
  RETURNING * INTO v_dispute;
  UPDATE public.service_requests SET status = 'DISPUTED', updated_at = now() WHERE id = p_request_id;
  RETURN v_dispute;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_admin_release_payout(
  p_request_id uuid,
  p_note text DEFAULT NULL
)
RETURNS public.service_payouts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
  v_payout public.service_payouts;
  v_gross numeric(14,2);
  v_platform numeric(14,2);
  v_transfer numeric(14,2);
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  SELECT * INTO v_request FROM public.service_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status NOT IN ('WAITING_CONFIRMATION','COMPLETED') OR NOT (v_request.requester_completed AND v_request.provider_completed) THEN
    RAISE EXCEPTION 'Both parties must confirm completion';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED') THEN
    RAISE EXCEPTION 'Verified payment is required';
  END IF;
  SELECT * INTO v_payout FROM public.service_payouts WHERE request_id = p_request_id FOR UPDATE;
  IF FOUND AND v_payout.status = 'RELEASED' THEN RETURN v_payout; END IF;

  v_gross := coalesce(v_request.agreed_price, 0);
  v_platform := round(v_gross * 0.05, 2);
  v_transfer := coalesce(v_request.transfer_fee, 0);
  INSERT INTO public.service_payouts (
    request_id, gross_amount, platform_fee, transfer_fee, net_amount,
    status, released_by, released_at, note
  ) VALUES (
    p_request_id, v_gross, v_platform, v_transfer,
    greatest(0, v_gross - v_platform - v_transfer), 'RELEASED', auth.uid(), now(), nullif(trim(p_note), '')
  )
  ON CONFLICT (request_id) DO UPDATE SET
    gross_amount = EXCLUDED.gross_amount,
    platform_fee = EXCLUDED.platform_fee,
    transfer_fee = EXCLUDED.transfer_fee,
    net_amount = EXCLUDED.net_amount,
    status = 'RELEASED',
    released_by = auth.uid(),
    released_at = now(),
    note = EXCLUDED.note
  RETURNING * INTO v_payout;

  UPDATE public.service_requests SET status = 'COMPLETED', updated_at = now() WHERE id = p_request_id;
  RETURN v_payout;
END;
$$;

CREATE OR REPLACE FUNCTION public.service_admin_decide_dispute(
  p_dispute_id uuid,
  p_decision text,
  p_note text
)
RETURNS public.service_disputes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dispute public.service_disputes;
  v_request public.service_requests;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  IF p_decision NOT IN ('IN_REVIEW','WAITING_PARTIES','REFUND_APPROVED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED')
     OR length(trim(coalesce(p_note, ''))) < 3 THEN
    RAISE EXCEPTION 'Invalid dispute decision';
  END IF;
  SELECT * INTO v_dispute FROM public.service_disputes WHERE id = p_dispute_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found'; END IF;
  SELECT * INTO v_request FROM public.service_requests WHERE id = v_dispute.request_id FOR UPDATE;

  UPDATE public.service_disputes SET
    status = p_decision, admin_note = trim(p_note),
    resolution = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED') THEN trim(p_note) ELSE resolution END,
    resolved_by = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_dispute_id RETURNING * INTO v_dispute;

  IF p_decision = 'REFUND_APPROVED' THEN
    UPDATE public.service_requests SET status = 'REFUNDED', updated_at = now() WHERE id = v_request.id;
  ELSIF p_decision = 'RELEASE_APPROVED' THEN
    UPDATE public.service_requests SET status = 'WAITING_CONFIRMATION', updated_at = now() WHERE id = v_request.id;
  ELSIF p_decision IN ('RESOLVED','CLOSED') THEN
    UPDATE public.service_requests SET status = 'COMPLETED', updated_at = now() WHERE id = v_request.id;
  END IF;
  RETURN v_dispute;
END;
$$;

-- Direct browser mutations are revoked. Reads remain available through RLS.
REVOKE INSERT, UPDATE, DELETE ON public.service_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.service_payment_proofs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.service_payouts FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.service_disputes FROM authenticated;

GRANT EXECUTE ON FUNCTION public.service_create_request(uuid,uuid,uuid,text,text,text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_submit_payment_proof(uuid,numeric,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_provider_propose_price(uuid,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_requester_accept_price(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_admin_review_payment(uuid,boolean,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_mark_completed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_open_dispute(uuid,text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_admin_release_payout(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.service_admin_decide_dispute(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.service_admin_release_payout(uuid,text) IS 'Atomic service payout release. Actual bank/gateway transfer must be reconciled with the returned payout reference.';
COMMENT ON FUNCTION public.service_admin_decide_dispute(uuid,text,text) IS 'Atomic dispute decision and service request status transition; external refund remains a settlement integration responsibility.';
