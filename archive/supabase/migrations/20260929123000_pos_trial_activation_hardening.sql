-- POS trial activation hardening.
-- Trial activation must be decided atomically in the database; the browser must
-- never insert a subscription row directly.
DO $$
BEGIN
  EXECUTE $sql$
    CREATE OR REPLACE FUNCTION public.activate_pos_trial()
    RETURNS public.pos_subscriptions
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $fn$
    DECLARE
      v_merchant_id uuid;
      v_config jsonb;
      v_trial_days integer;
      v_subscription public.pos_subscriptions%ROWTYPE;
    BEGIN
      IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Autentikasi diperlukan' USING ERRCODE = '42501';
      END IF;

      SELECT id INTO v_merchant_id
      FROM public.merchants
      WHERE user_id = auth.uid()
      FOR UPDATE;
      IF v_merchant_id IS NULL THEN
        RAISE EXCEPTION 'Merchant tidak ditemukan' USING ERRCODE = '42501';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.pos_subscriptions
        WHERE merchant_id = v_merchant_id AND is_trial = true
      ) THEN
        RAISE EXCEPTION 'Trial POS sudah pernah digunakan' USING ERRCODE = '23505';
      END IF;

      IF EXISTS (
        SELECT 1 FROM public.pos_subscriptions
        WHERE merchant_id = v_merchant_id
          AND status IN ('PENDING', 'ACTIVE')
      ) THEN
        RAISE EXCEPTION 'Sudah ada subscription POS yang sedang berjalan' USING ERRCODE = '23505';
      END IF;

      SELECT value INTO v_config
      FROM public.app_settings
      WHERE key = 'pos_config'
      FOR SHARE;
      v_trial_days := LEAST(GREATEST(COALESCE((v_config ->> 'trial_days')::integer, 30), 1), 90);

      INSERT INTO public.pos_subscriptions (
        merchant_id, package_id, status, is_trial, payment_amount,
        payment_status, started_at, expired_at
      ) VALUES (
        v_merchant_id, NULL, 'ACTIVE', true, 0,
        'FREE', now(), now() + make_interval(days => v_trial_days)
      )
      RETURNING * INTO v_subscription;

      RETURN v_subscription;
    END;
    $fn$
  $sql$;
  EXECUTE 'REVOKE ALL ON FUNCTION public.activate_pos_trial() FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.activate_pos_trial() TO authenticated';
END
$$;
