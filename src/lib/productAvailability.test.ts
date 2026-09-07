import { describe, expect, it } from 'vitest';
import { getProductUnavailableReason } from './productAvailability';

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