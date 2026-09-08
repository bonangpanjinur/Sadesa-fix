import { describe, expect, it } from 'vitest';
import { calculateAdminFinancials, calculateOrderPlatformFee } from './adminFinance';

describe('adminFinance', () => {
  it('uses the fee engine for a single platform fee calculation', () => {
    expect(calculateOrderPlatformFee(50_000, 5)).toBe(2_500);
  });

  it('only includes completed orders and separates merchant and courier fees', () => {
    const result = calculateAdminFinancials([
      { total: 56_250, subtotal: 50_000, shipping_cost: 6_250, status: 'DONE' },
      { total: 30_000, subtotal: 30_000, shipping_cost: 0, status: 'DELIVERED' },
      { total: 99_000, subtotal: 90_000, shipping_cost: 9_000, status: 'CANCELLED' },
    ], 5, 80);

    expect(result).toEqual({
      totalRevenue: 86_250,
      platformFees: 4_000,
      courierFees: 5_000,
      merchantRevenue: 76_000,
      shippingCollected: 6_250,
      completedOrders: 2,
    });
  });

  it('never creates negative fee inputs from malformed finance values', () => {
    const result = calculateAdminFinancials([
      { total: -10, subtotal: -20, shipping_cost: Number.NaN, status: 'DONE' },
    ], -5, 80);

    expect(result.totalRevenue).toBe(0);
    expect(result.platformFees).toBe(0);
    expect(result.courierFees).toBe(0);
    expect(result.merchantRevenue).toBe(0);
  });
});
