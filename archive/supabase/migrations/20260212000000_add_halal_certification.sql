-- Update merchants table with halal certification fields
ALTER TABLE merchants
ADD COLUMN IF NOT EXISTS halal_status text DEFAULT 'NONE',
ADD COLUMN IF NOT EXISTS halal_certificate_url text,
ADD COLUMN IF NOT EXISTS ktp_url text$bootstrap_sql_cd0a39cab9f2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cd0a39cab9f2$;

DO $bootstrap_do_c6ec9395a327$
BEGIN
  EXECUTE $bootstrap_sql_c6ec9395a327$-- Create halal_regulations table
CREATE TABLE IF NOT EXISTS halal_regulations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
)$bootstrap_sql_c6ec9395a327$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_c6ec9395a327$;

DO $bootstrap_do_947112bff8b5$
BEGIN
  EXECUTE $bootstrap_sql_947112bff8b5$-- Add RLS policies for halal_regulations
ALTER TABLE halal_regulations ENABLE ROW LEVEL SECURITY$bootstrap_sql_947112bff8b5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_947112bff8b5$;

DO $bootstrap_do_9ea7ccd21ce8$
BEGIN
  EXECUTE $bootstrap_sql_9ea7ccd21ce8$-- Policy: Allow public read access to halal_regulations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'halal_regulations' AND policyname = 'Allow public read access to halal_regulations'
    ) THEN
        CREATE POLICY "Allow public read access to halal_regulations"
        ON halal_regulations FOR SELECT
        USING (true);
    END IF;
END $$$bootstrap_sql_9ea7ccd21ce8$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9ea7ccd21ce8$;

DO $bootstrap_do_42d42f1a2113$
BEGIN
  EXECUTE $bootstrap_sql_42d42f1a2113$-- Policy: Allow admin to manage halal_regulations
-- Using public.is_admin() function which is standard in this project
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'halal_regulations' AND policyname = 'Allow admin to manage halal_regulations'
    ) THEN
        CREATE POLICY "Allow admin to manage halal_regulations"
        ON halal_regulations FOR ALL
        USING (public.is_admin());
    END IF;
END $$$bootstrap_sql_42d42f1a2113$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_42d42f1a2113$;

DO $bootstrap_do_5a043f05e227$
BEGIN
  EXECUTE $bootstrap_sql_5a043f05e227$
