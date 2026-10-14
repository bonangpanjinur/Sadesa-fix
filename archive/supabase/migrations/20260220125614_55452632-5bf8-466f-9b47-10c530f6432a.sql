ALTER TABLE public.orders DROP CONSTRAINT orders_status_check$bootstrap_sql_ae9dd03e91e2$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_ae9dd03e91e2$;

DO $bootstrap_do_797d73bdc880$
BEGIN
  EXECUTE $bootstrap_sql_797d73bdc880$ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (status = ANY (ARRAY[
  'NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT', 'PROCESSED', 'READY',
  'ASSIGNED', 'PICKED_UP', 'SENT', 'DELIVERING', 'DELIVERED', 'DONE',
  'CANCELED', 'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED'
]))$bootstrap_sql_797d73bdc880$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_797d73bdc880$;

DO $bootstrap_do_3ae6ae9b8dbf$
BEGIN
  EXECUTE $bootstrap_sql_3ae6ae9b8dbf$
