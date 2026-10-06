import { describe, expect, it } from 'vitest';
import { getMaxOrderQuantity, getProductUnavailableReason } from './productAvailability';

describe('getProductUnavailableReason', () => {
  it.each([
    [{ isActive: false, stock: 10 }, 'Produk Nonaktif'],
    [{ isActive: true, stock: 10, hasQuota: false }, 'Kuota Habis'],
    [{ isActive: true, stock: 10, isMerchantOpen: false }, 'Toko Tutup'],
    [{ isActive: true, stock: 0 }, 'Stok Habis'],
  ])('returns the most actionable reason', (input, expected) => {
    expect(getProductUnavailableReason(input)).toBe(expected);
  });

  it('returns no reason when the product can be ordered', () => {
    expect(getProductUnavailableReason({
      isActive: true,
      stock: 3,
      hasQuota: true,
      isMerchantOpen: true,
    })).toBeUndefined();
  });
});

describe('getMaxOrderQuantity', () => {
  it('limits quantity to the product stock', () => {
    expect(getMaxOrderQuantity({ stock: 1 })).toBe(1);
    expect(getMaxOrderQuantity({ stock: 8 })).toBe(8);
  });

  it('also limits quantity by the stock required for toppings', () => {
    expect(getMaxOrderQuantity({ stock: 10 }, [{ product: { stock: 2 }, quantity: 1 }])).toBe(2);
    expect(getMaxOrderQuantity({ stock: 10 }, [{ product: { stock: 5 }, quantity: 2 }])).toBe(2);
  });

  it('never returns a negative or fractional order quantity', () => {
    expect(getMaxOrderQuantity({ stock: -1 })).toBe(0);
    expect(getMaxOrderQuantity({ stock: 3.9 })).toBe(3);
  });
});
