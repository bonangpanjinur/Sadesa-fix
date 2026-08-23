import { supabase } from '@/integrations/supabase/client';

export interface CashSessionRpcResult {
  session_id: string;
  session_number?: string;
  status?: string;
  expected_balance?: number;
  closing_balance?: number;
  difference?: number;
  cash_sales_total?: number;
  non_cash_sales_total?: number;
  cash_in_total?: number;
  cash_out_total?: number;
}

export interface StockAdjustmentRpcResult {
  stock_id: string;
  quantity_before: number;
  quantity_after: number;
  delta: number;
}

export async function openCashSession(input: {
  tenantId: string;
  outletId: string;
  cashierId: string;
  cashierName: string;
  openingBalance: number;
  notes?: string | null;
}): Promise<CashSessionRpcResult> {
  const { data, error } = await supabase.rpc('open_cash_session' as never, {
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_cashier_id: input.cashierId,
    p_cashier_name: input.cashierName,
    p_opening_balance: input.openingBalance,
    p_notes: input.notes || null,
  } as never);
  if (error) throw error;
  return data as unknown as CashSessionRpcResult;
}

export async function recordCashMutation(input: {
  sessionId: string;
  tenantId: string;
  outletId: string;
  type: 'in' | 'out';
  category: string;
  amount: number;
  description: string;
  reference?: string | null;
}): Promise<{ mutation_id: string; session_id: string }> {
  const { data, error } = await supabase.rpc('record_cash_mutation' as never, {
    p_session_id: input.sessionId,
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_type: input.type,
    p_category: input.category,
    p_amount: input.amount,
    p_description: input.description,
    p_reference: input.reference || null,
  } as never);
  if (error) throw error;
  return data as unknown as { mutation_id: string; session_id: string };
}

export async function closeCashSession(input: {
  sessionId: string;
  closingBalance: number;
  notes?: string | null;
}): Promise<CashSessionRpcResult> {
  const { data, error } = await supabase.rpc('close_cash_session' as never, {
    p_session_id: input.sessionId,
    p_closing_balance: input.closingBalance,
    p_notes: input.notes || null,
  } as never);
  if (error) throw error;
  return data as unknown as CashSessionRpcResult;
}

export async function adjustPOSStock(input: {
  stockId: string;
  tenantId: string;
  outletId: string;
  type: string;
  quantity: number;
  notes?: string | null;
}): Promise<StockAdjustmentRpcResult> {
  const { data, error } = await supabase.rpc('adjust_pos_stock' as never, {
    p_stock_id: input.stockId,
    p_tenant_id: input.tenantId,
    p_outlet_id: input.outletId,
    p_type: input.type,
    p_quantity: input.quantity,
    p_notes: input.notes || null,
  } as never);
  if (error) throw error;
  return data as unknown as StockAdjustmentRpcResult;
}
