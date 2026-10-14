-- 1. Tambahkan kolom verifikator_code jika belum ada
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS verifikator_code text$bootstrap_sql_0fd3bc9ad2fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0fd3bc9ad2fd$;

DO $bootstrap_do_83464e6b79f6$
BEGIN
  EXECUTE $bootstrap_sql_83464e6b79f6$-- 2. Tambahkan index untuk performa pencarian (opsional tapi disarankan)
CREATE INDEX IF NOT EXISTS idx_merchants_verifikator_code ON public.merchants(verifikator_code)$bootstrap_sql_83464e6b79f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83464e6b79f6$;

DO $bootstrap_do_98a0aac51c79$
BEGIN
  EXECUTE $bootstrap_sql_98a0aac51c79$-- 3. Perbarui Policy agar Merchant bisa melihat data mereka sendiri
-- Hapus policy lama untuk menghindari konflik
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants$bootstrap_sql_98a0aac51c79$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_98a0aac51c79$;

DO $bootstrap_do_83c1a7d14fec$
BEGIN
  EXECUTE $bootstrap_sql_83c1a7d14fec$DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants$bootstrap_sql_83c1a7d14fec$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_83c1a7d14fec$;

DO $bootstrap_do_d99de37b645c$
BEGIN
  EXECUTE $bootstrap_sql_d99de37b645c$-- Buat policy baru yang mengizinkan akses ke semua kolom (termasuk verifikator_code)
DROP POLICY IF EXISTS "Merchants can view own data" ON public.merchants$bootstrap_sql_d99de37b645c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d99de37b645c$;

DO $bootstrap_do_8574c4fe8d9c$
BEGIN
  EXECUTE $bootstrap_sql_8574c4fe8d9c$CREATE POLICY "Merchants can view own data"
ON public.merchants FOR SELECT
USING (auth.uid() = id)$bootstrap_sql_8574c4fe8d9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8574c4fe8d9c$;

DO $bootstrap_do_9859ed860460$
BEGIN
  EXECUTE $bootstrap_sql_9859ed860460$DROP POLICY IF EXISTS "Merchants can update own data" ON public.merchants$bootstrap_sql_9859ed860460$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9859ed860460$;

DO $bootstrap_do_18a71333900f$
BEGIN
  EXECUTE $bootstrap_sql_18a71333900f$CREATE POLICY "Merchants can update own data"
ON public.merchants FOR UPDATE
USING (auth.uid() = id)$bootstrap_sql_18a71333900f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_18a71333900f$;

DO $bootstrap_do_33e091b446d5$
BEGIN
  EXECUTE $bootstrap_sql_33e091b446d5$
