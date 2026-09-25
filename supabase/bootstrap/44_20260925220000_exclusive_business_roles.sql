-- One account may operate as exactly one business role:
-- merchant, courier/ojek, or service_provider. The buyer role remains available
-- for every account and is not considered an exclusive business role.

CREATE OR REPLACE FUNCTION public.assert_exclusive_business_role(
  p_user_id uuid,
  p_requested_role public.app_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conflict text;
BEGIN
  IF p_user_id IS NULL OR p_requested_role NOT IN ('merchant', 'courier', 'service_provider') THEN
    RAISE EXCEPTION 'Invalid exclusive business role request';
  END IF;

  IF public.is_admin() OR EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RETURN;
  END IF;

  IF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'You may only register the account currently signed in';
  END IF;

  IF p_requested_role <> 'merchant' AND EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = p_user_id AND role = 'merchant'
  ) OR p_requested_role <> 'merchant' AND EXISTS (
    SELECT 1 FROM public.merchants WHERE user_id = p_user_id AND COALESCE(registration_status, '') <> 'REJECTED'
  ) THEN
    v_conflict := 'merchant';
  ELSIF p_requested_role <> 'courier' AND EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = p_user_id AND role = 'courier'
  ) OR p_requested_role <> 'courier' AND EXISTS (
    SELECT 1 FROM public.couriers WHERE user_id = p_user_id AND COALESCE(registration_status, '') <> 'REJECTED'
  ) THEN
    v_conflict := 'courier';
  ELSIF p_requested_role <> 'service_provider' AND EXISTS (
    SELECT 1 FROM public.user_roles WHERE user_id = p_user_id AND role = 'service_provider'
  ) OR p_requested_role <> 'service_provider' AND EXISTS (
    SELECT 1 FROM public.service_profiles WHERE provider_id = p_user_id
  ) THEN
    v_conflict := 'service_provider';
  END IF;

  IF v_conflict IS NOT NULL THEN
    RAISE EXCEPTION 'Account is already registered as %, one account can only have one business role', v_conflict;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_exclusive_business_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assert_exclusive_business_role(uuid, public.app_role) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_exclusive_merchant_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND COALESCE(NEW.registration_status, '') <> 'REJECTED' THEN
    PERFORM public.assert_exclusive_business_role(NEW.user_id, 'merchant');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_exclusive_merchant_role ON public.merchants;
CREATE TRIGGER trg_exclusive_merchant_role
  BEFORE INSERT OR UPDATE OF user_id, registration_status ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.enforce_exclusive_merchant_role();

CREATE OR REPLACE FUNCTION public.enforce_exclusive_courier_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.user_id IS NOT NULL AND COALESCE(NEW.registration_status, '') <> 'REJECTED' THEN
    PERFORM public.assert_exclusive_business_role(NEW.user_id, 'courier');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_exclusive_courier_role ON public.couriers;
CREATE TRIGGER trg_exclusive_courier_role
  BEFORE INSERT OR UPDATE OF user_id, registration_status ON public.couriers
  FOR EACH ROW EXECUTE FUNCTION public.enforce_exclusive_courier_role();

-- Service registration is also blocked when the account already has another
-- business profile. The existing RPC remains the only write entry point.
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
  PERFORM public.assert_exclusive_business_role(auth.uid(), 'service_provider');
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 39021));
  SELECT verifikator_code INTO v_existing_code FROM public.service_profiles WHERE provider_id = auth.uid() FOR UPDATE;
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
  SELECT count(DISTINCT selected.skill_id), count(*) INTO v_unique_count, v_subcategory_count
    FROM unnest(p_subcategory_ids) AS selected(skill_id);
  IF v_unique_count <> cardinality(p_subcategory_ids) THEN RAISE EXCEPTION 'Duplicate service skills are not allowed'; END IF;
  SELECT count(*) INTO v_subcategory_count FROM public.service_subcategories WHERE id = ANY(p_subcategory_ids) AND is_active = true;
  IF v_subcategory_count <> cardinality(p_subcategory_ids) THEN RAISE EXCEPTION 'One or more selected service skills are unavailable'; END IF;
  IF v_code IS NOT NULL THEN
    SELECT verifikator_id, usage_count, max_usage INTO v_verifikator_id, v_usage, v_max_usage
      FROM public.verifikator_codes WHERE code = v_code AND is_active = true FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Referral code is invalid or inactive'; END IF;
    IF v_verifikator_id = auth.uid() THEN RAISE EXCEPTION 'You cannot use your own referral code'; END IF;
    IF v_code IS DISTINCT FROM v_existing_code AND v_max_usage IS NOT NULL AND coalesce(v_usage, 0) >= v_max_usage THEN RAISE EXCEPTION 'Referral code has reached its usage limit'; END IF;
    IF v_code IS DISTINCT FROM v_existing_code THEN UPDATE public.verifikator_codes SET usage_count = coalesce(usage_count, 0) + 1 WHERE code = v_code; END IF;
  END IF;
  INSERT INTO public.service_profiles (provider_id, provider_name, headline, bio, village, phone, min_price, is_active, is_verified, verification_status, verification_note, verified_by, verified_at, verifikator_code, updated_at)
  VALUES (auth.uid(), trim(p_provider_name), trim(p_headline), nullif(trim(p_bio), ''), nullif(trim(p_village), ''), trim(p_phone), p_min_price, true, false, 'PENDING', NULL, NULL, NULL, v_code, now())
  ON CONFLICT (provider_id) DO UPDATE SET provider_name = EXCLUDED.provider_name, headline = EXCLUDED.headline, bio = EXCLUDED.bio, village = EXCLUDED.village, phone = EXCLUDED.phone, min_price = EXCLUDED.min_price, is_active = true, is_verified = false, verification_status = 'PENDING', verification_note = NULL, verified_by = NULL, verified_at = NULL, verifikator_code = EXCLUDED.verifikator_code, updated_at = now()
  RETURNING * INTO v_profile;
  DELETE FROM public.service_skills WHERE profile_id = v_profile.id;
  INSERT INTO public.service_skills (profile_id, subcategory_id) SELECT v_profile.id, selected.skill_id FROM unnest(p_subcategory_ids) AS selected(skill_id);
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.service_publish_profile(text, text, text, text, numeric, uuid[], text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_publish_profile(text, text, text, text, numeric, uuid[], text, text) TO authenticated;

-- Approval cannot create a provider role for an account that already has a
-- merchant/courier role. This also protects legacy rows when they are reviewed.
CREATE OR REPLACE FUNCTION public.service_admin_review_provider(
  p_profile_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS public.service_profiles
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_profile public.service_profiles;
  v_is_admin boolean := public.is_admin();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_decision NOT IN ('VERIFIED', 'REJECTED') OR (p_decision = 'REJECTED' AND length(trim(coalesce(p_note, ''))) < 3) OR length(coalesce(p_note, '')) > 1000 THEN
    RAISE EXCEPTION 'Invalid provider verification decision';
  END IF;
  SELECT * INTO v_profile FROM public.service_profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND OR v_profile.verification_status <> 'PENDING' THEN RAISE EXCEPTION 'Provider profile is not awaiting review'; END IF;
  IF NOT v_is_admin AND NOT (public.is_verifikator() AND v_profile.verifikator_code IS NOT NULL AND EXISTS (SELECT 1 FROM public.verifikator_codes code WHERE code.code = v_profile.verifikator_code AND code.verifikator_id = auth.uid() AND code.is_active = true)) THEN
    RAISE EXCEPTION 'Only the assigned referral verifier or an admin may review this provider';
  END IF;
  IF p_decision = 'VERIFIED' THEN PERFORM public.assert_exclusive_business_role(v_profile.provider_id, 'service_provider'); END IF;
  UPDATE public.service_profiles SET verification_status = p_decision, is_verified = (p_decision = 'VERIFIED'), verification_note = nullif(trim(p_note), ''), verified_by = auth.uid(), verified_at = CASE WHEN p_decision = 'VERIFIED' THEN now() ELSE NULL END, updated_at = now() WHERE id = p_profile_id RETURNING * INTO v_profile;
  IF p_decision = 'VERIFIED' THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_profile.provider_id, 'service_provider') ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.service_admin_review_provider(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.service_admin_review_provider(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.assert_exclusive_business_role(uuid, public.app_role)
IS 'Enforces the one-account-one-business-role rule while preserving the buyer role.';
