-- Tambah kolom slug ke merchants
ALTER TABLE merchants ADD COLUMN IF NOT EXISTS slug text UNIQUE$bootstrap_sql_33e091b446d5$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_33e091b446d5$;

DO $bootstrap_do_6a97a7b2d358$
BEGIN
  EXECUTE $bootstrap_sql_6a97a7b2d358$-- Index untuk pencarian slug
CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_slug ON merchants(slug) WHERE slug IS NOT NULL$bootstrap_sql_6a97a7b2d358$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_6a97a7b2d358$;

DO $bootstrap_do_afe03730be93$
BEGIN
  EXECUTE $bootstrap_sql_afe03730be93$-- Function untuk generate slug dari nama
CREATE OR REPLACE FUNCTION generate_merchant_slug(merchant_name text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  base_slug text;
  final_slug text;
  counter integer := 0;
BEGIN
  base_slug := lower(regexp_replace(merchant_name, '[^a-zA-Z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  final_slug := base_slug;
  WHILE EXISTS (SELECT 1 FROM merchants WHERE slug = final_slug) LOOP
    counter := counter + 1;
    final_slug := base_slug || '-' || counter;
  END LOOP;
  RETURN final_slug;
END;
$$$bootstrap_sql_afe03730be93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_afe03730be93$;

DO $bootstrap_do_f2959d727f8b$
BEGIN
  EXECUTE $bootstrap_sql_f2959d727f8b$-- Set slug untuk merchant yang sudah ada
UPDATE merchants SET slug = generate_merchant_slug(name) WHERE slug IS NULL$bootstrap_sql_f2959d727f8b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f2959d727f8b$;

DO $bootstrap_do_e2a3015c2d55$
BEGIN
  EXECUTE $bootstrap_sql_e2a3015c2d55$
