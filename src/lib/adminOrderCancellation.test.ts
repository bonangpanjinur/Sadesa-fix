import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const adminOrdersPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminOrdersPage.tsx'), 'utf8');

describe('admin order cancellation contract', () => {
  it('uses the audited order transition RPC instead of a direct PATCH', () => {
    expect(adminOrdersPage).toContain("supabase.rpc('merchant_transition_order' as never");
    expect(adminOrdersPage).toContain("p_to_status: newStatus");
    expect(adminOrdersPage).not.toContain("p_is_self_delivery");
    expect(adminOrdersPage).not.toContain(".from('orders')\n        .update(updateData)");
  });

  it('sends the database-compatible CANCELED status and exposes cancellation before terminal states', () => {
    expect(adminOrdersPage).toContain("newStatus === 'CANCELED'");
    expect(adminOrdersPage).toContain('requestAdminCancellation(item)');
    expect(adminOrdersPage).toContain("'PENDING_PAYMENT'");
    expect(adminOrdersPage).toContain("'DELIVERING'");
    expect(adminOrdersPage).toContain('Batalkan Pesanan');
    expect(adminOrdersPage).not.toContain("updateOrderStatus(item.id, 'CANCELLED')");
  });

  it('shows a clear confirmation modal and blocks duplicate submission while cancelling', () => {
    expect(adminOrdersPage).toContain('Batalkan pesanan ini?');
    expect(adminOrdersPage).toContain('Ya, Batalkan Pesanan');
    expect(adminOrdersPage).toContain('cancelSubmitting');
    expect(adminOrdersPage).toContain('Tindakan ini akan mengubah status pesanan');
  });

  it('requires a standard or custom cancellation reason and sends it to the transition RPC', () => {
    expect(adminOrdersPage).toContain('ADMIN_CANCEL_REASONS');
    expect(adminOrdersPage).toContain('Pilih alasan pembatalan');
    expect(adminOrdersPage).toContain('Alasan pembatalan lainnya');
    expect(adminOrdersPage).toContain('Pilih atau isi alasan pembatalan terlebih dahulu');
    expect(adminOrdersPage).toContain('p_reason: newStatus === \'CANCELED\' ? reason ?? \'Dibatalkan oleh admin\'');
    expect(adminOrdersPage).toContain("updateOrderStatus(pendingCancelOrder.id, 'CANCELED', finalReason)");
  });

  it('summarizes cancellation reasons and ranks merchants for operational evaluation', () => {
    expect(adminOrdersPage).toContain('cancellation_reason: string | null');
    expect(adminOrdersPage).toContain('const cancellationReport = useMemo');
    expect(adminOrdersPage).toContain("['CANCELED', 'CANCELLED'].includes(order.status)");
    expect(adminOrdersPage).toContain('Alasan tidak dicatat');
    expect(adminOrdersPage).toContain('Analisis Alasan Pembatalan');
    expect(adminOrdersPage).toContain('Merchant dengan Pembatalan Terbanyak');
    expect(adminOrdersPage).toContain('Prioritaskan evaluasi pada merchant berikut.');
  });
});
