-- Merchant audit operations: server summaries and atomic stock adjustments.
DO $bootstrap_do_merchant_audit_ops$
BEGIN
  EXECUTE $bootstrap_sql_merchant_order_summary$
    CREATE OR REPLACE FUNCTION public.merchant_order_summary(p_merchant_id uuid)
    RETURNS TABLE(total_orders bigint, new_orders bigint, processed_orders bigint, shipping_orders bigint, completed_orders bigint, total_revenue numeric)
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
    BEGIN
      IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid()
      ) THEN
        RAISE EXCEPTION 'Merchant tidak ditemukan' USING ERRCODE = '42501';
      END IF;
      RETURN QUERY
      SELECT
        count(*)::bigint,
        count(*) FILTER (WHERE o.status IN ('NEW','PENDING_CONFIRMATION','PENDING_PAYMENT'))::bigint,
        count(*) FILTER (WHERE o.status IN ('PROCESSED','READY','ASSIGNED','COURIER_ASSIGNED','COURIER_ACCEPTED','PICKED_UP'))::bigint,
        count(*) FILTER (WHERE o.status IN ('SENT','DELIVERING','ON_DELIVERY','DELIVERED'))::bigint,
        count(*) FILTER (WHERE o.status = 'DONE')::bigint,
        COALESCE(sum(o.subtotal) FILTER (WHERE o.status IN ('DONE','DELIVERED')), 0)::numeric
      FROM public.orders o
      WHERE o.merchant_id = p_merchant_id;
    END;
    $fn$;
    GRANT EXECUTE ON FUNCTION public.merchant_order_summary(uuid) TO authenticated
  $bootstrap_sql_merchant_order_summary$;

  EXECUTE $bootstrap_sql_stock_history$
    CREATE TABLE IF NOT EXISTS public.stock_history (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
      merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
      type text NOT NULL,
      qty_change integer NOT NULL,
      stock_before integer NOT NULL,
      stock_after integer NOT NULL,
      note text,
      created_by uuid REFERENCES auth.users(id),
      created_at timestamptz NOT NULL DEFAULT now()
    )
  $bootstrap_sql_stock_history$;

  EXECUTE $bootstrap_sql_stock_rpc$
    CREATE OR REPLACE FUNCTION public.merchant_adjust_stock_atomic(
      p_product_id uuid, p_merchant_id uuid, p_type text, p_quantity integer, p_note text DEFAULT NULL
    ) RETURNS public.products LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
    DECLARE v_product public.products%ROWTYPE; v_after integer; v_change integer;
    BEGIN
      IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.merchants m WHERE m.id = p_merchant_id AND m.user_id = auth.uid()
      ) THEN RAISE EXCEPTION 'Merchant tidak ditemukan' USING ERRCODE = '42501'; END IF;
      IF p_quantity IS NULL OR p_quantity < 0 OR p_type NOT IN ('in','out','set') THEN
        RAISE EXCEPTION 'Penyesuaian stok tidak valid' USING ERRCODE = '22023';
      END IF;
      SELECT * INTO v_product FROM public.products WHERE id = p_product_id AND merchant_id = p_merchant_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Produk tidak ditemukan' USING ERRCODE = 'P0002'; END IF;
      v_after := CASE p_type WHEN 'in' THEN v_product.stock + p_quantity WHEN 'out' THEN GREATEST(0, v_product.stock - p_quantity) ELSE p_quantity END;
      v_change := v_after - v_product.stock;
      UPDATE public.products SET stock = v_after WHERE id = p_product_id;
      INSERT INTO public.stock_history(product_id, merchant_id, type, qty_change, stock_before, stock_after, note, created_by)
      VALUES (p_product_id, p_merchant_id, CASE p_type WHEN 'in' THEN 'masuk' WHEN 'out' THEN 'keluar' ELSE 'penyesuaian' END, v_change, v_product.stock, v_after, NULLIF(trim(p_note), ''), auth.uid());
      SELECT * INTO v_product FROM public.products WHERE id = p_product_id;
      RETURN v_product;
    END;
    $fn$;
    GRANT EXECUTE ON FUNCTION public.merchant_adjust_stock_atomic(uuid,uuid,text,integer,text) TO authenticated
  $bootstrap_sql_stock_rpc$;
EXCEPTION WHEN duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation THEN NULL;
END $bootstrap_do_merchant_audit_ops$;
