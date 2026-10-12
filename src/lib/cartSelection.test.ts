import { describe, expect, it } from 'vitest';
import type { CartItem, Product } from '@/types';
import { getCheckoutMerchantIds, getMerchantSelectionPlan, hasMultipleCheckoutMerchants } from './cartSelection';

function cartItem(id: string, merchantId: string, quantity = 1): CartItem {
  const product: Product = {
    id,
    merchantId,
    merchantName: merchantId,
    name: id,
    description: '',
    price: 10_000,
    stock: 10,
    image: '',
    category: 'Makanan',
    isActive: true,
  };
  return { product, quantity };
}

describe('cart merchant selection and checkout policy', () => {
  it('deduplicates product variants before selecting all items from a merchant', () => {
    const plan = getMerchantSelectionPlan(['product-a', 'product-a', 'product-b'], []);

    expect(plan.allSelected).toBe(false);
    expect(plan.productIdsToToggle).toEqual(['product-a', 'product-b']);
  });

  it('selects only the missing products in a merchant and preserves other merchants selections', () => {
    const selectedBefore = new Set(['product-a', 'other-merchant-product']);
    const plan = getMerchantSelectionPlan(
      ['product-a', 'product-a', 'product-b'],
      [...selectedBefore],
    );

    expect(plan.allSelected).toBe(false);
    expect(plan.productIdsToToggle).toEqual(['product-b']);
    plan.productIdsToToggle.forEach((id) => selectedBefore.add(id));
    expect([...selectedBefore].sort()).toEqual(['other-merchant-product', 'product-a', 'product-b']);
  });

  it('deselects each selected product once even when its cart has multiple variants', () => {
    const selectedBefore = new Set(['product-a', 'product-b', 'other-merchant-product']);
    const plan = getMerchantSelectionPlan(
      ['product-a', 'product-a', 'product-b'],
      [...selectedBefore],
    );

    expect(plan.allSelected).toBe(true);
    expect(plan.productIdsToToggle).toEqual(['product-a', 'product-b']);
    plan.productIdsToToggle.forEach((id) => selectedBefore.delete(id));
    expect([...selectedBefore]).toEqual(['other-merchant-product']);
  });

  it('treats several product lines from one merchant as one checkout merchant', () => {
    const merchantIds = getCheckoutMerchantIds([
      cartItem('product-a', 'merchant-a'),
      cartItem('product-b', 'merchant-a'),
      cartItem('product-a', 'merchant-a'),
    ]);

    expect(merchantIds).toEqual(['merchant-a']);
    expect(hasMultipleCheckoutMerchants(merchantIds)).toBe(false);
  });

  it('blocks carts spanning distinct merchant IDs, even when display names might match', () => {
    const merchantIds = getCheckoutMerchantIds([
      cartItem('product-a', 'merchant-a'),
      cartItem('product-b', 'merchant-b'),
    ]);

    expect(merchantIds).toEqual(['merchant-a', 'merchant-b']);
    expect(hasMultipleCheckoutMerchants(merchantIds)).toBe(true);
  });

  it('does not report multiple merchants for an empty cart', () => {
    expect(hasMultipleCheckoutMerchants(getCheckoutMerchantIds([]))).toBe(false);
  });
});
