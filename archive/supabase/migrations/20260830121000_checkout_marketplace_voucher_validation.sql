-- Marketplace voucher validation for create_checkout_orders.
-- This migration keeps the existing 11-argument RPC and adds a 12-argument
-- overload, so existing clients remain compatible while new clients can send
-- only a voucher code. All voucher rules and discount amounts are server-side.

CREATE TABLE IF NOT EXISTS public.marketplace_vouchers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  discount_type text NOT NULL CHECK (discount_type IN ('FIXED', 'PERCENT')),
  discount_value integer NOT NULL CHECK (discount_value > 0),
  max_discount integer CHECK (max_discount IS NULL OR max_discount > 0),
  min_subtotal integer NOT NULL DEFAULT 0 CHECK (min_subtotal >= 0),
  usage_limit integer CHECK (usage_limit IS NULL OR usage_limit > 0),
  usage_count integer NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
  per_buyer_limit integer NOT NULL DEFAULT 1 CHECK (per_buyer_limit > 0),
  starts_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at IS NULL OR expires_at > starts_at),
  CHECK (discount_type <> 'PERCENT' OR discount_value <= 100)
);

CREATE TABLE IF NOT EXISTS public.marketplace_voucher_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  voucher_id uuid NOT NULL REFERENCES public.marketplace_vouchers(id) ON DELETE RESTRICT,
  buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  discount_amount integer NOT NULL CHECK (discount_amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (voucher_id, order_id)
);

ALTER TABLE public.marketplace_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_voucher_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Buyers view active marketplace vouchers" ON public.marketplace_vouchers;
CREATE POLICY "Buyers view active marketplace vouchers"
ON public.marketplace_vouchers FOR SELECT TO authenticated
USING (is_active AND starts_at <= now() AND (expires_at IS NULL OR expires_at > now()));

DROP POLICY IF EXISTS "Buyers view own voucher redemptions" ON public.marketplace_voucher_redemptions;
CREATE POLICY "Buyers view own voucher redemptions"
ON public.marketplace_voucher_redemptions FOR SELECT TO authenticated
USING (buyer_id = auth.uid());

CREATE INDEX IF NOT EXISTS marketplace_vouchers_code_idx
  ON public.marketplace_vouchers (lower(code));
CREATE INDEX IF NOT EXISTS marketplace_voucher_redemptions_buyer_idx
  ON public.marketplace_voucher_redemptions (voucher_id, buyer_id);

CREATE OR REPLACE FUNCTION public.consume_marketplace_voucher(
  p_code text,
  p_buyer_id uuid,
  p_order_id uuid,
  p_subtotal integer,
  p_merchant_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voucher public.marketplace_vouchers%ROWTYPE;
  v_discount integer;
BEGIN
  IF NULLIF(trim(p_code), '') IS NULL THEN RETURN 0; END IF;
  IF p_buyer_id IS NULL OR p_order_id IS NULL OR p_subtotal < 0
     OR p_buyer_id <> auth.uid() THEN
    RAISE EXCEPTION 'Invalid voucher request' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.orders
    WHERE id = p_order_id AND buyer_id = p_buyer_id AND merchant_id = p_merchant_id
  ) THEN
    RAISE EXCEPTION 'Voucher order ownership validation failed' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_voucher
  FROM public.marketplace_vouchers
  WHERE lower(code) = lower(trim(p_code))
    AND is_active
    AND starts_at <= now()
    AND (expires_at IS NULL OR expires_at > now())
    AND min_subtotal <= p_subtotal
    AND (merchant_id IS NULL OR merchant_id = p_merchant_id)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher tidak valid, tidak berlaku untuk toko ini, atau sudah kedaluwarsa' USING ERRCODE = '22023';
  END IF;

  IF v_voucher.usage_limit IS NOT NULL AND v_voucher.usage_count >= v_voucher.usage_limit THEN
    RAISE EXCEPTION 'Batas penggunaan voucher sudah tercapai' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.marketplace_voucher_redemptions
    WHERE voucher_id = v_voucher.id AND buyer_id = p_buyer_id
    GROUP BY voucher_id, buyer_id
    HAVING count(*) >= v_voucher.per_buyer_limit
  ) THEN
    RAISE EXCEPTION 'Voucher sudah mencapai batas penggunaan akun ini' USING ERRCODE = '23514';
  END IF;

  v_discount := CASE
    WHEN v_voucher.discount_type = 'FIXED' THEN v_voucher.discount_value
    ELSE floor(p_subtotal * v_voucher.discount_value / 100.0)::integer
  END;
  v_discount := LEAST(v_discount, p_subtotal);
  IF v_voucher.max_discount IS NOT NULL THEN
    v_discount := LEAST(v_discount, v_voucher.max_discount);
  END IF;

  UPDATE public.marketplace_vouchers
  SET usage_count = usage_count + 1, updated_at = now()
  WHERE id = v_voucher.id;
  INSERT INTO public.marketplace_voucher_redemptions(voucher_id, buyer_id, order_id, discount_amount)
  VALUES (v_voucher.id, p_buyer_id, p_order_id, v_discount);
  RETURN v_discount;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_marketplace_voucher(text, uuid, uuid, integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_marketplace_voucher(text, uuid, uuid, integer, uuid) TO authenticated;

-- New overload. It calls the existing atomic 11-argument checkout RPC first;
-- because PostgreSQL functions share the caller transaction, a voucher error
-- rolls back orders, stock reservations, quota deduction, and redemption.
CREATE OR REPLACE FUNCTION public.create_checkout_orders(
  p_items jsonb,
  p_delivery_type text,
  p_delivery_name text,
  p_delivery_phone text,
  p_delivery_address text DEFAULT NULL,
  p_delivery_lat numeric DEFAULT NULL,
  p_delivery_lng numeric DEFAULT NULL,
  p_payment_method text DEFAULT 'COD',
  p_distance_km numeric DEFAULT 0,
  p_notes text DEFAULT NULL,
  p_checkout_request_id text DEFAULT NULL,
  p_voucher_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_base jsonb;
  v_order jsonb;
  v_order_id uuid;
  v_merchant_id uuid;
  v_discount integer;
  v_total_discount integer := 0;
  v_voucher_merchant_id uuid;
  v_applied boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  -- The old RPC remains the source of truth for server prices, shipping,
  -- stock locking and quota. Do not pass any client-calculated discount.
  v_base := public.create_checkout_orders(
    p_items, p_delivery_type, p_delivery_name, p_delivery_phone,
    p_delivery_address, p_delivery_lat, p_delivery_lng, p_payment_method,
    p_distance_km, p_notes, p_checkout_request_id
  );
  IF COALESCE((v_base->>'idempotent')::boolean, false) THEN
    RETURN v_base;
  END IF;
  IF NULLIF(trim(p_voucher_code), '') IS NULL THEN
    RETURN v_base;
  END IF;

  SELECT merchant_id INTO v_voucher_merchant_id
  FROM public.marketplace_vouchers
  WHERE lower(code) = lower(trim(p_voucher_code));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher tidak ditemukan' USING ERRCODE = '22023';
  END IF;

  FOR v_order IN SELECT value FROM jsonb_array_elements(COALESCE(v_base->'orders', '[]'::jsonb)) LOOP
    v_order_id := (v_order->>'order_id')::uuid;
    v_merchant_id := (v_order->>'merchant_id')::uuid;
    IF NOT v_applied AND (v_voucher_merchant_id IS NULL OR v_voucher_merchant_id = v_merchant_id) THEN
      v_discount := public.consume_marketplace_voucher(
        p_voucher_code, v_user_id, v_order_id,
        (v_order->>'subtotal')::integer, v_merchant_id
      );
      UPDATE public.orders
      SET total = GREATEST(0, total - v_discount),
          flash_sale_discount = COALESCE(flash_sale_discount, 0) + v_discount,
          updated_at = now()
      WHERE id = v_order_id AND buyer_id = v_user_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Checkout order not found while applying voucher' USING ERRCODE = 'P0002';
      END IF;
      v_total_discount := v_discount;
      v_applied := true;
    END IF;
  END LOOP;

  IF NOT v_applied THEN
    RAISE EXCEPTION 'Voucher tidak berlaku untuk merchant pada checkout ini' USING ERRCODE = '22023';
  END IF;

  RETURN v_base || jsonb_build_object('voucher_discount', v_total_discount);
END;
$$;

REVOKE ALL ON FUNCTION public.create_checkout_orders(
  jsonb, text, text, text, text, numeric, numeric, text, numeric, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_checkout_orders(
  jsonb, text, text, text, text, numeric, numeric, text, numeric, text, text, text
) TO authenticated;
