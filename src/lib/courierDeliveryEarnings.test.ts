import { describe, expect, it } from 'vitest';
import { getCourierDeliveryEarningBreakdown } from './courierDeliveryEarnings';

describe('courier delivery earning breakdown', () => {
  it('estimates platform commission and net from the active delivery fee policy', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 0,
      policy: { feePercent: 10, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 20000, platformFee: 2000, net: 18000 });
  });

  it('uses the authoritative earning base when it differs from the customer shipping charge', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: 15000,
      policy: { feePercent: 10, enabled: true, chargeCourierDelivery: true },
    })).toEqual({ gross: 15000, platformFee: 1500, net: 13500 });
  });

  it('does not show a gross-only amount as net when the commission policy could not load', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: null,
      policy: null,
    })).toEqual({ gross: 20000, platformFee: null, net: null });
  });

  it('does not deduct a commission when delivery fees are disabled', () => {
    expect(getCourierDeliveryEarningBreakdown({
      shippingCost: 20000,
      earningEstimate: null,
      policy: { feePercent: 10, enabled: false, chargeCourierDelivery: true },
    })).toEqual({ gross: 20000, platformFee: 0, net: 20000 });
  });
});
