-- Fase 5: partner desa/koperasi, promo onboarding yang benar-benar ditebus,
-- dan SLA dukungan prioritas.

ALTER TABLE public.pos_subscriptions
  ADD COLUMN IF NOT EXISTS original_amount INTEGER,
  ADD COLUMN IF NOT EXISTS discount_amount INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promotion_id UUID REFERENCES public.pos_onboarding_promotions(id),
  ADD COLUMN IF NOT EXISTS promotion_code TEXT;

CREATE INDEX IF NOT EXISTS idx_pos_subscriptions_promotion_id
  ON public.pos_subscriptions(promotion_id);

DROP FUNCTION IF EXISTS public.preview_pos_onboarding_promotion(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.preview_pos_onboarding_promotion(
  p_code TEXT,
  p_package_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id UUID;
  v_promotion public.pos_onboarding_promotions%ROWTYPE;
  v_package public.pos_packages%ROWTYPE;
  v_discount_amount INTEGER;
  v_final_amount INTEGER;
BEGIN
  SELECT id INTO v_merchant_id FROM public.merchants WHERE user_id = auth.uid();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan';
  END IF;

  SELECT * INTO v_promotion
  FROM public.pos_onboarding_promotions
  WHERE code = upper(trim(p_code))
    AND is_active
    AND starts_at <= now()
    AND expires_at > now();
  IF v_promotion.id IS NULL THEN
    RAISE EXCEPTION 'Kode promo tidak ditemukan atau sudah kedaluwarsa';
  END IF;
  IF v_promotion.max_redemptions IS NOT NULL
    AND v_promotion.redeemed_count >= v_promotion.max_redemptions THEN
    RAISE EXCEPTION 'Kuota kode promo sudah habis';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.pos_onboarding_promotion_redemptions
    WHERE promotion_id = v_promotion.id AND merchant_id = v_merchant_id
  ) THEN
    RAISE EXCEPTION 'Kode promo ini sudah digunakan oleh merchant Anda';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages
  WHERE id = p_package_id AND is_active;
  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket POS tidak ditemukan';
  END IF;

  v_discount_amount := floor(v_package.price * v_promotion.discount_percent / 100.0);
  v_final_amount := greatest(v_package.price - v_discount_amount, 0);
  RETURN jsonb_build_object(
    'promotion_id', v_promotion.id,
    'code', v_promotion.code,
    'name', v_promotion.name,
    'partner_type', v_promotion.partner_type,
    'discount_percent', v_promotion.discount_percent,
    'discount_amount', v_discount_amount,
    'original_amount', v_package.price,
    'final_amount', v_final_amount,
    'expires_at', v_promotion.expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pos_subscription_with_promotion(
  p_package_id UUID,
  p_payment_proof_url TEXT DEFAULT NULL,
  p_promo_code TEXT DEFAULT NULL
)
RETURNS public.pos_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_id UUID;
  v_package public.pos_packages%ROWTYPE;
  v_promotion public.pos_onboarding_promotions%ROWTYPE;
  v_subscription public.pos_subscriptions%ROWTYPE;
  v_discount_amount INTEGER := 0;
  v_original_amount INTEGER;
  v_final_amount INTEGER;
  v_code TEXT := NULLIF(upper(trim(p_promo_code)), '');
BEGIN
  SELECT id INTO v_merchant_id FROM public.merchants WHERE user_id = auth.uid();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Merchant tidak ditemukan';
  END IF;

  SELECT * INTO v_package FROM public.pos_packages
  WHERE id = p_package_id AND is_active;
  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket POS tidak ditemukan';
  END IF;

  v_original_amount := v_package.price;
  IF v_code IS NOT NULL THEN
    SELECT * INTO v_promotion
    FROM public.pos_onboarding_promotions
    WHERE code = v_code
    FOR UPDATE;
    IF v_promotion.id IS NULL
      OR NOT v_promotion.is_active
      OR v_promotion.starts_at > now()
      OR v_promotion.expires_at <= now() THEN
      RAISE EXCEPTION 'Kode promo tidak ditemukan atau sudah kedaluwarsa';
    END IF;
    IF v_promotion.max_redemptions IS NOT NULL
      AND v_promotion.redeemed_count >= v_promotion.max_redemptions THEN
      RAISE EXCEPTION 'Kuota kode promo sudah habis';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.pos_onboarding_promotion_redemptions
      WHERE promotion_id = v_promotion.id AND merchant_id = v_merchant_id
    ) THEN
      RAISE EXCEPTION 'Kode promo ini sudah digunakan oleh merchant Anda';
    END IF;
    v_discount_amount := floor(v_original_amount * v_promotion.discount_percent / 100.0);
  END IF;
  v_final_amount := greatest(v_original_amount - v_discount_amount, 0);

  INSERT INTO public.pos_subscriptions (
    merchant_id, package_id, status, payment_amount, original_amount,
    discount_amount, promotion_id, promotion_code, payment_proof_url,
    payment_status, started_at, expired_at
  ) VALUES (
    v_merchant_id, p_package_id, 'PENDING', v_final_amount, v_original_amount,
    v_discount_amount, v_promotion.id, v_promotion.code, p_payment_proof_url,
    CASE WHEN v_final_amount = 0 THEN 'FREE' ELSE 'PENDING' END, NULL, NULL
  )
  RETURNING * INTO v_subscription;

  IF v_promotion.id IS NOT NULL THEN
    INSERT INTO public.pos_onboarding_promotion_redemptions (promotion_id, merchant_id)
    VALUES (v_promotion.id, v_merchant_id);
    UPDATE public.pos_onboarding_promotions
    SET redeemed_count = redeemed_count + 1, updated_at = now()
    WHERE id = v_promotion.id;
  END IF;
  RETURN v_subscription;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_pos_onboarding_promotion(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.preview_pos_onboarding_promotion(TEXT, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_pos_subscription_with_promotion(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pos_subscription_with_promotion(UUID, TEXT, TEXT) TO authenticated;

-- Support tables were historically used by the UI without a canonical
-- bootstrap. IF NOT EXISTS keeps this safe for projects that already have them.
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'medium',
  priority_source TEXT NOT NULL DEFAULT 'standard',
  status TEXT NOT NULL DEFAULT 'open',
  sla_due_at TIMESTAMPTZ,
  first_response_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_message_at TIMESTAMPTZ,
  message_count INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS priority_source TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS sla_due_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS first_response_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('user', 'admin')),
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_sla
  ON public.support_tickets(status, sla_due_at);
CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket
  ON public.support_ticket_messages(ticket_id, created_at);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own support tickets" ON public.support_tickets;
CREATE POLICY "Users view own support tickets" ON public.support_tickets
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "Users create own support tickets" ON public.support_tickets;
CREATE POLICY "Users create own support tickets" ON public.support_tickets
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() OR is_admin());
DROP POLICY IF EXISTS "Users update own support tickets" ON public.support_tickets;
CREATE POLICY "Users update own support tickets" ON public.support_tickets
  FOR UPDATE TO authenticated USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "Users view permitted support messages" ON public.support_ticket_messages;
CREATE POLICY "Users view permitted support messages" ON public.support_ticket_messages
  FOR SELECT TO authenticated USING (
    is_admin() OR EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "Users create permitted support messages" ON public.support_ticket_messages;
CREATE POLICY "Users create permitted support messages" ON public.support_ticket_messages
  FOR INSERT TO authenticated WITH CHECK (
    sender_id = auth.uid() AND (
      is_admin() OR EXISTS (
        SELECT 1 FROM public.support_tickets t
        WHERE t.id = ticket_id AND t.user_id = auth.uid()
      )
    )
  );

CREATE OR REPLACE FUNCTION public.create_support_ticket(
  p_subject TEXT,
  p_category TEXT,
  p_message TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket_id UUID;
  v_priority_support BOOLEAN := false;
  v_priority TEXT := 'medium';
  v_priority_source TEXT := 'standard';
  v_sla_due_at TIMESTAMPTZ := now() + interval '24 hours';
BEGIN
  IF NULLIF(trim(p_subject), '') IS NULL OR NULLIF(trim(p_message), '') IS NULL THEN
    RAISE EXCEPTION 'Subjek dan pesan tiket wajib diisi';
  END IF;

  SELECT COALESCE(pp.priority_support, false) INTO v_priority_support
  FROM public.merchants m
  JOIN public.pos_subscriptions ps ON ps.merchant_id = m.id
  JOIN public.pos_packages pp ON pp.id = ps.package_id
  WHERE m.user_id = auth.uid()
    AND ps.status = 'ACTIVE'
    AND (ps.expired_at IS NULL OR ps.expired_at > now())
  ORDER BY ps.created_at DESC
  LIMIT 1;

  IF v_priority_support THEN
    v_priority := 'high';
    v_priority_source := 'pos_priority_support';
    v_sla_due_at := now() + interval '4 hours';
  END IF;

  INSERT INTO public.support_tickets (
    user_id, subject, category, priority, priority_source, status,
    sla_due_at, created_at, updated_at, last_message_at, message_count
  ) VALUES (
    auth.uid(), trim(p_subject), trim(p_category), v_priority, v_priority_source, 'open',
    v_sla_due_at, now(), now(), now(), 1
  ) RETURNING id INTO v_ticket_id;

  INSERT INTO public.support_ticket_messages (
    ticket_id, sender_id, sender_role, message
  ) VALUES (v_ticket_id, auth.uid(), 'user', trim(p_message));
  RETURN v_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_support_ticket(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_support_ticket(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_support_first_response(p_ticket_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can mark support response';
  END IF;
  UPDATE public.support_tickets
  SET first_response_at = COALESCE(first_response_at, now()),
      updated_at = now()
  WHERE id = p_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_support_first_response(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_support_first_response(UUID) TO authenticated;