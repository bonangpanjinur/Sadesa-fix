import { describe, expect, it } from 'vitest';
import {
  canBuyerCancelOrder,
  canUseOnlinePaymentForMerchantCount,
  getOrderStatusGroup,
  isTerminalOrderStatus,
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
});
