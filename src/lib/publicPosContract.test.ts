import { describe, expect, it } from 'vitest';
import {
  buildPublicMenuRpcArgs,
  buildPublicOrderStatusRpcArgs,
  buildPublicTableOrderRpcArgs,
} from './publicPosContract';

describe('public QR menu/table-order contract', () => {
  it('keeps the ordinary tenant menu free of table context', () => {
    expect(buildPublicMenuRpcArgs('tenant-1')).toEqual({
      p_tenant_id: 'tenant-1',
      p_table_id: null,
    });
  });

  it('scopes a table menu and order to the same tenant identifier', () => {
    const menu = buildPublicMenuRpcArgs('tenant-1', 'table-1');
    const order = buildPublicTableOrderRpcArgs('tenant-1', 'table-1', '', '', [{
      product_id: 'product-1',
      qty: 2,
      notes: null,
    }]);

    expect(menu).toMatchObject({ p_tenant_id: 'tenant-1', p_table_id: 'table-1' });
    expect(order).toMatchObject({
      p_tenant_id: 'tenant-1',
      p_table_id: 'table-1',
      p_customer_name: 'Tamu',
    });
    expect(order.p_items).toHaveLength(1);
  });

  it('does not let the client supply an order price or status', () => {
    const order = buildPublicTableOrderRpcArgs('tenant-1', 'table-1', 'Tamu', '', [{
      product_id: 'product-1',
      qty: 1,
      notes: 'tanpa pedas',
    }]);
    const status = buildPublicOrderStatusRpcArgs('tenant-1', 'order-1');

    expect(order).not.toHaveProperty('p_total');
    expect(order).not.toHaveProperty('p_status');
    expect(status).toEqual({ p_tenant_id: 'tenant-1', p_order_id: 'order-1' });
  });
});