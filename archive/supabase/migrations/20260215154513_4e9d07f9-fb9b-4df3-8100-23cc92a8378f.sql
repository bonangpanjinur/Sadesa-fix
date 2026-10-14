ALTER TABLE kas_payments ADD COLUMN IF NOT EXISTS invoice_note text$bootstrap_sql_0d39acfddd5c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0d39acfddd5c$;

DO $bootstrap_do_cb08c6b29f93$
BEGIN
  EXECUTE $bootstrap_sql_cb08c6b29f93$ALTER TABLE kas_payments ADD COLUMN IF NOT EXISTS sent_at timestamptz$bootstrap_sql_cb08c6b29f93$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_cb08c6b29f93$;

DO $bootstrap_do_345681b30c24$
BEGIN
  EXECUTE $bootstrap_sql_345681b30c24$
