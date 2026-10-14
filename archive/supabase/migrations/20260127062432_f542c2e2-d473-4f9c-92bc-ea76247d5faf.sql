-- Add foreign key for admin_audit_logs to profiles
ALTER TABLE public.admin_audit_logs
ADD CONSTRAINT admin_audit_logs_admin_id_fkey
FOREIGN KEY (admin_id) REFERENCES auth.users(id)$bootstrap_sql_873fd34cdaca$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_873fd34cdaca$;

DO $bootstrap_do_daa487bfe894$
BEGIN
  EXECUTE $bootstrap_sql_daa487bfe894$-- Add foreign key for refund_requests buyer_id to auth.users
ALTER TABLE public.refund_requests
ADD CONSTRAINT refund_requests_buyer_id_fkey
FOREIGN KEY (buyer_id) REFERENCES auth.users(id)$bootstrap_sql_daa487bfe894$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_daa487bfe894$;

DO $bootstrap_do_0ddf13359f1b$
BEGIN
  EXECUTE $bootstrap_sql_0ddf13359f1b$
