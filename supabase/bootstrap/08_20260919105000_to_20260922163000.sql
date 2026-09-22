-- DesaMart canonical bootstrap bundle; consolidated from ordered bundles.
-- DO NOT apply to an existing project with migration history.
-- Consolidated range: 92_20260919105000_merchant_ad_payment_proof_storage.sql .. 106_20260922163000_to_20260922163000.sql

-- ===== BEGIN BUNDLE: 92_20260919105000_merchant_ad_payment_proof_storage.sql =====
-- Merchant paid-ad payment proofs are uploaded under <merchant_id>/<file>.
-- Keep this separate from buyer order proofs, whose policies are more restrictive.
DROP POLICY IF EXISTS "Merchant can upload ad payment proof" ON storage.objects;
CREATE POLICY "Merchant can upload ad payment proof" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id::text = split_part(name, '/', 1)
        AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Merchant can read own ad payment proof" ON storage.objects;
CREATE POLICY "Merchant can read own ad payment proof" ON storage.objects
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
  );

DROP POLICY IF EXISTS "Admin can read ad payment proof" ON storage.objects;
CREATE POLICY "Admin can read ad payment proof" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'payment-proofs' AND public.is_admin());

NOTIFY pgrst, 'reload schema';
-- ===== END BUNDLE: 92_20260919105000_merchant_ad_payment_proof_storage.sql =====

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
$$;

COMMENT ON COLUMN public.refund_settlements.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund settlement records.';
COMMENT ON COLUMN public.merchant_refund_shortfalls.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase refund shortfall records.';
COMMENT ON COLUMN public.quota_audit_logs.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase quota audit records.';
COMMENT ON COLUMN public.verifikator_earnings.merchant_id IS
  'Nullable historical reference; merchant deletion must not erase commission records.';
-- ===== END BUNDLE: 93_20260920100000_admin_merchant_delete_fk_repair.sql =====

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
$$;

COMMENT ON COLUMN public.marketplace_stock_reservation_items.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.';
COMMENT ON COLUMN public.marketplace_stock_reservation_items.variant_id IS
  'Nullable historical reference; removed product variants must not block merchant deletion.';
COMMENT ON COLUMN public.marketplace_stock_allocations.product_id IS
  'Nullable historical reference; removed merchant products must not block merchant deletion.';
-- ===== END BUNDLE: 94_20260920110000_merchant_delete_stock_reservation_fk_repair.sql =====

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
);

CREATE TABLE IF NOT EXISTS public.merchant_ads (
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
);

CREATE INDEX IF NOT EXISTS idx_ad_packages_active ON public.ad_packages(is_active, placement_type);
CREATE INDEX IF NOT EXISTS idx_merchant_ads_delivery ON public.merchant_ads(placement_type, status, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_merchant_ads_merchant ON public.merchant_ads(merchant_id, created_at DESC);

ALTER TABLE public.ad_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_ads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active ad packages" ON public.ad_packages;
CREATE POLICY "Anyone can view active ad packages" ON public.ad_packages
  FOR SELECT USING (is_active = true OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admin manages ad packages" ON public.ad_packages;
CREATE POLICY "Admin manages ad packages" ON public.ad_packages
  FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Public can view active merchant ads" ON public.merchant_ads;
CREATE POLICY "Public can view active merchant ads" ON public.merchant_ads
  FOR SELECT USING (
    status = 'active'
    AND (start_date IS NULL OR start_date <= now())
    AND (end_date IS NULL OR end_date > now())
  );

DROP POLICY IF EXISTS "Merchant can view own ads" ON public.merchant_ads;
CREATE POLICY "Merchant can view own ads" ON public.merchant_ads
  FOR SELECT TO authenticated USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Merchant can submit own ads" ON public.merchant_ads;
CREATE POLICY "Merchant can submit own ads" ON public.merchant_ads
  FOR INSERT TO authenticated WITH CHECK (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
    AND status = 'pending'
  );

DROP POLICY IF EXISTS "Admin moderates merchant ads" ON public.merchant_ads;
CREATE POLICY "Admin moderates merchant ads" ON public.merchant_ads
  FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admin deletes merchant ads" ON public.merchant_ads;
CREATE POLICY "Admin deletes merchant ads" ON public.merchant_ads
  FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- A public bucket is needed for creative images; database policies still control
-- which campaigns can be delivered to buyers.
INSERT INTO storage.buckets (id, name, public)
VALUES ('merchant-ads', 'merchant-ads', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public can view merchant ad creatives" ON storage.objects;
CREATE POLICY "Public can view merchant ad creatives" ON storage.objects
  FOR SELECT USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can upload merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can upload merchant ad creatives" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can update merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can update merchant ad creatives" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'merchant-ads');

DROP POLICY IF EXISTS "Authenticated users can delete merchant ad creatives" ON storage.objects;
CREATE POLICY "Authenticated users can delete merchant ad creatives" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'merchant-ads');

INSERT INTO public.ad_packages (name, placement_type, description, price_per_day, max_days)
SELECT * FROM (VALUES
  ('Spotlight Pencarian', 'search_top', 'Produk Anda muncul di atas hasil pencarian', 15000::numeric, 30),
  ('Teratas Kategori', 'category_top', 'Muncul paling atas di halaman kategori', 20000::numeric, 30),
  ('Banner Homepage', 'home_banner', 'Tampil sebagai rekomendasi sponsor di halaman utama', 50000::numeric, 14),
  ('Produk Pilihan', 'product_recommend', 'Tampil di seksi produk pilihan', 10000::numeric, 30)
) AS seed(name, placement_type, description, price_per_day, max_days)
WHERE NOT EXISTS (SELECT 1 FROM public.ad_packages WHERE ad_packages.placement_type = seed.placement_type);

-- ===== END SOURCE: 20260918233000_merchant_paid_ads.sql =====
-- ===== END BUNDLE: 95_20260918233000_to_20260918233000.sql =====

-- ===== BEGIN BUNDLE: 96_20260919123000_to_20260919123000.sql =====
-- DesaMart canonical bootstrap bundle; consolidated from deployment sources.
-- DO NOT apply to an existing project with migration history.
-- Source range: 20260919123000_active_merchant_category.sql .. 20260919123000_active_merchant_category.sql

-- ===== BEGIN SOURCE: 20260919123000_active_merchant_category.sql =====
-- Keep merchant business categories aligned with the admin-managed categories catalog.
ALTER TABLE public.merchants
  ALTER COLUMN business_category SET DEFAULT NULL;

CREATE OR REPLACE FUNCTION public.validate_active_merchant_business_category()
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
$$;

DROP TRIGGER IF EXISTS merchants_active_business_category ON public.merchants;
CREATE TRIGGER merchants_active_business_category
  BEFORE INSERT OR UPDATE OF business_category ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_active_merchant_business_category();

COMMENT ON FUNCTION public.validate_active_merchant_business_category() IS
  'Prevents merchant registrations and updates from using categories that are missing or inactive in the admin catalog.';

-- ===== END SOURCE: 20260919123000_active_merchant_category.sql =====
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
);

CREATE OR REPLACE FUNCTION public.grant_new_merchant_free_trial()
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
$$;

DROP TRIGGER IF EXISTS grant_new_merchant_free_trial_trigger ON public.merchants;
CREATE TRIGGER grant_new_merchant_free_trial_trigger
AFTER INSERT ON public.merchants
FOR EACH ROW
EXECUTE FUNCTION public.grant_new_merchant_free_trial();

COMMENT ON FUNCTION public.grant_new_merchant_free_trial() IS
  'Automatically activates new merchants and grants the 2-month free transaction quota.';

-- ===== END SOURCE: 20260920220000_merchant_free_trial_quota.sql =====
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
);

ALTER TABLE public.merchant_quota_expiry_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view quota expiry notification ledger"
  ON public.merchant_quota_expiry_notifications;
CREATE POLICY "Admins can view quota expiry notification ledger"
ON public.merchant_quota_expiry_notifications
FOR SELECT
USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.notify_free_quota_expiring_merchants()
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
$$;

COMMENT ON FUNCTION public.notify_free_quota_expiring_merchants() IS
  'Sends one in-app reminder per free merchant subscription when it enters the 7-day expiry window.';

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'free-quota-expiry-reminders') THEN
    PERFORM cron.unschedule('free-quota-expiry-reminders');
  END IF;
END
$$;

SELECT cron.schedule(
  'free-quota-expiry-reminders',
  '15 0 * * *',
  $$SELECT public.notify_free_quota_expiring_merchants()$$
);

-- ===== END SOURCE: 20260920223000_free_quota_expiry_notifications.sql =====
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
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260920230000_seed_free_tier_quota_setting.sql =====
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
);

CREATE INDEX IF NOT EXISTS merchant_categories_category_id_idx
  ON public.merchant_categories(category_id);

ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merchant_manage_own_categories" ON public.merchant_categories;
CREATE POLICY "merchant_manage_own_categories" ON public.merchant_categories
  FOR ALL
  USING (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()))
  WITH CHECK (merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "admin_manage_merchant_categories" ON public.merchant_categories;
CREATE POLICY "admin_manage_merchant_categories" ON public.merchant_categories
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "public_read_merchant_categories" ON public.merchant_categories;
CREATE POLICY "public_read_merchant_categories" ON public.merchant_categories
  FOR SELECT
  USING (true);

-- Preserve the existing single-category value for all merchants during rollout.
INSERT INTO public.merchant_categories (merchant_id, category_id)
SELECT m.id, c.id
FROM public.merchants m
JOIN public.categories c ON c.slug = m.business_category
WHERE m.business_category IS NOT NULL
  AND c.is_active = true
ON CONFLICT (merchant_id, category_id) DO NOTHING;

COMMENT ON TABLE public.merchant_categories IS
  'Many-to-many category assignment for merchants. merchants.business_category remains as a legacy fallback.';

-- Make weekly schedules safe for overnight hours while preserving existing rows.
ALTER TABLE public.merchant_operating_hours
  DROP CONSTRAINT IF EXISTS merchant_operating_hours_time_order;

ALTER TABLE public.merchant_operating_hours
  ADD CONSTRAINT merchant_operating_hours_time_format
  CHECK (open_time IS NOT NULL AND close_time IS NOT NULL);

COMMENT ON TABLE public.merchant_operating_hours IS
  'Weekly merchant schedule; day_of_week uses 0 Sunday through 6 Saturday, and close_time may be earlier than open_time for overnight hours.';

NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260920240000_merchant_categories_and_schedule.sql =====
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
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Anyone can listen to notification sounds" ON storage.objects;
CREATE POLICY "Anyone can listen to notification sounds"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'notification-sounds');

DROP POLICY IF EXISTS "Admins can upload notification sounds" ON storage.objects;
CREATE POLICY "Admins can upload notification sounds"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can update notification sounds" ON storage.objects;
CREATE POLICY "Admins can update notification sounds"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin())
WITH CHECK (bucket_id = 'notification-sounds' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete notification sounds" ON storage.objects;
CREATE POLICY "Admins can delete notification sounds"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'notification-sounds' AND public.is_admin());

INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'order_notification_sound_settings',
  '{"enabled":true,"merchant_enabled":true,"courier_enabled":true,"preset":"urgent","custom_audio_url":"","volume":1,"repeat_count":3,"repeat_gap_ms":700}'::jsonb,
  'notification',
  'Pengaturan suara alarm pesanan masuk untuk merchant dan kurir'
)
ON CONFLICT (key) DO NOTHING;

-- ===== END SOURCE: 20260921170000_order_notification_sounds.sql =====
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
  ADD COLUMN IF NOT EXISTS direct_target_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_context_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_context_type_check
  CHECK (context_type IN ('order', 'ride', 'direct'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_one_context;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_one_context CHECK (
  (context_type = 'order' AND order_id IS NOT NULL AND ride_request_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'ride' AND ride_request_id IS NOT NULL AND order_id IS NULL AND merchant_id IS NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
  OR (context_type = 'direct' AND order_id IS NULL AND ride_request_id IS NULL AND (
    (merchant_id IS NOT NULL AND direct_admin_user_id IS NULL AND direct_target_user_id IS NULL)
    OR (merchant_id IS NULL AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL)
  ))
);

ALTER TABLE public.chat_participants DROP CONSTRAINT IF EXISTS chat_participants_role_check;
ALTER TABLE public.chat_participants ADD CONSTRAINT chat_participants_role_check
  CHECK (role IN ('admin', 'buyer', 'merchant', 'courier', 'passenger'));

ALTER TABLE public.chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_conversation_type_check;
ALTER TABLE public.chat_conversations ADD CONSTRAINT chat_conversations_conversation_type_check
  CHECK (conversation_type IN ('buyer_merchant', 'buyer_courier', 'merchant_courier', 'passenger_courier', 'admin_merchant', 'admin_courier'));

CREATE UNIQUE INDEX IF NOT EXISTS chat_conversations_admin_direct_uidx
  ON public.chat_conversations(direct_admin_user_id, direct_target_user_id, conversation_type)
  WHERE context_type = 'direct' AND direct_admin_user_id IS NOT NULL AND direct_target_user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_or_create_admin_direct_chat(
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
$$;

REVOKE ALL ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_admin_direct_chat(uuid, text) TO authenticated;

-- PostgREST caches database functions; reload immediately after migration.
NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260921193000_admin_direct_chat.sql =====
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
$$;

GRANT EXECUTE ON FUNCTION public.chat_notification_deep_link(uuid, uuid)
  TO service_role;

NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260921201500_admin_chat_notification_link.sql =====
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
);

CREATE INDEX IF NOT EXISTS idx_product_toppings_product_id
  ON public.product_toppings(product_id, sort_order);

ALTER TABLE public.product_toppings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active product toppings" ON public.product_toppings;
CREATE POLICY "Anyone can read active product toppings"
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
  );

DROP POLICY IF EXISTS "Merchant manages own product toppings" ON public.product_toppings;
CREATE POLICY "Merchant manages own product toppings"
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
  );

GRANT SELECT ON public.product_toppings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_toppings TO authenticated;
COMMENT ON TABLE public.product_toppings IS 'Existing products offered as toppings/add-ons for another product.';
COMMENT ON COLUMN public.product_toppings.topping_product_id IS 'The existing product whose own price and stock are used at checkout.';

-- Keep merchant ownership checks simple and avoid relying on client-supplied prices.
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
$$;

DROP TRIGGER IF EXISTS trg_validate_product_topping_merchant ON public.product_toppings;
CREATE TRIGGER trg_validate_product_topping_merchant
  BEFORE INSERT OR UPDATE ON public.product_toppings
  FOR EACH ROW EXECUTE FUNCTION public.validate_product_topping_merchant();

REVOKE ALL ON FUNCTION public.validate_product_topping_merchant() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_product_topping_merchant() TO authenticated;

-- The checkout RPC remains authoritative: selected topping products are submitted as
-- regular p_items, so their live price, active state, and stock are revalidated there.
COMMENT ON FUNCTION public.validate_product_topping_merchant() IS 'Ensures topping and parent product belong to the same merchant.';

NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260922100000_product_toppings.sql =====
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
WHERE key = 'cod_settings';

-- Defense in depth for stale clients or previously deployed checkout functions:
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
$$;

DROP TRIGGER IF EXISTS orders_free_cod_fee ON public.orders;
CREATE TRIGGER orders_free_cod_fee
BEFORE INSERT OR UPDATE OF payment_method, total, cod_service_fee ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.normalize_cod_service_fee();

COMMENT ON FUNCTION public.normalize_cod_service_fee() IS
  'Ensures COD never adds a service fee to an order total.';

-- ===== END SOURCE: 20260922160000_remove_cod_service_fee.sql =====
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
$$;

CREATE OR REPLACE FUNCTION public.create_marketplace_checkout(
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
$$;

REVOKE ALL ON FUNCTION public.create_marketplace_checkout_legacy(jsonb, jsonb, text, text, uuid, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_marketplace_checkout(jsonb, jsonb, text, text, uuid, numeric, text) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';

-- ===== END SOURCE: 20260922163000_repair_marketplace_checkout_overload.sql =====
-- ===== END BUNDLE: 106_20260922163000_to_20260922163000.sql =====

