-- Add has_review column to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_review BOOLEAN DEFAULT FALSE$bootstrap_sql_674e0ebd5f47$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_674e0ebd5f47$;

DO $bootstrap_do_c04afc15f93e$
BEGIN
  EXECUTE $bootstrap_sql_c04afc15f93e$
