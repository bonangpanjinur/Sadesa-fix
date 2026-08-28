import { describe, expect, it } from 'vitest';
import { getEffectivePaymentAmount, validatePOSPayment } from './posPaymentValidation';

const base = {
  total: 10000,
  paymentMethod: 'cash',
  paymentAmount: 10000,
  isSplitPayment: false,
  splitAmount1: 0,
  splitAmount2: 0,
  isOnline: true,
  usePoints: false,
  pointsToRedeem: 0,
  minimumRedeemPoints: 100,
};

describe('POS payment validation', () => {
  it('rejects underpayment and accepts exact cash payment', () => {
    expect(validatePOSPayment({ ...base, paymentAmount: 9999 })).toContain('kurang');
    expect(validatePOSPayment(base)).toBeNull();
  });

  it('requires split payment to equal the order total', () => {
    expect(validatePOSPayment({ ...base, isSplitPayment: true, splitAmount1: 6000, splitAmount2: 3000 })).toContain('split');
    expect(validatePOSPayment({ ...base, isSplitPayment: true, splitAmount1: 6000, splitAmount2: 4000 })).toBeNull();
    expect(getEffectivePaymentAmount({ ...base, isSplitPayment: true, splitAmount1: 6000, splitAmount2: 4000 })).toBe(10000);
  });

  it('rejects offline non-cash payment and loyalty below minimum', () => {
    expect(validatePOSPayment({ ...base, paymentMethod: 'qris', isOnline: false })).toContain('internet');
    expect(validatePOSPayment({ ...base, usePoints: true, pointsToRedeem: 50 })).toContain('Min. tukar');
  });
});
