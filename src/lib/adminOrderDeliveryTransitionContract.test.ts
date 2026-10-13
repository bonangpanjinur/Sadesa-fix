import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const adminOrdersPage = readFileSync(resolve(process.cwd(), 'src/pages/admin/AdminOrdersPage.tsx'), 'utf8');

describe('admin order delivery transition contract', () => {
  it('keeps pickup processing on the READY transition', () => {
    expect(adminOrdersPage).toContain("item.status === 'PROCESSED' && item.delivery_type === 'PICKUP'");
    expect(adminOrdersPage).toContain("updateOrderStatus(item.id, 'READY')");
  });

  it('assigns internal delivery instead of attempting the expedition-only SENT transition', () => {
    expect(adminOrdersPage).toContain("item.status === 'PROCESSED' && item.delivery_type === 'INTERNAL' && !item.courier_id");
    expect(adminOrdersPage).toContain('onClick={() => openAssignDialog(item)}');
    expect(adminOrdersPage).not.toContain("updateOrderStatus(item.id, item.delivery_type === 'PICKUP' ? 'READY' : 'SENT')");
  });
});
