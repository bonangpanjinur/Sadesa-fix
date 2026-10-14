-- =============================================
-- MIGRASI: Fix RLS Policies untuk saved_addresses
-- =============================================
-- Tanggal: 2026-02-20
-- Deskripsi: Perbaiki RLS policies dan trigger untuk saved_addresses table
--            Tambahkan kolom email ke profiles table jika belum ada
--            Idempotent: Aman untuk dijalankan berkali-kali

-- 1. Pastikan tabel saved_addresses ada dengan benar
CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  label TEXT NOT NULL DEFAULT 'Rumah',
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  province_id TEXT,
  province_name TEXT,
  city_id TEXT,
  city_name TEXT,
  district_id TEXT,
  district_name TEXT,
  village_id TEXT,
  village_name TEXT,
  address_detail TEXT,
  full_address TEXT,
  lat NUMERIC,
  lng NUMERIC,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)$bootstrap_sql_7f2c5f150e9c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7f2c5f150e9c$;

DO $bootstrap_do_c5d75392df54$
BEGIN
  EXECUTE $bootstrap_sql_c5d75392df54$-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY$bootstrap_sql_c5d75392df54$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c5d75392df54$;

DO $bootstrap_do_8424ce93d2e6$
BEGIN
  EXECUTE $bootstrap_sql_8424ce93d2e6$-- 3. Bersihkan dan buat ulang policies
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses$bootstrap_sql_8424ce93d2e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8424ce93d2e6$;

DO $bootstrap_do_c2f153dc2d18$
BEGIN
  EXECUTE $bootstrap_sql_c2f153dc2d18$DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_c2f153dc2d18$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c2f153dc2d18$;

DO $bootstrap_do_08854fe68d0f$
BEGIN
  EXECUTE $bootstrap_sql_08854fe68d0f$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_08854fe68d0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_08854fe68d0f$;

DO $bootstrap_do_51b8a7a187fa$
BEGIN
  EXECUTE $bootstrap_sql_51b8a7a187fa$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_51b8a7a187fa$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51b8a7a187fa$;

DO $bootstrap_do_88ecc437e83b$
BEGIN
  EXECUTE $bootstrap_sql_88ecc437e83b$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_88ecc437e83b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88ecc437e83b$;

DO $bootstrap_do_0437baaf67bf$
BEGIN
  EXECUTE $bootstrap_sql_0437baaf67bf$DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_0437baaf67bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0437baaf67bf$;

DO $bootstrap_do_bf95cffb1fc7$
BEGIN
  EXECUTE $bootstrap_sql_bf95cffb1fc7$CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_bf95cffb1fc7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bf95cffb1fc7$;

DO $bootstrap_do_9da422cad5e3$
BEGIN
  EXECUTE $bootstrap_sql_9da422cad5e3$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_9da422cad5e3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9da422cad5e3$;

DO $bootstrap_do_057d5ce9fa82$
BEGIN
  EXECUTE $bootstrap_sql_057d5ce9fa82$CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_057d5ce9fa82$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_057d5ce9fa82$;

DO $bootstrap_do_b2af6070ac5a$
BEGIN
  EXECUTE $bootstrap_sql_b2af6070ac5a$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_b2af6070ac5a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2af6070ac5a$;

DO $bootstrap_do_7fc841cc052d$
BEGIN
  EXECUTE $bootstrap_sql_7fc841cc052d$CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_7fc841cc052d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7fc841cc052d$;

DO $bootstrap_do_b2461e227b58$
BEGIN
  EXECUTE $bootstrap_sql_b2461e227b58$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_b2461e227b58$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b2461e227b58$;

DO $bootstrap_do_71f851e76711$
BEGIN
  EXECUTE $bootstrap_sql_71f851e76711$CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_71f851e76711$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_71f851e76711$;

DO $bootstrap_do_02d877f0ccc1$
BEGIN
  EXECUTE $bootstrap_sql_02d877f0ccc1$-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql$bootstrap_sql_02d877f0ccc1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_02d877f0ccc1$;

DO $bootstrap_do_766c099adedc$
BEGIN
  EXECUTE $bootstrap_sql_766c099adedc$DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses$bootstrap_sql_766c099adedc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_766c099adedc$;

DO $bootstrap_do_79d0130459bf$
BEGIN
  EXECUTE $bootstrap_sql_79d0130459bf$CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()$bootstrap_sql_79d0130459bf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_79d0130459bf$;

DO $bootstrap_do_d0f769e2b74d$
BEGIN
  EXECUTE $bootstrap_sql_d0f769e2b74d$-- 5. Tambahkan kolom email ke profiles (fix bug column "email" does not exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'profiles'
    AND column_name = 'email'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN email TEXT;
  END IF;
END $$$bootstrap_sql_d0f769e2b74d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d0f769e2b74d$;

DO $bootstrap_do_9cee8cffe360$
BEGIN
  EXECUTE $bootstrap_sql_9cee8cffe360$-- 6. Backfill email dari auth.users
UPDATE public.profiles p
SET email = u.email
FROM auth.users u
WHERE p.user_id = u.id
AND p.email IS NULL$bootstrap_sql_9cee8cffe360$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9cee8cffe360$;

DO $bootstrap_do_a198a821ff5f$
BEGIN
  EXECUTE $bootstrap_sql_a198a821ff5f$-- 7. Enable realtime untuk saved_addresses (idempotent - hanya jika belum ada)
DO $$
BEGIN
  -- Check if saved_addresses is already in supabase_realtime publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON pr.prpubid = p.oid
    JOIN pg_class c ON pr.prrelid = c.oid
    WHERE p.pubname = 'supabase_realtime'
    AND c.relname = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
END $$$bootstrap_sql_a198a821ff5f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a198a821ff5f$;

DO $bootstrap_do_f7593c801f67$
BEGIN
  EXECUTE $bootstrap_sql_f7593c801f67$
