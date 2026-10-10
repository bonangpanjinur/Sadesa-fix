-- Support the merchant stock-history feed and composite-key order pagination.
DO $bootstrap_do_merchant_history_query_indexes$
BEGIN
  EXECUTE $bootstrap_sql_stock_history_index$
    CREATE INDEX IF NOT EXISTS idx_stock_history_merchant_created_at_id
    ON public.stock_history (merchant_id, created_at DESC, id DESC)
  $bootstrap_sql_stock_history_index$;

  EXECUTE $bootstrap_sql_merchant_orders_index$
    CREATE INDEX IF NOT EXISTS idx_orders_merchant_created_at_id
    ON public.orders (merchant_id, created_at DESC, id DESC)
  $bootstrap_sql_merchant_orders_index$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_merchant_history_query_indexes$;
