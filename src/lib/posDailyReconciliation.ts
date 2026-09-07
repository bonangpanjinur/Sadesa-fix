import { supabase } from '@/integrations/supabase/client';

export type DailyReconciliationStatus = 'balanced' | 'attention' | 'unbalanced';

export interface DailyReconciliation {
  reconciliation_id?: string;
  tenant_id: string;
  outlet_id: string;
  reconciliation_date: string;
  status: DailyReconciliationStatus;
  sales_total: number;
  cash_sales: number;
  cash_refunds: number;
  cash_in: number;
  cash_out: number;
  supplier_payments: number;
  shift_difference: number;
  unreconciled_sessions: number;
  journal_debit: number;
  journal_credit: number;
  unbalanced_journals: number;
  report_snapshot?: Record<string, unknown>;
  reconciled_at?: string | null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
}

function asNumber(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function normalize(value: unknown): DailyReconciliation {
  const raw = asRecord(value);
  const status = raw.status === 'unbalanced' || raw.status === 'attention' ? raw.status : 'balanced';
  return {
    reconciliation_id: typeof raw.reconciliation_id === 'string' ? raw.reconciliation_id : undefined,
    tenant_id: String(raw.tenant_id || ''),
    outlet_id: String(raw.outlet_id || ''),
    reconciliation_date: String(raw.reconciliation_date || ''),
    status,
    sales_total: asNumber(raw.sales_total),
    cash_sales: asNumber(raw.cash_sales),
    cash_refunds: asNumber(raw.cash_refunds),
    cash_in: asNumber(raw.cash_in),
    cash_out: asNumber(raw.cash_out),
    supplier_payments: asNumber(raw.supplier_payments),
    shift_difference: asNumber(raw.shift_difference),
    unreconciled_sessions: asNumber(raw.unreconciled_sessions),
    journal_debit: asNumber(raw.journal_debit),
    journal_credit: asNumber(raw.journal_credit),
    unbalanced_journals: asNumber(raw.unbalanced_journals),
    report_snapshot: asRecord(raw.report_snapshot),
    reconciled_at: typeof raw.reconciled_at === 'string' ? raw.reconciled_at : null,
  };
}

export function reconciliationStatusLabel(status: DailyReconciliationStatus): string {
  if (status === 'balanced') return 'Seimbang';
  if (status === 'unbalanced') return 'Jurnal tidak seimbang';
  return 'Perlu ditinjau';
}

export function deriveDailyReconciliationStatus(input: {
  unbalancedJournals: number;
  unreconciledSessions: number;
  shiftDifference: number;
}): DailyReconciliationStatus {
  if (input.unbalancedJournals > 0) return 'unbalanced';
  if (input.unreconciledSessions > 0 || Math.abs(input.shiftDifference) > 0.01) return 'attention';
  return 'balanced';
}

export async function fetchDailyReconciliation(input: {
  tenantId: string;
  outletId: string;
  date: string;
}): Promise<DailyReconciliation> {
  const { data, error } = await supabase.rpc('get_pos_daily_reconciliation' as never, {
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_reconciliation_date: input.date,
  } as never);
  if (error) throw error;
  return normalize(data);
}

export async function reconcileDaily(input: {
  tenantId: string;
  outletId: string;
  date: string;
}): Promise<DailyReconciliation> {
  const { data, error } = await supabase.rpc('reconcile_pos_daily' as never, {
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_reconciliation_date: input.date,
  } as never);
  if (error) throw error;
  return normalize(data);
}
