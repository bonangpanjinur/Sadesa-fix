import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const ordersPage = readFileSync(resolve(process.cwd(), 'src/pages/merchant/MerchantOrdersPage.tsx'), 'utf8');
const financePage = readFileSync(resolve(process.cwd(), 'src/pages/merchant/MerchantFinancePage.tsx'), 'utf8');

describe('merchant operational feedback contract', () => {
  it('opens order details immediately and shares a merchant/order-scoped item query with printing', () => {
    const start = ordersPage.indexOf('const viewOrderDetail =');
    const end = ordersPage.indexOf('const handleExpeditionHandoff', start);
    const viewOrderDetail = ordersPage.slice(start, end);

    expect(viewOrderDetail).toContain('setDetailDialogOpen(true)');
    expect(viewOrderDetail).not.toContain('await');
    expect(viewOrderDetail).not.toContain("from('order_items')");
    expect(ordersPage).toContain("queryKey: ['merchant-order-items', merchantId, selectedOrder?.id]");
    expect(ordersPage).toContain('enabled: !!merchantId && !!selectedOrder?.id && (detailDialogOpen || printDialogOpen)');
    expect(ordersPage).toContain('if (error) throw error;');
  });

  it('shows loading, retryable error, and valid empty states for order items and proof', () => {
    expect(ordersPage.match(/<DialogDescription/g)).toHaveLength(3);
    expect(ordersPage).toContain('Memuat item pesanan...');
    expect(ordersPage).toContain('orderItemsQuery.isError');
    expect(ordersPage).toContain('onRetry={() => void orderItemsQuery.refetch()}');
    expect(ordersPage).toContain('Belum ada item pesanan yang dapat ditampilkan.');
    expect(ordersPage).toContain('Memuat bukti pembayaran...');
    expect(ordersPage).toContain('onRetry={() => void paymentProofQuery.refetch()}');
    expect(ordersPage).toContain('minta pembeli mengunggah ulang bukti pembayaran');
    expect(ordersPage).toContain('orderItemsQuery.isError || orderItems.length === 0');
  });

  it('does not turn finance query failures into a valid zero report and provides retry', () => {
    expect(financePage).toContain('if (error) throw error;');
    expect(financePage).toContain('if (query.isError)');
    expect(financePage).toContain('<MerchantCardError');
    expect(financePage).toContain('onRetry={() => void query.refetch()}');
    expect(financePage).toContain('Belum ada transaksi yang cocok');
  });
});
