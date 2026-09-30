import { describe, expect, it } from 'vitest';
import {
  canBuyerCancelOrder,
  canUseOnlinePaymentForMerchantCount,
  getOrderStatusGroup,
  isTerminalOrderStatus,
  MERCHANT_ORDER_STATUS_FILTER_OPTIONS,
} from './orderStatus';

describe('order lifecycle guards', () => {
  it('allows buyer cancellation only before merchant processing', () => {
    expect(canBuyerCancelOrder('NEW')).toBe(true);
    expect(canBuyerCancelOrder('PENDING_PAYMENT')).toBe(true);
    expect(canBuyerCancelOrder('PENDING_CONFIRMATION')).toBe(true);
    expect(canBuyerCancelOrder('PROCESSED')).toBe(false);
    expect(canBuyerCancelOrder('DONE')).toBe(false);
  });

  it('allows online payment only for one merchant checkout', () => {
    expect(canUseOnlinePaymentForMerchantCount(1)).toBe(true);
    expect(canUseOnlinePaymentForMerchantCount(0)).toBe(false);
    expect(canUseOnlinePaymentForMerchantCount(2)).toBe(false);
    expect(canUseOnlinePaymentForMerchantCount(1.5)).toBe(false);
  });

  it('uses one canonical group for equivalent lifecycle states', () => {
    expect(getOrderStatusGroup('PENDING_CONFIRMATION')).toBe('pending');
    expect(getOrderStatusGroup('COURIER_ACCEPTED')).toBe('processing');
    expect(getOrderStatusGroup('DELIVERING')).toBe('shipping');
    expect(getOrderStatusGroup('CANCELLED')).toBe('canceled');
    expect(isTerminalOrderStatus('DONE')).toBe(true);
    expect(isTerminalOrderStatus('CANCELED')).toBe(true);
    expect(isTerminalOrderStatus('PROCESSED')).toBe(false);
  });

  it('offers all operational merchant statuses with official grouped labels', () => {
    const options = new Map(MERCHANT_ORDER_STATUS_FILTER_OPTIONS.map(({ value, label }) => [value, label]));

    for (const status of [
      'NEW', 'PENDING_PAYMENT', 'PENDING_CONFIRMATION', 'PROCESSED', 'READY', 'ASSIGNED',
      'COURIER_ASSIGNED', 'COURIER_ACCEPTED', 'PICKED_UP', 'ON_DELIVERY', 'DELIVERING',
      'SENT', 'DELIVERED', 'DONE', 'CANCELED', 'REJECTED', 'REJECTED_BY_BUYER', 'REFUNDED',
    ]) {
      expect(options.has(status), `${status} should be filterable`).toBe(true);
    }

    expect(options.get('READY')).toBe('Diproses · Siap dikirim/diambil');
    expect(options.get('ON_DELIVERY')).toBe('Pengiriman · Dalam perjalanan');
  });
});
