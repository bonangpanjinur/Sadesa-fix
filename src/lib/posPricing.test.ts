import { describe, expect, it } from 'vitest';
import { calculatePOSPricing, calculatePromotionDiscount, calculateVoucherDiscount } from './posPricing';
import { posFixture } from '@/test/fixtures/posFixture';

const cart = [
  {
    productId: posFixture.products[0].id,
    name: posFixture.products[0].name,
    price: posFixture.products[0].price,
    costPrice: posFixture.products[0].cost_price,
    unit: 'pcs',
    qty: 1,
    discount: 0,
    taxRate: 11,
    notes: '',
  },
  {
    productId: posFixture.products[1].id,
    name: posFixture.products[1].name,
    price: posFixture.products[1].price,
    costPrice: posFixture.products[1].cost_price,
    unit: 'pcs',
    qty: 1,
    discount: 0,
    taxRate: 11,
    notes: '',
  },
];

describe('posPricing', () => {
  it('calculates tax and total without mutating cart values', () => {
    const result = calculatePOSPricing({ cart, paymentMethod: 'cash', paymentAmount: 40000 });
    expect(result.subtotal).toBe(30000);
    expect(result.taxAmount).toBe(3300);
    expect(result.total).toBe(33300);
    expect(result.change).toBe(6700);
    expect(cart[0].price).toBe(18000);
  });

  it('caps promotion and voucher discounts at their configured limits', () => {
    const promo = { type: 'discount_percent', min_purchase: 0, discount_percent: 50, max_discount: 5000 } as never;
    const voucher = { type: 'discount_amount', min_purchase: 0, discount_amount: 100000 } as never;
    expect(calculatePromotionDiscount(promo, 30000)).toBe(5000);
    expect(calculateVoucherDiscount(voucher, 30000)).toBe(30000);
  });

  it('caps redeemable points by customer balance and configured percentage', () => {
    const result = calculatePOSPricing({
      cart,
      usePoints: true,
      pointsToRedeem: 1000,
      customerPoints: 1000,
      loyaltyProgram: {
        id: 'program', is_active: true, earn_per_rupiah: 1000, redeem_rate: 10,
        min_redeem_points: 10, max_redeem_percent: 10, tiers: [],
      },
    });
    expect(result.pointsDiscount).toBe(100);
    expect(result.total).toBe(33200);
    expect(result.pointsEarned).toBe(33);
  });
});
