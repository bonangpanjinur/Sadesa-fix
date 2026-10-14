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
)$bootstrap_sql_cf431239ec01$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf431239ec01$;

DO $bootstrap_do_56857b81b3ed$
BEGIN
  EXECUTE $bootstrap_sql_56857b81b3ed$-- 2. Aktifkan RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY$bootstrap_sql_56857b81b3ed$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_56857b81b3ed$;

DO $bootstrap_do_0c4746070705$
BEGIN
  EXECUTE $bootstrap_sql_0c4746070705$-- 3. Bersihkan dan buat ulang policies
DROP POLICY IF EXISTS "Service role has full access to saved_addresses" ON public.saved_addresses$bootstrap_sql_0c4746070705$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0c4746070705$;

DO $bootstrap_do_c363f90db26f$
BEGIN
  EXECUTE $bootstrap_sql_c363f90db26f$DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_c363f90db26f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c363f90db26f$;

DO $bootstrap_do_2b9cda5c4473$
BEGIN
  EXECUTE $bootstrap_sql_2b9cda5c4473$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_2b9cda5c4473$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2b9cda5c4473$;

DO $bootstrap_do_54ece80912e8$
BEGIN
  EXECUTE $bootstrap_sql_54ece80912e8$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_54ece80912e8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_54ece80912e8$;

DO $bootstrap_do_a540ced38452$
BEGIN
  EXECUTE $bootstrap_sql_a540ced38452$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_a540ced38452$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a540ced38452$;

DO $bootstrap_do_3a97a1eeb90d$
BEGIN
  EXECUTE $bootstrap_sql_3a97a1eeb90d$DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_3a97a1eeb90d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3a97a1eeb90d$;

DO $bootstrap_do_ae0783aabe0f$
BEGIN
  EXECUTE $bootstrap_sql_ae0783aabe0f$CREATE POLICY "Users can view own addresses"
  ON public.saved_addresses FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_ae0783aabe0f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae0783aabe0f$;

DO $bootstrap_do_8e144f35f957$
BEGIN
  EXECUTE $bootstrap_sql_8e144f35f957$DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_8e144f35f957$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e144f35f957$;

DO $bootstrap_do_d1c0d7a1defb$
BEGIN
  EXECUTE $bootstrap_sql_d1c0d7a1defb$CREATE POLICY "Users can insert own addresses"
  ON public.saved_addresses FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_d1c0d7a1defb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d1c0d7a1defb$;

DO $bootstrap_do_6d42d345337b$
BEGIN
  EXECUTE $bootstrap_sql_6d42d345337b$DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_6d42d345337b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6d42d345337b$;

DO $bootstrap_do_b6b2a94ef452$
BEGIN
  EXECUTE $bootstrap_sql_b6b2a94ef452$CREATE POLICY "Users can update own addresses"
  ON public.saved_addresses FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)$bootstrap_sql_b6b2a94ef452$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_b6b2a94ef452$;

DO $bootstrap_do_35be298de0ea$
BEGIN
  EXECUTE $bootstrap_sql_35be298de0ea$DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_35be298de0ea$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_35be298de0ea$;

DO $bootstrap_do_856d85a51f52$
BEGIN
  EXECUTE $bootstrap_sql_856d85a51f52$CREATE POLICY "Users can delete own addresses"
  ON public.saved_addresses FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id)$bootstrap_sql_856d85a51f52$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_856d85a51f52$;

DO $bootstrap_do_718e6540173d$
BEGIN
  EXECUTE $bootstrap_sql_718e6540173d$-- 4. Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql$bootstrap_sql_718e6540173d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_718e6540173d$;

DO $bootstrap_do_cfebfbcf2267$
BEGIN
  EXECUTE $bootstrap_sql_cfebfbcf2267$DROP TRIGGER IF EXISTS set_saved_addresses_updated_at ON public.saved_addresses$bootstrap_sql_cfebfbcf2267$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cfebfbcf2267$;

DO $bootstrap_do_fdaf69e7c196$
BEGIN
  EXECUTE $bootstrap_sql_fdaf69e7c196$CREATE TRIGGER set_saved_addresses_updated_at
  BEFORE UPDATE ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()$bootstrap_sql_fdaf69e7c196$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_fdaf69e7c196$;

DO $bootstrap_do_ffc2e13ba476$
BEGIN
  EXECUTE $bootstrap_sql_ffc2e13ba476$-- 5. Tambahkan kolom email ke profiles
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
END $$$bootstrap_sql_ffc2e13ba476$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ffc2e13ba476$;

DO $bootstrap_do_1fc0b4ff9d73$
BEGIN
  EXECUTE $bootstrap_sql_1fc0b4ff9d73$-- 6. Backfill email dari auth.users
UPDATE public.profiles p
SET email = u.email
FROM auth.users u
WHERE p.user_id = u.id
AND p.email IS NULL$bootstrap_sql_1fc0b4ff9d73$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1fc0b4ff9d73$;

DO $bootstrap_do_f2b46a1f8ec8$
BEGIN
  EXECUTE $bootstrap_sql_f2b46a1f8ec8$-- 7. Enable realtime untuk saved_addresses
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'saved_addresses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.saved_addresses;
  END IF;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$$bootstrap_sql_f2b46a1f8ec8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2b46a1f8ec8$;

DO $bootstrap_do_2d57410cf5af$
BEGIN
  EXECUTE $bootstrap_sql_2d57410cf5af$
