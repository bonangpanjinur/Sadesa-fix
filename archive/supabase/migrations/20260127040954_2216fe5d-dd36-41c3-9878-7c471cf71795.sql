-- Add verifikator referral system
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS verifikator_code text,
ADD COLUMN IF NOT EXISTS verifikator_id uuid,
ADD COLUMN IF NOT EXISTS trade_group text,
ADD COLUMN IF NOT EXISTS province text,
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS district text,
ADD COLUMN IF NOT EXISTS subdistrict text,
ADD COLUMN IF NOT EXISTS business_category text DEFAULT 'kuliner',
ADD COLUMN IF NOT EXISTS business_description text$bootstrap_sql_9b4eebf3f9e7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b4eebf3f9e7$;

DO $bootstrap_do_cf39c454d2eb$
BEGIN
  EXECUTE $bootstrap_sql_cf39c454d2eb$-- Create verifikator_codes table for referral system
CREATE TABLE IF NOT EXISTS public.verifikator_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verifikator_id uuid NOT NULL,
  code text NOT NULL UNIQUE,
  trade_group text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0,
  max_usage integer,
  created_at timestamp with time zone NOT NULL DEFAULT now()
)$bootstrap_sql_cf39c454d2eb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cf39c454d2eb$;

DO $bootstrap_do_2db08653a2f0$
BEGIN
  EXECUTE $bootstrap_sql_2db08653a2f0$-- Enable RLS
ALTER TABLE public.verifikator_codes ENABLE ROW LEVEL SECURITY$bootstrap_sql_2db08653a2f0$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2db08653a2f0$;

DO $bootstrap_do_10a3d47220f7$
BEGIN
  EXECUTE $bootstrap_sql_10a3d47220f7$-- Anyone can view active codes (for validation)
DROP POLICY IF EXISTS "Anyone can view active codes" ON public.verifikator_codes$bootstrap_sql_10a3d47220f7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_10a3d47220f7$;

DO $bootstrap_do_dfc3249cbc87$
BEGIN
  EXECUTE $bootstrap_sql_dfc3249cbc87$CREATE POLICY "Anyone can view active codes"
ON public.verifikator_codes
FOR SELECT
USING (is_active = true)$bootstrap_sql_dfc3249cbc87$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dfc3249cbc87$;

DO $bootstrap_do_04b011811082$
BEGIN
  EXECUTE $bootstrap_sql_04b011811082$-- Verifikator can manage their own codes
DROP POLICY IF EXISTS "Verifikator can manage own codes" ON public.verifikator_codes$bootstrap_sql_04b011811082$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_04b011811082$;

DO $bootstrap_do_5565d7735997$
BEGIN
  EXECUTE $bootstrap_sql_5565d7735997$CREATE POLICY "Verifikator can manage own codes"
ON public.verifikator_codes
FOR ALL
USING (
  verifikator_id = auth.uid() OR
  is_admin()
)$bootstrap_sql_5565d7735997$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5565d7735997$;

DO $bootstrap_do_4ce8eac82a49$
BEGIN
  EXECUTE $bootstrap_sql_4ce8eac82a49$-- Admin can manage all codes
DROP POLICY IF EXISTS "Admin can manage all codes" ON public.verifikator_codes$bootstrap_sql_4ce8eac82a49$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4ce8eac82a49$;

DO $bootstrap_do_e083a22a4feb$
BEGIN
  EXECUTE $bootstrap_sql_e083a22a4feb$CREATE POLICY "Admin can manage all codes"
ON public.verifikator_codes
FOR ALL
USING (is_admin())$bootstrap_sql_e083a22a4feb$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e083a22a4feb$;

DO $bootstrap_do_da7c1ffe7e4a$
BEGIN
  EXECUTE $bootstrap_sql_da7c1ffe7e4a$-- Update villages to include subdistrict for matching
ALTER TABLE public.villages
ADD COLUMN IF NOT EXISTS subdistrict text$bootstrap_sql_da7c1ffe7e4a$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_da7c1ffe7e4a$;

DO $bootstrap_do_5d1f93becc72$
BEGIN
  EXECUTE $bootstrap_sql_5d1f93becc72$-- Update existing villages with subdistrict from district if not set
UPDATE public.villages
SET subdistrict = district
WHERE subdistrict IS NULL$bootstrap_sql_5d1f93becc72$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5d1f93becc72$;

DO $bootstrap_do_88cf7bcb93cd$
BEGIN
  EXECUTE $bootstrap_sql_88cf7bcb93cd$-- Insert sample verifikator codes for testing
INSERT INTO public.verifikator_codes (verifikator_id, code, trade_group, description)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'KULINER2024', 'Kelompok Kuliner Desa', 'Kode referral untuk pedagang kuliner'),
  ('00000000-0000-0000-0000-000000000000', 'KRIYA2024', 'Kelompok Kerajinan Tangan', 'Kode referral untuk pengrajin'),
  ('00000000-0000-0000-0000-000000000000', 'FASHION2024', 'Kelompok Fashion Lokal', 'Kode referral untuk pedagang fashion')
ON CONFLICT (code) DO NOTHING$bootstrap_sql_88cf7bcb93cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_88cf7bcb93cd$;

DO $bootstrap_do_e5b81e1d1d59$
BEGIN
  EXECUTE $bootstrap_sql_e5b81e1d1d59$
