import { describe, expect, it } from 'vitest';
import { getCourierDeliveryEarningBreakdown } from './courierDeliveryEarnings';

describe('courier delivery earning breakdown', () => {
  it('estimates platform commission and net from the active delivery fee policy', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 15000,
      policy: { feePercent: 10, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 15000, platformFee: 1500, net: 13500, available: true });
  });

  it('uses the authoritative earning base when it differs from the customer shipping charge', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 15000,
      policy: { feePercent: 10, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 15000, platformFee: 1500, net: 13500, available: true });
  });

  it('does not use the customer shipping charge when the courier estimate is missing', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: null,
      policy: { feePercent: 10, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 0, platformFee: null, net: null, available: false });
  });

  it('does not deduct a commission when delivery fees are disabled', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 15000,
      policy: { feePercent: 10, enabled: false, chargeCourierDelivery: true },
    })).toEqual({ gross: 15000, platformFee: 0, net: 15000, available: true });
  });

  it('uses the saved platform fee for completed orders instead of the current policy', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 15000,
      savedPlatformFee: 750,
      policy: { feePercent: 25, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 15000, platformFee: 750, net: 14250, available: true });
  });
});
