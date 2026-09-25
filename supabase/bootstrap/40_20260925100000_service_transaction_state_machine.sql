-- ===== BEGIN SOURCE: 40_20260925100000_service_transaction_state_machine.sql =====
-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_6681a0153f80$
BEGIN
  EXECUTE $bootstrap_sql_6681a0153f80$-- Perkuat transaksi marketplace jasa dengan validasi actor, lock, dan pencatatan settlement manual.
-- Transfer bank/refund tetap dilakukan admin di luar aplikasi; RPC hanya mencatat referensinya.

ALTER TABLE public.service_requests
  ADD COLUMN IF NOT EXISTS requester_budget numeric(14,2)
  CHECK (requester_budget IS NULL OR requester_budget >= 0)$bootstrap_sql_6681a0153f80$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6681a0153f80$;

DO $bootstrap_do_f88e515d27c5$
BEGIN
  EXECUTE $bootstrap_sql_f88e515d27c5$ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'PENDING'
  CHECK (verification_status IN ('PENDING','VERIFIED','REJECTED'))$bootstrap_sql_f88e515d27c5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f88e515d27c5$;

DO $bootstrap_do_0b089066bed1$
BEGIN
  EXECUTE $bootstrap_sql_0b089066bed1$ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verification_note text$bootstrap_sql_0b089066bed1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b089066bed1$;

DO $bootstrap_do_2ab0c186167e$
BEGIN
  EXECUTE $bootstrap_sql_2ab0c186167e$ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES auth.users(id)$bootstrap_sql_2ab0c186167e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2ab0c186167e$;

DO $bootstrap_do_6046ebae6cdb$
BEGIN
  EXECUTE $bootstrap_sql_6046ebae6cdb$ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verified_at timestamptz$bootstrap_sql_6046ebae6cdb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6046ebae6cdb$;

DO $bootstrap_do_64daff8ec86f$
BEGIN
  EXECUTE $bootstrap_sql_64daff8ec86f$UPDATE public.service_profiles
SET verification_status = CASE WHEN is_verified THEN 'VERIFIED' ELSE 'PENDING' END
WHERE verification_status = 'PENDING' AND is_verified = true$bootstrap_sql_64daff8ec86f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_64daff8ec86f$;

DO $bootstrap_do_e6984c959a4e$
BEGIN
  EXECUTE $bootstrap_sql_e6984c959a4e$DROP POLICY IF EXISTS "service profiles are public" ON public.service_profiles$bootstrap_sql_e6984c959a4e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6984c959a4e$;

DO $bootstrap_do_9475a0f2268a$
BEGIN
  EXECUTE $bootstrap_sql_9475a0f2268a$CREATE POLICY "verified active service profiles are public" ON public.service_profiles
  FOR SELECT USING (
    (is_active AND verification_status = 'VERIFIED')
    OR provider_id = auth.uid()
    OR public.is_admin()
  )$bootstrap_sql_9475a0f2268a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9475a0f2268a$;

DO $bootstrap_do_4a3c6fcc8b54$
BEGIN
  EXECUTE $bootstrap_sql_4a3c6fcc8b54$ALTER TABLE public.service_payouts
  ADD COLUMN IF NOT EXISTS external_transfer_reference text$bootstrap_sql_4a3c6fcc8b54$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4a3c6fcc8b54$;

DO $bootstrap_do_a7a945c82dc2$
BEGIN
  EXECUTE $bootstrap_sql_a7a945c82dc2$ALTER TABLE public.service_disputes
  ADD COLUMN IF NOT EXISTS prior_request_status text$bootstrap_sql_a7a945c82dc2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7a945c82dc2$;

DO $bootstrap_do_7b764434506c$
BEGIN
  EXECUTE $bootstrap_sql_7b764434506c$ALTER TABLE public.service_disputes
  DROP CONSTRAINT IF EXISTS service_disputes_status_check$bootstrap_sql_7b764434506c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7b764434506c$;

DO $bootstrap_do_703278f9a573$
BEGIN
  EXECUTE $bootstrap_sql_703278f9a573$ALTER TABLE public.service_disputes
  ADD CONSTRAINT service_disputes_status_check
  CHECK (status IN ('OPEN','IN_REVIEW','WAITING_PARTIES','REFUND_APPROVED','REFUNDED','RELEASE_APPROVED','RESOLVED','CLOSED','REJECTED'))$bootstrap_sql_703278f9a573$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_703278f9a573$;

DO $bootstrap_do_f8ea00bed59f$
BEGIN
  EXECUTE $bootstrap_sql_f8ea00bed59f$CREATE TABLE IF NOT EXISTS public.service_refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES public.service_requests(id) ON DELETE RESTRICT,
  dispute_id uuid NOT NULL UNIQUE REFERENCES public.service_disputes(id) ON DELETE RESTRICT,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','COMPLETED')),
  external_reference text,
  recorded_by uuid REFERENCES auth.users(id),
  recorded_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((status = 'PENDING' AND external_reference IS NULL AND recorded_at IS NULL)
      OR (status = 'COMPLETED' AND length(trim(coalesce(external_reference, ''))) > 0 AND recorded_at IS NOT NULL))
)$bootstrap_sql_f8ea00bed59f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8ea00bed59f$;

DO $bootstrap_do_a7691f155ff7$
BEGIN
  EXECUTE $bootstrap_sql_a7691f155ff7$ALTER TABLE public.service_refunds ENABLE ROW LEVEL SECURITY$bootstrap_sql_a7691f155ff7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7691f155ff7$;

DO $bootstrap_do_6f758f8f1eee$
BEGIN
  EXECUTE $bootstrap_sql_6f758f8f1eee$DROP POLICY IF EXISTS "participants read service refunds" ON public.service_refunds$bootstrap_sql_6f758f8f1eee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f758f8f1eee$;

DO $bootstrap_do_f533a9067986$
BEGIN
  EXECUTE $bootstrap_sql_f533a9067986$CREATE POLICY "participants read service refunds" ON public.service_refunds
  FOR SELECT USING (
    public.is_admin() OR EXISTS (
      SELECT 1 FROM public.service_requests r
      WHERE r.id = request_id AND (r.requester_id = auth.uid() OR r.provider_id = auth.uid())
    )
  )$bootstrap_sql_f533a9067986$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f533a9067986$;

DO $bootstrap_do_7a5debbee64d$
BEGIN
  EXECUTE $bootstrap_sql_7a5debbee64d$REVOKE INSERT, UPDATE, DELETE ON public.service_refunds FROM authenticated$bootstrap_sql_7a5debbee64d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7a5debbee64d$;

DO $bootstrap_do_451a7f706b4f$
BEGIN
  EXECUTE $bootstrap_sql_451a7f706b4f$GRANT SELECT ON public.service_refunds TO authenticated$bootstrap_sql_451a7f706b4f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_451a7f706b4f$;

DO $bootstrap_do_a6ba09a925a0$
BEGIN
  EXECUTE $bootstrap_sql_a6ba09a925a0$CREATE OR REPLACE FUNCTION public.service_publish_profile(
  p_provider_name text,
  p_headline text,
  p_bio text,
  p_village text,
  p_min_price numeric,
  p_subcategory_ids uuid[]
)
RETURNS public.service_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.service_profiles;
  v_subcategory_count integer;
  v_unique_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'service_provider') THEN
    RAISE EXCEPTION 'Service provider role is required';
  END IF;
  IF length(trim(coalesce(p_provider_name, ''))) NOT BETWEEN 2 AND 100
     OR length(trim(coalesce(p_headline, ''))) NOT BETWEEN 3 AND 120
     OR length(coalesce(p_bio, '')) > 2000
     OR length(coalesce(p_village, '')) > 150
     OR p_min_price IS NULL OR p_min_price < 0 THEN
    RAISE EXCEPTION 'Profile data is invalid';
  END IF;
  IF coalesce(cardinality(p_subcategory_ids), 0) = 0 OR cardinality(p_subcategory_ids) > 30 THEN
    RAISE EXCEPTION 'Select between 1 and 30 service skills';
  END IF;
  SELECT count(DISTINCT selected.skill_id), count(*) INTO v_unique_count, v_subcategory_count
    FROM unnest(p_subcategory_ids) AS selected(skill_id);
  IF v_unique_count <> cardinality(p_subcategory_ids) THEN
    RAISE EXCEPTION 'Duplicate service skills are not allowed';
  END IF;
  SELECT count(*) INTO v_subcategory_count FROM public.service_subcategories
    WHERE id = ANY(p_subcategory_ids) AND is_active = true;
  IF v_subcategory_count <> cardinality(p_subcategory_ids) THEN
    RAISE EXCEPTION 'One or more selected service skills are unavailable';
  END IF;

  INSERT INTO public.service_profiles (
    provider_id, provider_name, headline, bio, village, min_price, is_active
  ) VALUES (
    auth.uid(), trim(p_provider_name), trim(p_headline), nullif(trim(p_bio), ''),
    nullif(trim(p_village), ''), p_min_price, true
  )
  ON CONFLICT (provider_id) DO UPDATE SET
    provider_name = EXCLUDED.provider_name,
    headline = EXCLUDED.headline,
    bio = EXCLUDED.bio,
    village = EXCLUDED.village,
    min_price = EXCLUDED.min_price,
    is_active = true,
    is_verified = false,
    verification_status = 'PENDING',
    verification_note = NULL,
    verified_by = NULL,
    verified_at = NULL,
    updated_at = now()
  RETURNING * INTO v_profile;

  DELETE FROM public.service_skills WHERE profile_id = v_profile.id;
  INSERT INTO public.service_skills (profile_id, subcategory_id)
    SELECT v_profile.id, selected.skill_id FROM unnest(p_subcategory_ids) AS selected(skill_id);
  RETURN v_profile;
END;
$$$bootstrap_sql_a6ba09a925a0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6ba09a925a0$;

DO $bootstrap_do_a88f9d95f1f4$
BEGIN
  EXECUTE $bootstrap_sql_a88f9d95f1f4$CREATE OR REPLACE FUNCTION public.service_admin_review_provider(
  p_profile_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS public.service_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.service_profiles;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  IF p_decision NOT IN ('VERIFIED','REJECTED')
     OR (p_decision = 'REJECTED' AND length(trim(coalesce(p_note, ''))) < 3)
     OR length(coalesce(p_note, '')) > 1000 THEN
    RAISE EXCEPTION 'Invalid provider verification decision';
  END IF;
  SELECT * INTO v_profile FROM public.service_profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service provider profile not found'; END IF;
  IF v_profile.verification_status <> 'PENDING' THEN
    RAISE EXCEPTION 'Provider profile is not awaiting review';
  END IF;
  UPDATE public.service_profiles SET
    verification_status = p_decision,
    is_verified = (p_decision = 'VERIFIED'),
    verification_note = nullif(trim(p_note), ''),
    verified_by = auth.uid(),
    verified_at = CASE WHEN p_decision = 'VERIFIED' THEN now() ELSE NULL END,
    updated_at = now()
  WHERE id = p_profile_id RETURNING * INTO v_profile;
  RETURN v_profile;
END;
$$$bootstrap_sql_a88f9d95f1f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a88f9d95f1f4$;

DO $bootstrap_do_8f411e019780$
BEGIN
  EXECUTE $bootstrap_sql_8f411e019780$CREATE OR REPLACE FUNCTION public.service_create_request(
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
  IF p_provider_id IS NULL OR p_profile_id IS NULL
     OR length(trim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120
     OR length(trim(coalesce(p_description, ''))) NOT BETWEEN 10 AND 4000
     OR length(trim(coalesce(p_location, ''))) NOT BETWEEN 3 AND 250 THEN
    RAISE EXCEPTION 'Request data is incomplete or too long';
  END IF;
  IF p_budget IS NOT NULL AND p_budget < 0 THEN
    RAISE EXCEPTION 'Budget cannot be negative';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_profiles
    WHERE id = p_profile_id AND provider_id = p_provider_id
      AND is_active = true AND verification_status = 'VERIFIED'
  ) THEN
    RAISE EXCEPTION 'Provider profile is not available';
  END IF;
  IF p_subcategory_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.service_skills s
    WHERE s.profile_id = p_profile_id AND s.subcategory_id = p_subcategory_id
  ) THEN
    RAISE EXCEPTION 'Service skill does not belong to this profile';
  END IF;

  INSERT INTO public.service_requests (
    requester_id, provider_id, profile_id, subcategory_id,
    title, description, location, agreed_price, requester_budget, status
  ) VALUES (
    auth.uid(), p_provider_id, p_profile_id, p_subcategory_id,
    trim(p_title), trim(p_description), trim(p_location), NULL, p_budget, 'NEGOTIATING'
  ) RETURNING * INTO v_request;
  RETURN v_request;
END;
$$$bootstrap_sql_8f411e019780$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8f411e019780$;

DO $bootstrap_do_8cfeea478862$
BEGIN
  EXECUTE $bootstrap_sql_8cfeea478862$CREATE OR REPLACE FUNCTION public.service_provider_propose_price(
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
    requester_approved = false,
    updated_at = now()
  WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$$bootstrap_sql_8cfeea478862$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8cfeea478862$;

DO $bootstrap_do_11ac02aa4f5e$
BEGIN
  EXECUTE $bootstrap_sql_11ac02aa4f5e$CREATE OR REPLACE FUNCTION public.service_requester_accept_price(p_request_id uuid)
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
  IF v_request.status = 'WAITING_PAYMENT' AND v_request.requester_approved THEN RETURN v_request; END IF;
  IF v_request.status <> 'NEGOTIATING' OR v_request.agreed_price IS NULL OR v_request.agreed_price <= 0
     OR NOT v_request.provider_approved THEN
    RAISE EXCEPTION 'A provider price proposal is required';
  END IF;
  UPDATE public.service_requests SET requester_approved = true, status = 'WAITING_PAYMENT', updated_at = now()
    WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$$bootstrap_sql_11ac02aa4f5e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_11ac02aa4f5e$;

DO $bootstrap_do_eb0fbe6f4310$
BEGIN
  EXECUTE $bootstrap_sql_eb0fbe6f4310$CREATE OR REPLACE FUNCTION public.service_submit_payment_proof(
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
  IF length(trim(coalesce(p_proof_url, ''))) = 0 OR length(p_proof_url) > 2048
     OR length(coalesce(p_transfer_reference, '')) > 200 THEN
    RAISE EXCEPTION 'Payment proof or transfer reference is invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'PENDING') THEN
    RAISE EXCEPTION 'A payment proof is already under review';
  END IF;

  INSERT INTO public.service_payment_proofs (
    request_id, uploaded_by, amount, transfer_reference, payment_reference, proof_url, status
  ) VALUES (
    p_request_id, auth.uid(), p_amount, nullif(trim(p_transfer_reference), ''),
    encode(gen_random_bytes(12), 'hex'), trim(p_proof_url), 'PENDING'
  ) RETURNING * INTO v_proof;
  RETURN v_proof;
END;
$$$bootstrap_sql_eb0fbe6f4310$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb0fbe6f4310$;

DO $bootstrap_do_9cfd2c4b4ed3$
BEGIN
  EXECUTE $bootstrap_sql_9cfd2c4b4ed3$CREATE OR REPLACE FUNCTION public.service_admin_review_payment(
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
  IF NOT FOUND OR v_request.status <> 'WAITING_PAYMENT'
     OR v_request.agreed_price IS NULL OR v_proof.amount <> v_request.agreed_price THEN
    RAISE EXCEPTION 'Payment amount does not match an awaiting request';
  END IF;
  IF NOT p_approved AND length(trim(coalesce(p_note, ''))) < 3 THEN
    RAISE EXCEPTION 'A reason is required when rejecting a payment proof';
  END IF;
  IF p_approved AND EXISTS (
    SELECT 1 FROM public.service_payment_proofs
    WHERE request_id = v_request.id AND status = 'VERIFIED' AND id <> v_proof.id
  ) THEN
    RAISE EXCEPTION 'A verified payment already exists for this request';
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
$$$bootstrap_sql_9cfd2c4b4ed3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cfd2c4b4ed3$;

DO $bootstrap_do_df43c3c3de0b$
BEGIN
  EXECUTE $bootstrap_sql_df43c3c3de0b$CREATE OR REPLACE FUNCTION public.service_mark_started(p_request_id uuid)
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
  IF v_request.status = 'IN_PROGRESS' THEN RETURN v_request; END IF;
  IF v_request.status <> 'APPROVED_TO_START' OR NOT EXISTS (
    SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED'
  ) THEN
    RAISE EXCEPTION 'Verified payment is required before work can start';
  END IF;
  UPDATE public.service_requests SET status = 'IN_PROGRESS', updated_at = now()
    WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$$bootstrap_sql_df43c3c3de0b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_df43c3c3de0b$;

DO $bootstrap_do_6c83e1e90058$
BEGIN
  EXECUTE $bootstrap_sql_6c83e1e90058$CREATE OR REPLACE FUNCTION public.service_mark_completed(p_request_id uuid)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
  v_actor uuid := auth.uid();
  v_gross numeric(14,2);
  v_platform numeric(14,2);
  v_transfer numeric(14,2);
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND (requester_id = v_actor OR provider_id = v_actor) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status = 'COMPLETED' THEN RETURN v_request; END IF;
  IF v_request.status NOT IN ('IN_PROGRESS','WAITING_CONFIRMATION') THEN
    RAISE EXCEPTION 'Request cannot be completed in its current state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED') THEN
    RAISE EXCEPTION 'Verified payment is required';
  END IF;

  UPDATE public.service_requests SET
    requester_completed = requester_completed OR requester_id = v_actor,
    provider_completed = provider_completed OR provider_id = v_actor,
    status = 'WAITING_CONFIRMATION',
    updated_at = now()
  WHERE id = v_request.id RETURNING * INTO v_request;

  IF v_request.requester_completed AND v_request.provider_completed THEN
    v_gross := v_request.agreed_price;
    v_platform := coalesce(v_request.platform_fee, round(v_gross * 0.05, 2));
    v_transfer := coalesce(v_request.transfer_fee, 0);
    INSERT INTO public.service_payouts (
      request_id, gross_amount, platform_fee, transfer_fee, net_amount, status
    ) VALUES (
      v_request.id, v_gross, v_platform, v_transfer,
      greatest(0, v_gross - v_platform - v_transfer), 'PENDING'
    ) ON CONFLICT (request_id) DO NOTHING;
  END IF;
  RETURN v_request;
END;
$$$bootstrap_sql_6c83e1e90058$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6c83e1e90058$;

DO $bootstrap_do_c6a72265a033$
BEGIN
  EXECUTE $bootstrap_sql_c6a72265a033$CREATE OR REPLACE FUNCTION public.service_open_dispute(
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
  v_amount numeric(14,2);
BEGIN
  SELECT * INTO v_request FROM public.service_requests
    WHERE id = p_request_id AND (requester_id = auth.uid() OR provider_id = auth.uid()) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status NOT IN ('APPROVED_TO_START','IN_PROGRESS','WAITING_CONFIRMATION') THEN
    RAISE EXCEPTION 'Request cannot be disputed in its current state';
  END IF;
  IF length(trim(coalesce(p_reason, ''))) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'Dispute reason must contain 10 to 2000 characters';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED') THEN
    RAISE EXCEPTION 'Verified payment is required before opening a dispute';
  END IF;
  IF EXISTS (SELECT 1 FROM public.service_disputes WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION 'A dispute already exists for this request';
  END IF;
  v_amount := coalesce(p_amount, v_request.agreed_price);
  IF v_amount IS NULL OR v_amount <= 0 OR v_amount > v_request.agreed_price THEN
    RAISE EXCEPTION 'Dispute amount must be positive and no greater than the agreed price';
  END IF;

  INSERT INTO public.service_disputes (
    request_id, opened_by, requester_id, provider_id, reason, amount, status, prior_request_status
  ) VALUES (
    p_request_id, auth.uid(), v_request.requester_id, v_request.provider_id,
    trim(p_reason), v_amount, 'OPEN', v_request.status
  ) RETURNING * INTO v_dispute;
  UPDATE public.service_requests SET status = 'DISPUTED', updated_at = now() WHERE id = p_request_id;
  RETURN v_dispute;
END;
$$$bootstrap_sql_c6a72265a033$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6a72265a033$;

DO $bootstrap_do_5f9b051b154a$
BEGIN
  EXECUTE $bootstrap_sql_5f9b051b154a$CREATE OR REPLACE FUNCTION public.service_admin_release_payout(
  p_request_id uuid,
  p_external_transfer_reference text,
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
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  IF length(trim(coalesce(p_external_transfer_reference, ''))) < 3
     OR length(p_external_transfer_reference) > 200 THEN
    RAISE EXCEPTION 'Actual bank transfer reference is required';
  END IF;
  SELECT * INTO v_request FROM public.service_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  SELECT * INTO v_payout FROM public.service_payouts WHERE request_id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'A queued payout is required'; END IF;
  IF v_payout.status = 'RELEASED' THEN RETURN v_payout; END IF;
  IF v_payout.status <> 'PENDING'
     OR v_request.status NOT IN ('WAITING_CONFIRMATION','COMPLETED')
     OR NOT (v_request.requester_completed AND v_request.provider_completed) THEN
    RAISE EXCEPTION 'Both parties must confirm completion before payout';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED') THEN
    RAISE EXCEPTION 'Verified payment is required';
  END IF;

  UPDATE public.service_payouts SET
    status = 'RELEASED',
    external_transfer_reference = trim(p_external_transfer_reference),
    released_by = auth.uid(),
    released_at = now(),
    note = nullif(trim(p_note), '')
  WHERE request_id = p_request_id RETURNING * INTO v_payout;
  UPDATE public.service_requests SET status = 'COMPLETED', updated_at = now() WHERE id = p_request_id;
  RETURN v_payout;
END;
$$$bootstrap_sql_5f9b051b154a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5f9b051b154a$;

DO $bootstrap_do_4cad7fd65202$
BEGIN
  EXECUTE $bootstrap_sql_4cad7fd65202$CREATE OR REPLACE FUNCTION public.service_admin_decide_dispute(
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
  v_amount numeric(14,2);
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  IF p_decision NOT IN ('IN_REVIEW','WAITING_PARTIES','REFUND_APPROVED','RELEASE_APPROVED','REJECTED')
     OR length(trim(coalesce(p_note, ''))) NOT BETWEEN 3 AND 2000 THEN
    RAISE EXCEPTION 'Invalid dispute decision';
  END IF;
  SELECT * INTO v_dispute FROM public.service_disputes WHERE id = p_dispute_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found'; END IF;
  IF v_dispute.status = p_decision THEN RETURN v_dispute; END IF;
  IF v_dispute.status NOT IN ('OPEN','IN_REVIEW','WAITING_PARTIES') THEN
    RAISE EXCEPTION 'Dispute is already resolved';
  END IF;
  SELECT * INTO v_request FROM public.service_requests WHERE id = v_dispute.request_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'DISPUTED' THEN RAISE EXCEPTION 'Request is not in dispute'; END IF;

  IF p_decision = 'REFUND_APPROVED' THEN
    SELECT amount INTO v_amount FROM public.service_payment_proofs
      WHERE request_id = v_request.id AND status = 'VERIFIED' ORDER BY verified_at DESC LIMIT 1;
    IF v_amount IS NULL THEN RAISE EXCEPTION 'Verified payment is required before approving a refund'; END IF;
    INSERT INTO public.service_refunds (request_id, dispute_id, amount, status, note)
      VALUES (v_request.id, v_dispute.id, v_amount, 'PENDING', trim(p_note))
      ON CONFLICT (request_id) DO NOTHING;
  ELSIF p_decision = 'RELEASE_APPROVED' THEN
    IF NOT (v_request.requester_completed AND v_request.provider_completed) THEN
      RAISE EXCEPTION 'Both parties must confirm completion before approving payout';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = v_request.id AND status = 'VERIFIED') THEN
      RAISE EXCEPTION 'Verified payment is required';
    END IF;
    INSERT INTO public.service_payouts (
      request_id, gross_amount, platform_fee, transfer_fee, net_amount, status
    ) VALUES (
      v_request.id, v_request.agreed_price, v_request.platform_fee, v_request.transfer_fee,
      greatest(0, v_request.agreed_price - v_request.platform_fee - v_request.transfer_fee), 'PENDING'
    ) ON CONFLICT (request_id) DO NOTHING;
    UPDATE public.service_requests SET status = 'WAITING_CONFIRMATION', updated_at = now() WHERE id = v_request.id;
  ELSIF p_decision = 'REJECTED' THEN
    UPDATE public.service_requests SET status = coalesce(v_dispute.prior_request_status, 'IN_PROGRESS'), updated_at = now()
      WHERE id = v_request.id;
  END IF;

  UPDATE public.service_disputes SET
    status = p_decision,
    admin_note = trim(p_note),
    resolution = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','REJECTED') THEN trim(p_note) ELSE resolution END,
    resolved_by = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','REJECTED') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_decision IN ('REFUND_APPROVED','RELEASE_APPROVED','REJECTED') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_dispute_id RETURNING * INTO v_dispute;
  RETURN v_dispute;
END;
$$$bootstrap_sql_4cad7fd65202$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4cad7fd65202$;

DO $bootstrap_do_0aaf760f0e24$
BEGIN
  EXECUTE $bootstrap_sql_0aaf760f0e24$CREATE OR REPLACE FUNCTION public.service_admin_record_refund(
  p_dispute_id uuid,
  p_external_reference text,
  p_note text DEFAULT NULL
)
RETURNS public.service_refunds
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dispute public.service_disputes;
  v_refund public.service_refunds;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  IF length(trim(coalesce(p_external_reference, ''))) < 3 OR length(p_external_reference) > 200 THEN
    RAISE EXCEPTION 'Actual refund transfer reference is required';
  END IF;
  SELECT * INTO v_dispute FROM public.service_disputes WHERE id = p_dispute_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispute not found'; END IF;
  SELECT * INTO v_refund FROM public.service_refunds WHERE dispute_id = p_dispute_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund must be approved before it is recorded'; END IF;
  IF v_refund.status = 'COMPLETED' THEN RETURN v_refund; END IF;
  IF v_dispute.status <> 'REFUND_APPROVED' THEN RAISE EXCEPTION 'Refund is not approved'; END IF;

  UPDATE public.service_refunds SET
    status = 'COMPLETED', external_reference = trim(p_external_reference),
    recorded_by = auth.uid(), recorded_at = now(),
    note = coalesce(nullif(trim(p_note), ''), note)
  WHERE dispute_id = p_dispute_id RETURNING * INTO v_refund;
  UPDATE public.service_disputes SET
    status = 'REFUNDED', admin_note = coalesce(nullif(trim(p_note), ''), admin_note),
    resolved_by = auth.uid(), resolved_at = now(), updated_at = now()
  WHERE id = p_dispute_id;
  UPDATE public.service_requests SET status = 'REFUNDED', updated_at = now() WHERE id = v_refund.request_id;
  RETURN v_refund;
END;
$$$bootstrap_sql_0aaf760f0e24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0aaf760f0e24$;

DO $bootstrap_do_be26127fba6f$
BEGIN
  EXECUTE $bootstrap_sql_be26127fba6f$-- Migrasikan completion lama yang memenuhi seluruh syarat ke antrean payout authoritative.
INSERT INTO public.service_payouts (
  request_id, gross_amount, platform_fee, transfer_fee, net_amount, status
)
SELECT r.id, r.agreed_price, r.platform_fee, r.transfer_fee,
       greatest(0, r.agreed_price - r.platform_fee - r.transfer_fee), 'PENDING'
FROM public.service_requests r
WHERE r.status IN ('WAITING_CONFIRMATION','COMPLETED')
  AND r.requester_completed AND r.provider_completed
  AND r.agreed_price IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.service_payment_proofs proof
    WHERE proof.request_id = r.id AND proof.status = 'VERIFIED'
  )
ON CONFLICT (request_id) DO NOTHING$bootstrap_sql_be26127fba6f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_be26127fba6f$;

DO $bootstrap_do_83c4c215f3d8$
BEGIN
  EXECUTE $bootstrap_sql_83c4c215f3d8$REVOKE INSERT, UPDATE, DELETE ON public.service_profiles FROM authenticated$bootstrap_sql_83c4c215f3d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83c4c215f3d8$;

DO $bootstrap_do_20309d35f393$
BEGIN
  EXECUTE $bootstrap_sql_20309d35f393$REVOKE INSERT, UPDATE, DELETE ON public.service_skills FROM authenticated$bootstrap_sql_20309d35f393$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20309d35f393$;

DO $bootstrap_do_0c3fe9ce75e5$
BEGIN
  EXECUTE $bootstrap_sql_0c3fe9ce75e5$REVOKE ALL ON FUNCTION public.service_publish_profile(text,text,text,text,numeric,uuid[]) FROM PUBLIC$bootstrap_sql_0c3fe9ce75e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c3fe9ce75e5$;

DO $bootstrap_do_a11f03bedf8f$
BEGIN
  EXECUTE $bootstrap_sql_a11f03bedf8f$REVOKE ALL ON FUNCTION public.service_admin_review_provider(uuid,text,text) FROM PUBLIC$bootstrap_sql_a11f03bedf8f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a11f03bedf8f$;

DO $bootstrap_do_2cc71e13ad47$
BEGIN
  EXECUTE $bootstrap_sql_2cc71e13ad47$REVOKE ALL ON FUNCTION public.service_create_request(uuid,uuid,uuid,text,text,text,numeric) FROM PUBLIC$bootstrap_sql_2cc71e13ad47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2cc71e13ad47$;

DO $bootstrap_do_9653e077dd41$
BEGIN
  EXECUTE $bootstrap_sql_9653e077dd41$REVOKE ALL ON FUNCTION public.service_submit_payment_proof(uuid,numeric,text,text) FROM PUBLIC$bootstrap_sql_9653e077dd41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9653e077dd41$;

DO $bootstrap_do_6e537dbc41d3$
BEGIN
  EXECUTE $bootstrap_sql_6e537dbc41d3$REVOKE ALL ON FUNCTION public.service_provider_propose_price(uuid,numeric) FROM PUBLIC$bootstrap_sql_6e537dbc41d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e537dbc41d3$;

DO $bootstrap_do_b6fd019d0706$
BEGIN
  EXECUTE $bootstrap_sql_b6fd019d0706$REVOKE ALL ON FUNCTION public.service_requester_accept_price(uuid) FROM PUBLIC$bootstrap_sql_b6fd019d0706$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6fd019d0706$;

DO $bootstrap_do_e7b4a86159e3$
BEGIN
  EXECUTE $bootstrap_sql_e7b4a86159e3$REVOKE ALL ON FUNCTION public.service_admin_review_payment(uuid,boolean,text) FROM PUBLIC$bootstrap_sql_e7b4a86159e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7b4a86159e3$;

DO $bootstrap_do_7109d7161f8f$
BEGIN
  EXECUTE $bootstrap_sql_7109d7161f8f$REVOKE ALL ON FUNCTION public.service_mark_started(uuid) FROM PUBLIC$bootstrap_sql_7109d7161f8f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7109d7161f8f$;

DO $bootstrap_do_f79f9ad6c34e$
BEGIN
  EXECUTE $bootstrap_sql_f79f9ad6c34e$REVOKE ALL ON FUNCTION public.service_mark_completed(uuid) FROM PUBLIC$bootstrap_sql_f79f9ad6c34e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f79f9ad6c34e$;

DO $bootstrap_do_95254a183ae0$
BEGIN
  EXECUTE $bootstrap_sql_95254a183ae0$REVOKE ALL ON FUNCTION public.service_open_dispute(uuid,text,numeric) FROM PUBLIC$bootstrap_sql_95254a183ae0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95254a183ae0$;

DO $bootstrap_do_a3b5843eb812$
BEGIN
  EXECUTE $bootstrap_sql_a3b5843eb812$REVOKE ALL ON FUNCTION public.service_admin_release_payout(uuid,text) FROM PUBLIC, anon, authenticated$bootstrap_sql_a3b5843eb812$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3b5843eb812$;

DO $bootstrap_do_0de69bafb8f0$
BEGIN
  EXECUTE $bootstrap_sql_0de69bafb8f0$REVOKE ALL ON FUNCTION public.service_admin_release_payout(uuid,text,text) FROM PUBLIC$bootstrap_sql_0de69bafb8f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0de69bafb8f0$;

DO $bootstrap_do_0d3852637299$
BEGIN
  EXECUTE $bootstrap_sql_0d3852637299$REVOKE ALL ON FUNCTION public.service_admin_decide_dispute(uuid,text,text) FROM PUBLIC$bootstrap_sql_0d3852637299$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d3852637299$;

DO $bootstrap_do_d85df895e959$
BEGIN
  EXECUTE $bootstrap_sql_d85df895e959$REVOKE ALL ON FUNCTION public.service_admin_record_refund(uuid,text,text) FROM PUBLIC$bootstrap_sql_d85df895e959$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d85df895e959$;

DO $bootstrap_do_8fdea180d2ae$
BEGIN
  EXECUTE $bootstrap_sql_8fdea180d2ae$GRANT EXECUTE ON FUNCTION public.service_publish_profile(text,text,text,text,numeric,uuid[]) TO authenticated$bootstrap_sql_8fdea180d2ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8fdea180d2ae$;

DO $bootstrap_do_ead99fb661a7$
BEGIN
  EXECUTE $bootstrap_sql_ead99fb661a7$GRANT EXECUTE ON FUNCTION public.service_admin_review_provider(uuid,text,text) TO authenticated$bootstrap_sql_ead99fb661a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ead99fb661a7$;

DO $bootstrap_do_251bcaedced0$
BEGIN
  EXECUTE $bootstrap_sql_251bcaedced0$GRANT EXECUTE ON FUNCTION public.service_create_request(uuid,uuid,uuid,text,text,text,numeric) TO authenticated$bootstrap_sql_251bcaedced0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_251bcaedced0$;

DO $bootstrap_do_a98b45326506$
BEGIN
  EXECUTE $bootstrap_sql_a98b45326506$GRANT EXECUTE ON FUNCTION public.service_submit_payment_proof(uuid,numeric,text,text) TO authenticated$bootstrap_sql_a98b45326506$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a98b45326506$;

DO $bootstrap_do_2941534fdc0e$
BEGIN
  EXECUTE $bootstrap_sql_2941534fdc0e$GRANT EXECUTE ON FUNCTION public.service_provider_propose_price(uuid,numeric) TO authenticated$bootstrap_sql_2941534fdc0e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2941534fdc0e$;

DO $bootstrap_do_020c2a36c63e$
BEGIN
  EXECUTE $bootstrap_sql_020c2a36c63e$GRANT EXECUTE ON FUNCTION public.service_requester_accept_price(uuid) TO authenticated$bootstrap_sql_020c2a36c63e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_020c2a36c63e$;

DO $bootstrap_do_52fc7f144715$
BEGIN
  EXECUTE $bootstrap_sql_52fc7f144715$GRANT EXECUTE ON FUNCTION public.service_admin_review_payment(uuid,boolean,text) TO authenticated$bootstrap_sql_52fc7f144715$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52fc7f144715$;

DO $bootstrap_do_e8a8b4ac57c6$
BEGIN
  EXECUTE $bootstrap_sql_e8a8b4ac57c6$GRANT EXECUTE ON FUNCTION public.service_mark_started(uuid) TO authenticated$bootstrap_sql_e8a8b4ac57c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e8a8b4ac57c6$;

DO $bootstrap_do_8fae0367f8d2$
BEGIN
  EXECUTE $bootstrap_sql_8fae0367f8d2$GRANT EXECUTE ON FUNCTION public.service_mark_completed(uuid) TO authenticated$bootstrap_sql_8fae0367f8d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8fae0367f8d2$;

DO $bootstrap_do_c3d1c223d4bc$
BEGIN
  EXECUTE $bootstrap_sql_c3d1c223d4bc$GRANT EXECUTE ON FUNCTION public.service_open_dispute(uuid,text,numeric) TO authenticated$bootstrap_sql_c3d1c223d4bc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c3d1c223d4bc$;

DO $bootstrap_do_28b05cce4730$
BEGIN
  EXECUTE $bootstrap_sql_28b05cce4730$GRANT EXECUTE ON FUNCTION public.service_admin_release_payout(uuid,text,text) TO authenticated$bootstrap_sql_28b05cce4730$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_28b05cce4730$;

DO $bootstrap_do_8255e7fa7787$
BEGIN
  EXECUTE $bootstrap_sql_8255e7fa7787$GRANT EXECUTE ON FUNCTION public.service_admin_decide_dispute(uuid,text,text) TO authenticated$bootstrap_sql_8255e7fa7787$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8255e7fa7787$;

DO $bootstrap_do_5a6d6ad0b0c1$
BEGIN
  EXECUTE $bootstrap_sql_5a6d6ad0b0c1$GRANT EXECUTE ON FUNCTION public.service_admin_record_refund(uuid,text,text) TO authenticated$bootstrap_sql_5a6d6ad0b0c1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a6d6ad0b0c1$;

DO $bootstrap_do_752c83053945$
BEGIN
  EXECUTE $bootstrap_sql_752c83053945$COMMENT ON FUNCTION public.service_admin_release_payout(uuid,text,text) IS
  'Records a completed manual bank transfer atomically; requires the external transfer reference.'$bootstrap_sql_752c83053945$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_752c83053945$;

DO $bootstrap_do_a2de596660ce$
BEGIN
  EXECUTE $bootstrap_sql_a2de596660ce$COMMENT ON FUNCTION public.service_admin_record_refund(uuid,text,text) IS
  'Records a completed manual refund transfer atomically; requires the external refund reference.'$bootstrap_sql_a2de596660ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2de596660ce$;

DO $bootstrap_do_1f0bc26c7eb9$
BEGIN
  EXECUTE $bootstrap_sql_1f0bc26c7eb9$COMMENT ON TABLE public.service_refunds IS
  'Refund approval and manual transfer reconciliation; COMPLETED means an admin recorded an external transfer reference.'$bootstrap_sql_1f0bc26c7eb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1f0bc26c7eb9$;
-- ===== END SOURCE: 40_20260925100000_service_transaction_state_machine.sql =====
