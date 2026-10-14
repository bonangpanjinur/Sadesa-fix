-- ====================================================================
-- MIGRASI: UPDATE LOGIKA PAKET GENERAL & KLASIFIKASI HARGA DINAMIS (REVISI)
-- ====================================================================

-- 1. Pastikan tabel transaction_packages ada
CREATE TABLE IF NOT EXISTS public.transaction_packages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  price_per_transaction INTEGER NOT NULL DEFAULT 0,
  kas_fee INTEGER NOT NULL DEFAULT 0,
  transaction_quota INTEGER NOT NULL DEFAULT 100,
  validity_days INTEGER NOT NULL DEFAULT 30,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_d8da1b2477ac$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8da1b2477ac$;

DO $bootstrap_do_eea86bc388c2$
BEGIN
  EXECUTE $bootstrap_sql_eea86bc388c2$-- Compatibility for an earlier transaction_packages shape. CREATE TABLE IF NOT EXISTS
-- does not add missing columns when the table already exists.
ALTER TABLE public.transaction_packages
  ADD COLUMN IF NOT EXISTS classification_price TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS price_per_transaction INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS kas_fee INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS transaction_quota INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS validity_days INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()$bootstrap_sql_eea86bc388c2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_eea86bc388c2$;

DO $bootstrap_do_b908b91f7759$
BEGIN
  EXECUTE $bootstrap_sql_b908b91f7759$-- 2. Keep classification_price available for package classification seeds.
-- The compatibility ALTER above adds it when an older table shape is present.

-- Menambahkan komentar untuk memperjelas fungsi kolom
COMMENT ON COLUMN public.transaction_packages.transaction_quota IS 'Total kuota transaksi (kredit) yang didapat dari paket ini'$bootstrap_sql_b908b91f7759$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b908b91f7759$;

DO $bootstrap_do_559b29fb20b2$
BEGIN
  EXECUTE $bootstrap_sql_559b29fb20b2$COMMENT ON COLUMN public.transaction_packages.price_per_transaction IS 'Biaya per transaksi dalam paket ini'$bootstrap_sql_559b29fb20b2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_559b29fb20b2$;

DO $bootstrap_do_410827302da6$
BEGIN
  EXECUTE $bootstrap_sql_410827302da6$COMMENT ON COLUMN public.transaction_packages.kas_fee IS 'Komisi kelompok/kas per transaksi'$bootstrap_sql_410827302da6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_410827302da6$;

DO $bootstrap_do_b862aff454e0$
BEGIN
  EXECUTE $bootstrap_sql_b862aff454e0$-- 3. Pastikan tabel quota_tiers ada
CREATE TABLE IF NOT EXISTS public.quota_tiers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  min_price INTEGER NOT NULL,
  max_price INTEGER, -- NULL berarti tidak ada batas atas
  credit_cost INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_b862aff454e0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b862aff454e0$;

DO $bootstrap_do_7f973465fb5f$
BEGIN
  EXECUTE $bootstrap_sql_7f973465fb5f$-- Aktifkan RLS
ALTER TABLE public.transaction_packages ENABLE ROW LEVEL SECURITY$bootstrap_sql_7f973465fb5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f973465fb5f$;

DO $bootstrap_do_6980c03eeed8$
BEGIN
  EXECUTE $bootstrap_sql_6980c03eeed8$ALTER TABLE public.quota_tiers ENABLE ROW LEVEL SECURITY$bootstrap_sql_6980c03eeed8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6980c03eeed8$;

DO $bootstrap_do_91218f2e7014$
BEGIN
  EXECUTE $bootstrap_sql_91218f2e7014$-- Kebijakan RLS untuk quota_tiers
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quota_tiers' AND policyname = 'Anyone can view quota tiers') THEN
        CREATE POLICY "Anyone can view quota tiers" ON public.quota_tiers FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quota_tiers' AND policyname = 'Admins can manage quota tiers') THEN
        CREATE POLICY "Admins can manage quota tiers" ON public.quota_tiers FOR ALL USING (is_admin());
    END IF;
END $$$bootstrap_sql_91218f2e7014$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_91218f2e7014$;

DO $bootstrap_do_58ca4c4c342a$
BEGIN
  EXECUTE $bootstrap_sql_58ca4c4c342a$-- Kebijakan RLS untuk transaction_packages (jika belum ada)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transaction_packages' AND policyname = 'Anyone can view active packages') THEN
        CREATE POLICY "Anyone can view active packages" ON public.transaction_packages FOR SELECT USING (is_active = true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transaction_packages' AND policyname = 'Admins can manage packages') THEN
        CREATE POLICY "Admins can manage packages" ON public.transaction_packages FOR ALL USING (is_admin());
    END IF;
END $$$bootstrap_sql_58ca4c4c342a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_58ca4c4c342a$;

DO $bootstrap_do_7c4b78207b38$
BEGIN
  EXECUTE $bootstrap_sql_7c4b78207b38$-- 4. Update data paket default (General)
-- Pertahankan paket dan subscription existing. Seed berikutnya hanya
-- menambahkan baris yang belum ada.
SELECT 1$bootstrap_sql_7c4b78207b38$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7c4b78207b38$;

DO $bootstrap_do_0c6383f39b45$
BEGIN
  EXECUTE $bootstrap_sql_0c6383f39b45$INSERT INTO public.transaction_packages (name, price_per_transaction, kas_fee, transaction_quota, validity_days, description, is_active) VALUES
('Paket Hemat', 500, 200, 50, 0, 'Paket dasar untuk pemula tanpa masa aktif', true),
('Paket Reguler', 450, 150, 100, 0, 'Paket standar untuk usaha menengah tanpa masa aktif', true),
('Paket Premium', 400, 100, 250, 0, 'Paket terbaik dengan biaya transaksi termurah tanpa masa aktif', true)
ON CONFLICT DO NOTHING$bootstrap_sql_0c6383f39b45$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c6383f39b45$;

DO $bootstrap_do_d0e0bbeef887$
BEGIN
  EXECUTE $bootstrap_sql_d0e0bbeef887$-- 5. Update data tier kuota default sesuai permintaan user
-- Pertahankan tier existing. Seed berikutnya hanya menambahkan baris yang
-- belum ada dan tidak mereset konfigurasi yang mungkin sudah dikustomisasi.
SELECT 1$bootstrap_sql_d0e0bbeef887$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d0e0bbeef887$;

DO $bootstrap_do_2c6f4c061cb4$
BEGIN
  EXECUTE $bootstrap_sql_2c6f4c061cb4$INSERT INTO public.quota_tiers (min_price, max_price, credit_cost) VALUES
(0, 3000, 1),
(3001, 5000, 1), -- Contoh user: > 3000 dan < 5000 menghabiskan 1 kuota
(5001, 10000, 2), -- Contoh user: > 5000 dan < 10000 menghabiskan 2 kuota
(10001, NULL, 3)
ON CONFLICT DO NOTHING$bootstrap_sql_2c6f4c061cb4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c6f4c061cb4$;

DO $bootstrap_do_7dec80706b7e$
BEGIN
  EXECUTE $bootstrap_sql_7dec80706b7e$-- 6. Modifikasi tabel merchants
-- Menghapus kolom classification_price jika ada
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='merchants' AND column_name='classification_price') THEN
        ALTER TABLE public.merchants DROP COLUMN classification_price;
    END IF;
END $$$bootstrap_sql_7dec80706b7e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7dec80706b7e$;

DO $bootstrap_do_0636fcb1102d$
BEGIN
  EXECUTE $bootstrap_sql_0636fcb1102d$-- 7. Update fungsi kalkulasi biaya kredit (kredit per transaksi)
CREATE OR REPLACE FUNCTION public.calculate_item_credit_cost(p_price INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_credit_cost INTEGER;
BEGIN
  SELECT credit_cost INTO v_credit_cost
  FROM public.quota_tiers
  WHERE p_price >= min_price
    AND (max_price IS NULL OR p_price <= max_price)
  ORDER BY min_price DESC
  LIMIT 1;

  RETURN COALESCE(v_credit_cost, 1);
END;
$$$bootstrap_sql_0636fcb1102d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0636fcb1102d$;

DO $bootstrap_do_83198b946baf$
BEGIN
  EXECUTE $bootstrap_sql_83198b946baf$-- 8. Update fungsi use_merchant_quota_v2 untuk mendukung pengurangan kuota dinamis
CREATE OR REPLACE FUNCTION public.use_merchant_quota_v2(p_merchant_id UUID, p_credits INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub_id UUID;
BEGIN
  -- Cari langganan aktif yang memiliki sisa kuota cukup
  -- Tanpa mengecek expired_at jika validity_days di paket adalah 0 (tanpa masa aktif)
  SELECT ms.id INTO v_sub_id
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now())
    AND (ms.transaction_quota - ms.used_quota) >= p_credits
  ORDER BY ms.created_at ASC -- Gunakan paket yang paling lama dulu (FIFO)
  LIMIT 1;

  IF v_sub_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE merchant_subscriptions
  SET used_quota = used_quota + p_credits, updated_at = now()
  WHERE id = v_sub_id;

  RETURN TRUE;
END;
$$$bootstrap_sql_83198b946baf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83198b946baf$;

DO $bootstrap_do_e559de4d9509$
BEGIN
  EXECUTE $bootstrap_sql_e559de4d9509$-- 9. Update fungsi check_merchant_quota untuk mendukung logika baru
CREATE OR REPLACE FUNCTION public.check_merchant_quota(p_merchant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_quota INTEGER;
  v_used_quota INTEGER;
BEGIN
  -- Hitung total kuota dari semua paket aktif
  SELECT
    COALESCE(SUM(ms.transaction_quota), 0),
    COALESCE(SUM(ms.used_quota), 0)
  INTO v_total_quota, v_used_quota
  FROM merchant_subscriptions ms
  JOIN transaction_packages tp ON ms.package_id = tp.id
  WHERE ms.merchant_id = p_merchant_id
    AND ms.status = 'ACTIVE'
    AND (tp.validity_days = 0 OR ms.expired_at > now());

  IF v_total_quota = 0 OR (v_total_quota - v_used_quota) <= 0 THEN
    RETURN jsonb_build_object(
      'can_transact', false,
      'reason', 'Tidak ada kuota transaksi aktif. Silakan beli paket terlebih dahulu.',
      'remaining_quota', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'can_transact', true,
    'remaining_quota', v_total_quota - v_used_quota
  );
END;
$$$bootstrap_sql_e559de4d9509$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e559de4d9509$;

DO $bootstrap_do_a741e3720b4d$
BEGIN
  EXECUTE $bootstrap_sql_a741e3720b4d$
