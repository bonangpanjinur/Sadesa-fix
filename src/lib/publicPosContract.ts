export interface PublicTableOrderItem {
  product_id: string;
  qty: number;
  notes: string | null;
}

export function buildPublicMenuRpcArgs(tenantId: string, tableId?: string) {
  return {
    p_tenant_id: tenantId,
    p_table_id: tableId || null,
  };
}

export function buildPublicTableOrderRpcArgs(
  tenantId: string,
  tableId: string,
  customerName: string,
  notes: string,
  items: PublicTableOrderItem[],
) {
  return {
    p_tenant_id: tenantId,
    p_table_id: tableId,
    p_customer_name: customerName || 'Tamu',
    p_notes: notes || null,
    p_items: items,
  };
}

export function buildPublicOrderStatusRpcArgs(tenantId: string, orderId: string) {
  return {
    p_tenant_id: tenantId,
    p_order_id: orderId,
  };
}