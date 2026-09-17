import { describe, expect, it } from 'vitest';
import { getBuyerTransactionKind, isCourierDelivery } from './buyerTransaction';

describe('buyer transaction classification', () => {
  it('prefers the explicit courier service type', () => {
    expect(getBuyerTransactionKind({ service_type: 'COURIER_DELIVERY' })).toBe('courier_delivery');
  });

  it('classifies legacy courier orders from their delivery shape', () => {
    expect(getBuyerTransactionKind({
      merchant_id: null,
      order_items: [],
      pickup_address: 'Pickup',
      package_type: 'Dokumen',
    })).toBe('courier_delivery');
  });

  it('keeps marketplace orders as products', () => {
    expect(isCourierDelivery({
      service_type: 'MARKETPLACE',
      merchant_id: 'merchant-1',
      order_items: [{ id: 'item-1' }],
    })).toBe(false);
  });

  it('does not misclassify incomplete legacy rows', () => {
    expect(getBuyerTransactionKind({ merchant_id: null, order_items: [] })).toBe('product');
  });
});
