export type BuyerTransactionKind = 'product' | 'courier_delivery';

export interface BuyerTransactionShape {
  service_type?: string | null;
  merchant_id?: string | null;
  order_items?: unknown[] | null;
  pickup_address?: string | null;
  package_type?: string | null;
}

/**
 * Classifies legacy orders using the courier fields until service_type is
 * present on every row. Explicit service_type always wins.
 */
export function getBuyerTransactionKind(order: BuyerTransactionShape): BuyerTransactionKind {
  if (order.service_type === 'COURIER_DELIVERY') return 'courier_delivery';
  if (order.service_type === 'MARKETPLACE') return 'product';

  return !order.merchant_id
    && !order.order_items?.length
    && Boolean(order.pickup_address)
    && Boolean(order.package_type)
    ? 'courier_delivery'
    : 'product';
}

export function isCourierDelivery(order: BuyerTransactionShape): boolean {
  return getBuyerTransactionKind(order) === 'courier_delivery';
}

export const BUYER_ORDER_SERVICE_FIELDS = [
  'service_type',
  'pickup_address',
  'pickup_lat',
  'pickup_lng',
  'package_type',
  'package_weight_kg',
  'courier_notes',
  'delivery_type',
  'delivery_address',
  'delivery_name',
  'delivery_phone',
  'delivery_lat',
  'delivery_lng',
  'courier_id',
].join(', ');
