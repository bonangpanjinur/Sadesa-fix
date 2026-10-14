-- Create saved_addresses table for storing multiple addresses per user
CREATE TABLE public.saved_addresses (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
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
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
)$bootstrap_sql_f623660df96f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f623660df96f$;

DO $bootstrap_do_c6d035404f46$
BEGIN
  EXECUTE $bootstrap_sql_c6d035404f46$-- Enable RLS
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY$bootstrap_sql_c6d035404f46$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6d035404f46$;

DO $bootstrap_do_af8767cddb70$
BEGIN
  EXECUTE $bootstrap_sql_af8767cddb70$-- Users can view their own addresses
DROP POLICY IF EXISTS "Users can view own addresses" ON public.saved_addresses$bootstrap_sql_af8767cddb70$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_af8767cddb70$;

DO $bootstrap_do_020e41ae41a7$
BEGIN
  EXECUTE $bootstrap_sql_020e41ae41a7$CREATE POLICY "Users can view own addresses"
ON public.saved_addresses
FOR SELECT
USING (auth.uid() = user_id)$bootstrap_sql_020e41ae41a7$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_020e41ae41a7$;

DO $bootstrap_do_bb8a6a2149ef$
BEGIN
  EXECUTE $bootstrap_sql_bb8a6a2149ef$-- Users can insert their own addresses
DROP POLICY IF EXISTS "Users can insert own addresses" ON public.saved_addresses$bootstrap_sql_bb8a6a2149ef$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_bb8a6a2149ef$;

DO $bootstrap_do_a51590dea28b$
BEGIN
  EXECUTE $bootstrap_sql_a51590dea28b$CREATE POLICY "Users can insert own addresses"
ON public.saved_addresses
FOR INSERT
WITH CHECK (auth.uid() = user_id)$bootstrap_sql_a51590dea28b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a51590dea28b$;

DO $bootstrap_do_a1e9de014273$
BEGIN
  EXECUTE $bootstrap_sql_a1e9de014273$-- Users can update their own addresses
DROP POLICY IF EXISTS "Users can update own addresses" ON public.saved_addresses$bootstrap_sql_a1e9de014273$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_a1e9de014273$;

DO $bootstrap_do_320937dc21e1$
BEGIN
  EXECUTE $bootstrap_sql_320937dc21e1$CREATE POLICY "Users can update own addresses"
ON public.saved_addresses
FOR UPDATE
USING (auth.uid() = user_id)$bootstrap_sql_320937dc21e1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_320937dc21e1$;

DO $bootstrap_do_3c6ba67e906f$
BEGIN
  EXECUTE $bootstrap_sql_3c6ba67e906f$-- Users can delete their own addresses
DROP POLICY IF EXISTS "Users can delete own addresses" ON public.saved_addresses$bootstrap_sql_3c6ba67e906f$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3c6ba67e906f$;

DO $bootstrap_do_5a180c9183dc$
BEGIN
  EXECUTE $bootstrap_sql_5a180c9183dc$CREATE POLICY "Users can delete own addresses"
ON public.saved_addresses
FOR DELETE
USING (auth.uid() = user_id)$bootstrap_sql_5a180c9183dc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_5a180c9183dc$;

DO $bootstrap_do_8d3a34be31d5$
BEGIN
  EXECUTE $bootstrap_sql_8d3a34be31d5$-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_saved_addresses_updated_at ON public.saved_addresses$bootstrap_sql_8d3a34be31d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8d3a34be31d5$;

DO $bootstrap_do_8e0cfb827908$
BEGIN
  EXECUTE $bootstrap_sql_8e0cfb827908$CREATE TRIGGER update_saved_addresses_updated_at
BEFORE UPDATE ON public.saved_addresses
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column()$bootstrap_sql_8e0cfb827908$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_8e0cfb827908$;

DO $bootstrap_do_27e0fe238829$
BEGIN
  EXECUTE $bootstrap_sql_27e0fe238829$
