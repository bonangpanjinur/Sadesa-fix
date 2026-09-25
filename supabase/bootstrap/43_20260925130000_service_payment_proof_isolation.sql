-- Isolate private service payment evidence and make manual transfer references idempotent.
-- Service proofs remain in the shared private bucket but use a separate authorized namespace.

ALTER TABLE public.service_payment_proofs
  ADD COLUMN IF NOT EXISTS proof_path text,
  ADD COLUMN IF NOT EXISTS normalized_transfer_reference text;

-- Ensure columns used by this bundle's RPCs exist even when the preceding
-- state-machine and rental bundles have not yet been applied to this database.
ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'PENDING'
    CHECK (verification_status IN ('PENDING', 'VERIFIED', 'REJECTED')),
  ADD COLUMN IF NOT EXISTS verification_note text,
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verifikator_code text;

UPDATE public.service_profiles
SET verification_status = CASE WHEN is_verified THEN 'VERIFIED' ELSE 'PENDING' END
WHERE verification_status = 'PENDING' AND is_verified = true;

ALTER TABLE public.service_requests
  ADD COLUMN IF NOT EXISTS requester_budget numeric(14,2)
    CHECK (requester_budget IS NULL OR requester_budget >= 0),
  ADD COLUMN IF NOT EXISTS service_type text NOT NULL DEFAULT 'JOB',
  ADD COLUMN IF NOT EXISTS rental_start_at timestamptz,
  ADD COLUMN IF NOT EXISTS rental_end_at timestamptz,
  ADD COLUMN IF NOT EXISTS rental_deposit numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rental_late_fee_per_day numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS handover_condition text;

-- Preserve historical rows without allowing pre-existing duplicate references to
-- prevent deployment. Ambiguous active references remain visible in the legacy
-- column and are rejected by the RPC when reused.
WITH normalized AS (
  SELECT id,
         upper(regexp_replace(trim(transfer_reference), '\s+', '', 'g')) AS reference_key,
         status
  FROM public.service_payment_proofs
  WHERE nullif(trim(transfer_reference), '') IS NOT NULL
), unique_active AS (
  SELECT reference_key
  FROM normalized
  WHERE status IN ('PENDING', 'VERIFIED')
  GROUP BY reference_key
  HAVING count(*) = 1
)
UPDATE public.service_payment_proofs proof
SET normalized_transfer_reference = normalized.reference_key
FROM normalized
WHERE proof.id = normalized.id
  AND (normalized.status NOT IN ('PENDING', 'VERIFIED') OR normalized.reference_key IN (SELECT reference_key FROM unique_active));

CREATE UNIQUE INDEX IF NOT EXISTS idx_service_payment_proofs_active_transfer_reference
  ON public.service_payment_proofs(normalized_transfer_reference)
  WHERE normalized_transfer_reference IS NOT NULL AND status IN ('PENDING', 'VERIFIED');

-- Services use a dedicated key; never overwrite the commerce platform_fee schema.
INSERT INTO public.app_settings (key, value, category, description)
VALUES ('service_platform_fee', '{"percent":5}'::jsonb, 'payment', 'Fee platform khusus transaksi jasa')
ON CONFLICT (key) DO NOTHING;

UPDATE storage.buckets SET public = false WHERE id = 'payment-proofs';

CREATE OR REPLACE FUNCTION public.can_access_service_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid;
  v_uploader_id uuid;
BEGIN
  IF auth.uid() IS NULL OR split_part(p_object_name, '/', 1) <> 'services'
     OR split_part(p_object_name, '/', 4) = '' OR split_part(p_object_name, '/', 5) <> '' THEN
    RETURN false;
  END IF;
  BEGIN
    v_request_id := split_part(p_object_name, '/', 2)::uuid;
    v_uploader_id := split_part(p_object_name, '/', 3)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;
  RETURN EXISTS (
    SELECT 1
    FROM public.service_payment_proofs proof
    JOIN public.service_requests request ON request.id = proof.request_id
    WHERE proof.request_id = v_request_id
      AND proof.uploaded_by = v_uploader_id
      AND proof.proof_path = p_object_name
      AND (request.requester_id = auth.uid() OR request.provider_id = auth.uid() OR public.is_admin())
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_service_payment_proof(p_object_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid;
  v_uploader_id uuid;
BEGIN
  IF auth.uid() IS NULL OR split_part(p_object_name, '/', 1) <> 'services'
     OR split_part(p_object_name, '/', 4) = '' OR split_part(p_object_name, '/', 5) <> '' THEN
    RETURN false;
  END IF;
  BEGIN
    v_request_id := split_part(p_object_name, '/', 2)::uuid;
    v_uploader_id := split_part(p_object_name, '/', 3)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;
  IF v_uploader_id <> auth.uid() THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.service_requests request
    WHERE request.id = v_request_id
      AND request.requester_id = auth.uid()
      AND request.status = 'WAITING_PAYMENT'
      AND NOT EXISTS (
        SELECT 1 FROM public.service_payment_proofs proof WHERE proof.proof_path = p_object_name
      )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_service_payment_proof(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_service_payment_proof(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_service_payment_proof(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_service_payment_proof(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "Service participants can read own payment proof objects" ON storage.objects;
CREATE POLICY "Service participants can read own payment proof objects" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.can_access_service_payment_proof(name));

DROP POLICY IF EXISTS "Service requester can upload own payment proof object" ON storage.objects;
CREATE POLICY "Service requester can upload own payment proof object" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'payment-proofs' AND public.can_manage_service_payment_proof(name));

DROP POLICY IF EXISTS "Service requester can clean up unsubmitted payment proof object" ON storage.objects;
CREATE POLICY "Service requester can clean up unsubmitted payment proof object" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.can_manage_service_payment_proof(name));

COMMENT ON FUNCTION public.can_access_service_payment_proof(text)
  IS 'Restricts service payment proof reads to request participants and admins, using the exact recorded private object path.';
COMMENT ON FUNCTION public.can_manage_service_payment_proof(text)
  IS 'Allows a requester to upload or clean up an unsubmitted proof under services/<request-id>/<uploader-id>/<file>.';

-- Replace the URL-accepting endpoint with a private object-path-only contract.
DROP FUNCTION IF EXISTS public.service_submit_payment_proof(uuid, numeric, text, text);
CREATE FUNCTION public.service_submit_payment_proof(
  p_request_id uuid,
  p_amount numeric,
  p_transfer_reference text,
  p_proof_path text
)
RETURNS public.service_payment_proofs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.service_requests;
  v_proof public.service_payment_proofs;
  v_reference text;
  v_path_request_id uuid;
  v_path_uploader_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF split_part(coalesce(p_proof_path, ''), '/', 1) <> 'services'
     OR split_part(coalesce(p_proof_path, ''), '/', 4) = ''
     OR split_part(coalesce(p_proof_path, ''), '/', 5) <> '' THEN
    RAISE EXCEPTION 'Payment proof must be a service object path';
  END IF;
  BEGIN
    v_path_request_id := split_part(p_proof_path, '/', 2)::uuid;
    v_path_uploader_id := split_part(p_proof_path, '/', 3)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Payment proof path is invalid';
  END;
  IF v_path_request_id <> p_request_id OR v_path_uploader_id <> auth.uid() THEN
    RAISE EXCEPTION 'Payment proof path does not belong to this request and uploader';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects object
    WHERE object.bucket_id = 'payment-proofs' AND object.name = p_proof_path
  ) THEN
    RAISE EXCEPTION 'Uploaded payment proof object was not found';
  END IF;
  v_reference := upper(regexp_replace(trim(coalesce(p_transfer_reference, '')), '\s+', '', 'g'));
  IF v_reference = '' OR length(v_reference) > 200 THEN
    RAISE EXCEPTION 'A valid transfer reference is required';
  END IF;

  -- Serialize retries/re-use of the same bank reference, including concurrent RPCs.
  PERFORM pg_advisory_xact_lock(hashtext(v_reference));
  SELECT * INTO v_proof
  FROM public.service_payment_proofs
  WHERE request_id = p_request_id
    AND uploaded_by = auth.uid()
    AND status IN ('PENDING', 'VERIFIED')
    AND amount = p_amount
    AND upper(regexp_replace(trim(coalesce(transfer_reference, '')), '\s+', '', 'g')) = v_reference
  ORDER BY created_at DESC
  LIMIT 1;
  IF FOUND THEN RETURN v_proof; END IF;
  IF EXISTS (
    SELECT 1 FROM public.service_payment_proofs
    WHERE status IN ('PENDING', 'VERIFIED')
      AND upper(regexp_replace(trim(coalesce(transfer_reference, '')), '\s+', '', 'g')) = v_reference
  ) THEN
    RAISE EXCEPTION 'This transfer reference is already linked to another active service payment';
  END IF;

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
    request_id, uploaded_by, amount, transfer_reference, normalized_transfer_reference,
    payment_reference, proof_url, proof_path, status
  ) VALUES (
    p_request_id, auth.uid(), p_amount, trim(p_transfer_reference), v_reference,
    encode(gen_random_bytes(12), 'hex'), NULL, p_proof_path, 'PENDING'
  ) RETURNING * INTO v_proof;
  RETURN v_proof;
END;
$$;
REVOKE ALL ON FUNCTION public.service_submit_payment_proof(uuid, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_submit_payment_proof(uuid, numeric, text, text) TO authenticated;

-- A completed payout retry is idempotent only when it repeats the same transfer reference.
-- Keep this bundle independently runnable when an earlier state-machine bundle was skipped.
ALTER TABLE public.service_payouts
  ADD COLUMN IF NOT EXISTS external_transfer_reference text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_service_payouts_released_transfer_reference
  ON public.service_payouts (upper(regexp_replace(trim(external_transfer_reference), '\s+', '', 'g')))
  WHERE status = 'RELEASED' AND nullif(trim(external_transfer_reference), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.service_admin_release_payout(
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
  v_reference text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin role is required'; END IF;
  v_reference := upper(regexp_replace(trim(coalesce(p_external_transfer_reference, '')), '\s+', '', 'g'));
  IF length(v_reference) < 3 OR length(v_reference) > 200 THEN
    RAISE EXCEPTION 'Actual bank transfer reference is required';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_reference));
  SELECT * INTO v_request FROM public.service_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  SELECT * INTO v_payout FROM public.service_payouts WHERE request_id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'A queued payout is required'; END IF;
  IF v_payout.status = 'RELEASED' THEN
    IF upper(regexp_replace(trim(coalesce(v_payout.external_transfer_reference, '')), '\s+', '', 'g')) = v_reference THEN
      RETURN v_payout;
    END IF;
    RAISE EXCEPTION 'Payout was already released with a different transfer reference';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.service_payouts
    WHERE status = 'RELEASED'
      AND upper(regexp_replace(trim(coalesce(external_transfer_reference, '')), '\s+', '', 'g')) = v_reference
      AND request_id <> p_request_id
  ) THEN
    RAISE EXCEPTION 'This transfer reference is already linked to another payout';
  END IF;
  IF v_payout.status <> 'PENDING'
     OR v_request.status NOT IN ('WAITING_CONFIRMATION','COMPLETED')
     OR NOT (v_request.requester_completed AND v_request.provider_completed) THEN
    RAISE EXCEPTION 'Both parties must confirm completion before payout';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.service_payment_proofs WHERE request_id = p_request_id AND status = 'VERIFIED') THEN
    RAISE EXCEPTION 'Verified payment is required';
  END IF;
  UPDATE public.service_payouts SET
    status = 'RELEASED', external_transfer_reference = trim(p_external_transfer_reference),
    released_by = auth.uid(), released_at = now(), note = nullif(trim(p_note), '')
  WHERE request_id = p_request_id RETURNING * INTO v_payout;
  UPDATE public.service_requests SET status = 'COMPLETED', updated_at = now() WHERE id = p_request_id;
  RETURN v_payout;
END;
$$;
REVOKE ALL ON FUNCTION public.service_admin_release_payout(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_admin_release_payout(uuid, text, text) TO authenticated;

-- Rental deposit, return, late-fee and availability settlement are not implemented.
-- Block new rental requests at the trusted database boundary until that lifecycle exists.
CREATE OR REPLACE FUNCTION public.service_create_request_v2(
  p_provider_id uuid, p_profile_id uuid, p_subcategory_id uuid, p_title text, p_description text,
  p_location text, p_budget numeric DEFAULT NULL, p_service_type text DEFAULT 'JOB',
  p_rental_start_at timestamptz DEFAULT NULL, p_rental_end_at timestamptz DEFAULT NULL,
  p_rental_deposit numeric DEFAULT 0, p_rental_late_fee_per_day numeric DEFAULT 0,
  p_handover_condition text DEFAULT NULL
)
RETURNS public.service_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_request public.service_requests;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'buyer') THEN RAISE EXCEPTION 'Buyer role is required'; END IF;
  IF p_service_type <> 'JOB' THEN RAISE EXCEPTION 'Rental requests are temporarily unavailable until deposit settlement and return handling are supported'; END IF;
  IF length(trim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120
     OR length(trim(coalesce(p_description, ''))) NOT BETWEEN 10 AND 4000
     OR length(trim(coalesce(p_location, ''))) NOT BETWEEN 3 AND 250 THEN
    RAISE EXCEPTION 'Request data is incomplete or too long';
  END IF;
  IF p_budget IS NOT NULL AND p_budget < 0 THEN RAISE EXCEPTION 'Budget cannot be negative'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_profiles
    WHERE id = p_profile_id AND provider_id = p_provider_id AND is_active = true AND verification_status = 'VERIFIED'
  ) THEN RAISE EXCEPTION 'Verified provider profile is required'; END IF;
  INSERT INTO public.service_requests (
    requester_id, provider_id, profile_id, subcategory_id, title, description, location,
    requester_budget, agreed_price, service_type, rental_start_at, rental_end_at,
    rental_deposit, rental_late_fee_per_day, handover_condition, status
  ) VALUES (
    auth.uid(), p_provider_id, p_profile_id, p_subcategory_id, trim(p_title), trim(p_description), trim(p_location),
    p_budget, NULL, 'JOB', NULL, NULL, 0, 0, NULL, 'NEGOTIATING'
  ) RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;
REVOKE ALL ON FUNCTION public.service_create_request_v2(uuid, uuid, uuid, text, text, text, numeric, text, timestamptz, timestamptz, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_create_request_v2(uuid, uuid, uuid, text, text, text, numeric, text, timestamptz, timestamptz, numeric, numeric, text) TO authenticated;

-- Price proposals read only the service-specific configuration key.
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
  v_profile public.service_profiles;
  v_fee_percent numeric(7,4) := 5;
BEGIN
  SELECT * INTO v_request FROM public.service_requests
  WHERE id = p_request_id AND provider_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status <> 'NEGOTIATING' OR p_agreed_price IS NULL OR p_agreed_price <= 0 THEN
    RAISE EXCEPTION 'Request is not ready for a price proposal';
  END IF;
  SELECT * INTO v_profile FROM public.service_profiles
  WHERE id = v_request.profile_id AND provider_id = auth.uid() AND is_active = true FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Provider profile is not available'; END IF;
  IF p_agreed_price < coalesce(v_profile.min_price, 0) THEN
    RAISE EXCEPTION 'Price cannot be below provider minimum tariff of %', v_profile.min_price;
  END IF;
  SELECT CASE
    WHEN (value->>'percent') ~ '^[0-9]+([.][0-9]+)?$' THEN (value->>'percent')::numeric
    ELSE 5
  END
  INTO v_fee_percent FROM public.app_settings WHERE key = 'service_platform_fee';
  v_fee_percent := greatest(0, least(100, coalesce(v_fee_percent, 5)));
  UPDATE public.service_requests SET
    agreed_price = round(p_agreed_price, 2),
    platform_fee = round(p_agreed_price * v_fee_percent / 100, 2),
    transfer_fee = 0,
    provider_payout = round(p_agreed_price - (p_agreed_price * v_fee_percent / 100), 2),
    provider_approved = true,
    requester_approved = false,
    updated_at = now()
  WHERE id = p_request_id RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;
REVOKE ALL ON FUNCTION public.service_provider_propose_price(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_provider_propose_price(uuid, numeric) TO authenticated;

-- Provider registration follows the merchant/courier account flow: submit an application,
-- optionally attribute it to an active verifikator code, then wait for authorized review.
ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS verifikator_code text;

-- Keep public visibility restricted while granting read access to the referral verifier's queue.
DROP POLICY IF EXISTS "verified active service profiles are public" ON public.service_profiles;
CREATE POLICY "verified active service profiles are public" ON public.service_profiles
  FOR SELECT USING (
    (is_active AND verification_status = 'VERIFIED')
    OR provider_id = auth.uid()
    OR public.is_admin()
    OR (
      verification_status = 'PENDING'
      AND verifikator_code IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.verifikator_codes code
        WHERE code.code = service_profiles.verifikator_code
          AND code.verifikator_id = auth.uid()
          AND code.is_active = true
          AND public.is_verifikator()
      )
    )
  );

-- Replace instant role activation/profile publishing with application submission.
DO $$
BEGIN
  IF to_regprocedure('public.activate_service_provider()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.activate_service_provider() FROM PUBLIC, authenticated';
  END IF;
END;
$$;
DROP FUNCTION IF EXISTS public.service_publish_profile(text, text, text, text, numeric, uuid[]);
CREATE OR REPLACE FUNCTION public.service_publish_profile(
  p_provider_name text,
  p_headline text,
  p_bio text,
  p_village text,
  p_min_price numeric,
  p_subcategory_ids uuid[],
  p_verifikator_code text DEFAULT NULL,
  p_phone text DEFAULT NULL
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
  v_code text := nullif(upper(trim(coalesce(p_verifikator_code, ''))), '');
  v_verifikator_id uuid;
  v_usage integer;
  v_max_usage integer;
  v_existing_code text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 39021));
  SELECT verifikator_code INTO v_existing_code
  FROM public.service_profiles WHERE provider_id = auth.uid() FOR UPDATE;
  IF length(trim(coalesce(p_provider_name, ''))) NOT BETWEEN 2 AND 100
     OR length(trim(coalesce(p_headline, ''))) NOT BETWEEN 3 AND 120
     OR length(coalesce(p_bio, '')) > 2000
     OR length(coalesce(p_village, '')) > 150
     OR length(coalesce(p_phone, '')) NOT BETWEEN 8 AND 30
     OR p_min_price IS NULL OR p_min_price < 0 THEN
    RAISE EXCEPTION 'Provider application data is invalid';
  END IF;
  IF coalesce(cardinality(p_subcategory_ids), 0) = 0 OR cardinality(p_subcategory_ids) > 30 THEN
    RAISE EXCEPTION 'Select between 1 and 30 service skills';
  END IF;
  SELECT count(DISTINCT selected.skill_id), count(*)
    INTO v_unique_count, v_subcategory_count
  FROM unnest(p_subcategory_ids) AS selected(skill_id);
  IF v_unique_count <> cardinality(p_subcategory_ids) THEN
    RAISE EXCEPTION 'Duplicate service skills are not allowed';
  END IF;
  SELECT count(*) INTO v_subcategory_count FROM public.service_subcategories
  WHERE id = ANY(p_subcategory_ids) AND is_active = true;
  IF v_subcategory_count <> cardinality(p_subcategory_ids) THEN
    RAISE EXCEPTION 'One or more selected service skills are unavailable';
  END IF;

  IF v_code IS NOT NULL THEN
    SELECT verifikator_id, usage_count, max_usage
    INTO v_verifikator_id, v_usage, v_max_usage
    FROM public.verifikator_codes
    WHERE code = v_code AND is_active = true
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Referral code is invalid or inactive'; END IF;
    IF v_verifikator_id = auth.uid() THEN RAISE EXCEPTION 'You cannot use your own referral code'; END IF;
    IF v_code IS DISTINCT FROM v_existing_code AND v_max_usage IS NOT NULL AND coalesce(v_usage, 0) >= v_max_usage THEN
      RAISE EXCEPTION 'Referral code has reached its usage limit';
    END IF;
    IF v_code IS DISTINCT FROM v_existing_code THEN
      UPDATE public.verifikator_codes SET usage_count = coalesce(usage_count, 0) + 1 WHERE code = v_code;
    END IF;
  END IF;

  INSERT INTO public.service_profiles (
    provider_id, provider_name, headline, bio, village, phone, min_price, is_active,
    is_verified, verification_status, verification_note, verified_by, verified_at,
    verifikator_code, updated_at
  ) VALUES (
    auth.uid(), trim(p_provider_name), trim(p_headline), nullif(trim(p_bio), ''),
    nullif(trim(p_village), ''), trim(p_phone), p_min_price, true,
    false, 'PENDING', NULL, NULL, NULL, v_code, now()
  )
  ON CONFLICT (provider_id) DO UPDATE SET
    provider_name = EXCLUDED.provider_name,
    headline = EXCLUDED.headline,
    bio = EXCLUDED.bio,
    village = EXCLUDED.village,
    phone = EXCLUDED.phone,
    min_price = EXCLUDED.min_price,
    is_active = true,
    is_verified = false,
    verification_status = 'PENDING',
    verification_note = NULL,
    verified_by = NULL,
    verified_at = NULL,
    verifikator_code = EXCLUDED.verifikator_code,
    updated_at = now()
  RETURNING * INTO v_profile;

  DELETE FROM public.service_skills WHERE profile_id = v_profile.id;
  INSERT INTO public.service_skills (profile_id, subcategory_id)
    SELECT v_profile.id, selected.skill_id FROM unnest(p_subcategory_ids) AS selected(skill_id);
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.service_publish_profile(text, text, text, text, numeric, uuid[], text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_publish_profile(text, text, text, text, numeric, uuid[], text, text) TO authenticated;

-- A profile may only be approved by an admin or by the active verifikator whose code
-- was attached to the application. Both decisions remain audited on the profile row.
CREATE OR REPLACE FUNCTION public.service_admin_review_provider(
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
  v_is_admin boolean := public.is_admin();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_decision NOT IN ('VERIFIED', 'REJECTED')
     OR (p_decision = 'REJECTED' AND length(trim(coalesce(p_note, ''))) < 3)
     OR length(coalesce(p_note, '')) > 1000 THEN
    RAISE EXCEPTION 'Invalid provider verification decision';
  END IF;
  SELECT * INTO v_profile FROM public.service_profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND OR v_profile.verification_status <> 'PENDING' THEN
    RAISE EXCEPTION 'Provider profile is not awaiting review';
  END IF;
  IF NOT v_is_admin AND NOT (
    public.is_verifikator()
    AND v_profile.verifikator_code IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.verifikator_codes code
      WHERE code.code = v_profile.verifikator_code
        AND code.verifikator_id = auth.uid()
        AND code.is_active = true
    )
  ) THEN
    RAISE EXCEPTION 'Only the assigned referral verifier or an admin may review this provider';
  END IF;

  UPDATE public.service_profiles SET
    verification_status = p_decision,
    is_verified = (p_decision = 'VERIFIED'),
    verification_note = nullif(trim(p_note), ''),
    verified_by = auth.uid(),
    verified_at = CASE WHEN p_decision = 'VERIFIED' THEN now() ELSE NULL END,
    updated_at = now()
  WHERE id = p_profile_id RETURNING * INTO v_profile;

  IF p_decision = 'VERIFIED' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (v_profile.provider_id, 'service_provider')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.service_admin_review_provider(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_admin_review_provider(uuid, text, text) TO authenticated;
