-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_27702b96a039$
BEGIN
  EXECUTE $bootstrap_sql_27702b96a039$-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_efbe6d39b891$
BEGIN
  EXECUTE $bootstrap_sql_efbe6d39b891$-- Merchant referral commissions for verifikator and admin_desa.
-- Basis: the merchant platform fee actually collected, never gross sales.
-- This file is converted to repeatable per-statement bootstrap wrappers before deployment.

CREATE TABLE IF NOT EXISTS public.merchant_referral_commission_settings (
  owner_role text PRIMARY KEY CHECK (owner_role IN ('VERIFIKATOR', 'ADMIN_DESA')),
  commission_percent numeric(7,4) NOT NULL DEFAULT 0 CHECK (commission_percent BETWEEN 0 AND 100),
  is_enabled boolean NOT NULL DEFAULT false,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_efbe6d39b891$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_efbe6d39b891$$bootstrap_sql_27702b96a039$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27702b96a039$;

DO $bootstrap_do_de30863a8bd2$
BEGIN
  EXECUTE $bootstrap_sql_de30863a8bd2$DO $bootstrap_do_bb0be3d328fb$
BEGIN
  EXECUTE $bootstrap_sql_bb0be3d328fb$INSERT INTO public.merchant_referral_commission_settings(owner_role, commission_percent, is_enabled)
VALUES ('VERIFIKATOR', 0, false), ('ADMIN_DESA', 0, false)
ON CONFLICT (owner_role) DO NOTHING$bootstrap_sql_bb0be3d328fb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb0be3d328fb$$bootstrap_sql_de30863a8bd2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de30863a8bd2$;

DO $bootstrap_do_dc82bac23583$
BEGIN
  EXECUTE $bootstrap_sql_dc82bac23583$DO $bootstrap_do_906f4af68e1e$
BEGIN
  EXECUTE $bootstrap_sql_906f4af68e1e$CREATE TABLE IF NOT EXISTS public.merchant_referral_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  owner_role text NOT NULL CHECK (owner_role IN ('VERIFIKATOR', 'ADMIN_DESA')),
  village_id uuid REFERENCES public.villages(id) ON DELETE SET NULL,
  legacy_verifikator_code_id uuid UNIQUE REFERENCES public.verifikator_codes(id) ON DELETE SET NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
  max_usage integer CHECK (max_usage IS NULL OR max_usage > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((owner_role = 'VERIFIKATOR' AND legacy_verifikator_code_id IS NOT NULL) OR owner_role = 'ADMIN_DESA')
)$bootstrap_sql_906f4af68e1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_906f4af68e1e$$bootstrap_sql_dc82bac23583$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc82bac23583$;

DO $bootstrap_do_b8a7f6010e8e$
BEGIN
  EXECUTE $bootstrap_sql_b8a7f6010e8e$DO $bootstrap_do_3d32c45770d1$
BEGIN
  EXECUTE $bootstrap_sql_3d32c45770d1$CREATE INDEX IF NOT EXISTS merchant_referral_codes_owner_idx
  ON public.merchant_referral_codes(owner_user_id, created_at DESC)$bootstrap_sql_3d32c45770d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3d32c45770d1$$bootstrap_sql_b8a7f6010e8e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b8a7f6010e8e$;

DO $bootstrap_do_070dcf46be77$
BEGIN
  EXECUTE $bootstrap_sql_070dcf46be77$DO $bootstrap_do_b56c9a326ff2$
BEGIN
  EXECUTE $bootstrap_sql_b56c9a326ff2$-- Mirror the existing verifier-owned codes into the generic referral code registry.
INSERT INTO public.merchant_referral_codes(
  code, owner_user_id, owner_role, legacy_verifikator_code_id, description,
  is_active, usage_count, max_usage, created_at
)
SELECT upper(trim(vc.code)), vc.verifikator_id, 'VERIFIKATOR', vc.id, vc.description,
       vc.is_active, vc.usage_count, vc.max_usage, vc.created_at
FROM public.verifikator_codes vc
ON CONFLICT (legacy_verifikator_code_id) DO UPDATE
SET code = EXCLUDED.code,
    owner_user_id = EXCLUDED.owner_user_id,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active,
    usage_count = GREATEST(public.merchant_referral_codes.usage_count, EXCLUDED.usage_count),
    max_usage = EXCLUDED.max_usage$bootstrap_sql_b56c9a326ff2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b56c9a326ff2$$bootstrap_sql_070dcf46be77$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_070dcf46be77$;

DO $bootstrap_do_bcfc7202cc7c$
BEGIN
  EXECUTE $bootstrap_sql_bcfc7202cc7c$DO $bootstrap_do_0c3747398c6b$
BEGIN
  EXECUTE $bootstrap_sql_0c3747398c6b$ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS referral_owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS referral_owner_role text,
  ADD COLUMN IF NOT EXISTS referral_code_id uuid REFERENCES public.merchant_referral_codes(id) ON DELETE SET NULL$bootstrap_sql_0c3747398c6b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c3747398c6b$$bootstrap_sql_bcfc7202cc7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bcfc7202cc7c$;

DO $bootstrap_do_ada1e5425017$
BEGIN
  EXECUTE $bootstrap_sql_ada1e5425017$DO $bootstrap_do_0b9e039c6927$
BEGIN
  EXECUTE $bootstrap_sql_0b9e039c6927$ALTER TABLE public.merchants DROP CONSTRAINT IF EXISTS merchants_referral_owner_role_check$bootstrap_sql_0b9e039c6927$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b9e039c6927$$bootstrap_sql_ada1e5425017$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ada1e5425017$;

DO $bootstrap_do_59ae756210e5$
BEGIN
  EXECUTE $bootstrap_sql_59ae756210e5$DO $bootstrap_do_f476f3b9a90d$
BEGIN
  EXECUTE $bootstrap_sql_f476f3b9a90d$ALTER TABLE public.merchants ADD CONSTRAINT merchants_referral_owner_role_check
  CHECK (referral_owner_role IS NULL OR referral_owner_role IN ('VERIFIKATOR', 'ADMIN_DESA'))$bootstrap_sql_f476f3b9a90d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f476f3b9a90d$$bootstrap_sql_59ae756210e5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_59ae756210e5$;

DO $bootstrap_do_bab1035e0495$
BEGIN
  EXECUTE $bootstrap_sql_bab1035e0495$DO $bootstrap_do_52aed15cd99b$
BEGIN
  EXECUTE $bootstrap_sql_52aed15cd99b$UPDATE public.merchants m
SET referral_owner_user_id = c.owner_user_id,
    referral_owner_role = c.owner_role,
    referral_code_id = c.id
FROM public.merchant_referral_codes c
WHERE upper(trim(COALESCE(m.verifikator_code, ''))) = c.code
  AND m.referral_owner_user_id IS NULL$bootstrap_sql_52aed15cd99b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52aed15cd99b$$bootstrap_sql_bab1035e0495$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bab1035e0495$;

DO $bootstrap_do_5dbeadd3d9b4$
BEGIN
  EXECUTE $bootstrap_sql_5dbeadd3d9b4$DO $bootstrap_do_2562cdfd8c11$
BEGIN
  EXECUTE $bootstrap_sql_2562cdfd8c11$UPDATE public.merchants m
SET referral_owner_user_id = m.verifikator_id,
    referral_owner_role = 'VERIFIKATOR'
WHERE m.referral_owner_user_id IS NULL AND m.verifikator_id IS NOT NULL$bootstrap_sql_2562cdfd8c11$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2562cdfd8c11$$bootstrap_sql_5dbeadd3d9b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5dbeadd3d9b4$;

DO $bootstrap_do_0fb1fd4a421f$
BEGIN
  EXECUTE $bootstrap_sql_0fb1fd4a421f$DO $bootstrap_do_89199e034d4b$
BEGIN
  EXECUTE $bootstrap_sql_89199e034d4b$CREATE INDEX IF NOT EXISTS merchants_referral_owner_idx
  ON public.merchants(referral_owner_user_id, referral_owner_role)
  WHERE referral_owner_user_id IS NOT NULL$bootstrap_sql_89199e034d4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89199e034d4b$$bootstrap_sql_0fb1fd4a421f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0fb1fd4a421f$;

DO $bootstrap_do_39114c76b261$
BEGIN
  EXECUTE $bootstrap_sql_39114c76b261$DO $bootstrap_do_57651eee83b4$
BEGIN
  EXECUTE $bootstrap_sql_57651eee83b4$CREATE OR REPLACE FUNCTION public.sync_verifikator_code_to_referral_registry()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.merchant_referral_codes SET is_active = false
    WHERE legacy_verifikator_code_id = OLD.id;
    RETURN OLD;
  END IF;
  INSERT INTO public.merchant_referral_codes(
    code, owner_user_id, owner_role, legacy_verifikator_code_id, description,
    is_active, usage_count, max_usage, created_at
  ) VALUES (
    upper(trim(NEW.code)), NEW.verifikator_id, 'VERIFIKATOR', NEW.id, NEW.description,
    NEW.is_active, NEW.usage_count, NEW.max_usage, NEW.created_at
  )
  ON CONFLICT (legacy_verifikator_code_id) DO UPDATE
  SET code = EXCLUDED.code,
      owner_user_id = EXCLUDED.owner_user_id,
      description = EXCLUDED.description,
      is_active = EXCLUDED.is_active,
      max_usage = EXCLUDED.max_usage;
  RETURN NEW;
END;
$$$bootstrap_sql_57651eee83b4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57651eee83b4$$bootstrap_sql_39114c76b261$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_39114c76b261$;

DO $bootstrap_do_e675fbd0ea37$
BEGIN
  EXECUTE $bootstrap_sql_e675fbd0ea37$DO $bootstrap_do_0621b94d7e31$
BEGIN
  EXECUTE $bootstrap_sql_0621b94d7e31$DROP TRIGGER IF EXISTS sync_verifikator_code_to_referral_registry ON public.verifikator_codes$bootstrap_sql_0621b94d7e31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0621b94d7e31$$bootstrap_sql_e675fbd0ea37$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e675fbd0ea37$;

DO $bootstrap_do_e1384d2e0923$
BEGIN
  EXECUTE $bootstrap_sql_e1384d2e0923$DO $bootstrap_do_a62efd3e8ec5$
BEGIN
  EXECUTE $bootstrap_sql_a62efd3e8ec5$CREATE TRIGGER sync_verifikator_code_to_referral_registry
AFTER INSERT OR UPDATE OF code, verifikator_id, description, is_active, max_usage
ON public.verifikator_codes
FOR EACH ROW EXECUTE FUNCTION public.sync_verifikator_code_to_referral_registry()$bootstrap_sql_a62efd3e8ec5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a62efd3e8ec5$$bootstrap_sql_e1384d2e0923$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e1384d2e0923$;

DO $bootstrap_do_c04f106b3cf7$
BEGIN
  EXECUTE $bootstrap_sql_c04f106b3cf7$DO $bootstrap_do_9ac734cf9703$
BEGIN
  EXECUTE $bootstrap_sql_9ac734cf9703$CREATE OR REPLACE FUNCTION public.capture_merchant_referral_attribution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_code public.merchant_referral_codes%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.verifikator_code IS NOT DISTINCT FROM OLD.verifikator_code THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NULLIF(trim(COALESCE(OLD.verifikator_code, '')), '') IS NOT NULL
     AND NEW.verifikator_code IS DISTINCT FROM OLD.verifikator_code THEN
    RAISE EXCEPTION 'Kode referral pedagang tidak dapat diganti setelah pendaftaran' USING ERRCODE = '23514';
  END IF;

  IF NULLIF(trim(COALESCE(NEW.verifikator_code, '')), '') IS NULL THEN
    NEW.referral_owner_user_id := NULL;
    NEW.referral_owner_role := NULL;
    NEW.referral_code_id := NULL;
    RETURN NEW;
  END IF;

  SELECT * INTO v_code
  FROM public.merchant_referral_codes
  WHERE code = upper(trim(NEW.verifikator_code)) AND is_active = true
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kode referral tidak valid atau tidak aktif' USING ERRCODE = '22023';
  END IF;
  IF v_code.max_usage IS NOT NULL AND v_code.usage_count >= v_code.max_usage THEN
    RAISE EXCEPTION 'Batas penggunaan kode referral sudah tercapai' USING ERRCODE = '23514';
  END IF;
  UPDATE public.merchant_referral_codes
  SET usage_count = usage_count + 1
  WHERE id = v_code.id AND is_active = true
    AND (max_usage IS NULL OR usage_count < max_usage)
  RETURNING * INTO v_code;
  IF NOT FOUND THEN RAISE EXCEPTION 'Kode referral tidak tersedia' USING ERRCODE = '23514'; END IF;

  IF v_code.legacy_verifikator_code_id IS NOT NULL THEN
    UPDATE public.verifikator_codes SET usage_count = usage_count + 1
    WHERE id = v_code.legacy_verifikator_code_id;
    NEW.verifikator_id := v_code.owner_user_id;
  ELSE
    NEW.verifikator_id := NULL;
    NEW.trade_group := NULL;
  END IF;
  NEW.verifikator_code := v_code.code;
  NEW.referral_owner_user_id := v_code.owner_user_id;
  NEW.referral_owner_role := v_code.owner_role;
  NEW.referral_code_id := v_code.id;
  RETURN NEW;
END;
$$$bootstrap_sql_9ac734cf9703$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ac734cf9703$$bootstrap_sql_c04f106b3cf7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c04f106b3cf7$;

DO $bootstrap_do_bb937a711aaf$
BEGIN
  EXECUTE $bootstrap_sql_bb937a711aaf$DO $bootstrap_do_f35937cbdd35$
BEGIN
  EXECUTE $bootstrap_sql_f35937cbdd35$DROP TRIGGER IF EXISTS capture_merchant_referral_attribution ON public.merchants$bootstrap_sql_f35937cbdd35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f35937cbdd35$$bootstrap_sql_bb937a711aaf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb937a711aaf$;

DO $bootstrap_do_208c495649e1$
BEGIN
  EXECUTE $bootstrap_sql_208c495649e1$DO $bootstrap_do_aeb3e569cec8$
BEGIN
  EXECUTE $bootstrap_sql_aeb3e569cec8$CREATE TRIGGER capture_merchant_referral_attribution
BEFORE INSERT OR UPDATE OF verifikator_code ON public.merchants
FOR EACH ROW EXECUTE FUNCTION public.capture_merchant_referral_attribution()$bootstrap_sql_aeb3e569cec8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_aeb3e569cec8$$bootstrap_sql_208c495649e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_208c495649e1$;

DO $bootstrap_do_c406982d9f1e$
BEGIN
  EXECUTE $bootstrap_sql_c406982d9f1e$DO $bootstrap_do_5fa4413ecc48$
BEGIN
  EXECUTE $bootstrap_sql_5fa4413ecc48$CREATE TABLE IF NOT EXISTS public.merchant_referral_fee_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id uuid NOT NULL REFERENCES public.commission_wallets(id) ON DELETE RESTRICT,
  source_fee_ledger_id uuid UNIQUE REFERENCES public.commission_wallet_ledger(id) ON DELETE RESTRICT,
  source_order_id uuid REFERENCES public.orders(id) ON DELETE RESTRICT,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  referral_code_id uuid REFERENCES public.merchant_referral_codes(id) ON DELETE SET NULL,
  referrer_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  referrer_role text CHECK (referrer_role IS NULL OR referrer_role IN ('VERIFIKATOR', 'ADMIN_DESA')),
  fee_amount_rupiah bigint NOT NULL CHECK (fee_amount_rupiah >= 0),
  fee_collected_rupiah bigint NOT NULL DEFAULT 0 CHECK (fee_collected_rupiah >= 0),
  outstanding_debt_rupiah bigint NOT NULL DEFAULT 0 CHECK (outstanding_debt_rupiah >= 0),
  refunded_collected_rupiah bigint NOT NULL DEFAULT 0 CHECK (refunded_collected_rupiah >= 0),
  refunded_debt_rupiah bigint NOT NULL DEFAULT 0 CHECK (refunded_debt_rupiah >= 0),
  referral_percent numeric(7,4) NOT NULL DEFAULT 0 CHECK (referral_percent BETWEEN 0 AND 100),
  referral_amount_recorded_rupiah bigint NOT NULL DEFAULT 0 CHECK (referral_amount_recorded_rupiah >= 0),
  release_at timestamptz NOT NULL,
  is_legacy_debt boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (fee_collected_rupiah + outstanding_debt_rupiah + refunded_debt_rupiah <= fee_amount_rupiah)
)$bootstrap_sql_5fa4413ecc48$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5fa4413ecc48$$bootstrap_sql_c406982d9f1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c406982d9f1e$;

DO $bootstrap_do_ddd9d77a374f$
BEGIN
  EXECUTE $bootstrap_sql_ddd9d77a374f$DO $bootstrap_do_087ece725f25$
BEGIN
  EXECUTE $bootstrap_sql_087ece725f25$CREATE UNIQUE INDEX IF NOT EXISTS merchant_referral_fee_source_ledger_uq
  ON public.merchant_referral_fee_sources(source_fee_ledger_id)
  WHERE source_fee_ledger_id IS NOT NULL$bootstrap_sql_087ece725f25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_087ece725f25$$bootstrap_sql_ddd9d77a374f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddd9d77a374f$;

DO $bootstrap_do_607872ad4879$
BEGIN
  EXECUTE $bootstrap_sql_607872ad4879$DO $bootstrap_do_fb2545bb5b36$
BEGIN
  EXECUTE $bootstrap_sql_fb2545bb5b36$CREATE UNIQUE INDEX IF NOT EXISTS merchant_referral_fee_sources_legacy_wallet_uq
  ON public.merchant_referral_fee_sources(wallet_id) WHERE is_legacy_debt = true$bootstrap_sql_fb2545bb5b36$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb2545bb5b36$$bootstrap_sql_607872ad4879$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_607872ad4879$;

DO $bootstrap_do_7359489b5f64$
BEGIN
  EXECUTE $bootstrap_sql_7359489b5f64$DO $bootstrap_do_896fcaaeaaf6$
BEGIN
  EXECUTE $bootstrap_sql_896fcaaeaaf6$CREATE INDEX IF NOT EXISTS merchant_referral_fee_sources_wallet_debt_idx
  ON public.merchant_referral_fee_sources(wallet_id, is_legacy_debt DESC, created_at, id)
  WHERE outstanding_debt_rupiah > 0$bootstrap_sql_896fcaaeaaf6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_896fcaaeaaf6$$bootstrap_sql_7359489b5f64$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7359489b5f64$;

DO $bootstrap_do_d2438004dc13$
BEGIN
  EXECUTE $bootstrap_sql_d2438004dc13$DO $bootstrap_do_f62717614e2f$
BEGIN
  EXECUTE $bootstrap_sql_f62717614e2f$-- Preserve existing aggregate debt as a non-referrable FIFO source so new top-ups
-- do not mistakenly earn referral commission on fee debt created before this feature.
INSERT INTO public.merchant_referral_fee_sources(
  wallet_id, merchant_id, fee_amount_rupiah, outstanding_debt_rupiah,
  release_at, is_legacy_debt
)
SELECT w.id, w.merchant_id, w.debt_rupiah, w.debt_rupiah, now(), true
FROM public.commission_wallets w
WHERE w.owner_type = 'MERCHANT' AND w.debt_rupiah > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.merchant_referral_fee_sources s
    WHERE s.wallet_id = w.id AND s.is_legacy_debt = true AND s.outstanding_debt_rupiah > 0
  )
ON CONFLICT DO NOTHING$bootstrap_sql_f62717614e2f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f62717614e2f$$bootstrap_sql_d2438004dc13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2438004dc13$;

DO $bootstrap_do_b9a6462ec8fe$
BEGIN
  EXECUTE $bootstrap_sql_b9a6462ec8fe$DO $bootstrap_do_89a9de73ec0a$
BEGIN
  EXECUTE $bootstrap_sql_89a9de73ec0a$CREATE TABLE IF NOT EXISTS public.merchant_referral_fee_collection_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fee_source_id uuid NOT NULL REFERENCES public.merchant_referral_fee_sources(id) ON DELETE RESTRICT,
  funding_wallet_ledger_id uuid NOT NULL REFERENCES public.commission_wallet_ledger(id) ON DELETE RESTRICT,
  collected_amount_rupiah bigint NOT NULL CHECK (collected_amount_rupiah > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fee_source_id, funding_wallet_ledger_id)
)$bootstrap_sql_89a9de73ec0a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_89a9de73ec0a$$bootstrap_sql_b9a6462ec8fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9a6462ec8fe$;

DO $bootstrap_do_1ebfce656f7e$
BEGIN
  EXECUTE $bootstrap_sql_1ebfce656f7e$DO $bootstrap_do_06d1206b960d$
BEGIN
  EXECUTE $bootstrap_sql_06d1206b960d$CREATE TABLE IF NOT EXISTS public.merchant_referral_payout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  owner_role text NOT NULL CHECK (owner_role IN ('VERIFIKATOR', 'ADMIN_DESA')),
  amount_rupiah bigint NOT NULL CHECK (amount_rupiah >= 10000),
  bank_name text NOT NULL,
  account_number text NOT NULL,
  account_holder text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'PAID', 'REJECTED')),
  admin_notes text,
  payout_reference text,
  processed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  processed_at timestamptz,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  paid_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_06d1206b960d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_06d1206b960d$$bootstrap_sql_1ebfce656f7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1ebfce656f7e$;

DO $bootstrap_do_5b164caf20ac$
BEGIN
  EXECUTE $bootstrap_sql_5b164caf20ac$DO $bootstrap_do_31870d050a4c$
BEGIN
  EXECUTE $bootstrap_sql_31870d050a4c$CREATE INDEX IF NOT EXISTS merchant_referral_payout_owner_idx
  ON public.merchant_referral_payout_requests(owner_user_id, created_at DESC)$bootstrap_sql_31870d050a4c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31870d050a4c$$bootstrap_sql_5b164caf20ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b164caf20ac$;

DO $bootstrap_do_dd75782ed443$
BEGIN
  EXECUTE $bootstrap_sql_dd75782ed443$DO $bootstrap_do_24bd1dd21524$
BEGIN
  EXECUTE $bootstrap_sql_24bd1dd21524$ALTER TABLE public.merchant_referral_payout_requests
  ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz$bootstrap_sql_24bd1dd21524$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_24bd1dd21524$$bootstrap_sql_dd75782ed443$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dd75782ed443$;

DO $bootstrap_do_7c2c51565792$
BEGIN
  EXECUTE $bootstrap_sql_7c2c51565792$DO $bootstrap_do_cc7a8d738bea$
BEGIN
  EXECUTE $bootstrap_sql_cc7a8d738bea$CREATE INDEX IF NOT EXISTS merchant_referral_payout_status_idx
  ON public.merchant_referral_payout_requests(status, created_at DESC)$bootstrap_sql_cc7a8d738bea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc7a8d738bea$$bootstrap_sql_7c2c51565792$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c2c51565792$;

DO $bootstrap_do_cf03903ce259$
BEGIN
  EXECUTE $bootstrap_sql_cf03903ce259$DO $bootstrap_do_5250d5fcc61c$
BEGIN
  EXECUTE $bootstrap_sql_5250d5fcc61c$CREATE TABLE IF NOT EXISTS public.merchant_referral_commission_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  owner_role text NOT NULL CHECK (owner_role IN ('VERIFIKATOR', 'ADMIN_DESA')),
  merchant_id uuid REFERENCES public.merchants(id) ON DELETE RESTRICT,
  referral_code_id uuid REFERENCES public.merchant_referral_codes(id) ON DELETE SET NULL,
  source_order_id uuid REFERENCES public.orders(id) ON DELETE RESTRICT,
  source_fee_ledger_id uuid REFERENCES public.commission_wallet_ledger(id) ON DELETE RESTRICT,
  funding_wallet_ledger_id uuid REFERENCES public.commission_wallet_ledger(id) ON DELETE RESTRICT,
  payout_request_id uuid REFERENCES public.merchant_referral_payout_requests(id) ON DELETE RESTRICT,
  entry_type text NOT NULL CHECK (entry_type IN ('EARNING', 'REFUND_REVERSAL', 'WITHDRAWAL')),
  amount_rupiah bigint NOT NULL CHECK (
    (entry_type = 'EARNING' AND amount_rupiah > 0)
    OR (entry_type IN ('REFUND_REVERSAL', 'WITHDRAWAL') AND amount_rupiah < 0)
  ),
  fee_collected_base_rupiah bigint NOT NULL DEFAULT 0 CHECK (fee_collected_base_rupiah >= 0),
  commission_percent numeric(7,4) NOT NULL CHECK (commission_percent BETWEEN 0 AND 100),
  release_at timestamptz NOT NULL DEFAULT now(),
  idempotency_key text NOT NULL UNIQUE,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
)$bootstrap_sql_5250d5fcc61c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5250d5fcc61c$$bootstrap_sql_cf03903ce259$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf03903ce259$;

DO $bootstrap_do_9190602ab180$
BEGIN
  EXECUTE $bootstrap_sql_9190602ab180$DO $bootstrap_do_b9dc4eef93f8$
BEGIN
  EXECUTE $bootstrap_sql_b9dc4eef93f8$CREATE INDEX IF NOT EXISTS merchant_referral_ledger_owner_created_idx
  ON public.merchant_referral_commission_ledger(owner_user_id, created_at DESC, id DESC)$bootstrap_sql_b9dc4eef93f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b9dc4eef93f8$$bootstrap_sql_9190602ab180$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9190602ab180$;

DO $bootstrap_do_19fb2e3ae507$
BEGIN
  EXECUTE $bootstrap_sql_19fb2e3ae507$DO $bootstrap_do_d5209920b5e8$
BEGIN
  EXECUTE $bootstrap_sql_d5209920b5e8$CREATE INDEX IF NOT EXISTS merchant_referral_ledger_source_idx
  ON public.merchant_referral_commission_ledger(source_fee_ledger_id, created_at)$bootstrap_sql_d5209920b5e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d5209920b5e8$$bootstrap_sql_19fb2e3ae507$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19fb2e3ae507$;

DO $bootstrap_do_6785d29fa1c9$
BEGIN
  EXECUTE $bootstrap_sql_6785d29fa1c9$DO $bootstrap_do_0394e49b2c9d$
BEGIN
  EXECUTE $bootstrap_sql_0394e49b2c9d$ALTER TABLE public.merchant_referral_commission_settings ENABLE ROW LEVEL SECURITY$bootstrap_sql_0394e49b2c9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0394e49b2c9d$$bootstrap_sql_6785d29fa1c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6785d29fa1c9$;

DO $bootstrap_do_770eb17cd471$
BEGIN
  EXECUTE $bootstrap_sql_770eb17cd471$DO $bootstrap_do_b04d7af23a10$
BEGIN
  EXECUTE $bootstrap_sql_b04d7af23a10$DROP POLICY IF EXISTS merchant_referral_settings_read ON public.merchant_referral_commission_settings$bootstrap_sql_b04d7af23a10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b04d7af23a10$$bootstrap_sql_770eb17cd471$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_770eb17cd471$;

DO $bootstrap_do_6093ecf2a663$
BEGIN
  EXECUTE $bootstrap_sql_6093ecf2a663$DO $bootstrap_do_bfe556bc364d$
BEGIN
  EXECUTE $bootstrap_sql_bfe556bc364d$CREATE POLICY merchant_referral_settings_read ON public.merchant_referral_commission_settings
  FOR SELECT TO authenticated USING (true)$bootstrap_sql_bfe556bc364d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfe556bc364d$$bootstrap_sql_6093ecf2a663$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6093ecf2a663$;

DO $bootstrap_do_2d2040ef5515$
BEGIN
  EXECUTE $bootstrap_sql_2d2040ef5515$DO $bootstrap_do_926e2406bd01$
BEGIN
  EXECUTE $bootstrap_sql_926e2406bd01$DROP POLICY IF EXISTS merchant_referral_settings_admin_write ON public.merchant_referral_commission_settings$bootstrap_sql_926e2406bd01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_926e2406bd01$$bootstrap_sql_2d2040ef5515$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d2040ef5515$;

DO $bootstrap_do_f849cef7a13a$
BEGIN
  EXECUTE $bootstrap_sql_f849cef7a13a$DO $bootstrap_do_d2e435f50d2d$
BEGIN
  EXECUTE $bootstrap_sql_d2e435f50d2d$CREATE POLICY merchant_referral_settings_admin_write ON public.merchant_referral_commission_settings
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$bootstrap_sql_d2e435f50d2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d2e435f50d2d$$bootstrap_sql_f849cef7a13a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f849cef7a13a$;

DO $bootstrap_do_473093821505$
BEGIN
  EXECUTE $bootstrap_sql_473093821505$DO $bootstrap_do_b11e7763b3ce$
BEGIN
  EXECUTE $bootstrap_sql_b11e7763b3ce$GRANT SELECT, INSERT, UPDATE ON public.merchant_referral_commission_settings TO authenticated$bootstrap_sql_b11e7763b3ce$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b11e7763b3ce$$bootstrap_sql_473093821505$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_473093821505$;

DO $bootstrap_do_c2f100f056f0$
BEGIN
  EXECUTE $bootstrap_sql_c2f100f056f0$DO $bootstrap_do_82c8bfc35ecd$
BEGIN
  EXECUTE $bootstrap_sql_82c8bfc35ecd$GRANT ALL ON public.merchant_referral_commission_settings TO service_role$bootstrap_sql_82c8bfc35ecd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_82c8bfc35ecd$$bootstrap_sql_c2f100f056f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2f100f056f0$;

DO $bootstrap_do_beb56af19d93$
BEGIN
  EXECUTE $bootstrap_sql_beb56af19d93$DO $bootstrap_do_181dab436ecc$
BEGIN
  EXECUTE $bootstrap_sql_181dab436ecc$ALTER TABLE public.merchant_referral_codes ENABLE ROW LEVEL SECURITY$bootstrap_sql_181dab436ecc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_181dab436ecc$$bootstrap_sql_beb56af19d93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_beb56af19d93$;

DO $bootstrap_do_69bd112fb33f$
BEGIN
  EXECUTE $bootstrap_sql_69bd112fb33f$DO $bootstrap_do_791f73231657$
BEGIN
  EXECUTE $bootstrap_sql_791f73231657$DROP POLICY IF EXISTS merchant_referral_codes_public_active_read ON public.merchant_referral_codes$bootstrap_sql_791f73231657$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_791f73231657$$bootstrap_sql_69bd112fb33f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_69bd112fb33f$;

DO $bootstrap_do_5685d1ed407a$
BEGIN
  EXECUTE $bootstrap_sql_5685d1ed407a$DO $bootstrap_do_5105e57b7f92$
BEGIN
  EXECUTE $bootstrap_sql_5105e57b7f92$DROP POLICY IF EXISTS merchant_referral_codes_owner_admin_read ON public.merchant_referral_codes$bootstrap_sql_5105e57b7f92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5105e57b7f92$$bootstrap_sql_5685d1ed407a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5685d1ed407a$;

DO $bootstrap_do_7458f9c87ce2$
BEGIN
  EXECUTE $bootstrap_sql_7458f9c87ce2$DO $bootstrap_do_916ebd8b1dc4$
BEGIN
  EXECUTE $bootstrap_sql_916ebd8b1dc4$CREATE POLICY merchant_referral_codes_owner_admin_read ON public.merchant_referral_codes
  FOR SELECT TO authenticated USING (owner_user_id = auth.uid() OR public.is_admin())$bootstrap_sql_916ebd8b1dc4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_916ebd8b1dc4$$bootstrap_sql_7458f9c87ce2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7458f9c87ce2$;

DO $bootstrap_do_e24161f4af95$
BEGIN
  EXECUTE $bootstrap_sql_e24161f4af95$DO $bootstrap_do_d823d5917a7c$
BEGIN
  EXECUTE $bootstrap_sql_d823d5917a7c$DROP POLICY IF EXISTS merchant_referral_codes_admin_desa_update ON public.merchant_referral_codes$bootstrap_sql_d823d5917a7c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d823d5917a7c$$bootstrap_sql_e24161f4af95$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e24161f4af95$;

DO $bootstrap_do_47bb8a653e7e$
BEGIN
  EXECUTE $bootstrap_sql_47bb8a653e7e$DO $bootstrap_do_befd322b8b8c$
BEGIN
  EXECUTE $bootstrap_sql_befd322b8b8c$CREATE POLICY merchant_referral_codes_admin_desa_update ON public.merchant_referral_codes
  FOR UPDATE TO authenticated USING (owner_user_id = auth.uid() AND owner_role = 'ADMIN_DESA' OR public.is_admin())
  WITH CHECK (owner_user_id = auth.uid() AND owner_role = 'ADMIN_DESA' OR public.is_admin())$bootstrap_sql_befd322b8b8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_befd322b8b8c$$bootstrap_sql_47bb8a653e7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47bb8a653e7e$;

DO $bootstrap_do_1416dc3a5e71$
BEGIN
  EXECUTE $bootstrap_sql_1416dc3a5e71$DO $bootstrap_do_f0c91b4bfec6$
BEGIN
  EXECUTE $bootstrap_sql_f0c91b4bfec6$REVOKE SELECT ON public.merchant_referral_codes FROM anon$bootstrap_sql_f0c91b4bfec6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f0c91b4bfec6$$bootstrap_sql_1416dc3a5e71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1416dc3a5e71$;

DO $bootstrap_do_a7699806525e$
BEGIN
  EXECUTE $bootstrap_sql_a7699806525e$DO $bootstrap_do_2d1e3902b7e1$
BEGIN
  EXECUTE $bootstrap_sql_2d1e3902b7e1$GRANT SELECT ON public.merchant_referral_codes TO authenticated$bootstrap_sql_2d1e3902b7e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d1e3902b7e1$$bootstrap_sql_a7699806525e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a7699806525e$;

DO $bootstrap_do_f7e6dadde9aa$
BEGIN
  EXECUTE $bootstrap_sql_f7e6dadde9aa$DO $bootstrap_do_e774331aa44b$
BEGIN
  EXECUTE $bootstrap_sql_e774331aa44b$GRANT UPDATE (is_active) ON public.merchant_referral_codes TO authenticated$bootstrap_sql_e774331aa44b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e774331aa44b$$bootstrap_sql_f7e6dadde9aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f7e6dadde9aa$;

DO $bootstrap_do_7e988e8a7528$
BEGIN
  EXECUTE $bootstrap_sql_7e988e8a7528$DO $bootstrap_do_79240b4c307d$
BEGIN
  EXECUTE $bootstrap_sql_79240b4c307d$GRANT ALL ON public.merchant_referral_codes TO service_role$bootstrap_sql_79240b4c307d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79240b4c307d$$bootstrap_sql_7e988e8a7528$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7e988e8a7528$;

DO $bootstrap_do_124d2c84374b$
BEGIN
  EXECUTE $bootstrap_sql_124d2c84374b$DO $bootstrap_do_b98e74b66a24$
BEGIN
  EXECUTE $bootstrap_sql_b98e74b66a24$ALTER TABLE public.merchant_referral_fee_sources ENABLE ROW LEVEL SECURITY$bootstrap_sql_b98e74b66a24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b98e74b66a24$$bootstrap_sql_124d2c84374b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_124d2c84374b$;

DO $bootstrap_do_40c5ed9cb7d3$
BEGIN
  EXECUTE $bootstrap_sql_40c5ed9cb7d3$DO $bootstrap_do_27d09bb99626$
BEGIN
  EXECUTE $bootstrap_sql_27d09bb99626$ALTER TABLE public.merchant_referral_fee_collection_allocations ENABLE ROW LEVEL SECURITY$bootstrap_sql_27d09bb99626$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_27d09bb99626$$bootstrap_sql_40c5ed9cb7d3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_40c5ed9cb7d3$;

DO $bootstrap_do_9f807b9e8d24$
BEGIN
  EXECUTE $bootstrap_sql_9f807b9e8d24$DO $bootstrap_do_ebcd6c2388a8$
BEGIN
  EXECUTE $bootstrap_sql_ebcd6c2388a8$ALTER TABLE public.merchant_referral_commission_ledger ENABLE ROW LEVEL SECURITY$bootstrap_sql_ebcd6c2388a8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ebcd6c2388a8$$bootstrap_sql_9f807b9e8d24$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f807b9e8d24$;

DO $bootstrap_do_babb4629146f$
BEGIN
  EXECUTE $bootstrap_sql_babb4629146f$DO $bootstrap_do_69fa4a825eef$
BEGIN
  EXECUTE $bootstrap_sql_69fa4a825eef$ALTER TABLE public.merchant_referral_payout_requests ENABLE ROW LEVEL SECURITY$bootstrap_sql_69fa4a825eef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_69fa4a825eef$$bootstrap_sql_babb4629146f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_babb4629146f$;

DO $bootstrap_do_3c9e0370d50f$
BEGIN
  EXECUTE $bootstrap_sql_3c9e0370d50f$DO $bootstrap_do_17fd1e21a574$
BEGIN
  EXECUTE $bootstrap_sql_17fd1e21a574$DROP POLICY IF EXISTS merchant_referral_ledger_owner_admin_read ON public.merchant_referral_commission_ledger$bootstrap_sql_17fd1e21a574$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_17fd1e21a574$$bootstrap_sql_3c9e0370d50f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c9e0370d50f$;

DO $bootstrap_do_7d3a0b348a07$
BEGIN
  EXECUTE $bootstrap_sql_7d3a0b348a07$DO $bootstrap_do_d3dd9eae3311$
BEGIN
  EXECUTE $bootstrap_sql_d3dd9eae3311$CREATE POLICY merchant_referral_ledger_owner_admin_read ON public.merchant_referral_commission_ledger
  FOR SELECT TO authenticated USING (owner_user_id = auth.uid() OR public.is_admin())$bootstrap_sql_d3dd9eae3311$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d3dd9eae3311$$bootstrap_sql_7d3a0b348a07$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7d3a0b348a07$;

DO $bootstrap_do_8259daf19eb0$
BEGIN
  EXECUTE $bootstrap_sql_8259daf19eb0$DO $bootstrap_do_7aafd545dd98$
BEGIN
  EXECUTE $bootstrap_sql_7aafd545dd98$DROP POLICY IF EXISTS merchant_referral_payout_owner_admin_read ON public.merchant_referral_payout_requests$bootstrap_sql_7aafd545dd98$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7aafd545dd98$$bootstrap_sql_8259daf19eb0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8259daf19eb0$;

DO $bootstrap_do_9df4e1fe6e86$
BEGIN
  EXECUTE $bootstrap_sql_9df4e1fe6e86$DO $bootstrap_do_23385ae24fed$
BEGIN
  EXECUTE $bootstrap_sql_23385ae24fed$CREATE POLICY merchant_referral_payout_owner_admin_read ON public.merchant_referral_payout_requests
  FOR SELECT TO authenticated USING (owner_user_id = auth.uid() OR public.is_admin())$bootstrap_sql_23385ae24fed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23385ae24fed$$bootstrap_sql_9df4e1fe6e86$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9df4e1fe6e86$;

DO $bootstrap_do_63684a4e632f$
BEGIN
  EXECUTE $bootstrap_sql_63684a4e632f$DO $bootstrap_do_4bfb51971210$
BEGIN
  EXECUTE $bootstrap_sql_4bfb51971210$DROP POLICY IF EXISTS merchant_referral_source_admin_read ON public.merchant_referral_fee_sources$bootstrap_sql_4bfb51971210$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4bfb51971210$$bootstrap_sql_63684a4e632f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_63684a4e632f$;

DO $bootstrap_do_d05d31d28f41$
BEGIN
  EXECUTE $bootstrap_sql_d05d31d28f41$DO $bootstrap_do_f1e397dfdf63$
BEGIN
  EXECUTE $bootstrap_sql_f1e397dfdf63$CREATE POLICY merchant_referral_source_admin_read ON public.merchant_referral_fee_sources
  FOR SELECT TO authenticated USING (public.is_admin())$bootstrap_sql_f1e397dfdf63$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f1e397dfdf63$$bootstrap_sql_d05d31d28f41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d05d31d28f41$;

DO $bootstrap_do_7db93f544638$
BEGIN
  EXECUTE $bootstrap_sql_7db93f544638$DO $bootstrap_do_01e745750740$
BEGIN
  EXECUTE $bootstrap_sql_01e745750740$DROP POLICY IF EXISTS merchant_referral_alloc_admin_read ON public.merchant_referral_fee_collection_allocations$bootstrap_sql_01e745750740$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_01e745750740$$bootstrap_sql_7db93f544638$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7db93f544638$;

DO $bootstrap_do_856cb7760cc5$
BEGIN
  EXECUTE $bootstrap_sql_856cb7760cc5$DO $bootstrap_do_a61f9f9663aa$
BEGIN
  EXECUTE $bootstrap_sql_a61f9f9663aa$CREATE POLICY merchant_referral_alloc_admin_read ON public.merchant_referral_fee_collection_allocations
  FOR SELECT TO authenticated USING (public.is_admin())$bootstrap_sql_a61f9f9663aa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a61f9f9663aa$$bootstrap_sql_856cb7760cc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_856cb7760cc5$;

DO $bootstrap_do_b028caf15d5f$
BEGIN
  EXECUTE $bootstrap_sql_b028caf15d5f$DO $bootstrap_do_fc76faa363fa$
BEGIN
  EXECUTE $bootstrap_sql_fc76faa363fa$GRANT SELECT ON public.merchant_referral_commission_ledger, public.merchant_referral_payout_requests,
  public.merchant_referral_fee_sources, public.merchant_referral_fee_collection_allocations TO authenticated$bootstrap_sql_fc76faa363fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc76faa363fa$$bootstrap_sql_b028caf15d5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b028caf15d5f$;

DO $bootstrap_do_ec28d5b93baa$
BEGIN
  EXECUTE $bootstrap_sql_ec28d5b93baa$DO $bootstrap_do_c8f976c818b3$
BEGIN
  EXECUTE $bootstrap_sql_c8f976c818b3$GRANT ALL ON public.merchant_referral_commission_ledger, public.merchant_referral_payout_requests,
  public.merchant_referral_fee_sources, public.merchant_referral_fee_collection_allocations TO service_role$bootstrap_sql_c8f976c818b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c8f976c818b3$$bootstrap_sql_ec28d5b93baa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ec28d5b93baa$;

DO $bootstrap_do_da65a68af242$
BEGIN
  EXECUTE $bootstrap_sql_da65a68af242$DO $bootstrap_do_b020361c5abc$
BEGIN
  EXECUTE $bootstrap_sql_b020361c5abc$CREATE OR REPLACE FUNCTION public.check_merchant_referral_code(p_code text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'valid', EXISTS (
      SELECT 1 FROM public.merchant_referral_codes c
      WHERE c.code = upper(trim(COALESCE(p_code, ''))) AND c.is_active
        AND (c.max_usage IS NULL OR c.usage_count < c.max_usage)
    ),
    'owner_role', (
      SELECT c.owner_role FROM public.merchant_referral_codes c
      WHERE c.code = upper(trim(COALESCE(p_code, ''))) AND c.is_active
        AND (c.max_usage IS NULL OR c.usage_count < c.max_usage)
      LIMIT 1
    )
  );
$$$bootstrap_sql_b020361c5abc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b020361c5abc$$bootstrap_sql_da65a68af242$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da65a68af242$;

DO $bootstrap_do_52912d667c34$
BEGIN
  EXECUTE $bootstrap_sql_52912d667c34$DO $bootstrap_do_f15af1196d76$
BEGIN
  EXECUTE $bootstrap_sql_f15af1196d76$REVOKE ALL ON FUNCTION public.check_merchant_referral_code(text) FROM PUBLIC$bootstrap_sql_f15af1196d76$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f15af1196d76$$bootstrap_sql_52912d667c34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_52912d667c34$;

DO $bootstrap_do_50621d447a13$
BEGIN
  EXECUTE $bootstrap_sql_50621d447a13$DO $bootstrap_do_006801ea9763$
BEGIN
  EXECUTE $bootstrap_sql_006801ea9763$GRANT EXECUTE ON FUNCTION public.check_merchant_referral_code(text) TO anon, authenticated$bootstrap_sql_006801ea9763$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_006801ea9763$$bootstrap_sql_50621d447a13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_50621d447a13$;

DO $bootstrap_do_738550c87e28$
BEGIN
  EXECUTE $bootstrap_sql_738550c87e28$DO $bootstrap_do_307432b25e34$
BEGIN
  EXECUTE $bootstrap_sql_307432b25e34$CREATE OR REPLACE FUNCTION public.create_admin_desa_referral_code(p_code text, p_description text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_village_id uuid;
  v_id uuid;
  v_code text := upper(trim(COALESCE(p_code, '')));
BEGIN
  IF v_user_id IS NULL OR NOT public.has_role(v_user_id, 'admin_desa') THEN
    RAISE EXCEPTION 'Hanya admin desa yang dapat membuat kode referral' USING ERRCODE = '42501';
  END IF;
  IF v_code !~ '^[A-Z0-9_-]{3,32}$' THEN
    RAISE EXCEPTION 'Format kode referral harus 3–32 karakter A-Z, 0-9, _ atau -' USING ERRCODE = '22023';
  END IF;
  SELECT uv.village_id INTO v_village_id
  FROM public.user_villages uv
  JOIN public.villages v ON v.id = uv.village_id
  WHERE uv.user_id = v_user_id AND uv.role = 'admin_desa'
    AND v.registration_status = 'APPROVED' AND v.is_active = true
  ORDER BY uv.created_at DESC LIMIT 1;
  IF v_village_id IS NULL THEN
    RAISE EXCEPTION 'Akun belum terhubung dengan desa yang disetujui' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.verifikator_codes WHERE upper(code) = v_code)
     OR EXISTS (SELECT 1 FROM public.merchant_referral_codes WHERE code = v_code) THEN
    RAISE EXCEPTION 'Kode referral sudah digunakan' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.merchant_referral_codes(code, owner_user_id, owner_role, village_id, description)
  VALUES (v_code, v_user_id, 'ADMIN_DESA', v_village_id, NULLIF(trim(p_description), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$$bootstrap_sql_307432b25e34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_307432b25e34$$bootstrap_sql_738550c87e28$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_738550c87e28$;

DO $bootstrap_do_8ad89c1193d1$
BEGIN
  EXECUTE $bootstrap_sql_8ad89c1193d1$DO $bootstrap_do_47a29d29536c$
BEGIN
  EXECUTE $bootstrap_sql_47a29d29536c$REVOKE ALL ON FUNCTION public.create_admin_desa_referral_code(text, text) FROM PUBLIC, anon$bootstrap_sql_47a29d29536c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_47a29d29536c$$bootstrap_sql_8ad89c1193d1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8ad89c1193d1$;

DO $bootstrap_do_dc82d82bfa2b$
BEGIN
  EXECUTE $bootstrap_sql_dc82d82bfa2b$DO $bootstrap_do_4300fa1438bf$
BEGIN
  EXECUTE $bootstrap_sql_4300fa1438bf$GRANT EXECUTE ON FUNCTION public.create_admin_desa_referral_code(text, text) TO authenticated$bootstrap_sql_4300fa1438bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4300fa1438bf$$bootstrap_sql_dc82d82bfa2b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc82d82bfa2b$;

DO $bootstrap_do_dcdac32e5ddd$
BEGIN
  EXECUTE $bootstrap_sql_dcdac32e5ddd$DO $bootstrap_do_9dcbdec56b9a$
BEGIN
  EXECUTE $bootstrap_sql_9dcbdec56b9a$CREATE OR REPLACE FUNCTION public.post_merchant_referral_fee_collection(
  p_fee_source_id uuid, p_funding_wallet_ledger_id uuid, p_collected_amount_rupiah bigint
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_source public.merchant_referral_fee_sources%ROWTYPE;
  v_allocation_id uuid;
  v_new_recorded bigint;
  v_delta bigint;
BEGIN
  IF p_collected_amount_rupiah <= 0 THEN RETURN 0; END IF;
  SELECT * INTO v_source FROM public.merchant_referral_fee_sources
  WHERE id = p_fee_source_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 0; END IF;
  IF v_source.outstanding_debt_rupiah < p_collected_amount_rupiah THEN
    RAISE EXCEPTION 'alokasi pelunasan referral melebihi debt source' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.merchant_referral_fee_collection_allocations(
    fee_source_id, funding_wallet_ledger_id, collected_amount_rupiah
  ) VALUES (v_source.id, p_funding_wallet_ledger_id, p_collected_amount_rupiah)
  ON CONFLICT (fee_source_id, funding_wallet_ledger_id) DO NOTHING
  RETURNING id INTO v_allocation_id;
  IF v_allocation_id IS NULL THEN RETURN 0; END IF;

  UPDATE public.merchant_referral_fee_sources
  SET fee_collected_rupiah = fee_collected_rupiah + p_collected_amount_rupiah,
      outstanding_debt_rupiah = outstanding_debt_rupiah - p_collected_amount_rupiah
  WHERE id = v_source.id
  RETURNING * INTO v_source;
  IF v_source.referrer_user_id IS NULL OR v_source.referral_percent <= 0 THEN RETURN 0; END IF;

  v_new_recorded := round(GREATEST(v_source.fee_collected_rupiah - v_source.refunded_collected_rupiah, 0)::numeric * v_source.referral_percent / 100)::bigint;
  v_delta := v_new_recorded - v_source.referral_amount_recorded_rupiah;
  UPDATE public.merchant_referral_fee_sources
  SET referral_amount_recorded_rupiah = v_new_recorded WHERE id = v_source.id;
  IF v_delta > 0 THEN
    INSERT INTO public.merchant_referral_commission_ledger(
      owner_user_id, owner_role, merchant_id, referral_code_id, source_order_id,
      source_fee_ledger_id, funding_wallet_ledger_id, entry_type, amount_rupiah,
      fee_collected_base_rupiah, commission_percent, release_at, idempotency_key,
      note
    ) VALUES (
      v_source.referrer_user_id, v_source.referrer_role, v_source.merchant_id, v_source.referral_code_id,
      v_source.source_order_id, v_source.source_fee_ledger_id, p_funding_wallet_ledger_id,
      'EARNING', v_delta, p_collected_amount_rupiah, v_source.referral_percent,
      v_source.release_at, 'referral-earned:' || v_allocation_id::text,
      'Bagi hasil dari fee komisi merchant yang tertagih'
    );
  END IF;
  RETURN GREATEST(v_delta, 0);
END;
$$$bootstrap_sql_9dcbdec56b9a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9dcbdec56b9a$$bootstrap_sql_dcdac32e5ddd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dcdac32e5ddd$;

DO $bootstrap_do_9e1775a963f0$
BEGIN
  EXECUTE $bootstrap_sql_9e1775a963f0$DO $bootstrap_do_9af47506d7e2$
BEGIN
  EXECUTE $bootstrap_sql_9af47506d7e2$REVOKE ALL ON FUNCTION public.post_merchant_referral_fee_collection(uuid, uuid, bigint) FROM PUBLIC, anon, authenticated$bootstrap_sql_9af47506d7e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9af47506d7e2$$bootstrap_sql_9e1775a963f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e1775a963f0$;

DO $bootstrap_do_23fa8be39b40$
BEGIN
  EXECUTE $bootstrap_sql_23fa8be39b40$DO $bootstrap_do_49aa439624f9$
BEGIN
  EXECUTE $bootstrap_sql_49aa439624f9$GRANT EXECUTE ON FUNCTION public.post_merchant_referral_fee_collection(uuid, uuid, bigint) TO service_role$bootstrap_sql_49aa439624f9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49aa439624f9$$bootstrap_sql_23fa8be39b40$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_23fa8be39b40$;

DO $bootstrap_do_88465a036263$
BEGIN
  EXECUTE $bootstrap_sql_88465a036263$DO $bootstrap_do_397211f6f098$
BEGIN
  EXECUTE $bootstrap_sql_397211f6f098$CREATE OR REPLACE FUNCTION public.process_merchant_referral_wallet_ledger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_wallet public.commission_wallets%ROWTYPE;
  v_merchant public.merchants%ROWTYPE;
  v_setting public.merchant_referral_commission_settings%ROWTYPE;
  v_order_completed timestamptz;
  v_refund_window integer;
  v_fee_total bigint;
  v_collected bigint;
  v_source_id uuid;
  v_remaining bigint;
  v_alloc bigint;
  v_source record;
BEGIN
  SELECT * INTO v_wallet FROM public.commission_wallets WHERE id = NEW.wallet_id;
  IF NOT FOUND OR v_wallet.owner_type <> 'MERCHANT' THEN RETURN NEW; END IF;

  IF NEW.entry_type = 'COMMISSION' AND NEW.source_type = 'ORDER' AND NEW.source_id IS NOT NULL THEN
    SELECT * INTO v_merchant FROM public.merchants WHERE id = v_wallet.merchant_id;
    SELECT * INTO v_setting FROM public.merchant_referral_commission_settings
      WHERE owner_role = v_merchant.referral_owner_role AND is_enabled = true;
    SELECT COALESCE(refund_window_days, 7) INTO v_refund_window
      FROM public.commission_wallet_policy_settings WHERE id = true;
    SELECT max(h.created_at) INTO v_order_completed
      FROM public.order_status_history h
      WHERE h.order_id = NEW.source_id AND upper(h.to_status) IN ('DONE', 'DELIVERED', 'COMPLETED');
    SELECT COALESCE(v_order_completed, o.updated_at, now()) INTO v_order_completed
      FROM public.orders o WHERE o.id = NEW.source_id;
    v_fee_total := GREATEST(-NEW.amount_delta_rupiah + NEW.debt_delta_rupiah, 0);
    v_collected := GREATEST(-NEW.amount_delta_rupiah, 0);
    INSERT INTO public.merchant_referral_fee_sources(
      wallet_id, source_fee_ledger_id, source_order_id, merchant_id, referral_code_id,
      referrer_user_id, referrer_role, fee_amount_rupiah, fee_collected_rupiah,
      outstanding_debt_rupiah, referral_percent, release_at
    ) VALUES (
      NEW.wallet_id, NEW.id, NEW.source_id, v_wallet.merchant_id, v_merchant.referral_code_id,
      v_merchant.referral_owner_user_id, v_merchant.referral_owner_role,
      v_fee_total, 0, v_fee_total,
      CASE WHEN COALESCE(v_setting.is_enabled, false) THEN COALESCE(v_setting.commission_percent, 0) ELSE 0 END,
      COALESCE(v_order_completed, now()) + make_interval(days => COALESCE(v_refund_window, 7))
    )
    ON CONFLICT (source_fee_ledger_id) DO NOTHING
    RETURNING id INTO v_source_id;
    IF v_source_id IS NOT NULL AND v_collected > 0 THEN
      PERFORM public.post_merchant_referral_fee_collection(v_source_id, NEW.id, v_collected);
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.entry_type = 'TOPUP' AND -NEW.debt_delta_rupiah > 0 THEN
    v_remaining := -NEW.debt_delta_rupiah;
    FOR v_source IN
      SELECT id, outstanding_debt_rupiah
      FROM public.merchant_referral_fee_sources
      WHERE wallet_id = NEW.wallet_id AND outstanding_debt_rupiah > 0
      ORDER BY is_legacy_debt DESC, created_at, id
      FOR UPDATE
    LOOP
      EXIT WHEN v_remaining <= 0;
      v_alloc := LEAST(v_remaining, v_source.outstanding_debt_rupiah);
      PERFORM public.post_merchant_referral_fee_collection(v_source.id, NEW.id, v_alloc);
      v_remaining := v_remaining - v_alloc;
    END LOOP;
    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'pelunasan debt merchant tidak memiliki sumber fee terpetakan' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_397211f6f098$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_397211f6f098$$bootstrap_sql_88465a036263$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88465a036263$;

DO $bootstrap_do_857582efb4ef$
BEGIN
  EXECUTE $bootstrap_sql_857582efb4ef$DO $bootstrap_do_afff207677b0$
BEGIN
  EXECUTE $bootstrap_sql_afff207677b0$DROP TRIGGER IF EXISTS process_merchant_referral_wallet_ledger ON public.commission_wallet_ledger$bootstrap_sql_afff207677b0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_afff207677b0$$bootstrap_sql_857582efb4ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_857582efb4ef$;

DO $bootstrap_do_0e6829c41009$
BEGIN
  EXECUTE $bootstrap_sql_0e6829c41009$DO $bootstrap_do_33d1820162a4$
BEGIN
  EXECUTE $bootstrap_sql_33d1820162a4$CREATE TRIGGER process_merchant_referral_wallet_ledger
AFTER INSERT ON public.commission_wallet_ledger
FOR EACH ROW EXECUTE FUNCTION public.process_merchant_referral_wallet_ledger()$bootstrap_sql_33d1820162a4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33d1820162a4$$bootstrap_sql_0e6829c41009$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0e6829c41009$;

DO $bootstrap_do_d22559637d82$
BEGIN
  EXECUTE $bootstrap_sql_d22559637d82$DO $bootstrap_do_551965c5a40e$
BEGIN
  EXECUTE $bootstrap_sql_551965c5a40e$REVOKE ALL ON FUNCTION public.process_merchant_referral_wallet_ledger() FROM PUBLIC, anon, authenticated$bootstrap_sql_551965c5a40e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_551965c5a40e$$bootstrap_sql_d22559637d82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d22559637d82$;

DO $bootstrap_do_cbf80595ce2e$
BEGIN
  EXECUTE $bootstrap_sql_cbf80595ce2e$DO $bootstrap_do_53cd0ad47f57$
BEGIN
  EXECUTE $bootstrap_sql_53cd0ad47f57$CREATE OR REPLACE FUNCTION public.get_merchant_referral_merchants(p_owner_role text)
RETURNS TABLE (
  merchant_id uuid, merchant_name text, registration_status text,
  fee_collected_rupiah bigint, referral_earned_rupiah bigint,
  recorded_fee_transactions bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_role text := upper(trim(p_owner_role));
BEGIN
  IF auth.uid() IS NULL OR v_role NOT IN ('VERIFIKATOR', 'ADMIN_DESA')
     OR NOT public.has_role(auth.uid(), lower(v_role)::public.app_role) THEN
    RAISE EXCEPTION 'Tidak berhak melihat daftar merchant referral ini' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT m.id, m.name, m.registration_status,
         COALESCE(f.fee_collected, 0)::bigint,
         COALESCE(e.referral_earned, 0)::bigint,
         COALESCE(f.fee_sources, 0)::bigint
  FROM public.merchants m
  LEFT JOIN LATERAL (
    SELECT sum(s.fee_collected_rupiah - s.refunded_collected_rupiah) AS fee_collected,
           count(*) AS fee_sources
    FROM public.merchant_referral_fee_sources s
    WHERE s.merchant_id = m.id AND s.referrer_user_id = auth.uid() AND s.referrer_role = v_role
  ) f ON true
  LEFT JOIN LATERAL (
    SELECT sum(l.amount_rupiah) AS referral_earned
    FROM public.merchant_referral_commission_ledger l
    WHERE l.merchant_id = m.id AND l.owner_user_id = auth.uid() AND l.owner_role = v_role
      AND l.entry_type IN ('EARNING', 'REFUND_REVERSAL')
  ) e ON true
  WHERE m.referral_owner_user_id = auth.uid() AND m.referral_owner_role = v_role
  ORDER BY m.created_at DESC;
END;
$$$bootstrap_sql_53cd0ad47f57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_53cd0ad47f57$$bootstrap_sql_cbf80595ce2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cbf80595ce2e$;

DO $bootstrap_do_16272e77d746$
BEGIN
  EXECUTE $bootstrap_sql_16272e77d746$DO $bootstrap_do_2e8a23bf2e0b$
BEGIN
  EXECUTE $bootstrap_sql_2e8a23bf2e0b$REVOKE ALL ON FUNCTION public.get_merchant_referral_merchants(text) FROM PUBLIC, anon$bootstrap_sql_2e8a23bf2e0b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e8a23bf2e0b$$bootstrap_sql_16272e77d746$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_16272e77d746$;

DO $bootstrap_do_3679bd1fca19$
BEGIN
  EXECUTE $bootstrap_sql_3679bd1fca19$DO $bootstrap_do_92097eba07c9$
BEGIN
  EXECUTE $bootstrap_sql_92097eba07c9$GRANT EXECUTE ON FUNCTION public.get_merchant_referral_merchants(text) TO authenticated$bootstrap_sql_92097eba07c9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_92097eba07c9$$bootstrap_sql_3679bd1fca19$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3679bd1fca19$;

DO $bootstrap_do_71b89a9e3aa1$
BEGIN
  EXECUTE $bootstrap_sql_71b89a9e3aa1$DO $bootstrap_do_e96974efec62$
BEGIN
  EXECUTE $bootstrap_sql_e96974efec62$CREATE OR REPLACE FUNCTION public.get_merchant_referral_commission_summary(p_owner_role text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_role text := upper(trim(p_owner_role));
  v_setting public.merchant_referral_commission_settings%ROWTYPE;
  v_pending bigint;
  v_available bigint;
  v_reserved bigint;
BEGIN
  IF auth.uid() IS NULL OR v_role NOT IN ('VERIFIKATOR', 'ADMIN_DESA')
     OR NOT public.has_role(auth.uid(), lower(v_role)::public.app_role) THEN
    RAISE EXCEPTION 'Tidak berhak melihat akun referral ini' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_setting FROM public.merchant_referral_commission_settings WHERE owner_role = v_role;
  SELECT COALESCE(sum(amount_rupiah) FILTER (WHERE release_at > now()), 0),
         COALESCE(sum(amount_rupiah) FILTER (WHERE release_at <= now()), 0)
  INTO v_pending, v_available
  FROM public.merchant_referral_commission_ledger
  WHERE owner_user_id = auth.uid() AND owner_role = v_role;
  SELECT COALESCE(sum(amount_rupiah), 0) INTO v_reserved
  FROM public.merchant_referral_payout_requests
  WHERE owner_user_id = auth.uid() AND owner_role = v_role AND status IN ('PENDING', 'APPROVED');
  RETURN jsonb_build_object(
    'owner_role', v_role,
    'commission_percent', COALESCE(v_setting.commission_percent, 0),
    'is_enabled', COALESCE(v_setting.is_enabled, false),
    'pending_rupiah', v_pending,
    'available_rupiah', v_available - v_reserved,
    'reserved_rupiah', v_reserved,
    'net_rupiah', v_pending + v_available
  );
END;
$$$bootstrap_sql_e96974efec62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e96974efec62$$bootstrap_sql_71b89a9e3aa1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71b89a9e3aa1$;

DO $bootstrap_do_ba1a91769ba6$
BEGIN
  EXECUTE $bootstrap_sql_ba1a91769ba6$DO $bootstrap_do_bbfc69ad408d$
BEGIN
  EXECUTE $bootstrap_sql_bbfc69ad408d$REVOKE ALL ON FUNCTION public.get_merchant_referral_commission_summary(text) FROM PUBLIC, anon$bootstrap_sql_bbfc69ad408d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbfc69ad408d$$bootstrap_sql_ba1a91769ba6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba1a91769ba6$;

DO $bootstrap_do_f758d1e8766e$
BEGIN
  EXECUTE $bootstrap_sql_f758d1e8766e$DO $bootstrap_do_6699a4af3355$
BEGIN
  EXECUTE $bootstrap_sql_6699a4af3355$GRANT EXECUTE ON FUNCTION public.get_merchant_referral_commission_summary(text) TO authenticated$bootstrap_sql_6699a4af3355$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6699a4af3355$$bootstrap_sql_f758d1e8766e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f758d1e8766e$;

DO $bootstrap_do_bab71a6a68cb$
BEGIN
  EXECUTE $bootstrap_sql_bab71a6a68cb$DO $bootstrap_do_b1a5c3048d8c$
BEGIN
  EXECUTE $bootstrap_sql_b1a5c3048d8c$CREATE OR REPLACE FUNCTION public.create_merchant_referral_payout_request(
  p_owner_role text, p_amount_rupiah bigint, p_bank_name text,
  p_account_number text, p_account_holder text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_role text := upper(trim(p_owner_role));
  v_available bigint;
  v_reserved bigint;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR v_role NOT IN ('VERIFIKATOR', 'ADMIN_DESA')
     OR NOT public.has_role(auth.uid(), lower(v_role)::public.app_role) THEN
    RAISE EXCEPTION 'Tidak berhak mengajukan penarikan referral' USING ERRCODE = '42501';
  END IF;
  IF p_amount_rupiah IS NULL OR p_amount_rupiah < 10000
     OR NULLIF(trim(COALESCE(p_bank_name, '')), '') IS NULL OR length(p_bank_name) > 80
     OR NULLIF(trim(COALESCE(p_account_number, '')), '') IS NULL OR length(p_account_number) > 80
     OR NULLIF(trim(COALESCE(p_account_holder, '')), '') IS NULL OR length(p_account_holder) > 120 THEN
    RAISE EXCEPTION 'Nominal minimum Rp10.000 dan data rekening wajib valid' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('referral-payout:' || auth.uid()::text || ':' || v_role, 0));
  SELECT COALESCE(sum(amount_rupiah), 0) INTO v_available
  FROM public.merchant_referral_commission_ledger
  WHERE owner_user_id = auth.uid() AND owner_role = v_role AND release_at <= now();
  SELECT COALESCE(sum(amount_rupiah), 0) INTO v_reserved
  FROM public.merchant_referral_payout_requests
  WHERE owner_user_id = auth.uid() AND owner_role = v_role AND status IN ('PENDING', 'APPROVED');
  IF p_amount_rupiah > v_available - v_reserved THEN
    RAISE EXCEPTION 'Saldo referral tersedia tidak mencukupi' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.merchant_referral_payout_requests(
    owner_user_id, owner_role, amount_rupiah, bank_name, account_number, account_holder
  ) VALUES (
    auth.uid(), v_role, p_amount_rupiah, trim(p_bank_name), trim(p_account_number), trim(p_account_holder)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$$bootstrap_sql_b1a5c3048d8c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b1a5c3048d8c$$bootstrap_sql_bab71a6a68cb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bab71a6a68cb$;

DO $bootstrap_do_fb1f7b42f6e8$
BEGIN
  EXECUTE $bootstrap_sql_fb1f7b42f6e8$DO $bootstrap_do_e7da2eb5b29b$
BEGIN
  EXECUTE $bootstrap_sql_e7da2eb5b29b$REVOKE ALL ON FUNCTION public.create_merchant_referral_payout_request(text, bigint, text, text, text) FROM PUBLIC, anon$bootstrap_sql_e7da2eb5b29b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7da2eb5b29b$$bootstrap_sql_fb1f7b42f6e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb1f7b42f6e8$;

DO $bootstrap_do_a6967bb2ddfb$
BEGIN
  EXECUTE $bootstrap_sql_a6967bb2ddfb$DO $bootstrap_do_2cdd0da95a49$
BEGIN
  EXECUTE $bootstrap_sql_2cdd0da95a49$GRANT EXECUTE ON FUNCTION public.create_merchant_referral_payout_request(text, bigint, text, text, text) TO authenticated$bootstrap_sql_2cdd0da95a49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2cdd0da95a49$$bootstrap_sql_a6967bb2ddfb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a6967bb2ddfb$;

DO $bootstrap_do_8d2bf8da6edd$
BEGIN
  EXECUTE $bootstrap_sql_8d2bf8da6edd$DO $bootstrap_do_86dc9a4fa263$
BEGIN
  EXECUTE $bootstrap_sql_86dc9a4fa263$CREATE OR REPLACE FUNCTION public.process_merchant_referral_payout(
  p_request_id uuid, p_status text, p_admin_notes text DEFAULT NULL,
  p_payout_reference text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.merchant_referral_payout_requests%ROWTYPE;
  v_status text := upper(trim(p_status));
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Hanya admin yang dapat memproses payout referral' USING ERRCODE = '42501'; END IF;
  IF v_status NOT IN ('APPROVED', 'PAID', 'REJECTED') THEN
    RAISE EXCEPTION 'Status payout tidak valid' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_request FROM public.merchant_referral_payout_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Permintaan payout tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
  IF v_request.status = v_status THEN
    RETURN jsonb_build_object('id', v_request.id, 'status', v_status, 'duplicate', true);
  END IF;
  IF v_status = 'APPROVED' THEN
    IF v_request.status <> 'PENDING' THEN RAISE EXCEPTION 'Hanya permintaan pending yang dapat disetujui'; END IF;
    UPDATE public.merchant_referral_payout_requests SET status = 'APPROVED', admin_notes = left(p_admin_notes, 1000), processed_by = auth.uid(), processed_at = now(), approved_by = auth.uid(), approved_at = now(), updated_at = now() WHERE id = p_request_id;
  ELSIF v_status = 'REJECTED' THEN
    IF v_request.status NOT IN ('PENDING', 'APPROVED') THEN RAISE EXCEPTION 'Status permintaan tidak dapat ditolak'; END IF;
    UPDATE public.merchant_referral_payout_requests SET status = 'REJECTED', admin_notes = left(p_admin_notes, 1000), processed_by = auth.uid(), processed_at = now(), updated_at = now() WHERE id = p_request_id;
  ELSE
    IF v_request.status <> 'APPROVED' THEN RAISE EXCEPTION 'Setujui permintaan sebelum menandai transfer telah dibayar'; END IF;
    IF NULLIF(trim(COALESCE(p_payout_reference, '')), '') IS NULL OR length(p_payout_reference) > 200 THEN
      RAISE EXCEPTION 'Referensi transfer wajib dicatat sebelum payout diselesaikan' USING ERRCODE = '22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('referral-payout:' || v_request.owner_user_id::text || ':' || v_request.owner_role, 0));
    IF v_request.amount_rupiah > (
      SELECT COALESCE(sum(l.amount_rupiah), 0)
      FROM public.merchant_referral_commission_ledger l
      WHERE l.owner_user_id = v_request.owner_user_id AND l.owner_role = v_request.owner_role AND l.release_at <= now()
    ) - (
      SELECT COALESCE(sum(r.amount_rupiah), 0)
      FROM public.merchant_referral_payout_requests r
      WHERE r.owner_user_id = v_request.owner_user_id AND r.owner_role = v_request.owner_role
        AND r.status IN ('PENDING', 'APPROVED') AND r.id <> p_request_id
    ) THEN RAISE EXCEPTION 'Saldo referral berubah; payout tidak lagi tersedia' USING ERRCODE = '23514'; END IF;
    UPDATE public.merchant_referral_payout_requests SET status = 'PAID', payout_reference = trim(p_payout_reference), admin_notes = left(p_admin_notes, 1000), processed_by = auth.uid(), processed_at = now(), paid_by = auth.uid(), paid_at = now(), updated_at = now() WHERE id = p_request_id;
    INSERT INTO public.merchant_referral_commission_ledger(
      owner_user_id, owner_role, payout_request_id, entry_type,
      amount_rupiah, commission_percent, release_at, idempotency_key, note
    ) VALUES (
      v_request.owner_user_id, v_request.owner_role, p_request_id, 'WITHDRAWAL', -v_request.amount_rupiah, 0, now(),
      'referral-payout:' || p_request_id::text,
      'Payout referral manual; referensi ' || trim(p_payout_reference)
    );
  END IF;
  RETURN jsonb_build_object('id', p_request_id, 'status', v_status, 'duplicate', false);
END;
$$$bootstrap_sql_86dc9a4fa263$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_86dc9a4fa263$$bootstrap_sql_8d2bf8da6edd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d2bf8da6edd$;

DO $bootstrap_do_9276b5819cd9$
BEGIN
  EXECUTE $bootstrap_sql_9276b5819cd9$DO $bootstrap_do_c98a52aff1ae$
BEGIN
  EXECUTE $bootstrap_sql_c98a52aff1ae$REVOKE ALL ON FUNCTION public.process_merchant_referral_payout(uuid, text, text, text) FROM PUBLIC, anon$bootstrap_sql_c98a52aff1ae$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c98a52aff1ae$$bootstrap_sql_9276b5819cd9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9276b5819cd9$;

DO $bootstrap_do_285ae693d686$
BEGIN
  EXECUTE $bootstrap_sql_285ae693d686$DO $bootstrap_do_1e3c7da4fa8b$
BEGIN
  EXECUTE $bootstrap_sql_1e3c7da4fa8b$GRANT EXECUTE ON FUNCTION public.process_merchant_referral_payout(uuid, text, text, text) TO authenticated, service_role$bootstrap_sql_1e3c7da4fa8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1e3c7da4fa8b$$bootstrap_sql_285ae693d686$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_285ae693d686$;

DO $bootstrap_do_7901aaf8390a$
BEGIN
  EXECUTE $bootstrap_sql_7901aaf8390a$DO $bootstrap_do_5451500ec91d$
BEGIN
  EXECUTE $bootstrap_sql_5451500ec91d$CREATE OR REPLACE FUNCTION public.reverse_commission_for_refund(
  p_refund_request_id uuid, p_order_id uuid, p_refund_amount numeric
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_request public.refund_requests%ROWTYPE;
  v_order_total numeric;
  v_window_days integer;
  v_completed_at timestamptz;
  v_cumulative_refund numeric;
  v_commission record;
  v_source public.merchant_referral_fee_sources%ROWTYPE;
  v_gross_fee bigint;
  v_target_refund bigint;
  v_already_refunded bigint;
  v_refund_fee bigint;
  v_debt_paid bigint;
  v_balance_credit bigint;
  v_reversed bigint := 0;
  v_idempotency_key text;
  v_net_referral bigint;
  v_target_referral bigint;
  v_referral_reversal bigint;
  v_debt_remaining bigint;
  v_debt_source record;
  v_debt_alloc bigint;
BEGIN
  SELECT * INTO v_request FROM public.refund_requests WHERE id = p_refund_request_id;
  IF NOT FOUND OR v_request.order_id <> p_order_id THEN RAISE EXCEPTION 'refund request/order mismatch'; END IF;
  SELECT o.total INTO v_order_total FROM public.orders o WHERE o.id = p_order_id;
  IF v_order_total IS NULL OR v_order_total <= 0 OR p_refund_amount <= 0 THEN RETURN 0; END IF;
  SELECT COALESCE(refund_window_days, 7) INTO v_window_days FROM public.commission_wallet_policy_settings WHERE id = true;
  v_window_days := COALESCE(v_window_days, 7);
  SELECT max(h.created_at) INTO v_completed_at
  FROM public.order_status_history h
  WHERE h.order_id = p_order_id AND upper(h.to_status) IN ('DONE', 'DELIVERED', 'COMPLETED');
  IF v_request.created_at > COALESCE(v_completed_at, now()) + make_interval(days => v_window_days) THEN RETURN 0; END IF;
  SELECT LEAST(COALESCE(sum(rs.amount), p_refund_amount), v_order_total)
  INTO v_cumulative_refund
  FROM public.refund_settlements rs
  WHERE rs.order_id = p_order_id AND rs.status = 'COMPLETED';
  v_cumulative_refund := GREATEST(COALESCE(v_cumulative_refund, p_refund_amount), p_refund_amount);

  FOR v_commission IN
    SELECT l.id, l.wallet_id, l.source_type, l.source_id, l.amount_delta_rupiah,
           l.debt_delta_rupiah, w.debt_rupiah
    FROM public.commission_wallet_ledger l
    JOIN public.commission_wallets w ON w.id = l.wallet_id
    WHERE l.entry_type = 'COMMISSION' AND l.source_id = p_order_id
      AND l.source_type IN ('ORDER', 'COURIER_DELIVERY')
    ORDER BY l.source_type
    FOR UPDATE OF l, w
  LOOP
    v_idempotency_key := 'commission-refund:' || p_refund_request_id::text || ':' || v_commission.source_type;
    IF EXISTS (SELECT 1 FROM public.commission_wallet_ledger WHERE idempotency_key = v_idempotency_key) THEN CONTINUE; END IF;
    v_gross_fee := GREATEST(-v_commission.amount_delta_rupiah + v_commission.debt_delta_rupiah, 0);
    v_target_refund := LEAST(v_gross_fee, round(v_gross_fee::numeric * LEAST(v_cumulative_refund / v_order_total, 1))::bigint);
    SELECT COALESCE(sum(amount_delta_rupiah - debt_delta_rupiah), 0) INTO v_already_refunded
    FROM public.commission_wallet_ledger
    WHERE entry_type = 'REFUND' AND source_id = p_order_id AND source_type = v_commission.source_type;
    v_refund_fee := GREATEST(v_target_refund - v_already_refunded, 0);
    IF v_refund_fee <= 0 THEN CONTINUE; END IF;

    IF v_commission.source_type = 'ORDER' THEN
      SELECT * INTO v_source FROM public.merchant_referral_fee_sources
      WHERE source_fee_ledger_id = v_commission.id FOR UPDATE;
    ELSE
      v_source := NULL;
    END IF;

    IF v_source.id IS NOT NULL THEN
      v_debt_paid := LEAST(v_source.outstanding_debt_rupiah, v_refund_fee);
      v_balance_credit := v_refund_fee - v_debt_paid;
      UPDATE public.commission_wallets
      SET debt_rupiah = GREATEST(debt_rupiah - v_debt_paid, 0),
          balance_rupiah = balance_rupiah + v_balance_credit, updated_at = now()
      WHERE id = v_commission.wallet_id;
      UPDATE public.merchant_referral_fee_sources
      SET outstanding_debt_rupiah = outstanding_debt_rupiah - v_debt_paid,
          refunded_debt_rupiah = refunded_debt_rupiah + v_debt_paid,
          refunded_collected_rupiah = refunded_collected_rupiah + v_balance_credit
      WHERE id = v_source.id RETURNING * INTO v_source;
      INSERT INTO public.commission_wallet_ledger(
        wallet_id, entry_type, source_type, source_id, idempotency_key,
        amount_delta_rupiah, debt_delta_rupiah, note, created_by
      ) VALUES (
        v_commission.wallet_id, 'REFUND', v_commission.source_type, p_order_id,
        v_idempotency_key, v_balance_credit, -v_debt_paid,
        'Pembalikan komisi proporsional atas refund ' || p_refund_request_id::text, NULL
      );
      v_target_referral := round(GREATEST(v_source.fee_collected_rupiah - v_source.refunded_collected_rupiah, 0)::numeric * v_source.referral_percent / 100)::bigint;
      SELECT COALESCE(sum(amount_rupiah), 0) INTO v_net_referral
      FROM public.merchant_referral_commission_ledger
      WHERE source_fee_ledger_id = v_commission.id AND entry_type IN ('EARNING', 'REFUND_REVERSAL');
      v_referral_reversal := GREATEST(v_net_referral - v_target_referral, 0);
      UPDATE public.merchant_referral_fee_sources
      SET referral_amount_recorded_rupiah = v_target_referral WHERE id = v_source.id;
      IF v_referral_reversal > 0 AND v_source.referrer_user_id IS NOT NULL THEN
        INSERT INTO public.merchant_referral_commission_ledger(
          owner_user_id, owner_role, merchant_id, referral_code_id, source_order_id,
          source_fee_ledger_id, entry_type, amount_rupiah, fee_collected_base_rupiah,
          commission_percent, release_at, idempotency_key, note
        ) VALUES (
          v_source.referrer_user_id, v_source.referrer_role, v_source.merchant_id,
          v_source.referral_code_id, v_source.source_order_id, v_commission.id,
          'REFUND_REVERSAL', -v_referral_reversal, v_balance_credit,
          v_source.referral_percent, v_source.release_at,
          'referral-refund:' || p_refund_request_id::text || ':' || v_commission.id::text,
          'Pembalikan referral proporsional setelah refund berhasil'
        ) ON CONFLICT (idempotency_key) DO NOTHING;
      END IF;
    ELSE
      -- Preserve legacy wallet refund behavior for courier fees and pre-feature merchant fees.
      v_debt_paid := LEAST(v_commission.debt_rupiah, v_refund_fee);
      v_balance_credit := v_refund_fee - v_debt_paid;
      UPDATE public.commission_wallets
      SET debt_rupiah = debt_rupiah - v_debt_paid,
          balance_rupiah = balance_rupiah + v_balance_credit, updated_at = now()
      WHERE id = v_commission.wallet_id;
      v_debt_remaining := v_debt_paid;
      FOR v_debt_source IN
        SELECT id, outstanding_debt_rupiah
        FROM public.merchant_referral_fee_sources
        WHERE wallet_id = v_commission.wallet_id AND outstanding_debt_rupiah > 0
        ORDER BY is_legacy_debt DESC, created_at, id FOR UPDATE
      LOOP
        EXIT WHEN v_debt_remaining <= 0;
        v_debt_alloc := LEAST(v_debt_remaining, v_debt_source.outstanding_debt_rupiah);
        UPDATE public.merchant_referral_fee_sources
        SET outstanding_debt_rupiah = outstanding_debt_rupiah - v_debt_alloc,
            refunded_debt_rupiah = refunded_debt_rupiah + v_debt_alloc
        WHERE id = v_debt_source.id;
        v_debt_remaining := v_debt_remaining - v_debt_alloc;
      END LOOP;
      IF v_debt_remaining > 0 THEN RAISE EXCEPTION 'refund legacy tidak memiliki debt source'; END IF;
      INSERT INTO public.commission_wallet_ledger(
        wallet_id, entry_type, source_type, source_id, idempotency_key,
        amount_delta_rupiah, debt_delta_rupiah, note, created_by
      ) VALUES (
        v_commission.wallet_id, 'REFUND', v_commission.source_type, p_order_id,
        v_idempotency_key, v_balance_credit, -v_debt_paid,
        'Pembalikan komisi proporsional atas refund ' || p_refund_request_id::text, NULL
      );
    END IF;
    v_reversed := v_reversed + v_refund_fee;
  END LOOP;
  RETURN v_reversed;
END;
$$$bootstrap_sql_5451500ec91d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5451500ec91d$$bootstrap_sql_7901aaf8390a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7901aaf8390a$;

DO $bootstrap_do_de3e005f28da$
BEGIN
  EXECUTE $bootstrap_sql_de3e005f28da$DO $bootstrap_do_a1ffccab6a7f$
BEGIN
  EXECUTE $bootstrap_sql_a1ffccab6a7f$REVOKE ALL ON FUNCTION public.reverse_commission_for_refund(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated$bootstrap_sql_a1ffccab6a7f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1ffccab6a7f$$bootstrap_sql_de3e005f28da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de3e005f28da$;

DO $bootstrap_do_fe2e8572f5f4$
BEGIN
  EXECUTE $bootstrap_sql_fe2e8572f5f4$DO $bootstrap_do_8b4871fadb49$
BEGIN
  EXECUTE $bootstrap_sql_8b4871fadb49$GRANT EXECUTE ON FUNCTION public.reverse_commission_for_refund(uuid, uuid, numeric) TO service_role$bootstrap_sql_8b4871fadb49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b4871fadb49$$bootstrap_sql_fe2e8572f5f4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fe2e8572f5f4$;

DO $bootstrap_do_4c2eaae80c17$
BEGIN
  EXECUTE $bootstrap_sql_4c2eaae80c17$DO $bootstrap_do_7cc5a3a0047e$
BEGIN
  EXECUTE $bootstrap_sql_7cc5a3a0047e$NOTIFY pgrst, 'reload schema'$bootstrap_sql_7cc5a3a0047e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cc5a3a0047e$$bootstrap_sql_4c2eaae80c17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4c2eaae80c17$;
