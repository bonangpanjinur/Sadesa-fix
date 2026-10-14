-- Add payment columns to orders table
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'UNPAID',
ADD COLUMN IF NOT EXISTS payment_invoice_id TEXT,
ADD COLUMN IF NOT EXISTS payment_invoice_url TEXT,
ADD COLUMN IF NOT EXISTS payment_paid_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS payment_method TEXT,
ADD COLUMN IF NOT EXISTS payment_channel TEXT$bootstrap_sql_57284176c6cd$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_57284176c6cd$;

DO $bootstrap_do_68465a31f15d$
BEGIN
  EXECUTE $bootstrap_sql_68465a31f15d$-- Add index for payment status
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status)$bootstrap_sql_68465a31f15d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_68465a31f15d$;

DO $bootstrap_do_61b282a9f3f3$
BEGIN
  EXECUTE $bootstrap_sql_61b282a9f3f3$-- Comment for documentation
COMMENT ON COLUMN public.orders.payment_status IS 'Payment status: UNPAID, PENDING, PAID, EXPIRED, REFUNDED'$bootstrap_sql_61b282a9f3f3$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_61b282a9f3f3$;

DO $bootstrap_do_0f5309dd61e4$
BEGIN
  EXECUTE $bootstrap_sql_0f5309dd61e4$COMMENT ON COLUMN public.orders.payment_invoice_id IS 'Xendit invoice ID'$bootstrap_sql_0f5309dd61e4$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_0f5309dd61e4$;

DO $bootstrap_do_354d43684ee1$
BEGIN
  EXECUTE $bootstrap_sql_354d43684ee1$COMMENT ON COLUMN public.orders.payment_invoice_url IS 'URL for payment page'$bootstrap_sql_354d43684ee1$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_354d43684ee1$;

DO $bootstrap_do_0352f166d51c$
BEGIN
  EXECUTE $bootstrap_sql_0352f166d51c$
