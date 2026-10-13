-- DesaMart repeatable canonical bootstrap bundle.
-- Admin-only cleanup for canceled test orders.
DO $bootstrap_do_admin_delete_canceled_order$
BEGIN
  EXECUTE $bootstrap_sql_admin_delete_canceled_order$CREATE OR REPLACE FUNCTION public.admin_delete_canceled_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted integer;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Hanya admin yang dapat menghapus pesanan';
  END IF;

  DELETE FROM public.orders
  WHERE id = p_order_id
    AND status IN ('CANCELED', 'CANCELLED');

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted = 0 THEN
    RAISE EXCEPTION 'Pesanan tidak ditemukan atau belum berstatus dibatalkan';
  END IF;
END;
$$;$bootstrap_sql_admin_delete_canceled_order$;
  EXECUTE $bootstrap_sql_admin_delete_canceled_order_grant$REVOKE ALL ON FUNCTION public.admin_delete_canceled_order(uuid) FROM PUBLIC$bootstrap_sql_admin_delete_canceled_order_grant$;
  EXECUTE $bootstrap_sql_admin_delete_canceled_order_grant_auth$GRANT EXECUTE ON FUNCTION public.admin_delete_canceled_order(uuid) TO authenticated$bootstrap_sql_admin_delete_canceled_order_grant_auth$;
EXCEPTION
  WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_admin_delete_canceled_order$;
