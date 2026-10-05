-- Restore the merchant order summary RPC for deployments where the client shipped
-- before the earlier operational bootstrap bundle was applied.
DO $bootstrap_do_merchant_order_summary_rpc$
BEGIN
  EXECUTE $bootstrap_sql_merchant_order_summary_rpc$
    CREATE OR REPLACE FUNCTION public.merchant_order_summary(p_merchant_id uuid)
    RETURNS TABLE(
      total_orders bigint,
      new_orders bigint,
      processed_orders bigint,
      shipping_orders bigint,
      completed_orders bigint,
      total_revenue numeric
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $fn$
    BEGIN
      IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.merchants m
        WHERE m.id = p_merchant_id
          AND m.user_id = auth.uid()
      ) THEN
        RAISE EXCEPTION 'Merchant tidak ditemukan' USING ERRCODE = '42501';
      END IF;

      RETURN QUERY
      SELECT
        count(*)::bigint,
        count(*) FILTER (WHERE o.status IN ('NEW', 'PENDING_CONFIRMATION', 'PENDING_PAYMENT'))::bigint,
        count(*) FILTER (WHERE o.status IN ('PROCESSED', 'READY', 'ASSIGNED', 'COURIER_ASSIGNED', 'COURIER_ACCEPTED', 'PICKED_UP'))::bigint,
        count(*) FILTER (WHERE o.status IN ('SENT', 'DELIVERING', 'ON_DELIVERY', 'DELIVERED'))::bigint,
        count(*) FILTER (WHERE o.status = 'DONE')::bigint,
        COALESCE(sum(o.subtotal) FILTER (WHERE o.status IN ('DONE', 'DELIVERED')), 0)::numeric
      FROM public.orders o
      WHERE o.merchant_id = p_merchant_id;
    END;
    $fn$
  $bootstrap_sql_merchant_order_summary_rpc$;

  EXECUTE 'REVOKE ALL ON FUNCTION public.merchant_order_summary(uuid) FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.merchant_order_summary(uuid) TO authenticated';
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_merchant_order_summary_rpc$;

COMMENT ON FUNCTION public.merchant_order_summary(uuid)
  IS 'Returns order totals for the authenticated owner of the requested merchant.';

NOTIFY pgrst, 'reload schema';
