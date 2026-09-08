import { describe, expect, it } from 'vitest';
import { buildMarketplaceOrderPayload } from './marketplaceOrderContract';

describe('marketplace order contract', () => {
  it('builds a marketplace order without POS tenant or subscription fields', () => {
    const payload = buildMarketplaceOrderPayload({
      buyerId: 'buyer-1',
      merchantId: 'merchant-1',
      status: 'PENDING_CONFIRMATION',
      deliveryType: 'INTERNAL',
      deliveryName: 'Buyer',
      deliveryPhone: '08123456789',
      deliveryAddress: 'Desa Contoh',
      deliveryLat: -6.2,
      deliveryLng: 106.8,
      shippingCost: 5000,
      subtotal: 25000,
      total: 30000,
      notes: null,
      flashSaleDiscount: 0,
      paymentMethod: 'COD',
      paymentStatus: 'COD',
      confirmationDeadline: '2026-09-08T01:00:00.000Z',
      codServiceFee: 0,
      buyerDistanceKm: 1.5,
    });

    expect(payload).toMatchObject({
      buyer_id: 'buyer-1',
      merchant_id: 'merchant-1',
      total: 30000,
      payment_method: 'COD',
    });
    expect(payload).not.toHaveProperty('pos_tenant_id');
    expect(payload).not.toHaveProperty('tenant_id');
    expect(payload).not.toHaveProperty('subscription_id');
  });
});