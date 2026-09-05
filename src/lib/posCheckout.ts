import { supabase } from '@/integrations/supabase/client';
import { createTraceId, getErrorCode, reportObservability } from '@/lib/observability';

export interface AtomicPOSSaleItem {
  product_id: string;
  variant_id?: string | null;
  name: string;
  variant_name?: string | null;
  sku?: string | null;
  qty: number;
  price: number;
  cost_price?: number;
  discount?: number;
  tax_amount?: number;
  subtotal: number;
  notes?: string | null;
}

export interface AtomicPOSSaleInput {
  sale_number: string;
  cashier_name?: string | null;
  customer_id?: string | null;
  customer_name?: string | null;
  customer_segment?: 'retail' | 'wholesale' | 'reseller' | 'member' | 'outlet';
  offline_sync?: boolean;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total: number;
  payment_method: string;
  payment_amount: number;
  change_amount: number;
  notes?: string | null;
  promotion_id?: string | null;
  voucher_id?: string | null;
  voucher_code?: string | null;
  promotion_discount: number;
  voucher_discount: number;
  loyalty_points_earned: number;
  loyalty_points_redeemed: number;
  loyalty_discount: number;
}

export interface AtomicPOSSaleResult {
  sale_id: string;
  sale_number: string;
  total: number;
  payment_method: string;
  duplicate: boolean;
}

export async function processAtomicPOSSale(
  requestKey: string,
  tenantId: string,
  outletId: string,
  cashierId: string,
  sale: AtomicPOSSaleInput,
  items: AtomicPOSSaleItem[],
): Promise<AtomicPOSSaleResult> {
  const traceId = createTraceId('pos-sale');
  const startedAt = Date.now();
  const telemetryContext = {
    checkoutSource: 'merchant_pos_kasir',
    transactionSource: sale.offline_sync ? 'offline_queue' : 'online_checkout',
    tenantId,
    outletId,
    cashierId,
    requestKeyPrefix: requestKey.slice(0, 12),
    itemCount: items.length,
    offline: Boolean(sale.offline_sync),
    paymentMethod: sale.payment_method,
  };
  reportObservability('payment', 'pos_checkout_started', 'info', telemetryContext, undefined, { traceId });
  try {
    const { data, error } = await supabase.rpc('process_pos_sale' as never, {
      p_request_key: requestKey,
      p_tenant_id: tenantId,
      p_outlet_id: outletId,
      p_cashier_id: cashierId,
      p_sale: sale,
      p_items: items,
    } as never);
    if (error) throw error;
    const result = data as unknown as AtomicPOSSaleResult;
    reportObservability('payment', result.duplicate ? 'pos_checkout_duplicate' : 'pos_checkout_succeeded', 'info', { ...telemetryContext, duplicate: result.duplicate, durationMs: Date.now() - startedAt }, undefined, { traceId, durationMs: Date.now() - startedAt });
    return result;
  } catch (error) {
    reportObservability('payment', 'pos_checkout_failed', 'error', { ...telemetryContext, errorCode: getErrorCode(error) }, error, { traceId, durationMs: Date.now() - startedAt });
    throw error;
  }
}
