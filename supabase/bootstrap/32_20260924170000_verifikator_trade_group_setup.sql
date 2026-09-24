-- Repair verifikator group setup.
-- The referral code belongs to verifikator_codes, not trade_groups. Keep both
-- inserts in one server-side transaction so a failed code insert cannot leave
-- an orphan trade group.
CREATE OR REPLACE FUNCTION public.create_verifikator_trade_group(
  p_name text,
  p_code text,
  p_description text DEFAULT NULL,
  p_monthly_fee integer DEFAULT 10000
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_code text := upper(trim(p_code));
  v_name text := trim(p_name);
BEGIN
  IF v_user_id IS NULL OR NOT public.is_verifikator() THEN
    RAISE EXCEPTION 'Only an authenticated verifikator can create a trade group'
      USING ERRCODE = '42501';
  END IF;

  IF v_name = '' OR length(v_name) > 120 THEN
    RAISE EXCEPTION 'Trade group name is required and must be at most 120 characters'
      USING ERRCODE = '22023';
  END IF;
  IF v_code = '' OR length(v_code) > 32 OR v_code !~ '^[A-Z0-9_-]+$' THEN
    RAISE EXCEPTION 'Referral code must contain only A-Z, 0-9, underscore, or hyphen'
      USING ERRCODE = '22023';
  END IF;
  IF p_monthly_fee IS NULL OR p_monthly_fee < 0 THEN
    RAISE EXCEPTION 'Monthly fee must be zero or greater' USING ERRCODE = '22023';
  END IF;

  -- Serialize setup attempts for this verifier before checking existing data.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  IF EXISTS (SELECT 1 FROM public.trade_groups WHERE verifikator_id = v_user_id) THEN
    RAISE EXCEPTION 'Verifikator already has a trade group' USING ERRCODE = '23505';
  END IF;
  IF EXISTS (SELECT 1 FROM public.verifikator_codes WHERE code = v_code) THEN
    RAISE EXCEPTION 'Referral code is already used' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.trade_groups (name, description, monthly_fee, verifikator_id)
  VALUES (v_name, NULLIF(trim(p_description), ''), p_monthly_fee, v_user_id)
  RETURNING id INTO v_group_id;

  INSERT INTO public.verifikator_codes (code, trade_group, verifikator_id)
  VALUES (v_code, v_name, v_user_id);

  RETURN v_group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_verifikator_trade_group(text, text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_verifikator_trade_group(text, text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.create_verifikator_trade_group(text, text, text, integer) IS
  'Atomically creates the single trade group and referral code owned by the authenticated verifikator.';
