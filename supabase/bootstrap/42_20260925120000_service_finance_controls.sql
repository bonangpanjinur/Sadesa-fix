-- Kontrol finansial marketplace jasa: minimum provider, fee policy aktif, dan payment info admin.

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
  SELECT * INTO v_request
  FROM public.service_requests
  WHERE id = p_request_id AND provider_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service request not found'; END IF;
  IF v_request.status <> 'NEGOTIATING' OR p_agreed_price IS NULL OR p_agreed_price <= 0 THEN
    RAISE EXCEPTION 'Request is not ready for a price proposal';
  END IF;

  SELECT * INTO v_profile
  FROM public.service_profiles
  WHERE id = v_request.profile_id
    AND provider_id = auth.uid()
    AND is_active = true
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Provider profile is not available'; END IF;
  IF p_agreed_price < coalesce(v_profile.min_price, 0) THEN
    RAISE EXCEPTION 'Price cannot be below provider minimum tariff of %', v_profile.min_price;
  END IF;

  SELECT CASE
    WHEN (value->>'percent') ~ '^[0-9]+(\\.[0-9]+)?$' THEN (value->>'percent')::numeric
    ELSE 5
  END
  INTO v_fee_percent
  FROM public.app_settings
  WHERE key = 'platform_fee';
  v_fee_percent := greatest(0, least(100, coalesce(v_fee_percent, 5)));

  UPDATE public.service_requests SET
    agreed_price = round(p_agreed_price, 2),
    platform_fee = round(p_agreed_price * v_fee_percent / 100, 2),
    transfer_fee = 0,
    provider_payout = round(p_agreed_price - (p_agreed_price * v_fee_percent / 100), 2),
    provider_approved = true,
    requester_approved = false,
    updated_at = now()
  WHERE id = p_request_id
  RETURNING * INTO v_request;
  RETURN v_request;
END;
$$;

GRANT EXECUTE ON FUNCTION public.service_provider_propose_price(uuid,numeric) TO authenticated;

COMMENT ON FUNCTION public.service_provider_propose_price(uuid,numeric)
IS 'Provider price proposal with server-side minimum tariff and admin platform fee policy.';

-- Ensure the existing admin settings have safe defaults for the services flow.
INSERT INTO public.app_settings (key, value, category, description)
VALUES
  ('platform_fee', '{"percent": 5}'::jsonb, 'payment', 'Fee platform untuk transaksi jasa dan order'),
  ('admin_payment_info', '{"bank_name":"", "bank_account_number":"", "bank_account_name":"", "qris_image_url":""}'::jsonb, 'payment', 'Rekening admin untuk pembayaran manual')
ON CONFLICT (key) DO NOTHING;
