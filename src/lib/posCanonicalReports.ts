import { supabase } from '@/integrations/supabase/client';

export interface CanonicalDailyReport {
  period: string;
  revenue: number;
  discounts: number;
  cogs: number;
  transactions: number;
  cash_in: number;
  cash_out: number;
  purchase_cash: number;
}

export interface CanonicalReport {
  scope: { tenant_id: string; outlet_id: string; from: string; to: string };
  sales: {
    transactions: number;
    gross_revenue: number;
    discounts: number;
    tax: number;
    net_revenue: number;
    cash: number;
    qris: number;
    transfer: number;
    debit: number;
    credit: number;
    split: number;
  };
  costs: { cogs: number; items: number };
  returns: {
    count: number;
    total_refund: number;
    cash_refund: number;
    store_credit_refund: number;
  };
  cash_mutations: {
    cash_in: number;
    cash_out: number;
    by_category: { category: string; type: 'in' | 'out'; amount: number }[];
  };
  purchases: {
    cash_paid: number;
    received_total: number;
    count: number;
    by_status: { status: string; amount_paid: number }[];
  };
  shifts: {
    closed_count: number;
    open_count: number;
    difference: number;
    absolute_difference: number;
    unreconciled_count: number;
  };
  journal: {
    entry_count: number;
    debit: number;
    credit: number;
    balanced: boolean;
    unbalanced_entries: number;
  };
  top_products: { name: string; qty: number; revenue: number; cogs: number; profit: number }[];
  daily: CanonicalDailyReport[];
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
}

function asNumber(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function normalizeReport(value: unknown): CanonicalReport {
  const raw = asRecord(value);
  const scope = asRecord(raw.scope);
  const sales = asRecord(raw.sales);
  const costs = asRecord(raw.costs);
  const returns = asRecord(raw.returns);
  const cashMutations = asRecord(raw.cash_mutations);
  const purchases = asRecord(raw.purchases);
  const shifts = asRecord(raw.shifts);
  const journal = asRecord(raw.journal);

  return {
    scope: {
      tenant_id: String(scope.tenant_id || ''),
      outlet_id: String(scope.outlet_id || ''),
      from: String(scope.from || ''),
      to: String(scope.to || ''),
    },
    sales: {
      transactions: asNumber(sales.transactions),
      gross_revenue: asNumber(sales.gross_revenue),
      discounts: asNumber(sales.discounts),
      tax: asNumber(sales.tax),
      net_revenue: asNumber(sales.net_revenue),
      cash: asNumber(sales.cash),
      qris: asNumber(sales.qris),
      transfer: asNumber(sales.transfer),
      debit: asNumber(sales.debit),
      credit: asNumber(sales.credit),
      split: asNumber(sales.split),
    },
    costs: { cogs: asNumber(costs.cogs), items: asNumber(costs.items) },
    returns: {
      count: asNumber(returns.count),
      total_refund: asNumber(returns.total_refund),
      cash_refund: asNumber(returns.cash_refund),
      store_credit_refund: asNumber(returns.store_credit_refund),
    },
    cash_mutations: {
      cash_in: asNumber(cashMutations.cash_in),
      cash_out: asNumber(cashMutations.cash_out),
      by_category: Array.isArray(cashMutations.by_category)
        ? cashMutations.by_category.map((item: unknown) => {
            const record = asRecord(item);
            return {
            category: String(record.category || 'other'),
            type: record.type === 'in' ? 'in' : 'out',
            amount: asNumber(record.amount),
            };
          })
        : [],
    },
    purchases: {
      cash_paid: asNumber(purchases.cash_paid),
      received_total: asNumber(purchases.received_total),
      count: asNumber(purchases.count),
      by_status: Array.isArray(purchases.by_status)
        ? purchases.by_status.map((item: unknown) => {
            const record = asRecord(item);
            return {
            status: String(record.status || 'unknown'),
            amount_paid: asNumber(record.amount_paid),
            };
          })
        : [],
    },
    shifts: {
      closed_count: asNumber(shifts.closed_count),
      open_count: asNumber(shifts.open_count),
      difference: asNumber(shifts.difference),
      absolute_difference: asNumber(shifts.absolute_difference),
      unreconciled_count: asNumber(shifts.unreconciled_count),
    },
    journal: {
      entry_count: asNumber(journal.entry_count),
      debit: asNumber(journal.debit),
      credit: asNumber(journal.credit),
      balanced: Boolean(journal.balanced),
      unbalanced_entries: asNumber(journal.unbalanced_entries),
    },
    top_products: Array.isArray(raw.top_products)
      ? raw.top_products.map((item: unknown) => {
          const record = asRecord(item);
          return {
          name: String(record.name || 'Produk Tidak Diketahui'),
          qty: asNumber(record.qty),
          revenue: asNumber(record.revenue),
          cogs: asNumber(record.cogs),
          profit: asNumber(record.profit),
          };
        })
      : [],
    daily: Array.isArray(raw.daily)
      ? raw.daily.map((item: unknown) => {
          const record = asRecord(item);
          return {
          period: String(record.period),
          revenue: asNumber(record.revenue),
          discounts: asNumber(record.discounts),
          cogs: asNumber(record.cogs),
          transactions: asNumber(record.transactions),
          cash_in: asNumber(record.cash_in),
          cash_out: asNumber(record.cash_out),
          purchase_cash: asNumber(record.purchase_cash),
          };
        })
      : [],
  };
}

export async function fetchPOSCanonicalReport(input: {
  tenantId: string;
  outletId: string;
  from: Date;
  to: Date;
}): Promise<CanonicalReport> {
  const { data, error } = await supabase.rpc('get_pos_canonical_report' as never, {
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_from: input.from.toISOString(),
    p_to: input.to.toISOString(),
  } as never);

  if (error) throw error;
  return normalizeReport(data);
}
