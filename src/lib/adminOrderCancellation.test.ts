import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const adminOrdersPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminOrdersPage.tsx'), 'utf8');

describe('admin order cancellation contract', () => {
  it('uses the audited order transition RPC instead of a direct PATCH', () => {
    expect(adminOrdersPage).toContain("supabase.rpc('merchant_transition_order' as never");
    expect(adminOrdersPage).toContain("p_to_status: newStatus");
    expect(adminOrdersPage).toContain("p_is_self_delivery: null");
    expect(adminOrdersPage).not.toContain(".from('orders')\n        .update(updateData)");
  });

  it('sends the database-compatible CANCELED status and exposes cancellation before terminal states', () => {
    expect(adminOrdersPage).toContain("newStatus === 'CANCELED'");
    expect(adminOrdersPage).toContain("updateOrderStatus(item.id, 'CANCELED')");
    expect(adminOrdersPage).toContain("'PENDING_PAYMENT'");
    expect(adminOrdersPage).toContain("'DELIVERING'");
    expect(adminOrdersPage).toContain('Batalkan Pesanan');
    expect(adminOrdersPage).not.toContain("updateOrderStatus(item.id, 'CANCELLED')");
  });
});
