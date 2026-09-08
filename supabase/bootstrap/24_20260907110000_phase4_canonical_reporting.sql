-- SaDesa manual bootstrap bundle; Phase 4 canonical reporting.
-- Apply after bundle 23 on a project that already has the POS bootstrap.
-- This bundle intentionally keeps reporting calculations server-side so every
-- report/export uses the same tenant, outlet, status, and date definitions.

CREATE OR REPLACE FUNCTION public.get_pos_canonical_report(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sales jsonb;
  v_returns jsonb;
  v_cash jsonb;
  v_cash_mutations jsonb;
  v_purchases jsonb;
  v_shifts jsonb;
  v_journal_summary jsonb;
  v_daily jsonb;
  v_top_products jsonb;
BEGIN
  IF auth.uid() IS NULL
     OR p_tenant_id IS NULL
     OR p_outlet_id IS NULL
     OR p_from IS NULL
     OR p_to IS NULL
     OR p_from > p_to
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid canonical report scope' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'transactions', COUNT(*)::integer,
    'gross_revenue', COALESCE(SUM(subtotal), 0),
    'discounts', COALESCE(SUM(discount_amount), 0),
    'tax', COALESCE(SUM(tax_amount), 0),
    'net_revenue', COALESCE(SUM(total), 0),
    'cash', COALESCE(SUM(total) FILTER (WHERE payment_method = 'cash'), 0),
    'qris', COALESCE(SUM(total) FILTER (WHERE payment_method = 'qris'), 0),
    'transfer', COALESCE(SUM(total) FILTER (WHERE payment_method = 'transfer'), 0),
    'debit', COALESCE(SUM(total) FILTER (WHERE payment_method = 'debit'), 0),
    'credit', COALESCE(SUM(total) FILTER (WHERE payment_method = 'credit'), 0),
    'split', COALESCE(SUM(total) FILTER (WHERE payment_method = 'split'), 0)
  )
  INTO v_sales
  FROM public.pos_sales
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status = 'completed'
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cogs', COALESCE(SUM(i.cost_price * i.qty), 0),
    'items', COALESCE(SUM(i.qty), 0)
  )
  INTO v_returns
  FROM public.pos_sale_items i
  JOIN public.pos_sales s ON s.id = i.sale_id
  WHERE s.tenant_id = p_tenant_id
    AND s.outlet_id = p_outlet_id
    AND s.status = 'completed'
    AND s.created_at >= p_from
    AND s.created_at <= p_to;

  SELECT jsonb_build_object(
    'count', COUNT(*)::integer,
    'total_refund', COALESCE(SUM(total_refund), 0),
    'cash_refund', COALESCE(SUM(total_refund) FILTER (WHERE refund_method = 'cash'), 0),
    'store_credit_refund', COALESCE(SUM(total_refund) FILTER (WHERE refund_method = 'store_credit'), 0)
  )
  INTO v_cash
  FROM public.pos_sale_returns
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status IN ('approved', 'processed')
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cash_in', COALESCE(SUM(amount) FILTER (WHERE type = 'in' AND COALESCE(category, 'other') <> 'sales_cash'), 0),
    'cash_out', COALESCE(SUM(amount) FILTER (WHERE type = 'out'), 0),
    'by_category', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('category', category, 'type', type, 'amount', amount))
      FROM (
        SELECT type, COALESCE(category, 'other') AS category, SUM(amount) AS amount
        FROM public.pos_cash_mutations
        WHERE tenant_id = p_tenant_id
          AND outlet_id = p_outlet_id
          AND created_at >= p_from
          AND created_at <= p_to
          AND NOT (type = 'in' AND category = 'sales_cash')
        GROUP BY type, COALESCE(category, 'other')
        ORDER BY type, amount DESC
      ) mutation_totals
    ), '[]'::jsonb)
  )
  INTO v_cash_mutations
  FROM public.pos_cash_mutations
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND created_at >= p_from
    AND created_at <= p_to;

  SELECT jsonb_build_object(
    'cash_paid', COALESCE(SUM(amount_paid), 0),
    'received_total', COALESCE(SUM(total), 0),
    'count', COUNT(*)::integer,
    'by_status', COALESCE(jsonb_agg(jsonb_build_object('status', status, 'amount_paid', amount_paid)), '[]'::jsonb)
  )
  INTO v_purchases
  FROM public.pos_purchase_orders
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND status IN ('received', 'partial')
    AND COALESCE(received_date::timestamptz, created_at) >= p_from
    AND COALESCE(received_date::timestamptz, created_at) <= p_to;

  SELECT jsonb_build_object(
    'closed_count', COUNT(*) FILTER (WHERE status = 'closed')::integer,
    'open_count', COUNT(*) FILTER (WHERE status = 'open')::integer,
    'difference', COALESCE(SUM(difference) FILTER (WHERE status = 'closed'), 0),
    'absolute_difference', COALESCE(SUM(ABS(difference)) FILTER (WHERE status = 'closed'), 0),
    'unreconciled_count', COUNT(*) FILTER (WHERE status = 'closed' AND COALESCE(difference, 0) <> 0)::integer
  )
  INTO v_shifts
  FROM public.pos_cash_sessions
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND opened_at >= p_from
    AND opened_at <= p_to;

  SELECT jsonb_build_object(
    'entry_count', COUNT(DISTINCT e.id)::integer,
    'debit', COALESCE(SUM(l.debit), 0),
    'credit', COALESCE(SUM(l.credit), 0),
    'balanced', COALESCE(SUM(l.debit), 0) = COALESCE(SUM(l.credit), 0),
    'unbalanced_entries', COUNT(DISTINCT e.id) FILTER (WHERE e.id IN (
      SELECT entry_id
      FROM (
        SELECT e2.id AS entry_id, SUM(l2.debit) AS debit, SUM(l2.credit) AS credit
        FROM public.pos_journal_entries e2
        JOIN public.pos_journal_lines l2 ON l2.journal_entry_id = e2.id
        WHERE e2.tenant_id = p_tenant_id
          AND (e2.outlet_id = p_outlet_id OR e2.outlet_id IS NULL)
          AND e2.status = 'posted'
          AND e2.entry_date >= p_from::date
          AND e2.entry_date <= p_to::date
        GROUP BY e2.id
        HAVING SUM(l2.debit) <> SUM(l2.credit)
      ) unbalanced
    ))::integer
  )
  INTO v_journal_summary
  FROM public.pos_journal_entries e
  JOIN public.pos_journal_lines l ON l.journal_entry_id = e.id
  WHERE e.tenant_id = p_tenant_id
    AND (e.outlet_id = p_outlet_id OR e.outlet_id IS NULL)
    AND e.status = 'posted'
    AND e.entry_date >= p_from::date
    AND e.entry_date <= p_to::date;

  SELECT COALESCE(jsonb_agg(row_to_json(product_totals)::jsonb ORDER BY product_totals.profit DESC), '[]'::jsonb)
  INTO v_top_products
  FROM (
    SELECT
      i.product_name AS name,
      SUM(i.qty) AS qty,
      SUM(i.subtotal) AS revenue,
      SUM(i.cost_price * i.qty) AS cogs,
      SUM(i.subtotal - (i.cost_price * i.qty)) AS profit
    FROM public.pos_sale_items i
    JOIN public.pos_sales s ON s.id = i.sale_id
    WHERE s.tenant_id = p_tenant_id
      AND s.outlet_id = p_outlet_id
      AND s.status = 'completed'
      AND s.created_at >= p_from
      AND s.created_at <= p_to
    GROUP BY i.product_name
    ORDER BY profit DESC
    LIMIT 10
  ) product_totals;

  SELECT COALESCE(jsonb_agg(row_to_json(day_totals)::jsonb ORDER BY day_totals.period), '[]'::jsonb)
  INTO v_daily
  FROM (
    SELECT
      d.period::date AS period,
      COALESCE((
        SELECT SUM(s.total)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS revenue,
      COALESCE((
        SELECT SUM(s.discount_amount)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS discounts,
      COALESCE((
        SELECT SUM(si.cost_price * si.qty)
        FROM public.pos_sale_items si
        JOIN public.pos_sales s ON s.id = si.sale_id
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      ), 0) AS cogs,
      (
        SELECT COUNT(*)
        FROM public.pos_sales s
        WHERE s.tenant_id = p_tenant_id
          AND s.outlet_id = p_outlet_id
          AND s.status = 'completed'
          AND s.created_at >= d.period
          AND s.created_at < d.period + interval '1 day'
      )::integer AS transactions,
      COALESCE((
        SELECT SUM(amount)
        FROM public.pos_cash_mutations m
        WHERE m.tenant_id = p_tenant_id
          AND m.outlet_id = p_outlet_id
          AND m.type = 'in'
          AND m.category <> 'sales_cash'
          AND m.created_at >= d.period
          AND m.created_at < d.period + interval '1 day'
      ), 0) AS cash_in,
      COALESCE((
        SELECT SUM(amount)
        FROM public.pos_cash_mutations m
        WHERE m.tenant_id = p_tenant_id
          AND m.outlet_id = p_outlet_id
          AND m.type = 'out'
          AND m.created_at >= d.period
          AND m.created_at < d.period + interval '1 day'
      ), 0) AS cash_out,
      COALESCE((
        SELECT SUM(amount_paid)
        FROM public.pos_purchase_orders p
        WHERE p.tenant_id = p_tenant_id
          AND p.outlet_id = p_outlet_id
          AND p.status IN ('received', 'partial')
          AND COALESCE(p.received_date::timestamptz, p.created_at) >= d.period
          AND COALESCE(p.received_date::timestamptz, p.created_at) < d.period + interval '1 day'
      ), 0) AS purchase_cash
    FROM generate_series(p_from::date, p_to::date, interval '1 day') d(period)
  ) day_totals;

  RETURN jsonb_build_object(
    'scope', jsonb_build_object('tenant_id', p_tenant_id, 'outlet_id', p_outlet_id, 'from', p_from, 'to', p_to),
    'sales', v_sales,
    'costs', v_returns,
    'returns', v_cash,
    'cash_mutations', v_cash_mutations,
    'purchases', v_purchases,
    'shifts', v_shifts,
    'journal', v_journal_summary,
    'top_products', v_top_products,
    'daily', v_daily
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
IS 'Canonical tenant/outlet-scoped POS reporting contract. Uses completed sales, approved/processed returns, actual cash mutations, paid purchases, closed shifts, and posted journals.';