-- Harden payment-proof path contracts for both guest and authenticated buyers.
-- The frontend stores bucket-relative paths, not public URLs:
-- orders/{order_id}/{filename}
-- orders/{order_id}/{guest_token_hash}/{filename}

DO $bootstrap_do_harden_payment_proof_path_contract_marker$
BEGIN
  NULL;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_harden_payment_proof_path_contract_marker$;

CREATE OR REPLACE FUNCTION public.normalize_payment_proof_path(p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_path text := split_part(trim(COALESCE(p_value, '')), '?', 1);
BEGIN
  -- Accept legacy object URLs while persisting only bucket-relative paths.
  v_path := regexp_replace(
    v_path,
    '^https?://[^/]+/storage/v1/object/(public|authenticated|sign)/payment-proofs/',
    '',
    'i'
  );
  v_path := regexp_replace(v_path, '^/+', '');
  RETURN v_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_valid_payment_proof_path(
  p_value text,
  p_order_id uuid,
  p_guest_token_hash text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_path text := public.normalize_payment_proof_path(p_value);
  v_parts text[] := string_to_array(v_path, '/');
BEGIN
  IF p_order_id IS NULL OR v_parts IS NULL OR v_parts[1] <> 'orders'
     OR v_parts[2] <> p_order_id::text THEN
    RETURN false;
  END IF;

  IF p_guest_token_hash IS NULL THEN
    RETURN array_length(v_parts, 1) = 3
      AND length(trim(v_parts[3])) > 0;
  END IF;

  RETURN array_length(v_parts, 1) = 4
    AND v_parts[3] = p_guest_token_hash
    AND length(trim(v_parts[4])) > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_payment_proof_path(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_valid_payment_proof_path(text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_payment_proof_path(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.is_valid_payment_proof_path(text, uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_guest_checkout_payment_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.buyer_id IS NULL AND NEW.guest_access_token_hash IS NOT NULL THEN
    IF NEW.payment_method <> 'TRANSFER' THEN
      RAISE EXCEPTION 'Guest payment method is unavailable' USING ERRCODE = '22023';
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.payment_proof_url IS DISTINCT FROM OLD.payment_proof_url
       AND NEW.payment_proof_url IS NOT NULL
       AND NOT public.is_valid_payment_proof_path(
         NEW.payment_proof_url,
         NEW.id,
         NEW.guest_access_token_hash
       ) THEN
      RAISE EXCEPTION 'Guest payment proof is invalid' USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_guest_checkout_payment_contract ON public.orders;
CREATE TRIGGER enforce_guest_checkout_payment_contract
  BEFORE INSERT OR UPDATE OF payment_method, payment_proof_url ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_guest_checkout_payment_contract();

REVOKE ALL ON FUNCTION public.enforce_guest_checkout_payment_contract() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.buyer_submit_payment_proof(
  p_order_id uuid,
  p_payment_proof_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_path text := trim(COALESCE(p_payment_proof_url, ''));
  v_next_payment_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR length(v_path) < 1 OR length(v_path) > 2000
     OR NOT public.is_valid_payment_proof_path(v_path, p_order_id, NULL) THEN
    RAISE EXCEPTION 'Payment proof is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND buyer_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = '42501';
  END IF;
  IF v_order.payment_method <> 'TRANSFER'
     OR v_order.payment_status IN ('PAID', 'REFUNDED', 'EXPIRED')
     OR v_order.status IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED') THEN
    RAISE EXCEPTION 'Order is not accepting transfer proof' USING ERRCODE = '22023';
  END IF;

  v_next_payment_status := CASE WHEN v_order.payment_status = 'FAILED' THEN 'PENDING_TRANSFER' ELSE v_order.payment_status END;
  UPDATE public.orders
  SET payment_proof_url = v_path, payment_status = v_next_payment_status, updated_at = now()
  WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', v_path, 'payment_status', v_next_payment_status);
END;
$$;
REVOKE ALL ON FUNCTION public.buyer_submit_payment_proof(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_submit_payment_proof(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.guest_submit_payment_proof(
  p_order_id uuid,
  p_guest_access_token text,
  p_payment_proof_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_token_hash text := encode(digest(p_guest_access_token, 'sha256'), 'hex');
  v_path text := trim(COALESCE(p_payment_proof_url, ''));
  v_next_payment_status text;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND guest_access_token_hash = v_token_hash
    AND guest_token_expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order payment unavailable' USING ERRCODE = '42501';
  END IF;
  IF v_order.payment_method <> 'TRANSFER'
     OR v_order.payment_status IN ('PAID', 'REFUNDED', 'EXPIRED')
     OR v_order.status IN ('CANCELLED', 'CANCELED', 'REJECTED', 'REFUNDED')
     OR length(v_path) < 1
     OR length(v_path) > 2000
     OR NOT public.is_valid_payment_proof_path(v_path, p_order_id, v_token_hash) THEN
    RAISE EXCEPTION 'Order is not accepting transfer proof' USING ERRCODE = '22023';
  END IF;

  v_next_payment_status := CASE WHEN v_order.payment_status = 'FAILED' THEN 'PENDING_TRANSFER' ELSE v_order.payment_status END;
  UPDATE public.orders
  SET payment_proof_url = v_path, payment_status = v_next_payment_status, updated_at = now()
  WHERE id = p_order_id;
  RETURN jsonb_build_object('order_id', p_order_id, 'payment_proof_url', v_path, 'payment_status', v_next_payment_status);
END;
$$;
REVOKE ALL ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.guest_submit_payment_proof(uuid, text, text) TO anon;

NOTIFY pgrst, 'reload schema';
