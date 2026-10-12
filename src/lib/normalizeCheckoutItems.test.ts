import { describe, expect, it } from 'vitest';
import { normalizeCheckoutProductQuantities } from './normalizeCheckoutItems';

describe('normalizeCheckoutProductQuantities', () => {
  it('merges repeated products and toppings before checkout', () => {
    expect(normalizeCheckoutProductQuantities([
      { product_id: 'product-b', quantity: 2 },
      { product_id: 'product-a', quantity: 1 },
      { product_id: 'product-b', quantity: 3 },
      { product_id: 'product-a', quantity: 2 },
    ])).toEqual([
      { product_id: 'product-a', quantity: 3 },
      { product_id: 'product-b', quantity: 5 },
    ]);
  });

  it('drops invalid rows and rejects no valid inventory implicitly with an empty result', () => {
    expect(normalizeCheckoutProductQuantities([
      { product_id: '', quantity: 1 },
      { product_id: 'product-a', quantity: 0 },
      { product_id: 'product-b', quantity: 1.5 },
    ])).toEqual([]);
  });
});
