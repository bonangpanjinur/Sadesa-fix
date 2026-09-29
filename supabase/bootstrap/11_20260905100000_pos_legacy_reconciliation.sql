-- DesaMart repeatable canonical bootstrap bundle.
-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.
-- Duplicate-object errors are ignored per statement; other errors remain visible.

DO $bootstrap_do_adcf345e0a3b$
BEGIN
  EXECUTE $bootstrap_sql_adcf345e0a3b$-- POS legacy reconciliation report and safe exact-match reconciliation.
-- This migration never copies financial rows and never creates a second sale.

CREATE OR REPLACE VIEW public.pos_legacy_reconciliation_report
WITH (security_invoker = true) AS
WITH candidate_matches AS (
  SELECT
    map.id AS map_id,
    sale.id AS pos_sale_id,
    count(*) OVER (PARTITION BY map.id) AS candidate_count,
    sale.total AS modern_total
  FROM public.pos_transaction_migration_map map
  JOIN public.pos_transactions legacy ON legacy.id = map.legacy_transaction_id
  JOIN public.pos_sales sale
    ON map.tenant_id = sale.tenant_id
   AND legacy.transaction_number = sale.sale_number
)
SELECT
  legacy.id AS legacy_transaction_id,
  legacy.merchant_id,
  legacy.transaction_number,
  legacy.created_at,
  legacy.total::numeric AS legacy_total,
  map.id AS migration_map_id,
  map.tenant_id,
  map.outlet_id,
  map.pos_sale_id,
  map.status AS map_status,
  map.exception_code,
  map.notes,
  candidate.pos_sale_id AS candidate_pos_sale_id,
  candidate.candidate_count,
  candidate.modern_total,
  CASE
    WHEN map.tenant_id IS NULL THEN 'merchant_tenant_unmapped'
    WHEN map.outlet_id IS NULL THEN 'outlet_mapping_required'
    WHEN candidate.candidate_count > 1 THEN 'multiple_modern_candidates'
    WHEN candidate.pos_sale_id IS NULL THEN 'no_modern_match'
    WHEN candidate.modern_total <> legacy.total::numeric THEN 'total_mismatch'
    WHEN map.pos_sale_id IS NOT NULL THEN 'reconciled'
    ELSE 'exact_match_ready'
  END AS reconciliation_status
FROM public.pos_transactions legacy
JOIN public.pos_transaction_migration_map map
  ON map.legacy_transaction_id = legacy.id
LEFT JOIN candidate_matches candidate ON candidate.map_id = map.id$bootstrap_sql_adcf345e0a3b$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_adcf345e0a3b$;

DO $bootstrap_do_f3dfda147e2d$
BEGIN
  EXECUTE $bootstrap_sql_f3dfda147e2d$COMMENT ON VIEW public.pos_legacy_reconciliation_report IS
  'Operator report for legacy POS reconciliation. It classifies mappings without copying or deleting financial rows.'$bootstrap_sql_f3dfda147e2d$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_f3dfda147e2d$;

DO $bootstrap_do_00eb7f9d496c$
BEGIN
  EXECUTE $bootstrap_sql_00eb7f9d496c$GRANT SELECT ON public.pos_legacy_reconciliation_report TO authenticated$bootstrap_sql_00eb7f9d496c$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_00eb7f9d496c$;

DO $bootstrap_do_76c39c2877e6$
BEGIN
  EXECUTE $bootstrap_sql_76c39c2877e6$CREATE OR REPLACE FUNCTION public.reconcile_exact_legacy_pos_transactions()
RETURNS TABLE (reconciled_count integer, skipped_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reconciled integer := 0;
BEGIN
  -- Admins may run this from the application; a direct database operator call
  -- has no auth.uid() and is intentionally allowed for controlled runbooks.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Legacy reconciliation requires administrator access' USING ERRCODE = '42501';
  END IF;

  WITH candidates AS (
    SELECT
      map.id AS map_id,
      sale.id AS pos_sale_id,
      row_number() OVER (PARTITION BY map.id ORDER BY sale.created_at, sale.id) AS candidate_rank,
      count(*) OVER (PARTITION BY map.id) AS candidate_count,
      sale.total AS modern_total,
      legacy.total::numeric AS legacy_total
    FROM public.pos_transaction_migration_map map
    JOIN public.pos_transactions legacy ON legacy.id = map.legacy_transaction_id
    JOIN public.pos_sales sale
      ON map.tenant_id = sale.tenant_id
     AND legacy.transaction_number = sale.sale_number
  ), updated AS (
    UPDATE public.pos_transaction_migration_map map
    SET pos_sale_id = candidates.pos_sale_id,
        status = 'migrated',
        exception_code = NULL,
        notes = 'Reconciled by exact tenant, sale number, and total match.',
        updated_at = now()
    FROM candidates
    WHERE map.id = candidates.map_id
      AND candidates.candidate_rank = 1
      AND candidates.candidate_count = 1
      AND candidates.modern_total = candidates.legacy_total
      AND map.pos_sale_id IS NULL
    RETURNING map.id
  )
  SELECT count(*)::integer INTO v_reconciled FROM updated;

  SELECT count(*)::integer - v_reconciled
  INTO skipped_count
  FROM public.pos_transaction_migration_map;

  reconciled_count := v_reconciled;
  RETURN NEXT;
END;
$$$bootstrap_sql_76c39c2877e6$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_76c39c2877e6$;

DO $bootstrap_do_e6b2de755778$
BEGIN
  EXECUTE $bootstrap_sql_e6b2de755778$REVOKE ALL ON FUNCTION public.reconcile_exact_legacy_pos_transactions() FROM PUBLIC$bootstrap_sql_e6b2de755778$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_e6b2de755778$;

DO $bootstrap_do_4d3e2f08140e$
BEGIN
  EXECUTE $bootstrap_sql_4d3e2f08140e$GRANT EXECUTE ON FUNCTION public.reconcile_exact_legacy_pos_transactions() TO authenticated$bootstrap_sql_4d3e2f08140e$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_4d3e2f08140e$;

DO $bootstrap_do_46c5f179c8ee$
BEGIN
  EXECUTE $bootstrap_sql_46c5f179c8ee$CREATE INDEX IF NOT EXISTS idx_pos_transactions_reconciliation_key
  ON public.pos_transactions(merchant_id, transaction_number, created_at)$bootstrap_sql_46c5f179c8ee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_46c5f179c8ee$;

DO $bootstrap_do_d9c1c17c3eee$
BEGIN
  EXECUTE $bootstrap_sql_d9c1c17c3eee$CREATE INDEX IF NOT EXISTS idx_pos_sales_reconciliation_key
  ON public.pos_sales(tenant_id, sale_number, created_at)$bootstrap_sql_d9c1c17c3eee$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_d9c1c17c3eee$;
