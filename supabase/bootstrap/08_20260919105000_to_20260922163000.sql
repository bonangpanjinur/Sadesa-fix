-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_3a251cdc18c6$
BEGIN
  EXECUTE $bootstrap_sql_3a251cdc18c6$-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 92_20260919105000_merchant_ad_payment_proof_storage.sql .. 106_20260922163000_to_20260922163000.sql

-- ===== BEGIN BUNDLE: 92_20260919105000_merchant_ad_payment_proof_storage.sql =====
-- Merchant paid-ad payment proofs are uploaded under <merchant_id>/<file>.
-- Keep this separate from buyer order proofs, whose policies are more restrictive.
DROP POLICY IF EXISTS "Merchant can upload ad payment proof" ON storage.objects$bootstrap_sql_3a251cdc18c6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a251cdc18c6$;

DO $bootstrap_do_bdbf94b15b59$
BEGIN
  EXECUTE $bootstrap_sql_bdbf94b15b59$CREATE POLICY "Merchant can upload ad payment proof" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id::text = split_part(name, '/', 1)
        AND m.user_id = auth.uid()
    )
  )$bootstrap_sql_bdbf94b15b59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bdbf94b15b59$;

DO $bootstrap_do_2987979823d0$
BEGIN
  EXECUTE $bootstrap_sql_2987979823d0$DROP POLICY IF EXISTS "Merchant can read own ad payment proof" ON storage.objects$bootstrap_sql_2987979823d0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2987979823d0$;

DO $bootstrap_do_8c6be5b32787$
BEGIN
  EXECUTE $bootstrap_sql_8c6be5b32787$CREATE POLICY "Merchant can read own ad payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1
      FROM public.merchant_ads a
      JOIN public.merchants m ON m.id = a.merchant_id
      WHERE m.id::text = split_part(name, '/', 1)
        AND m.user_id = auth.uid()
    )
  )$bootstrap_sql_8c6be5b32787$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8c6be5b32787$;

DO $bootstrap_do_bafc09a9d803$
BEGIN
  EXECUTE $bootstrap_sql_bafc09a9d803$DROP POLICY IF EXISTS "Admin can read ad payment proof" ON storage.objects$bootstrap_sql_bafc09a9d803$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bafc09a9d803$;

DO $bootstrap_do_f29b5a82df69$
BEGIN
  EXECUTE $bootstrap_sql_f29b5a82df69$CREATE POLICY "Admin can read ad payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.is_admin())$bootstrap_sql_f29b5a82df69$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f29b5a82df69$;

DO $bootstrap_do_ce27d3ba194f$
BEGIN
  EXECUTE $bootstrap_sql_ce27d3ba194f$NOTIFY pgrst, 'reload schema'$bootstrap_sql_ce27d3ba194f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ce27d3ba194f$;

DO $bootstrap_do_840b18d78afe$
BEGIN
  EXECUTE $bootstrap_sql_840b18d78afe$-- ===== END BUNDLE: 92_20260919105000_merchant_ad_payment_proof_storage.sql =====

-- ===== BEGIN BUNDLE: 93_20260920100000_admin_merchant_delete_fk_repair.sql =====
-- Admin merchant deletion repair.
--
-- The merchants DELETE policy already grants admins the operation, but several
-- late-added tables kept PostgreSQL's default NO ACTION/RESTRICT FK behavior.
-- A merchant with POS or refund history therefore could never be deleted.
-- Operational configuration is cascaded; financial/audit history is retained
-- with a NULL merchant reference.

DO $$
DECLARE
  v_table text;
  v_constraint text;
BEGIN
  -- Operational merchant-owned data can be removed with the merchant.
  FOREACH v_table IN ARRAY ARRAY['pos_subscriptions', 'pos_transactions', 'pos_settings'] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = 'public.merchants'::regclass
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE CASCADE',
      v_table, v_table || '_merchant_id_fkey'
    );
  END LOOP;

  -- Preserve audit, earnings, and refund history while allowing the merchant
  -- record itself to be removed. These columns are intentionally nullable.
  FOREACH v_table IN ARRAY ARRAY[
    'quota_audit_logs',
    'verifikator_earnings',
    'refund_requests',
    'refund_settlements',
    'merchant_refund_shortfalls'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = 'public.merchants'::regclass
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN merchant_id DROP NOT NULL', v_table);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (merchant_id) REFERENCES public.merchants(id) ON DELETE SET NULL',
      v_table, v_table || '_merchant_id_fkey'
    );
  END LOOP;
END;
$$$bootstrap_sql_840b18d78afe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_840b18d78afe$;

DO $bootstrap_do_065c98ca0b15$
BEGIN
  EXECUTE $bootstrap_sql_065c98ca0b15$COMMENT ON COLUMN public.refund_settlements.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund settlement records.'$bootstrap_sql_065c98ca0b15$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_065c98ca0b15$;

DO $bootstrap_do_e742ac398840$
BEGIN
  EXECUTE $bootstrap_sql_e742ac398840$COMMENT ON COLUMN public.merchant_refund_shortfalls.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund shortfall records.'$bootstrap_sql_e742ac398840$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e742ac398840$;

DO $bootstrap_do_3b2cf81db9c7$
BEGIN
  EXECUTE $bootstrap_sql_3b2cf81db9c7$COMMENT ON COLUMN public.quota_audit_logs.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase quota audit records.'$bootstrap_sql_3b2cf81db9c7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b2cf81db9c7$;

DO $bootstrap_do_24fc90b5c242$
BEGIN
  EXECUTE $bootstrap_sql_24fc90b5c242$COMMENT ON COLUMN public.verifikator_earnings.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase commission records.'$bootstrap_sql_24fc90b5c242$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_24fc90b5c242$;

DO $bootstrap_do_a3aa7e9aa1fa$
BEGIN
  EXECUTE $bootstrap_sql_a3aa7e9aa1fa$-- ===== END BUNDLE: 93_20260920100000_admin_merchant_delete_fk_repair.sql =====

-- ===== BEGIN BUNDLE: 94_20260920110000_merchant_delete_stock_reservation_fk_repair.sql =====
-- Merchant deletion repair: stock reservation history must not block product removal.
-- Reservation rows remain as historical records; references to removed products
-- or variants are detached instead of deleting the reservation audit trail.

DO $$
DECLARE
  v_table text;
  v_column text;
  v_constraint text;
  v_target text;
BEGIN
  FOR v_table, v_column, v_target IN
    SELECT * FROM (VALUES
      ('marketplace_stock_reservation_items', 'product_id', 'products'),
      ('marketplace_stock_reservation_items', 'variant_id', 'product_variants'),
      ('marketplace_stock_allocations', 'product_id', 'products')
    ) AS repair(table_name, column_name, target_table)
  LOOP
    IF to_regclass('public.' || v_table) IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = v_table AND column_name = v_column
       )
       OR to_regclass('public.' || v_target) IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      WHERE c.conrelid = ('public.' || v_table)::regclass
        AND c.contype = 'f'
        AND c.confrelid = ('public.' || v_target)::regclass
        AND c.conkey = ARRAY[
          (SELECT a.attnum
           FROM pg_attribute a
           WHERE a.attrelid = c.conrelid AND a.attname = v_column AND NOT a.attisdropped)
        ]::smallint[]
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_constraint);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL', v_table, v_column);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.%I(id) ON DELETE SET NULL',
      v_table, v_table || '_' || v_column || '_fkey', v_column, v_target
    );
  END LOOP;
END;
$$$bootstrap_sql_a3aa7e9aa1fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a3aa7e9aa1fa$;

DO $bootstrap_do_fc1106d7438a$
BEGIN
  EXECUTE $bootstrap_sql_fc1106d7438a$COMMENT ON COLUMN public.marketplace_stock_reservation_items.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.'$bootstrap_sql_fc1106d7438a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc1106d7438a$;

DO $bootstrap_do_b481f76d003c$
BEGIN
  EXECUTE $bootstrap_sql_b481f76d003c$COMMENT ON COLUMN public.marketplace_stock_reservation_items.variant_id IS
  'Nullable historical reference; removed product variants must not block merchant deletion.'$bootstrap_sql_b481f76d003c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b481f76d003c$;

DO $bootstrap_do_8a4ddc0fa7b9$
BEGIN
  EXECUTE $bootstrap_sql_8a4ddc0fa7b9$COMMENT ON COLUMN public.marketplace_stock_allocations.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.'$bootstrap_sql_8a4ddc0fa7b9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a4ddc0fa7b9$;

DO $bootstrap_do_1c14b98fd2b8$
BEGIN
  EXECUTE $bootstrap_sql_1c14b98fd2b8$-- ===== END BUNDLE: 94_20260920110000_merchant_delete_stock_reservation_fk_repair.sql =====

-- ===== BEGIN BUNDLE: 95_20260918233000_to_20260918233000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260918233000_merchant_paid_ads.sql .. 20260918233000_merchant_paid_ads.sql

-- ===== BEGIN SOURCE: 20260918233000_merchant_paid_ads.sql =====
-- Merchant paid advertising: packages, submissions, moderation and delivery.
CREATE TABLE IF NOT EXISTS public.ad_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  description TEXT,
  price_per_day NUMERIC(12, 2) NOT NULL CHECK (price_per_day > 0),
  max_days INTEGER NOT NULL DEFAULT 30 CHECK (max_days BETWEEN 1 AND 365),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_1c14b98fd2b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1c14b98fd2b8$;

DO $bootstrap_do_2a8679f5759a$
BEGIN
  EXECUTE $bootstrap_sql_2a8679f5759a$CREATE TABLE IF NOT EXISTS public.merchant_ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  package_id UUID REFERENCES public.ad_packages(id) ON DELETE SET NULL,
  placement_type TEXT NOT NULL CHECK (placement_type IN ('search_top', 'category_top', 'home_banner', 'product_recommend')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  description TEXT CHECK (description IS NULL OR char_length(description) <= 200),
  image_url TEXT,
  link_url TEXT,
  duration_days INTEGER NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'expired', 'rejected')),
  payment_amount NUMERIC(12, 2) NOT NULL CHECK (payment_amount >= 0),
  payment_proof_url TEXT,
  rejection_reason TEXT,
  view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  click_count INTEGER NOT NULL DEFAULT 0 CHECK (click_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT merchant_ads_date_order CHECK (end_date IS NULL OR start_date IS NULL OR end_date > start_date)
)$bootstrap_sql_2a8679f5759a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a8679f5759a$;

DO $bootstrap_do_fb3e992dc2d8$
BEGIN
  EXECUTE $bootstrap_sql_fb3e992dc2d8$CREATE INDEX IF NOT EXISTS idx_ad_packages_active ON public.ad_packages(is_active, placement_type)$bootstrap_sql_fb3e992dc2d8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fb3e992dc2d8$;

DO $bootstrap_do_90ddf159311b$
BEGIN
  EXECUTE $bootstrap_sql_90ddf159311b$CREATE INDEX IF NOT EXISTS idx_merchant_ads_delivery ON public.merchant_ads(placement_type, status, start_date, end_date)$bootstrap_sql_90ddf159311b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_90ddf159311b$;

DO $bootstrap_do_814b802fe83d$
BEGIN
  EXECUTE $bootstrap_sql_814b802fe83d$CREATE INDEX IF NOT EXISTS idx_merchant_ads_merchant ON public.merchant_ads(merchant_id, created_at DESC)$bootstrap_sql_814b802fe83d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_814b802fe83d$;

DO $bootstrap_do_2d6700019f46$
BEGIN
  EXECUTE $bootstrap_sql_2d6700019f46$ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_2d6700019f46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d6700019f46$;

DO $bootstrap_do_bba9b6103b88$
BEGIN
  EXECUTE $bootstrap_sql_bba9b6103b88$ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY$bootstrap_sql_bba9b6103b88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bba9b6103b88$;

DO $bootstrap_do_eb22ad4b6b16$
BEGIN
  EXECUTE $bootstrap_sql_eb22ad4b6b16$DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages$bootstrap_sql_eb22ad4b6b16$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eb22ad4b6b16$;

DO $bootstrap_do_f54135440733$
BEGIN
  EXECUTE $bootstrap_sql_f54135440733$CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.has_role(auth.uid(), 'admin'))$bootstrap_sql_f54135440733$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f54135440733$;

DO $bootstrap_do_f3f567749b41$
BEGIN
  EXECUTE $bootstrap_sql_f3f567749b41$DROP POLICY IF EXISTS "Admin manages ad packages" ON public.ad_packages$bootstrap_sql_f3f567749b41$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3f567749b41$;

DO $bootstrap_do_ad263997cb5d$
BEGIN
  EXECUTE $bootstrap_sql_ad263997cb5d$CREATE POLICY "Admin manages ad packages" ON public.ad_packages
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_ad263997cb5d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ad263997cb5d$;

DO $bootstrap_do_2a5444c9bfb9$
BEGIN
  EXECUTE $bootstrap_sql_2a5444c9bfb9$DROP POLICY IF EXISTS "Public can view active merchant ads" ON public.merchant_ads$bootstrap_sql_2a5444c9bfb9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a5444c9bfb9$;

DO $bootstrap_do_7cf60ca1eb1e$
BEGIN
  EXECUTE $bootstrap_sql_7cf60ca1eb1e$CREATE POLICY "Public can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    status = 'active'
    AND (start_date IS NULL OR start_date <= now())
    AND (end_date IS NULL OR end_date > now())
  )$bootstrap_sql_7cf60ca1eb1e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7cf60ca1eb1e$;

DO $bootstrap_do_8679a5482f35$
BEGIN
  EXECUTE $bootstrap_sql_8679a5482f35$DROP POLICY IF EXISTS "Merchant can view own ads" ON public.merchant_ads$bootstrap_sql_8679a5482f35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8679a5482f35$;

DO $bootstrap_do_dc0fcc3fb861$
BEGIN
  EXECUTE $bootstrap_sql_dc0fcc3fb861$CREATE POLICY "Merchant can view own ads" ON public.merchant_ads
  FOR SELECT TO authenticated USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  )$bootstrap_sql_dc0fcc3fb861$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc0fcc3fb861$;

DO $bootstrap_do_6f7eb3cb3695$
BEGIN
  EXECUTE $bootstrap_sql_6f7eb3cb3695$DROP POLICY IF EXISTS "Merchant can submit own ads" ON public.merchant_ads$bootstrap_sql_6f7eb3cb3695$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6f7eb3cb3695$;

DO $bootstrap_do_ab33caa9e871$
BEGIN
  EXECUTE $bootstrap_sql_ab33caa9e871$CREATE POLICY "Merchant can submit own ads" ON public.merchant_ads
  FOR INSERT TO authenticated WITH CHECK (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
    AND status = 'pending'
  )$bootstrap_sql_ab33caa9e871$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ab33caa9e871$;

DO $bootstrap_do_abbb52577a59$
BEGIN
  EXECUTE $bootstrap_sql_abbb52577a59$DROP POLICY IF EXISTS "Admin moderates merchant ads" ON public.merchant_ads$bootstrap_sql_abbb52577a59$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_abbb52577a59$;

DO $bootstrap_do_665d31ff5342$
BEGIN
  EXECUTE $bootstrap_sql_665d31ff5342$CREATE POLICY "Admin moderates merchant ads" ON public.merchant_ads
  FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_665d31ff5342$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_665d31ff5342$;

DO $bootstrap_do_4e0cda995ced$
BEGIN
  EXECUTE $bootstrap_sql_4e0cda995ced$DROP POLICY IF EXISTS "Admin deletes merchant ads" ON public.merchant_ads$bootstrap_sql_4e0cda995ced$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4e0cda995ced$;

DO $bootstrap_do_968a929b52dd$
BEGIN
  EXECUTE $bootstrap_sql_968a929b52dd$CREATE POLICY "Admin deletes merchant ads" ON public.merchant_ads
  FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'))$bootstrap_sql_968a929b52dd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_968a929b52dd$;

DO $bootstrap_do_4fbd6d33372c$
BEGIN
  EXECUTE $bootstrap_sql_4fbd6d33372c$-- A public bucket is needed for creative images; database policies still control
-- which campaigns can be delivered to buyers.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING$bootstrap_sql_4fbd6d33372c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4fbd6d33372c$;

DO $bootstrap_do_defc06c37ce7$
BEGIN
  EXECUTE $bootstrap_sql_defc06c37ce7$DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects$bootstrap_sql_defc06c37ce7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_defc06c37ce7$;

DO $bootstrap_do_bfe51739d13c$
BEGIN
  EXECUTE $bootstrap_sql_bfe51739d13c$CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads')$bootstrap_sql_bfe51739d13c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bfe51739d13c$;

DO $bootstrap_do_9532f2f57c9c$
BEGIN
  EXECUTE $bootstrap_sql_9532f2f57c9c$DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects$bootstrap_sql_9532f2f57c9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9532f2f57c9c$;

DO $bootstrap_do_440f2f23f5dc$
BEGIN
  EXECUTE $bootstrap_sql_440f2f23f5dc$CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads')$bootstrap_sql_440f2f23f5dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_440f2f23f5dc$;

DO $bootstrap_do_c83ac311cc88$
BEGIN
  EXECUTE $bootstrap_sql_c83ac311cc88$DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects$bootstrap_sql_c83ac311cc88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c83ac311cc88$;

DO $bootstrap_do_fd190a5bee73$
BEGIN
  EXECUTE $bootstrap_sql_fd190a5bee73$CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_fd190a5bee73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fd190a5bee73$;

DO $bootstrap_do_4458ecba248b$
BEGIN
  EXECUTE $bootstrap_sql_4458ecba248b$DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects$bootstrap_sql_4458ecba248b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4458ecba248b$;

DO $bootstrap_do_5681e10a4906$
BEGIN
  EXECUTE $bootstrap_sql_5681e10a4906$CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads')$bootstrap_sql_5681e10a4906$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5681e10a4906$;

DO $bootstrap_do_fc0f1a8fdf46$
BEGIN
  EXECUTE $bootstrap_sql_fc0f1a8fdf46$INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days)
SELECT * FROM (VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000::numeric, 30),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000::numeric, 30),
  ('Banner Homepage', 'home_banner', 'Tampil sebagai rekomendasi sponsor di halaman utama', 50000::numeric, 14),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi produk pilihan', 10000::numeric, 30)
) AS seed(name, placement_type, description, price_per_day, max_days)
WHERE NOT EXISTS (SELECT 1 FROM public.ad_packages WHERE ad_packages.placement_type = seed.placement_type)
ON CONFLICT DO NOTHING$bootstrap_sql_fc0f1a8fdf46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fc0f1a8fdf46$;

DO $bootstrap_do_f4f6480528db$
BEGIN
  EXECUTE $bootstrap_sql_f4f6480528db$-- ===== END SOURCE: 20260918233000_merchant_paid_ads.sql =====
-- ===== END BUNDLE: 95_20260918233000_to_20260918233000.sql =====

-- ===== BEGIN BUNDLE: 96_20260919123000_to_20260919123000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260919123000_active_merchant_category.sql .. 20260919123000_active_merchant_category.sql

-- ===== BEGIN SOURCE: 20260919123000_active_merchant_category.sql =====
-- Keep merchant business categories aligned with the admin-managed categories catalog.
ALTER TABLE public.merchants
  ALTER COLUMN business_category SET DEFAULT NULL$bootstrap_sql_f4f6480528db$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4f6480528db$;

DO $bootstrap_do_cc8964d0c21a$
BEGIN
  EXECUTE $bootstrap_sql_cc8964d0c21a$CREATE OR REPLACE FUNCTION public.validate_active_merchant_business_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.business_category IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.categories
       WHERE slug = NEW.business_category
         AND is_active = true
     ) THEN
    RAISE EXCEPTION 'business_category must reference an active admin category: %', NEW.business_category
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_cc8964d0c21a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc8964d0c21a$;

DO $bootstrap_do_791dae8a8544$
BEGIN
  EXECUTE $bootstrap_sql_791dae8a8544$DROP TRIGGER IF EXISTS merchants_active_business_category ON public.merchants$bootstrap_sql_791dae8a8544$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_791dae8a8544$;

DO $bootstrap_do_a51e146807f8$
BEGIN
  EXECUTE $bootstrap_sql_a51e146807f8$CREATE TRIGGER merchants_active_business_category
  BEFORE INSERT OR UPDATE OF business_category ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_active_merchant_business_category()$bootstrap_sql_a51e146807f8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a51e146807f8$;

DO $bootstrap_do_3b4b88abc0ab$
BEGIN
  EXECUTE $bootstrap_sql_3b4b88abc0ab$COMMENT ON FUNCTION public.validate_active_merchant_business_category() IS
  'Prevents merchant registrations and updates from using categories that are missing or inactive in the admin catalog.'$bootstrap_sql_3b4b88abc0ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b4b88abc0ab$;

DO $bootstrap_do_10e541a8cbed$
BEGIN
  EXECUTE $bootstrap_sql_10e541a8cbed$-- ===== END SOURCE: 20260919123000_active_merchant_category.sql =====
-- ===== END BUNDLE: 96_20260919123000_to_20260919123000.sql =====

-- ===== BEGIN BUNDLE: 97_20260920220000_to_20260920220000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260920220000_merchant_free_trial_quota.sql .. 20260920220000_merchant_free_trial_quota.sql

-- ===== BEGIN SOURCE: 20260920220000_merchant_free_trial_quota.sql =====
-- Free merchant onboarding: 100 transactions valid for 2 months.
-- A database trigger is used so the entitlement is granted atomically and cannot
-- be skipped by alternate clients or direct inserts.

INSERT INTO public.transaction_packages (
  name,
  description,
  classification_price,
  price_per_transaction,
  kas_fee,
  transaction_quota,
  validity_days,
  is_active
)
SELECT
  'Paket Gratis 2 Bulan',
  '100 transaksi gratis untuk merchant baru selama 2 bulan sejak pendaftaran.',
  'FREE',
  0,
  0,
  100,
  60,
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.transaction_packages
  WHERE name = 'Paket Gratis 2 Bulan'
)
ON CONFLICT DO NOTHING$bootstrap_sql_10e541a8cbed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10e541a8cbed$;

DO $bootstrap_do_9ccb36343852$
BEGIN
  EXECUTE $bootstrap_sql_9ccb36343852$CREATE OR REPLACE FUNCTION public.grant_new_merchant_free_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_package public.transaction_packages%ROWTYPE;
  v_subscription_id uuid;
BEGIN
  SELECT * INTO v_package
  FROM public.transaction_packages
  WHERE name = 'Paket Gratis 2 Bulan'
    AND is_active = true
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_package.id IS NULL THEN
    RAISE EXCEPTION 'Paket Gratis 2 Bulan belum tersedia';
  END IF;

  INSERT INTO public.merchant_subscriptions (
    merchant_id,
    package_id,
    transaction_quota,
    used_quota,
    status,
    payment_status,
    payment_amount,
    started_at,
    expired_at
  )
  VALUES (
    NEW.id,
    v_package.id,
    v_package.transaction_quota,
    0,
    'ACTIVE',
    'PAID',
    0,
    COALESCE(NEW.registered_at, now()),
    COALESCE(NEW.registered_at, now()) + make_interval(days => v_package.validity_days)
  )
  RETURNING id INTO v_subscription_id;

  UPDATE public.merchants
  SET current_subscription_id = v_subscription_id,
      status = 'ACTIVE',
      registration_status = 'APPROVED',
      approved_at = COALESCE(approved_at, now()),
      updated_at = now()
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$$bootstrap_sql_9ccb36343852$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ccb36343852$;

DO $bootstrap_do_a5e1dce1a62f$
BEGIN
  EXECUTE $bootstrap_sql_a5e1dce1a62f$DROP TRIGGER IF EXISTS grant_new_merchant_free_trial_trigger ON public.merchants$bootstrap_sql_a5e1dce1a62f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a5e1dce1a62f$;

DO $bootstrap_do_c204026a54e3$
BEGIN
  EXECUTE $bootstrap_sql_c204026a54e3$CREATE TRIGGER grant_new_merchant_free_trial_trigger
AFTER INSERT ON public.merchants
FOR EACH ROW
EXECUTE FUNCTION public.grant_new_merchant_free_trial()$bootstrap_sql_c204026a54e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c204026a54e3$;

DO $bootstrap_do_83ec56bb217c$
BEGIN
  EXECUTE $bootstrap_sql_83ec56bb217c$COMMENT ON FUNCTION public.grant_new_merchant_free_trial() IS
  'Automatically activates new merchants and grants the 2-month free transaction quota.'$bootstrap_sql_83ec56bb217c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83ec56bb217c$;

DO $bootstrap_do_2076255cf32a$
BEGIN
  EXECUTE $bootstrap_sql_2076255cf32a$-- ===== END SOURCE: 20260920220000_merchant_free_trial_quota.sql =====
-- ===== END BUNDLE: 97_20260920220000_to_20260920220000.sql =====

-- ===== BEGIN BUNDLE: 98_20260920223000_to_20260920223000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260920223000_free_quota_expiry_notifications.sql .. 20260920223000_free_quota_expiry_notifications.sql

-- ===== BEGIN SOURCE: 20260920223000_free_quota_expiry_notifications.sql =====
-- Daily reminder for merchants whose free quota subscription expires in 7 days.
-- The delivery ledger makes the operation idempotent across repeated cron runs.

CREATE TABLE IF NOT EXISTS public.merchant_quota_expiry_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.merchant_subscriptions(id) ON DELETE CASCADE,
  reminder_days integer NOT NULL DEFAULT 7,
  sent_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subscription_id, reminder_days)
)$bootstrap_sql_2076255cf32a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2076255cf32a$;

DO $bootstrap_do_2030610f7f23$
BEGIN
  EXECUTE $bootstrap_sql_2030610f7f23$ALTER TABLE public.merchant_quota_expiry_notifications ENABLE ROW LEVEL SECURITY$bootstrap_sql_2030610f7f23$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2030610f7f23$;

DO $bootstrap_do_95e4f7806006$
BEGIN
  EXECUTE $bootstrap_sql_95e4f7806006$DROP POLICY IF EXISTS "Admins can view quota expiry notification ledger"
  ON public.merchant_quota_expiry_notifications$bootstrap_sql_95e4f7806006$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95e4f7806006$;

DO $bootstrap_do_3b638becfaf4$
BEGIN
  EXECUTE $bootstrap_sql_3b638becfaf4$CREATE POLICY "Admins can view quota expiry notification ledger"
ON public.merchant_quota_expiry_notifications
FOR SELECT
USING (public.is_admin())$bootstrap_sql_3b638becfaf4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3b638becfaf4$;

DO $bootstrap_do_0d9019e7ecc9$
BEGIN
  EXECUTE $bootstrap_sql_0d9019e7ecc9$CREATE OR REPLACE FUNCTION public.notify_free_quota_expiring_merchants()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription record;
  v_claimed_id uuid;
  v_sent_count integer := 0;
  v_remaining_quota integer;
BEGIN
  FOR v_subscription IN
    SELECT
      ms.id,
      ms.merchant_id,
      ms.transaction_quota,
      ms.used_quota,
      ms.expired_at,
      m.user_id,
      m.name AS merchant_name
    FROM public.merchant_subscriptions ms
    JOIN public.transaction_packages tp ON tp.id = ms.package_id
    JOIN public.merchants m ON m.id = ms.merchant_id
    WHERE ms.status = 'ACTIVE'
      AND tp.name = 'Paket Gratis 2 Bulan'
      AND ms.expired_at > now() + interval '6 days'
      AND ms.expired_at <= now() + interval '7 days'
      AND m.user_id IS NOT NULL
  LOOP
    v_claimed_id := NULL;

    INSERT INTO public.merchant_quota_expiry_notifications (subscription_id, reminder_days)
    VALUES (v_subscription.id, 7)
    ON CONFLICT (subscription_id, reminder_days) DO NOTHING
    RETURNING id INTO v_claimed_id;

    IF v_claimed_id IS NOT NULL THEN
      v_remaining_quota := GREATEST(0, v_subscription.transaction_quota - v_subscription.used_quota);

      PERFORM public.send_notification(
        v_subscription.user_id,
        'Kuota gratis segera berakhir',
        format(
          'Paket gratis toko %s akan berakhir dalam 7 hari pada %s. Sisa kuota Anda %s transaksi. Segera pilih paket lanjutan agar penjualan tetap berjalan.',
          v_subscription.merchant_name,
          to_char(v_subscription.expired_at AT TIME ZONE 'Asia/Jakarta', 'DD FMMonth YYYY'),
          v_remaining_quota
        ),
        'warning',
        '/merchant/subscription'
      );

      v_sent_count := v_sent_count + 1;
    END IF;
  END LOOP;

  RETURN v_sent_count;
END;
$$$bootstrap_sql_0d9019e7ecc9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d9019e7ecc9$;

DO $bootstrap_do_c488ff07dee4$
BEGIN
  EXECUTE $bootstrap_sql_c488ff07dee4$COMMENT ON FUNCTION public.notify_free_quota_expiring_merchants() IS
  'Sends one in-app reminder per free merchant subscription when it enters the 7-day expiry window.'$bootstrap_sql_c488ff07dee4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c488ff07dee4$;

DO $bootstrap_do_251f0bf45b30$
BEGIN
  EXECUTE $bootstrap_sql_251f0bf45b30$CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog$bootstrap_sql_251f0bf45b30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_251f0bf45b30$;

DO $bootstrap_do_0ab0f5231f3f$
BEGIN
  EXECUTE $bootstrap_sql_0ab0f5231f3f$DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'free-quota-expiry-reminders') THEN
    PERFORM cron.unschedule('free-quota-expiry-reminders');
  END IF;
END
$$$bootstrap_sql_0ab0f5231f3f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ab0f5231f3f$;

DO $bootstrap_do_ba81543ac311$
BEGIN
  EXECUTE $bootstrap_sql_ba81543ac311$SELECT cron.schedule(
  'free-quota-expiry-reminders',
  '15 0 * * *',
  $$SELECT public.notify_free_quota_expiring_merchants()$$
)$bootstrap_sql_ba81543ac311$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ba81543ac311$;

DO $bootstrap_do_401bf2f34956$
BEGIN
  EXECUTE $bootstrap_sql_401bf2f34956$-- ===== END SOURCE: 20260920223000_free_quota_expiry_notifications.sql =====
-- ===== END BUNDLE: 98_20260920223000_to_20260920223000.sql =====

-- ===== BEGIN BUNDLE: 99_20260920230000_to_20260920230000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260920230000_seed_free_tier_quota_setting.sql .. 20260920230000_seed_free_tier_quota_setting.sql

-- ===== BEGIN SOURCE: 20260920230000_seed_free_tier_quota_setting.sql =====
-- Keep the legacy monthly free-tier fallback configured for merchants that do
-- not have an active subscription. The onboarding package remains authoritative
-- for new merchants.
INSERT INTO public.app_settings (key, category, value, description)
VALUES (
  'free_tier_quota',
  'quota',
  '{"limit": 100}'::jsonb,
  'Batas transaksi gratis fallback per bulan untuk merchant tanpa subscription aktif'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_401bf2f34956$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_401bf2f34956$;

DO $bootstrap_do_19d39a7cec60$
BEGIN
  EXECUTE $bootstrap_sql_19d39a7cec60$-- ===== END SOURCE: 20260920230000_seed_free_tier_quota_setting.sql =====
-- ===== END BUNDLE: 99_20260920230000_to_20260920230000.sql =====

-- ===== BEGIN BUNDLE: 100_20260920240000_to_20260920240000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260920240000_merchant_categories_and_schedule.sql .. 20260920240000_merchant_categories_and_schedule.sql

-- ===== BEGIN SOURCE: 20260920240000_merchant_categories_and_schedule.sql =====
-- Multi-category merchants and safe operating-hours constraints.
-- Legacy merchants.business_category is retained for backwards compatibility.

CREATE TABLE IF NOT EXISTS public.merchant_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (merchant_id, category_id)
)$bootstrap_sql_19d39a7cec60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_19d39a7cec60$;

DO $bootstrap_do_651557d618a9$
BEGIN
  EXECUTE $bootstrap_sql_651557d618a9$CREATE INDEX IF NOT EXISTS merchant_categories_category_id_idx
  ON public.merchant_categories(category_id)$bootstrap_sql_651557d618a9$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_651557d618a9$;

DO $bootstrap_do_ef3aa3df675d$
BEGIN
  EXECUTE $bootstrap_sql_ef3aa3df675d$ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY$bootstrap_sql_ef3aa3df675d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ef3aa3df675d$;

DO $bootstrap_do_95022b59629e$
BEGIN
  EXECUTE $bootstrap_sql_95022b59629e$DROP POLICY IF EXISTS "merchant_manage_own_categories" ON public.merchant_categories$bootstrap_sql_95022b59629e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_95022b59629e$;

DO $bootstrap_do_0593ea2b6a30$
BEGIN
  EXECUTE $bootstrap_sql_0593ea2b6a30$CREATE POLICY "merchant_manage_own_categories" ON public.merchant_categories
  FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))$bootstrap_sql_0593ea2b6a30$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0593ea2b6a30$;

DO $bootstrap_do_f48f32154b4b$
BEGIN
  EXECUTE $bootstrap_sql_f48f32154b4b$DROP POLICY IF EXISTS "admin_manage_merchant_categories" ON public.merchant_categories$bootstrap_sql_f48f32154b4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f48f32154b4b$;

DO $bootstrap_do_f8ca68e7099d$
BEGIN
  EXECUTE $bootstrap_sql_f8ca68e7099d$CREATE POLICY "admin_manage_merchant_categories" ON public.merchant_categories
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin())$bootstrap_sql_f8ca68e7099d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f8ca68e7099d$;

DO $bootstrap_do_741867492163$
BEGIN
  EXECUTE $bootstrap_sql_741867492163$DROP POLICY IF EXISTS "public_read_merchant_categories" ON public.merchant_categories$bootstrap_sql_741867492163$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_741867492163$;

DO $bootstrap_do_c2539c384de4$
BEGIN
  EXECUTE $bootstrap_sql_c2539c384de4$CREATE POLICY "public_read_merchant_categories" ON public.merchant_categories
  FOR SELECT
  USING (true)$bootstrap_sql_c2539c384de4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2539c384de4$;

DO $bootstrap_do_4683c6b61058$
BEGIN
  EXECUTE $bootstrap_sql_4683c6b61058$-- Preserve the existing single-category value for all merchants during rollout.
INSERT INTO public.merchant_categories (merchant_id, category_id)
SELECT m.id, c.id
FROM public.merchants m
JOIN public.categories c ON c.slug = m.business_category
WHERE m.business_category IS NOT NULL
  AND c.is_active = true
ON CONFLICT (merchant_id, category_id) DO NOTHING$bootstrap_sql_4683c6b61058$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4683c6b61058$;

DO $bootstrap_do_c5175f8b3dc5$
BEGIN
  EXECUTE $bootstrap_sql_c5175f8b3dc5$COMMENT ON TABLE public.merchant_categories IS
  'Many-to-many category assignment for merchants. merchants.business_category remains as a legacy fallback.'$bootstrap_sql_c5175f8b3dc5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5175f8b3dc5$;

DO $bootstrap_do_136489be7d62$
BEGIN
  EXECUTE $bootstrap_sql_136489be7d62$-- Make weekly schedules safe for overnight hours while preserving existing rows.
ALTER TABLE public.merchant_operating_hours
  DROP CONSTRAINT IF EXISTS merchant_operating_hours_time_order$bootstrap_sql_136489be7d62$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_136489be7d62$;

DO $bootstrap_do_618016552a25$
BEGIN
  EXECUTE $bootstrap_sql_618016552a25$ALTER TABLE public.merchant_operating_hours
  ADD CONSTRAINT merchant_operating_hours_time_format
  CHECK (open_time IS NOT NULL AND close_time IS NOT NULL)$bootstrap_sql_618016552a25$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_618016552a25$;

DO $bootstrap_do_68404d81ebe3$
BEGIN
  EXECUTE $bootstrap_sql_68404d81ebe3$COMMENT ON TABLE public.merchant_operating_hours IS
  'Weekly merchant schedule; day_of_week uses 0 Sunday through 6 Saturday, and close_time may be earlier than open_time for overnight hours.'$bootstrap_sql_68404d81ebe3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68404d81ebe3$;

DO $bootstrap_do_0a39a0f287bd$
BEGIN
  EXECUTE $bootstrap_sql_0a39a0f287bd$NOTIFY pgrst, 'reload schema'$bootstrap_sql_0a39a0f287bd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0a39a0f287bd$;

DO $bootstrap_do_83fa3e869a99$
BEGIN
  EXECUTE $bootstrap_sql_83fa3e869a99$-- ===== END SOURCE: 20260920240000_merchant_categories_and_schedule.sql =====
-- ===== END BUNDLE: 100_20260920240000_to_20260920240000.sql =====

-- ===== BEGIN BUNDLE: 101_20260921170000_to_20260921170000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260921170000_order_notification_sounds.sql .. 20260921170000_order_notification_sounds.sql

-- ===== BEGIN SOURCE: 20260921170000_order_notification_sounds.sql =====
-- Admin-managed audio assets for order notification alarms.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'notification-sounds',
  'notification-sounds',
  true,
  5242880,
  ARRAY['audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp4']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types$bootstrap_sql_83fa3e869a99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83fa3e869a99$;

DO $bootstrap_do_55e7e31f8901$
BEGIN
  EXECUTE $bootstrap_sql_55e7e31f8901$DROP POLICY IF EXISTS "Anyone can listen to notification sounds" ON storage.objects$bootstrap_sql_55e7e31f8901$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_55e7e31f8901$;

DO $bootstrap_do_2a0c4527484e$
BEGIN
  EXECUTE $bootstrap_sql_2a0c4527484e$CREATE POLICY "Anyone can listen to notification sounds"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'notification-sounds')$bootstrap_sql_2a0c4527484e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2a0c4527484e$;

DO $bootstrap_do_12540f3dc348$
BEGIN
  EXECUTE $bootstrap_sql_12540f3dc348$DROP POLICY IF EXISTS "Admins can upload notification sounds" ON storage.objects$bootstrap_sql_12540f3dc348$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12540f3dc348$;

DO $bootstrap_do_a84813d1f2da$
BEGIN
  EXECUTE $bootstrap_sql_a84813d1f2da$CREATE POLICY "Admins can upload notification sounds"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_a84813d1f2da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a84813d1f2da$;

DO $bootstrap_do_6e18c2a89b88$
BEGIN
  EXECUTE $bootstrap_sql_6e18c2a89b88$DROP POLICY IF EXISTS "Admins can update notification sounds" ON storage.objects$bootstrap_sql_6e18c2a89b88$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6e18c2a89b88$;

DO $bootstrap_do_b0217923a592$
BEGIN
  EXECUTE $bootstrap_sql_b0217923a592$CREATE POLICY "Admins can update notification sounds"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_b0217923a592$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b0217923a592$;

DO $bootstrap_do_22b974783646$
BEGIN
  EXECUTE $bootstrap_sql_22b974783646$DROP POLICY IF EXISTS "Admins can delete notification sounds" ON storage.objects$bootstrap_sql_22b974783646$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_22b974783646$;

DO $bootstrap_do_cc30a2c8cf57$
BEGIN
  EXECUTE $bootstrap_sql_cc30a2c8cf57$CREATE POLICY "Admins can delete notification sounds"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())$bootstrap_sql_cc30a2c8cf57$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cc30a2c8cf57$;

DO $bootstrap_do_12dbdc6181e6$
BEGIN
  EXECUTE $bootstrap_sql_12dbdc6181e6$INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'order_notification_sound_settings',
  '{"enabled":true,"merchant_enabled":true,"courier_enabled":true,"preset":"urgent","custom_audio_url":"","volume":1,"repeat_count":3,"repeat_gap_ms":700}'::jsonb,
  'notification',
  'Pengaturan suara alarm pesanan masuk untuk merchant dan kurir'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_12dbdc6181e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_12dbdc6181e6$;

DO $bootstrap_do_20a9f65def78$
BEGIN
  EXECUTE $bootstrap_sql_20a9f65def78$-- ===== END SOURCE: 20260921170000_order_notification_sounds.sql =====
-- ===== END BUNDLE: 101_20260921170000_to_20260921170000.sql =====

-- ===== BEGIN BUNDLE: 102_20260921193000_to_20260921193000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260921193000_admin_direct_chat.sql .. 20260921193000_admin_direct_chat.sql

-- ===== BEGIN SOURCE: 20260921193000_admin_direct_chat.sql =====
-- Admin direct chat: allow admins to start a conversation with an active merchant or approved courier.
-- This migration is intentionally independent from order/ride chat and does not require prior messages.

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS direct_admin_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS direct_target_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE$bootstrap_sql_20a9f65def78$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_20a9f65def78$;

DO $bootstrap_do_0f08908dcb9d$
BEGIN
  EXECUTE $bootstrap_sql_0f08908dcb9d$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check$bootstrap_sql_0f08908dcb9d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f08908dcb9d$;

DO $bootstrap_do_9e8ff7bfaf6c$
BEGIN
  EXECUTE $bootstrap_sql_9e8ff7bfaf6c$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'))$bootstrap_sql_9e8ff7bfaf6c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9e8ff7bfaf6c$;

DO $bootstrap_do_614f706d97b8$
BEGIN
  EXECUTE $bootstrap_sql_614f706d97b8$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_one_context$bootstrap_sql_614f706d97b8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_614f706d97b8$;

DO $bootstrap_do_b45c82576699$
BEGIN
  EXECUTE $bootstrap_sql_b45c82576699$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_one_context CHECK (
  (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'direct' AND order_id IS NULL AND ride_request_id IS NULL AND (
    (merchant_id IS NOT NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
    OR (merchant_id IS NULL AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL)
  ))
)$bootstrap_sql_b45c82576699$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b45c82576699$;

DO $bootstrap_do_438fe93a5ccf$
BEGIN
  EXECUTE $bootstrap_sql_438fe93a5ccf$ALTER TABLE public.chat_participants DROP CONSTRAINT IF EXISTS chat_participants_role_check$bootstrap_sql_438fe93a5ccf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_438fe93a5ccf$;

DO $bootstrap_do_71f1d0006ea1$
BEGIN
  EXECUTE $bootstrap_sql_71f1d0006ea1$ALTER TABLE public.chat_participants ADD CONSTRAINT chat_participants_role_check
  CHECK (role IN ('admin', 'buyer', 'merchant', 'courier', 'passenger'))$bootstrap_sql_71f1d0006ea1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71f1d0006ea1$;

DO $bootstrap_do_627f636f3c60$
BEGIN
  EXECUTE $bootstrap_sql_627f636f3c60$ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check$bootstrap_sql_627f636f3c60$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_627f636f3c60$;

DO $bootstrap_do_f4e4a03c6eeb$
BEGIN
  EXECUTE $bootstrap_sql_f4e4a03c6eeb$ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier'))$bootstrap_sql_f4e4a03c6eeb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4e4a03c6eeb$;

DO $bootstrap_do_930769e6c0da$
BEGIN
  EXECUTE $bootstrap_sql_930769e6c0da$CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_admin_direct_uidx
  ON public.chat_conversations(direct_admin_user_id, direct_target_user_id, conversation_type)
  WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL$bootstrap_sql_930769e6c0da$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_930769e6c0da$;

DO $bootstrap_do_a2dc0b53d21a$
BEGIN
  EXECUTE $bootstrap_sql_a2dc0b53d21a$CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
  p_target_user_id uuid,
  p_target_role text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conversation_id uuid;
  v_type text;
  v_target_exists boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.chat_is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid() OR p_target_role NOT IN ('merchant', 'courier') THEN
    RAISE EXCEPTION 'invalid chat target' USING ERRCODE = '22023';
  END IF;

  IF p_target_role = 'merchant' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.merchants
      WHERE user_id = p_target_user_id AND status = 'ACTIVE'
    ) INTO v_target_exists;
    v_type := 'admin_merchant';
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.couriers
      WHERE user_id = p_target_user_id AND registration_status = 'APPROVED'
    ) INTO v_target_exists;
    v_type := 'admin_courier';
  END IF;
  IF NOT v_target_exists THEN
    RAISE EXCEPTION 'chat target account not found or inactive' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.chat_conversations (
    context_type, conversation_type, direct_admin_user_id, direct_target_user_id
  )
  VALUES ('direct', v_type, auth.uid(), p_target_user_id)
  ON CONFLICT (direct_admin_user_id, direct_target_user_id, conversation_type)
    WHERE context_type = 'direct'
      AND direct_admin_user_id IS NOT NULL
      AND direct_target_user_id IS NOT NULL
  DO UPDATE SET status = 'active', closed_at = NULL, updated_at = now()
  RETURNING id INTO v_conversation_id;

  INSERT INTO public.chat_participants (conversation_id, user_id, role)
  VALUES
    (v_conversation_id, auth.uid(), 'admin'),
    (v_conversation_id, p_target_user_id, p_target_role)
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET left_at = NULL, role = EXCLUDED.role;

  RETURN v_conversation_id;
END;
$$$bootstrap_sql_a2dc0b53d21a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a2dc0b53d21a$;

DO $bootstrap_do_953d9ef82ae1$
BEGIN
  EXECUTE $bootstrap_sql_953d9ef82ae1$REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon$bootstrap_sql_953d9ef82ae1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_953d9ef82ae1$;

DO $bootstrap_do_8b2e5a441f03$
BEGIN
  EXECUTE $bootstrap_sql_8b2e5a441f03$GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated$bootstrap_sql_8b2e5a441f03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8b2e5a441f03$;

DO $bootstrap_do_3dbed7ed6a34$
BEGIN
  EXECUTE $bootstrap_sql_3dbed7ed6a34$-- PostgREST caches database functions; reload immediately after migration.
NOTIFY pgrst, 'reload schema'$bootstrap_sql_3dbed7ed6a34$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3dbed7ed6a34$;

DO $bootstrap_do_5e3316414fde$
BEGIN
  EXECUTE $bootstrap_sql_5e3316414fde$-- ===== END SOURCE: 20260921193000_admin_direct_chat.sql =====
-- ===== END BUNDLE: 102_20260921193000_to_20260921193000.sql =====

-- ===== BEGIN BUNDLE: 103_20260921201500_to_20260921201500.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260921201500_admin_chat_notification_link.sql .. 20260921201500_admin_chat_notification_link.sql

-- ===== BEGIN SOURCE: 20260921201500_admin_chat_notification_link.sql =====
-- Route chat notifications to the correct inbox for admin recipients.
CREATE OR REPLACE FUNCTION public.chat_notification_deep_link(
  p_user_id uuid,
  p_conversation_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE COALESCE((
    SELECT role
    FROM public.chat_participants
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id
      AND left_at IS NULL
    LIMIT 1
  ), '')
    WHEN 'admin' THEN '/admin/chat?conversationId=' || p_conversation_id::text
    WHEN 'merchant' THEN '/merchant/chat?conversationId=' || p_conversation_id::text
    WHEN 'courier' THEN CASE
      WHEN c.context_type = 'ride' AND c.ride_request_id IS NOT NULL
        THEN '/courier/rides?conversationId=' || p_conversation_id::text
      ELSE '/courier/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'passenger' THEN CASE
      WHEN c.ride_request_id IS NOT NULL
        THEN '/ride/' || c.ride_request_id::text || '?conversationId=' || p_conversation_id::text
      ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
    END
    WHEN 'admin_desa' THEN '/desa/chat?conversationId=' || p_conversation_id::text
    ELSE '/buyer/chat?conversationId=' || p_conversation_id::text
  END
  FROM public.chat_conversations c
  WHERE c.id = p_conversation_id);
$$$bootstrap_sql_5e3316414fde$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e3316414fde$;

DO $bootstrap_do_5bed09301e4b$
BEGIN
  EXECUTE $bootstrap_sql_5bed09301e4b$GRANT EXECUTE ON FUNCTION public.chat_notification_deep_link(uuid, uuid)
  TO service_role$bootstrap_sql_5bed09301e4b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5bed09301e4b$;

DO $bootstrap_do_6afa0319b2f1$
BEGIN
  EXECUTE $bootstrap_sql_6afa0319b2f1$NOTIFY pgrst, 'reload schema'$bootstrap_sql_6afa0319b2f1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6afa0319b2f1$;

DO $bootstrap_do_623fe5280103$
BEGIN
  EXECUTE $bootstrap_sql_623fe5280103$-- ===== END SOURCE: 20260921201500_admin_chat_notification_link.sql =====
-- ===== END BUNDLE: 103_20260921201500_to_20260921201500.sql =====

-- ===== BEGIN BUNDLE: 104_20260922100000_to_20260922100000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260922100000_product_toppings.sql .. 20260922100000_product_toppings.sql

-- ===== BEGIN SOURCE: 20260922100000_product_toppings.sql =====
-- Product toppings: a merchant can offer existing products as add-ons for another product.
CREATE TABLE IF NOT EXISTS public.product_toppings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  topping_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT product_toppings_unique_pair UNIQUE (product_id, topping_product_id),
  CONSTRAINT product_toppings_not_self CHECK (product_id <> topping_product_id)
)$bootstrap_sql_623fe5280103$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_623fe5280103$;

DO $bootstrap_do_f09c94594e0f$
BEGIN
  EXECUTE $bootstrap_sql_f09c94594e0f$CREATE INDEX IF NOT EXISTS idx_product_toppings_product_id
  ON public.product_toppings(product_id, sort_order)$bootstrap_sql_f09c94594e0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f09c94594e0f$;

DO $bootstrap_do_8a653a01ac27$
BEGIN
  EXECUTE $bootstrap_sql_8a653a01ac27$ALTER TABLE public.product_toppings ENABLE ROW LEVEL SECURITY$bootstrap_sql_8a653a01ac27$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8a653a01ac27$;

DO $bootstrap_do_d7661bb942ee$
BEGIN
  EXECUTE $bootstrap_sql_d7661bb942ee$DROP POLICY IF EXISTS "Anyone can read active product toppings" ON public.product_toppings$bootstrap_sql_d7661bb942ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d7661bb942ee$;

DO $bootstrap_do_a07e2faabf75$
BEGIN
  EXECUTE $bootstrap_sql_a07e2faabf75$CREATE POLICY "Anyone can read active product toppings"
  ON public.product_toppings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_toppings.product_id
        AND p.is_active = true
    )
    AND EXISTS (
      SELECT 1 FROM public.products t
      WHERE t.id = product_toppings.topping_product_id
        AND t.is_active = true
    )
  )$bootstrap_sql_a07e2faabf75$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a07e2faabf75$;

DO $bootstrap_do_0d30bd90e779$
BEGIN
  EXECUTE $bootstrap_sql_0d30bd90e779$DROP POLICY IF EXISTS "Merchant manages own product toppings" ON public.product_toppings$bootstrap_sql_0d30bd90e779$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d30bd90e779$;

DO $bootstrap_do_49b125360a35$
BEGIN
  EXECUTE $bootstrap_sql_49b125360a35$CREATE POLICY "Merchant manages own product toppings"
  ON public.product_toppings FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id
        AND m.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.merchants m ON m.id = p.merchant_id
      WHERE p.id = product_toppings.product_id
        AND m.user_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM public.products t
      WHERE t.id = product_toppings.topping_product_id
        AND t.merchant_id = (SELECT parent.merchant_id FROM public.products parent WHERE parent.id = product_toppings.product_id)
    )
  )$bootstrap_sql_49b125360a35$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_49b125360a35$;

DO $bootstrap_do_850bee2581ab$
BEGIN
  EXECUTE $bootstrap_sql_850bee2581ab$GRANT SELECT ON public.product_toppings TO anon, authenticated$bootstrap_sql_850bee2581ab$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_850bee2581ab$;

DO $bootstrap_do_9ad70e126e53$
BEGIN
  EXECUTE $bootstrap_sql_9ad70e126e53$GRANT INSERT, UPDATE, DELETE ON public.product_toppings TO authenticated$bootstrap_sql_9ad70e126e53$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ad70e126e53$;

DO $bootstrap_do_e50d56deed71$
BEGIN
  EXECUTE $bootstrap_sql_e50d56deed71$COMMENT ON TABLE public.product_toppings IS 'Existing products offered as toppings/add-ons for another product.'$bootstrap_sql_e50d56deed71$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e50d56deed71$;

DO $bootstrap_do_f4ad322c9b83$
BEGIN
  EXECUTE $bootstrap_sql_f4ad322c9b83$COMMENT ON COLUMN public.product_toppings.topping_product_id IS 'The existing product whose own price and stock are used at checkout.'$bootstrap_sql_f4ad322c9b83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4ad322c9b83$;

DO $bootstrap_do_31be05e6b515$
BEGIN
  EXECUTE $bootstrap_sql_31be05e6b515$-- Keep merchant ownership checks simple and avoid relying on client-supplied prices.
CREATE OR REPLACE FUNCTION public.validate_product_topping_merchant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  parent_merchant uuid;
  topping_merchant uuid;
BEGIN
  SELECT merchant_id INTO parent_merchant FROM public.products WHERE id = NEW.product_id;
  SELECT merchant_id INTO topping_merchant FROM public.products WHERE id = NEW.topping_product_id;
  IF parent_merchant IS NULL OR topping_merchant IS NULL OR parent_merchant <> topping_merchant THEN
    RAISE EXCEPTION 'Topping harus berasal dari merchant yang sama';
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_31be05e6b515$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_31be05e6b515$;

DO $bootstrap_do_bd0a3d9da3a1$
BEGIN
  EXECUTE $bootstrap_sql_bd0a3d9da3a1$DROP TRIGGER IF EXISTS trg_validate_product_topping_merchant ON public.product_toppings$bootstrap_sql_bd0a3d9da3a1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bd0a3d9da3a1$;

DO $bootstrap_do_580be85499f3$
BEGIN
  EXECUTE $bootstrap_sql_580be85499f3$CREATE TRIGGER trg_validate_product_topping_merchant
  BEFORE INSERT OR UPDATE ON public.product_toppings
  FOR EACH ROW EXECUTE FUNCTION public.validate_product_topping_merchant()$bootstrap_sql_580be85499f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_580be85499f3$;

DO $bootstrap_do_0ce041a0eb55$
BEGIN
  EXECUTE $bootstrap_sql_0ce041a0eb55$REVOKE ALL ON FUNCTION public.validate_product_topping_merchant() FROM PUBLIC$bootstrap_sql_0ce041a0eb55$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0ce041a0eb55$;

DO $bootstrap_do_b40b009d5221$
BEGIN
  EXECUTE $bootstrap_sql_b40b009d5221$GRANT EXECUTE ON FUNCTION public.validate_product_topping_merchant() TO authenticated$bootstrap_sql_b40b009d5221$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b40b009d5221$;

DO $bootstrap_do_2d7c864cb2e2$
BEGIN
  EXECUTE $bootstrap_sql_2d7c864cb2e2$-- The checkout RPC remains authoritative: selected topping products are submitted as
-- regular p_items, so their live price, active state, and stock are revalidated there.
COMMENT ON FUNCTION public.validate_product_topping_merchant() IS 'Ensures topping and parent product belong to the same merchant.'$bootstrap_sql_2d7c864cb2e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2d7c864cb2e2$;

DO $bootstrap_do_c7cf52d5935b$
BEGIN
  EXECUTE $bootstrap_sql_c7cf52d5935b$NOTIFY pgrst, 'reload schema'$bootstrap_sql_c7cf52d5935b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c7cf52d5935b$;

DO $bootstrap_do_c83d50398738$
BEGIN
  EXECUTE $bootstrap_sql_c83d50398738$-- ===== END SOURCE: 20260922100000_product_toppings.sql =====
-- ===== END BUNDLE: 104_20260922100000_to_20260922100000.sql =====

-- ===== BEGIN BUNDLE: 105_20260922160000_to_20260922160000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260922160000_remove_cod_service_fee.sql .. 20260922160000_remove_cod_service_fee.sql

-- ===== BEGIN SOURCE: 20260922160000_remove_cod_service_fee.sql =====
-- COD is free for every transaction.
-- Normalize the setting so older clients cannot re-enable a charge.
UPDATE public.app_settings
SET value = jsonb_set(COALESCE(value, '{}'::jsonb), '{service_fee}', '0'::jsonb, true),
    updated_at = now()
WHERE key = 'cod_settings'$bootstrap_sql_c83d50398738$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c83d50398738$;

DO $bootstrap_do_c03136480c2a$
BEGIN
  EXECUTE $bootstrap_sql_c03136480c2a$-- Defense in depth for stale clients or previously deployed checkout functions:
-- strip any COD fee from both the stored fee column and the transaction total.
CREATE OR REPLACE FUNCTION public.normalize_cod_service_fee()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing_fee numeric;
BEGIN
  IF NEW.payment_method = 'COD' THEN
    v_existing_fee := COALESCE(NEW.cod_service_fee, 0);
    NEW.total := GREATEST(0, COALESCE(NEW.total, 0) - v_existing_fee);
    NEW.cod_service_fee := 0;
  END IF;
  RETURN NEW;
END;
$$$bootstrap_sql_c03136480c2a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c03136480c2a$;

DO $bootstrap_do_5a03faa935d4$
BEGIN
  EXECUTE $bootstrap_sql_5a03faa935d4$DROP TRIGGER IF EXISTS orders_free_cod_fee ON public.orders$bootstrap_sql_5a03faa935d4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a03faa935d4$;

DO $bootstrap_do_5ae2e7071a10$
BEGIN
  EXECUTE $bootstrap_sql_5ae2e7071a10$CREATE TRIGGER orders_free_cod_fee
BEFORE INSERT OR UPDATE OF payment_method, total, cod_service_fee ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.normalize_cod_service_fee()$bootstrap_sql_5ae2e7071a10$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5ae2e7071a10$;

DO $bootstrap_do_c2562c775d93$
BEGIN
  EXECUTE $bootstrap_sql_c2562c775d93$COMMENT ON FUNCTION public.normalize_cod_service_fee() IS
  'Ensures COD never adds a service fee to an order total.'$bootstrap_sql_c2562c775d93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2562c775d93$;

DO $bootstrap_do_4571a4791cfe$
BEGIN
  EXECUTE $bootstrap_sql_4571a4791cfe$-- ===== END SOURCE: 20260922160000_remove_cod_service_fee.sql =====
-- ===== END BUNDLE: 105_20260922160000_to_20260922160000.sql =====

-- ===== BEGIN BUNDLE: 106_20260922163000_to_20260922163000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260922163000_repair_marketplace_checkout_overload.sql .. 20260922163000_repair_marketplace_checkout_overload.sql

-- ===== BEGIN SOURCE: 20260922163000_repair_marketplace_checkout_overload.sql =====
-- Repair databases where the six-argument checkout function and the
-- seven-argument idempotent wrapper coexist under the same name. PostgreSQL
-- treats the wrapper's default arguments as applicable to six-argument calls,
-- which makes the RPC fail with "function is not unique".
DO $$
BEGIN
  IF to_regprocedure('public.create_marketplace_checkout(jsonb,jsonb,text,text,uuid,numeric)') IS NOT NULL THEN
    ALTER FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric)
      RENAME TO create_marketplace_checkout_legacy;
  END IF;
END;
$$$bootstrap_sql_4571a4791cfe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4571a4791cfe$;

DO $bootstrap_do_9f0331c2a284$
BEGIN
  EXECUTE $bootstrap_sql_9f0331c2a284$CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
  p_items jsonb,
  p_delivery jsonb,
  p_delivery_type text,
  p_payment_method text,
  p_voucher_id uuid DEFAULT NULL,
  p_distance_km numeric DEFAULT NULL,
  p_checkout_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing jsonb;
  v_result jsonb;
  v_merchant_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_checkout_key IS NULL OR length(trim(p_checkout_key)) < 16 OR length(trim(p_checkout_key)) > 128 THEN
    RAISE EXCEPTION 'A valid checkout key is required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || trim(p_checkout_key), 0));
  SELECT result INTO v_existing
  FROM public.marketplace_checkout_idempotency
  WHERE user_id = auth.uid() AND checkout_key = trim(p_checkout_key);
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT count(DISTINCT p.merchant_id) INTO v_merchant_count
  FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb)) AS i(product_id uuid, quantity integer)
  JOIN public.products p ON p.id = i.product_id;
  IF v_merchant_count = 0 THEN
    RAISE EXCEPTION 'Cart is empty or contains invalid products' USING ERRCODE = '22023';
  END IF;
  IF p_payment_method IN ('ONLINE', 'TRANSFER') AND v_merchant_count > 1 THEN
    RAISE EXCEPTION 'Pembayaran online dan transfer hanya tersedia untuk checkout satu toko' USING ERRCODE = '22023';
  END IF;

  v_result := public.create_marketplace_checkout_legacy(
    p_items, p_delivery, p_delivery_type, p_payment_method, p_voucher_id, p_distance_km
  );
  INSERT INTO public.marketplace_checkout_idempotency(user_id, checkout_key, result)
  VALUES (auth.uid(), trim(p_checkout_key), v_result);
  RETURN v_result;
END;
$$$bootstrap_sql_9f0331c2a284$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9f0331c2a284$;

DO $bootstrap_do_bbf162630b26$
BEGIN
  EXECUTE $bootstrap_sql_bbf162630b26$REVOKE ALL ON FUNCTION public.create_marketplace_checkout_legacy(jsonb, jsonb, text, text, uuid, numeric) FROM PUBLIC, anon$bootstrap_sql_bbf162630b26$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bbf162630b26$;

DO $bootstrap_do_53b43b051541$
BEGIN
  EXECUTE $bootstrap_sql_53b43b051541$REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon$bootstrap_sql_53b43b051541$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_53b43b051541$;

DO $bootstrap_do_eadfd3957e73$
BEGIN
  EXECUTE $bootstrap_sql_eadfd3957e73$GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role$bootstrap_sql_eadfd3957e73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eadfd3957e73$;

DO $bootstrap_do_c9160327872d$
BEGIN
  EXECUTE $bootstrap_sql_c9160327872d$NOTIFY pgrst, 'reload schema'$bootstrap_sql_c9160327872d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c9160327872d$;

DO $bootstrap_do_c74c2b2bf9fe$
BEGIN
  EXECUTE $bootstrap_sql_c74c2b2bf9fe$-- ===== END SOURCE: 20260922163000_repair_marketplace_checkout_overload.sql =====
-- ===== END BUNDLE: 106_20260922163000_to_20260922163000.sql =====$bootstrap_sql_c74c2b2bf9fe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c74c2b2bf9fe$;
