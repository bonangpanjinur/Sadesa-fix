-- SaDesa manual bootstrap bundle; Phase 4 debt payment and daily reconciliation.
-- Apply after bundle 24.

CREATE TABLE IF NOT EXISTS public.pos_debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('payable', 'receivable')),
  party_name text NOT NULL,
  phone text,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  remaining numeric(15,2) NOT NULL CHECK (remaining >= 0),
  due_date date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid')),
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.pos_debt_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id uuid NOT NULL REFERENCES public.pos_debts(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  amount numeric(15,2) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'transfer', 'debit', 'credit', 'other')),
  paid_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pos_debts_scope_status
  ON public.pos_debts(tenant_id, outlet_id, status, due_date);
CREATE INDEX IF NOT EXISTS idx_pos_debt_payments_scope_paid_at
  ON public.pos_debt_payments(tenant_id, outlet_id, paid_at DESC);

ALTER TABLE public.pos_debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_debt_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "POS users view debts" ON public.pos_debts;
CREATE POLICY "POS users view debts"
  ON public.pos_debts FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users create debts" ON public.pos_debts;
CREATE POLICY "POS users create debts"
  ON public.pos_debts FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND public.pos_user_can_access_outlet(tenant_id, outlet_id));
DROP POLICY IF EXISTS "POS users view debt payments" ON public.pos_debt_payments;
CREATE POLICY "POS users view debt payments"
  ON public.pos_debt_payments FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.record_pos_debt_payment(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_debt_id uuid,
  p_amount numeric,
  p_payment_method text DEFAULT 'cash',
  p_paid_at timestamptz DEFAULT now(),
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debt public.pos_debts%ROWTYPE;
  v_payment_id uuid;
  v_remaining numeric;
  v_status text;
  v_cash_type text;
  v_cash_category text;
BEGIN
  IF auth.uid() IS NULL
     OR p_amount IS NULL
     OR p_amount <= 0
     OR p_payment_method NOT IN ('cash', 'transfer', 'debit', 'credit', 'other')
     OR p_paid_at IS NULL
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid debt payment' USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_debt
  FROM public.pos_debts
  WHERE id = p_debt_id
    AND tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
  FOR UPDATE;

  IF NOT FOUND OR v_debt.status = 'paid' THEN
    RAISE EXCEPTION 'Debt is not payable' USING ERRCODE = '55000';
  END IF;
  IF p_amount > v_debt.remaining THEN
    RAISE EXCEPTION 'Payment exceeds outstanding debt' USING ERRCODE = '23514';
  END IF;

  v_remaining := GREATEST(0, v_debt.remaining - p_amount);
  v_status := CASE WHEN v_remaining = 0 THEN 'paid' ELSE 'active' END;
  v_cash_type := CASE WHEN v_debt.type = 'receivable' THEN 'in' ELSE 'out' END;
  v_cash_category := CASE WHEN v_debt.type = 'receivable' THEN 'hutang_diterima' ELSE 'hutang_bayar' END;

  INSERT INTO public.pos_debt_payments(
    debt_id, tenant_id, outlet_id, amount, payment_method, paid_at, notes, created_by
  )
  VALUES (
    v_debt.id, p_tenant_id, p_outlet_id, p_amount, p_payment_method, p_paid_at,
    NULLIF(trim(p_notes), ''), auth.uid()
  )
  RETURNING id INTO v_payment_id;

  UPDATE public.pos_debts
  SET remaining = v_remaining,
      status = v_status,
      updated_at = now()
  WHERE id = v_debt.id;

  IF p_payment_method = 'cash' THEN
    INSERT INTO public.pos_cash_mutations(
      tenant_id, outlet_id, type, category, amount, description, reference, created_by, created_at
    )
    VALUES (
      p_tenant_id,
      p_outlet_id,
      v_cash_type,
      v_cash_category,
      p_amount,
      CASE WHEN v_debt.type = 'receivable' THEN 'Pembayaran piutang: ' ELSE 'Pembayaran hutang: ' END || v_debt.party_name,
      v_payment_id::text,
      auth.uid(),
      p_paid_at
    );
  END IF;

  RETURN jsonb_build_object(
    'payment_id', v_payment_id,
    'debt_id', v_debt.id,
    'type', v_debt.type,
    'amount', p_amount,
    'remaining', v_remaining,
    'status', v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_pos_debt_payment(uuid, uuid, uuid, numeric, text, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_pos_debt_payment(uuid, uuid, uuid, numeric, text, timestamptz, text)
  TO authenticated;

-- The first reporting bundle used purchase-order cumulative amount_paid, which
-- is not safe for a bounded cashflow period. Keep it as a private implementation
-- detail and expose a corrected wrapper based on actual supplier payments.
ALTER FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  RENAME TO get_pos_canonical_report_legacy;

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
  v_report jsonb;
  v_purchases jsonb;
  v_daily jsonb := '[]'::jsonb;
  v_day jsonb;
  v_day_date date;
  v_paid numeric;
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

  v_report := public.get_pos_canonical_report_legacy(p_tenant_id, p_outlet_id, p_from, p_to);

  SELECT COALESCE(SUM(amount) FILTER (WHERE payment_method = 'cash'), 0)
  INTO v_paid
  FROM public.pos_supplier_payments
  WHERE tenant_id = p_tenant_id
    AND outlet_id = p_outlet_id
    AND paid_at >= p_from
    AND paid_at <= p_to;

  v_purchases := jsonb_set(
    COALESCE(v_report->'purchases', '{}'::jsonb),
    '{cash_paid}',
    to_jsonb(v_paid),
    true
  );
  v_report := jsonb_set(v_report, '{purchases}', v_purchases, true);

  FOR v_day IN
    SELECT value FROM jsonb_array_elements(COALESCE(v_report->'daily', '[]'::jsonb))
  LOOP
    v_day_date := (v_day->>'period')::date;
    SELECT COALESCE(SUM(amount), 0)
    INTO v_paid
    FROM public.pos_supplier_payments
    WHERE tenant_id = p_tenant_id
      AND outlet_id = p_outlet_id
      AND paid_at >= v_day_date::timestamptz
      AND paid_at < (v_day_date + 1)::timestamptz;
    v_daily := v_daily || jsonb_build_array(
      jsonb_set(v_day, '{purchase_cash}', to_jsonb(v_paid), true)
    );
  END LOOP;

  RETURN jsonb_set(v_report, '{daily}', v_daily, true);
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_canonical_report_legacy(uuid, uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_canonical_report(uuid, uuid, timestamptz, timestamptz)
  TO authenticated;

CREATE TABLE IF NOT EXISTS public.pos_daily_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.pos_tenants(id) ON DELETE CASCADE,
  outlet_id uuid NOT NULL REFERENCES public.pos_outlets(id) ON DELETE CASCADE,
  reconciliation_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('balanced', 'attention', 'unbalanced')),
  sales_total numeric(15,2) NOT NULL DEFAULT 0,
  cash_sales numeric(15,2) NOT NULL DEFAULT 0,
  cash_refunds numeric(15,2) NOT NULL DEFAULT 0,
  cash_in numeric(15,2) NOT NULL DEFAULT 0,
  cash_out numeric(15,2) NOT NULL DEFAULT 0,
  supplier_payments numeric(15,2) NOT NULL DEFAULT 0,
  shift_difference numeric(15,2) NOT NULL DEFAULT 0,
  unreconciled_sessions integer NOT NULL DEFAULT 0,
  journal_debit numeric(15,2) NOT NULL DEFAULT 0,
  journal_credit numeric(15,2) NOT NULL DEFAULT 0,
  unbalanced_journals integer NOT NULL DEFAULT 0,
  report_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  reconciled_by uuid REFERENCES auth.users(id),
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, outlet_id, reconciliation_date)
);

CREATE INDEX IF NOT EXISTS idx_pos_daily_reconciliations_scope_date
  ON public.pos_daily_reconciliations(tenant_id, outlet_id, reconciliation_date DESC);

ALTER TABLE public.pos_daily_reconciliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "POS users view daily reconciliations" ON public.pos_daily_reconciliations;
CREATE POLICY "POS users view daily reconciliations"
  ON public.pos_daily_reconciliations FOR SELECT TO authenticated
  USING (public.pos_user_can_access_outlet(tenant_id, outlet_id));

CREATE OR REPLACE FUNCTION public.get_pos_daily_reconciliation(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_reconciliation_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report jsonb;
  v_shift_difference numeric;
  v_unreconciled_sessions integer;
  v_unbalanced_journals integer;
  v_status text;
BEGIN
  IF auth.uid() IS NULL
     OR p_reconciliation_date IS NULL
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid daily reconciliation scope' USING ERRCODE = '42501';
  END IF;

  v_report := public.get_pos_canonical_report(
    p_tenant_id,
    p_outlet_id,
    p_reconciliation_date::timestamptz,
    ((p_reconciliation_date + 1)::timestamptz - interval '1 microsecond')
  );
  v_shift_difference := COALESCE((v_report #>> '{shifts,difference}')::numeric, 0);
  v_unreconciled_sessions := COALESCE((v_report #>> '{shifts,unreconciled_count}')::integer, 0);
  v_unbalanced_journals := COALESCE((v_report #>> '{journal,unbalanced_entries}')::integer, 0);
  v_status := CASE
    WHEN v_unbalanced_journals > 0 THEN 'unbalanced'
    WHEN v_unreconciled_sessions > 0 OR ABS(v_shift_difference) > 0.01 THEN 'attention'
    ELSE 'balanced'
  END;

  RETURN jsonb_build_object(
    'tenant_id', p_tenant_id,
    'outlet_id', p_outlet_id,
    'reconciliation_date', p_reconciliation_date,
    'status', v_status,
    'sales_total', COALESCE((v_report #>> '{sales,net_revenue}')::numeric, 0),
    'cash_sales', COALESCE((v_report #>> '{sales,cash}')::numeric, 0),
    'cash_refunds', COALESCE((v_report #>> '{returns,cash_refund}')::numeric, 0),
    'cash_in', COALESCE((v_report #>> '{cash_mutations,cash_in}')::numeric, 0),
    'cash_out', COALESCE((v_report #>> '{cash_mutations,cash_out}')::numeric, 0),
    'supplier_payments', COALESCE((v_report #>> '{purchases,cash_paid}')::numeric, 0),
    'shift_difference', v_shift_difference,
    'unreconciled_sessions', v_unreconciled_sessions,
    'journal_debit', COALESCE((v_report #>> '{journal,debit}')::numeric, 0),
    'journal_credit', COALESCE((v_report #>> '{journal,credit}')::numeric, 0),
    'unbalanced_journals', v_unbalanced_journals,
    'report_snapshot', v_report
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_pos_daily(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_reconciliation_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Daily reconciliation denied' USING ERRCODE = '42501';
  END IF;

  v_result := public.get_pos_daily_reconciliation(p_tenant_id, p_outlet_id, p_reconciliation_date);
  INSERT INTO public.pos_daily_reconciliations(
    tenant_id, outlet_id, reconciliation_date, status, sales_total, cash_sales,
    cash_refunds, cash_in, cash_out, supplier_payments, shift_difference,
    unreconciled_sessions, journal_debit, journal_credit, unbalanced_journals,
    report_snapshot, reconciled_by, reconciled_at, updated_at
  )
  VALUES (
    p_tenant_id, p_outlet_id, p_reconciliation_date,
    v_result->>'status',
    (v_result->>'sales_total')::numeric,
    (v_result->>'cash_sales')::numeric,
    (v_result->>'cash_refunds')::numeric,
    (v_result->>'cash_in')::numeric,
    (v_result->>'cash_out')::numeric,
    (v_result->>'supplier_payments')::numeric,
    (v_result->>'shift_difference')::numeric,
    (v_result->>'unreconciled_sessions')::integer,
    (v_result->>'journal_debit')::numeric,
    (v_result->>'journal_credit')::numeric,
    (v_result->>'unbalanced_journals')::integer,
    v_result->'report_snapshot',
    auth.uid(),
    now(),
    now()
  )
  ON CONFLICT (tenant_id, outlet_id, reconciliation_date) DO UPDATE SET
    status = EXCLUDED.status,
    sales_total = EXCLUDED.sales_total,
    cash_sales = EXCLUDED.cash_sales,
    cash_refunds = EXCLUDED.cash_refunds,
    cash_in = EXCLUDED.cash_in,
    cash_out = EXCLUDED.cash_out,
    supplier_payments = EXCLUDED.supplier_payments,
    shift_difference = EXCLUDED.shift_difference,
    unreconciled_sessions = EXCLUDED.unreconciled_sessions,
    journal_debit = EXCLUDED.journal_debit,
    journal_credit = EXCLUDED.journal_credit,
    unbalanced_journals = EXCLUDED.unbalanced_journals,
    report_snapshot = EXCLUDED.report_snapshot,
    reconciled_by = EXCLUDED.reconciled_by,
    reconciled_at = EXCLUDED.reconciled_at,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_result || jsonb_build_object('reconciliation_id', v_id, 'reconciled_at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_daily_reconciliation(uuid, uuid, date)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reconcile_pos_daily(uuid, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_daily_reconciliation(uuid, uuid, date)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_pos_daily(uuid, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pos_posted_journal(
  p_tenant_id uuid,
  p_outlet_id uuid,
  p_from date,
  p_to date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entries jsonb;
  v_total_debit numeric;
  v_total_credit numeric;
  v_entry_count integer;
BEGIN
  IF auth.uid() IS NULL
     OR p_from IS NULL
     OR p_to IS NULL
     OR p_from > p_to
     OR NOT public.pos_user_can_access_outlet(p_tenant_id, p_outlet_id) THEN
    RAISE EXCEPTION 'Invalid posted journal scope' USING ERRCODE = '42501';
  END IF;

  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'date', to_char(e.entry_date, 'DD/MM/YYYY'),
      'ref', e.entry_number,
      'description', e.memo,
      'account_code', l.account_code,
      'account_name', l.account_name,
      'debit', l.debit,
      'credit', l.credit
    ) ORDER BY e.entry_date, e.entry_number, l.id), '[]'::jsonb),
    COALESCE(SUM(l.debit), 0),
    COALESCE(SUM(l.credit), 0),
    COUNT(DISTINCT e.id)::integer
  INTO v_entries, v_total_debit, v_total_credit, v_entry_count
  FROM public.pos_journal_entries e
  JOIN public.pos_journal_lines l ON l.journal_entry_id = e.id
  WHERE e.tenant_id = p_tenant_id
    AND e.outlet_id = p_outlet_id
    AND e.status = 'posted'
    AND e.entry_date BETWEEN p_from AND p_to;

  RETURN jsonb_build_object(
    'entries', v_entries,
    'entry_count', v_entry_count,
    'total_debit', v_total_debit,
    'total_credit', v_total_credit,
    'balanced', v_total_debit = v_total_credit
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_pos_posted_journal(uuid, uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pos_posted_journal(uuid, uuid, date, date)
  TO authenticated;