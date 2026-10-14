-- =============================================
-- MIGRASI: Perbaikan Komprehensif saved_addresses
-- =============================================
-- Deskripsi: Memastikan tabel saved_addresses memiliki struktur yang benar,
--            RLS policies yang tepat, dan terdaftar di realtime publication.

-- 1. Pastikan tabel saved_addresses ada dengan struktur yang benar
CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
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
)$bootstrap_sql_3ae6ae9b8dbf$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3ae6ae9b8dbf$;

DO $bootstrap_do_f158e2545159$
BEGIN
  EXECUTE $bootstrap_sql_f158e2545159$-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY$bootstrap_sql_f158e2545159$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f158e2545159$;

DO $bootstrap_do_e7c9635d6a03$
BEGIN
  EXECUTE $bootstrap_sql_e7c9635d6a03$-- 3. Bersihkan dan buat ulang policies
-- Hapus policy lama yang mungkin bermasalah
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses$bootstrap_sql_e7c9635d6a03$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e7c9635d6a03$;

DO $bootstrap_do_7694d23f5afe$
BEGIN
  EXECUTE $bootstrap_sql_7694d23f5afe$DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_7694d23f5afe$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7694d23f5afe$;

DO $bootstrap_do_0eb395500da8$
BEGIN
  EXECUTE $bootstrap_sql_0eb395500da8$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_0eb395500da8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0eb395500da8$;

DO $bootstrap_do_2f9c690127fd$
BEGIN
  EXECUTE $bootstrap_sql_2f9c690127fd$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_2f9c690127fd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2f9c690127fd$;

DO $bootstrap_do_d8a902621425$
BEGIN
  EXECUTE $bootstrap_sql_d8a902621425$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_d8a902621425$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d8a902621425$;

DO $bootstrap_do_45f4b1f55b96$
BEGIN
  EXECUTE $bootstrap_sql_45f4b1f55b96$DROP POLICY IF EXISTS "Anyone can insert addresses" ON public.saved_addresses$bootstrap_sql_45f4b1f55b96$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_45f4b1f55b96$;

DO $bootstrap_do_51ca21ec4b83$
BEGIN
  EXECUTE $bootstrap_sql_51ca21ec4b83$-- Buat policy baru yang bersih
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_51ca21ec4b83$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_51ca21ec4b83$;

DO $bootstrap_do_e29e86b1f9d2$
BEGIN
  EXECUTE $bootstrap_sql_e29e86b1f9d2$CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_e29e86b1f9d2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e29e86b1f9d2$;

DO $bootstrap_do_5e7cbc4f4da0$
BEGIN
  EXECUTE $bootstrap_sql_5e7cbc4f4da0$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_5e7cbc4f4da0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5e7cbc4f4da0$;

DO $bootstrap_do_701324fc2589$
BEGIN
  EXECUTE $bootstrap_sql_701324fc2589$CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_701324fc2589$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_701324fc2589$;

DO $bootstrap_do_760828f2e6f6$
BEGIN
  EXECUTE $bootstrap_sql_760828f2e6f6$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_760828f2e6f6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_760828f2e6f6$;

DO $bootstrap_do_d6468d30a5a6$
BEGIN
  EXECUTE $bootstrap_sql_d6468d30a5a6$CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_d6468d30a5a6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d6468d30a5a6$;

DO $bootstrap_do_44352a135970$
BEGIN
  EXECUTE $bootstrap_sql_44352a135970$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_44352a135970$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_44352a135970$;

DO $bootstrap_do_4750b032174c$
BEGIN
  EXECUTE $bootstrap_sql_4750b032174c$CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_4750b032174c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4750b032174c$;

DO $bootstrap_do_de0a31d3c509$
BEGIN
  EXECUTE $bootstrap_sql_de0a31d3c509$-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql$bootstrap_sql_de0a31d3c509$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_de0a31d3c509$;

DO $bootstrap_do_0b85ec1f930b$
BEGIN
  EXECUTE $bootstrap_sql_0b85ec1f930b$DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses$bootstrap_sql_0b85ec1f930b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0b85ec1f930b$;

DO $bootstrap_do_c652c7f3ce6a$
BEGIN
  EXECUTE $bootstrap_sql_c652c7f3ce6a$CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()$bootstrap_sql_c652c7f3ce6a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c652c7f3ce6a$;

DO $bootstrap_do_7397ed213052$
BEGIN
  EXECUTE $bootstrap_sql_7397ed213052$-- 5. Enable realtime untuk saved_addresses (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON pr.prpubid = p.oid
    JOIN pg_class c ON pr.prrelid = c.oid
    WHERE p.pubname = 'supabase_realtime'
    AND c.relname = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not add table to publication: %', SQLERRM;
END $$$bootstrap_sql_7397ed213052$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_7397ed213052$;

DO $bootstrap_do_7f2c5f150e9c$
BEGIN
  EXECUTE $bootstrap_sql_7f2c5f150e9c$
