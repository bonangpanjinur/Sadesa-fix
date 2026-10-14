-- Add payment settings columns to merchants table
ALTER TABLE public.merchants
ADD COLUMN IF NOT EXISTS payment_cod_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS payment_transfer_enabled boolean DEFAULT true,
ADD COLUMN IF NOT EXISTS bank_name text,
ADD COLUMN IF NOT EXISTS bank_account_number text,
ADD COLUMN IF NOT EXISTS bank_account_name text$bootstrap_sql_ee6e2d69fe17$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ee6e2d69fe17$;

DO $bootstrap_do_99d674b43e79$
BEGIN
  EXECUTE $bootstrap_sql_99d674b43e79$-- Update existing merchants with default values
UPDATE public.merchants SET
  payment_cod_enabled = true,
  payment_transfer_enabled = true
WHERE payment_cod_enabled IS NULL$bootstrap_sql_99d674b43e79$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_99d674b43e79$;

DO $bootstrap_do_14f375958b2c$
BEGIN
  EXECUTE $bootstrap_sql_14f375958b2c$COMMENT ON COLUMN public.merchants.payment_cod_enabled IS 'Allow COD payment for this merchant'$bootstrap_sql_14f375958b2c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_14f375958b2c$;

DO $bootstrap_do_ddd914064a96$
BEGIN
  EXECUTE $bootstrap_sql_ddd914064a96$COMMENT ON COLUMN public.merchants.payment_transfer_enabled IS 'Allow bank transfer payment for this merchant'$bootstrap_sql_ddd914064a96$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ddd914064a96$;

DO $bootstrap_do_ac14f7f42ef6$
BEGIN
  EXECUTE $bootstrap_sql_ac14f7f42ef6$COMMENT ON COLUMN public.merchants.bank_name IS 'Bank name for transfer payments'$bootstrap_sql_ac14f7f42ef6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ac14f7f42ef6$;

DO $bootstrap_do_1178e9899c2e$
BEGIN
  EXECUTE $bootstrap_sql_1178e9899c2e$COMMENT ON COLUMN public.merchants.bank_account_number IS 'Bank account number'$bootstrap_sql_1178e9899c2e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_1178e9899c2e$;

DO $bootstrap_do_2c5c4a90f926$
BEGIN
  EXECUTE $bootstrap_sql_2c5c4a90f926$COMMENT ON COLUMN public.merchants.bank_account_name IS 'Bank account holder name'$bootstrap_sql_2c5c4a90f926$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_2c5c4a90f926$;

DO $bootstrap_do_f4dd63db0f99$
BEGIN
  EXECUTE $bootstrap_sql_f4dd63db0f99$
