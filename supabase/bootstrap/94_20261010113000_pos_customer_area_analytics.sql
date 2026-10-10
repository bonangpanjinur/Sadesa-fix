-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: adds nullable area fields without altering existing customer records.
DO $bootstrap_do_c9a0dc1b8f42$
BEGIN
  EXECUTE $bootstrap_sql_c9a0dc1b8f42$ALTER TABLE public.pos_customers
    ADD COLUMN IF NOT EXISTS district_name text,
    ADD COLUMN IF NOT EXISTS city_name text$bootstrap_sql_c9a0dc1b8f42$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR unique_violation THEN NULL;
END $bootstrap_do_c9a0dc1b8f42$;
