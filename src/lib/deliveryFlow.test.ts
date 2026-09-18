import { describe, expect, it } from 'vitest';
import { DELIVERY_FLOWS, DELIVERY_SERVICE_TYPES, getDeliveryFlow, isDirectCourierService, isMarketplaceService } from './deliveryFlow';

describe('delivery flow contract', () => {
  it('keeps merchant fulfillment and direct courier as separate intents', () => {
    expect(DELIVERY_FLOWS.merchant_fulfillment.serviceType).toBe(DELIVERY_SERVICE_TYPES.MARKETPLACE);
    expect(DELIVERY_FLOWS.merchant_fulfillment.pickupOwner).toBe('merchant');
    expect(DELIVERY_FLOWS.merchant_fulfillment.requiresMerchant).toBe(true);
    expect(DELIVERY_FLOWS.direct_courier.serviceType).toBe(DELIVERY_SERVICE_TYPES.COURIER_DELIVERY);
    expect(DELIVERY_FLOWS.direct_courier.pickupOwner).toBe('buyer');
    expect(DELIVERY_FLOWS.direct_courier.requiresMerchant).toBe(false);
  });

  it('maps buyer classifications to the correct flow', () => {
    expect(getDeliveryFlow('product').intent).toBe('merchant_fulfillment');
    expect(getDeliveryFlow('courier_delivery').intent).toBe('direct_courier');
    expect(getDeliveryFlow('courier_delivery').allowsProductItems).toBe(false);
  });

  it('treats absent service type conservatively as marketplace', () => {
    expect(isMarketplaceService(null)).toBe(true);
    expect(isMarketplaceService(undefined)).toBe(true);
    expect(isDirectCourierService('COURIER_DELIVERY')).toBe(true);
    expect(isDirectCourierService('MARKETPLACE')).toBe(false);
  });
});
