-- Drop and recreate the status check constraint to include all needed statuses
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check$bootstrap_sql_f4dd63db0f99$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f4dd63db0f99$;

DO $bootstrap_do_dc52e55866fc$
BEGIN
  EXECUTE $bootstrap_sql_dc52e55866fc$ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
CHECK (status = ANY (ARRAY[
  'NEW'::text,
  'PENDING_CONFIRMATION'::text,
  'PENDING_PAYMENT'::text,
  'PROCESSED'::text,
  'READY'::text,
  'ASSIGNED'::text,
  'PICKED_UP'::text,
  'SENT'::text,
  'DONE'::text,
  'CANCELED'::text,
  'REJECTED'::text,
  'REJECTED_BY_BUYER'::text,
  'REFUNDED'::text
]))$bootstrap_sql_dc52e55866fc$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_dc52e55866fc$;

DO $bootstrap_do_073d857ab53c$
BEGIN
  EXECUTE $bootstrap_sql_073d857ab53c$
