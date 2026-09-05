\set ON_ERROR_STOP on
\pset pager off
\pset tuples_only on
\pset format unaligned
\pset fieldsep '|'

SELECT 'snapshot_started_at', now();
SELECT 'database', current_database();
SELECT 'database_user', current_user;
SELECT 'server_version', current_setting('server_version');

SELECT 'active_merchants', count(*)
FROM public.merchants
WHERE COALESCE(is_active, true) = true;

SELECT 'active_pos_tenants', count(*)
FROM public.pos_tenants
WHERE is_active = true;

SELECT 'active_pos_tenants_without_merchant', count(*)
FROM public.pos_tenants
WHERE is_active = true AND merchant_id IS NULL;

SELECT 'active_pos_outlets', count(*)
FROM public.pos_outlets
WHERE is_active = true;

SELECT 'active_pos_users', count(*)
FROM public.pos_users
WHERE is_active = true;

SELECT 'active_merchant_products', count(*)
FROM public.products
WHERE is_active = true;

SELECT 'active_pos_products', count(*)
FROM public.pos_products
WHERE is_active = true;

SELECT 'active_merchant_products_without_projection', count(*)
FROM public.products product
JOIN public.pos_tenants tenant
  ON tenant.merchant_id = product.merchant_id
 AND tenant.is_active = true
WHERE product.is_active = true
  AND NOT EXISTS (
    SELECT 1
    FROM public.pos_products projection
    WHERE projection.tenant_id = tenant.id
      AND projection.merchant_product_id = product.id
  );

SELECT 'pos_stock_rows', count(*)
FROM public.pos_stock;

SELECT 'pos_stock_negative_rows', count(*)
FROM public.pos_stock
WHERE quantity < 0;

SELECT 'active_outlets_without_stock_rows', count(*)
FROM public.pos_outlets outlet
WHERE outlet.is_active = true
  AND NOT EXISTS (
    SELECT 1
    FROM public.pos_stock stock
    WHERE stock.tenant_id = outlet.tenant_id
      AND stock.outlet_id = outlet.id
  );

SELECT 'legacy_pos_transactions', count(*)
FROM public.pos_transactions;

SELECT 'modern_pos_sales', count(*)
FROM public.pos_sales;

SELECT 'legacy_transactions_mapped', count(*)
FROM public.pos_transaction_migration_map;

SELECT 'legacy_transactions_unmapped', count(*)
FROM public.pos_transactions legacy
LEFT JOIN public.pos_transaction_migration_map mapping
  ON mapping.legacy_transaction_id = legacy.id
WHERE mapping.id IS NULL;

SELECT 'legacy_transactions_exception', count(*)
FROM public.pos_transaction_migration_map
WHERE status = 'exception';

SELECT 'unified_history_rows', count(*)
FROM public.pos_unified_transaction_history;

SELECT 'modern_sales_total', COALESCE(sum(total), 0)
FROM public.pos_sales
WHERE status = 'completed';

SELECT 'legacy_transactions_total', COALESCE(sum(total), 0)
FROM public.pos_transactions
WHERE upper(status) IN ('COMPLETED', 'COMPLETE', 'PAID');

SELECT 'snapshot_finished_at', now();
