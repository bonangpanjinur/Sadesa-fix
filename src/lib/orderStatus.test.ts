import { describe, expect, it } from 'vitest';
import {
  canBuyerCancelOrder,
  canUseOnlinePaymentForMerchantCount,
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
});
