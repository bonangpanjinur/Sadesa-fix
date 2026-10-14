-- ============================================
-- Backup Schedules Table (only if not exists)
-- ============================================
CREATE TABLE IF NOT EXISTS public.backup_schedules (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    schedule_type TEXT NOT NULL DEFAULT 'daily',
    schedule_time TIME NOT NULL DEFAULT '02:00',
    schedule_day INTEGER,
    tables_included TEXT[] DEFAULT ARRAY['merchants', 'products', 'orders', 'villages', 'tourism', 'couriers'],
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_5b6f62aeb942$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5b6f62aeb942$;

DO $bootstrap_do_765cf490c9e8$
BEGIN
  EXECUTE $bootstrap_sql_765cf490c9e8$ALTER TABLE public.backup_schedules ENABLE ROW LEVEL SECURITY$bootstrap_sql_765cf490c9e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_765cf490c9e8$;

DO $bootstrap_do_a40f8554d028$
BEGIN
  EXECUTE $bootstrap_sql_a40f8554d028$DROP POLICY IF EXISTS "Admins can manage backup schedules" ON public.backup_schedules$bootstrap_sql_a40f8554d028$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a40f8554d028$;

DO $bootstrap_do_908f84e639ba$
BEGIN
  EXECUTE $bootstrap_sql_908f84e639ba$CREATE POLICY "Admins can manage backup schedules" ON public.backup_schedules
    FOR ALL USING (is_admin())$bootstrap_sql_908f84e639ba$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_908f84e639ba$;

DO $bootstrap_do_93c9a19345b2$
BEGIN
  EXECUTE $bootstrap_sql_93c9a19345b2$-- ============================================
-- Add proof_image_url to verifikator_withdrawals if not exists
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'verifikator_withdrawals' AND column_name = 'proof_image_url') THEN
        ALTER TABLE public.verifikator_withdrawals ADD COLUMN proof_image_url TEXT;
    END IF;
END $$$bootstrap_sql_93c9a19345b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_93c9a19345b2$;

DO $bootstrap_do_579c32b89e7d$
BEGIN
  EXECUTE $bootstrap_sql_579c32b89e7d$-- ============================================
-- Add COD columns to orders if not exists
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_confirmed_at') THEN
        ALTER TABLE public.orders ADD COLUMN cod_confirmed_at TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_rejected_at') THEN
        ALTER TABLE public.orders ADD COLUMN cod_rejected_at TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'cod_rejection_reason') THEN
        ALTER TABLE public.orders ADD COLUMN cod_rejection_reason TEXT;
    END IF;
END $$$bootstrap_sql_579c32b89e7d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_579c32b89e7d$;

DO $bootstrap_do_a8052bf6f5e2$
BEGIN
  EXECUTE $bootstrap_sql_a8052bf6f5e2$-- ============================================
-- COD Eligibility Check Function
-- ============================================
CREATE OR REPLACE FUNCTION public.check_cod_eligibility(
    p_buyer_id UUID,
    p_merchant_id UUID,
    p_total_amount INTEGER,
    p_distance_km NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cod_settings JSONB;
    v_max_amount INTEGER;
    v_max_distance NUMERIC;
    v_min_trust_score INTEGER;
    v_buyer_trust_score INTEGER;
    v_buyer_cod_enabled BOOLEAN;
    v_merchant_cod_max_amount INTEGER;
    v_merchant_cod_max_distance NUMERIC;
BEGIN
    SELECT value INTO v_cod_settings FROM app_settings WHERE key = 'cod_settings';

    IF v_cod_settings IS NULL THEN
        v_max_amount := 75000;
        v_max_distance := 3;
        v_min_trust_score := 50;
    ELSE
        v_max_amount := COALESCE((v_cod_settings->>'max_amount')::INTEGER, 75000);
        v_max_distance := COALESCE((v_cod_settings->>'max_distance_km')::NUMERIC, 3);
        v_min_trust_score := COALESCE((v_cod_settings->>'min_trust_score')::INTEGER, 50);
    END IF;

    SELECT trust_score, cod_enabled INTO v_buyer_trust_score, v_buyer_cod_enabled
    FROM profiles WHERE user_id = p_buyer_id;

    IF v_buyer_cod_enabled = false THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'Akun Anda tidak dapat menggunakan COD');
    END IF;

    IF COALESCE(v_buyer_trust_score, 100) < v_min_trust_score THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'Trust score tidak mencukupi untuk COD');
    END IF;

    SELECT cod_max_amount, cod_max_distance_km INTO v_merchant_cod_max_amount, v_merchant_cod_max_distance
    FROM merchants WHERE id = p_merchant_id;

    v_max_amount := LEAST(v_max_amount, COALESCE(v_merchant_cod_max_amount, v_max_amount));
    v_max_distance := LEAST(v_max_distance, COALESCE(v_merchant_cod_max_distance, v_max_distance));

    IF p_total_amount > v_max_amount THEN
        RETURN jsonb_build_object('eligible', false, 'reason',
            format('Nominal terlalu besar untuk COD. Maks: Rp %s', to_char(v_max_amount, 'FM999,999,999')));
    END IF;

    IF p_distance_km IS NOT NULL AND p_distance_km > v_max_distance THEN
        RETURN jsonb_build_object('eligible', false, 'reason',
            format('Jarak terlalu jauh untuk COD. Maks: %s KM', v_max_distance));
    END IF;

    RETURN jsonb_build_object('eligible', true, 'reason', NULL);
END;
$$$bootstrap_sql_a8052bf6f5e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a8052bf6f5e2$;

DO $bootstrap_do_0df2ee8fa2b6$
BEGIN
  EXECUTE $bootstrap_sql_0df2ee8fa2b6$-- ============================================
-- Update buyer trust score function
-- ============================================
CREATE OR REPLACE FUNCTION public.update_cod_trust_score(
    p_buyer_id UUID,
    p_success BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cod_settings JSONB;
    v_penalty_points INTEGER;
    v_bonus_points INTEGER;
    v_min_trust_score INTEGER;
    v_current_score INTEGER;
    v_current_fail_count INTEGER;
    v_new_score INTEGER;
BEGIN
    SELECT value INTO v_cod_settings FROM app_settings WHERE key = 'cod_settings';

    v_penalty_points := COALESCE((v_cod_settings->>'penalty_points')::INTEGER, 50);
    v_bonus_points := COALESCE((v_cod_settings->>'success_bonus_points')::INTEGER, 1);
    v_min_trust_score := COALESCE((v_cod_settings->>'min_trust_score')::INTEGER, 50);

    SELECT trust_score, cod_fail_count INTO v_current_score, v_current_fail_count
    FROM profiles WHERE user_id = p_buyer_id;

    v_current_score := COALESCE(v_current_score, 100);
    v_current_fail_count := COALESCE(v_current_fail_count, 0);

    IF p_success THEN
        v_new_score := LEAST(100, v_current_score + v_bonus_points);
        UPDATE profiles SET trust_score = v_new_score WHERE user_id = p_buyer_id;
    ELSE
        v_new_score := GREATEST(0, v_current_score - v_penalty_points);
        UPDATE profiles
        SET
            trust_score = v_new_score,
            cod_fail_count = v_current_fail_count + 1,
            cod_enabled = CASE WHEN v_new_score < v_min_trust_score THEN false ELSE cod_enabled END
        WHERE user_id = p_buyer_id;
    END IF;
END;
$$$bootstrap_sql_0df2ee8fa2b6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0df2ee8fa2b6$;

DO $bootstrap_do_bd7b7c1742f5$
BEGIN
  EXECUTE $bootstrap_sql_bd7b7c1742f5$-- ============================================
-- Product-images storage bucket (ignore if exists)
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_bd7b7c1742f5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd7b7c1742f5$;

DO $bootstrap_do_596be1aba447$
BEGIN
  EXECUTE $bootstrap_sql_596be1aba447$-- Storage policies (drop and recreate)
DROP POLICY IF EXISTS "Anyone can view product images storage" ON storage.objects$bootstrap_sql_596be1aba447$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_596be1aba447$;

DO $bootstrap_do_2e7a57c96f92$
BEGIN
  EXECUTE $bootstrap_sql_2e7a57c96f92$DROP POLICY IF EXISTS "Authenticated users can upload product images storage" ON storage.objects$bootstrap_sql_2e7a57c96f92$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2e7a57c96f92$;

DO $bootstrap_do_761c1d6cea13$
BEGIN
  EXECUTE $bootstrap_sql_761c1d6cea13$DROP POLICY IF EXISTS "Users can delete own product images storage" ON storage.objects$bootstrap_sql_761c1d6cea13$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_761c1d6cea13$;

DO $bootstrap_do_5078f008945c$
BEGIN
  EXECUTE $bootstrap_sql_5078f008945c$DROP POLICY IF EXISTS "Anyone can view product images storage" ON storage.objects$bootstrap_sql_5078f008945c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5078f008945c$;

DO $bootstrap_do_bbca6991eeef$
BEGIN
  EXECUTE $bootstrap_sql_bbca6991eeef$CREATE POLICY "Anyone can view product images storage" ON storage.objects
    FOR SELECT USING (bucket_id = 'product-images')$bootstrap_sql_bbca6991eeef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbca6991eeef$;

DO $bootstrap_do_58c1de7d3057$
BEGIN
  EXECUTE $bootstrap_sql_58c1de7d3057$DROP POLICY IF EXISTS "Authenticated users can upload product images storage" ON storage.objects$bootstrap_sql_58c1de7d3057$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_58c1de7d3057$;

DO $bootstrap_do_6da368faa1b3$
BEGIN
  EXECUTE $bootstrap_sql_6da368faa1b3$CREATE POLICY "Authenticated users can upload product images storage" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'product-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_6da368faa1b3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6da368faa1b3$;

DO $bootstrap_do_afd13a1c4201$
BEGIN
  EXECUTE $bootstrap_sql_afd13a1c4201$DROP POLICY IF EXISTS "Users can delete own product images storage" ON storage.objects$bootstrap_sql_afd13a1c4201$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_afd13a1c4201$;

DO $bootstrap_do_6b96005a3add$
BEGIN
  EXECUTE $bootstrap_sql_6b96005a3add$CREATE POLICY "Users can delete own product images storage" ON storage.objects
    FOR DELETE USING (bucket_id = 'product-images' AND auth.uid() IS NOT NULL)$bootstrap_sql_6b96005a3add$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6b96005a3add$;

DO $bootstrap_do_6be3e5791b28$
BEGIN
  EXECUTE $bootstrap_sql_6be3e5791b28$
