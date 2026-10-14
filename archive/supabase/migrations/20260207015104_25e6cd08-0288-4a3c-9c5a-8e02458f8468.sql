-- Add QRIS image URL to merchants table
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS qris_image_url TEXT$bootstrap_sql_9b59248d9645$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_9b59248d9645$;

DO $bootstrap_do_3cf740a73f31$
BEGIN
  EXECUTE $bootstrap_sql_3cf740a73f31$-- Add admin default payment settings to app_settings if not exists
INSERT INTO public.app_settings (key, value, category, description)
VALUES (
  'admin_payment_info',
  '{"bank_name": "", "bank_account_number": "", "bank_account_name": "", "qris_image_url": ""}',
  'payment',
  'Default payment info (bank & QRIS) used for merchants who have not set their own'
)
ON CONFLICT (key) DO NOTHING$bootstrap_sql_3cf740a73f31$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_3cf740a73f31$;

DO $bootstrap_do_9644d890d31d$
BEGIN
  EXECUTE $bootstrap_sql_9644d890d31d$
