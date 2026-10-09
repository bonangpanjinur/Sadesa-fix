import { describe, expect, it } from 'vitest';
import type { CartItem } from '@/types';
import { getCartItemSubtotal, getCartItemsSubtotal } from './cartPricing';

const item: CartItem = {
  product: {
    id: 'product-1',
    merchantId: 'merchant-1',
    merchantName: 'Toko Contoh',
    name: 'Produk',
    description: '',
    price: 35_000,
    stock: 10,
    image: '',
    category: 'Makanan',
    isActive: true,
  },
  quantity: 2,
  toppings: [
    { product: { id: 'topping-1', name: 'Keju', price: 5_000, stock: 10 }, quantity: 1 },
  ],
};

describe('cart pricing', () => {
  it('includes per-item toppings multiplied by line quantity', () => {
    expect(getCartItemSubtotal(item)).toBe(80_000);
  });

  it('sums item lines consistently', () => {
    expect(getCartItemsSubtotal([item, { ...item, quantity: 1, toppings: undefined }])).toBe(115_000);
  });

  it('uses the base product price when there are no toppings', () => {
    expect(getCartItemSubtotal({ ...item, quantity: 3, toppings: undefined })).toBe(105_000);
  });
});
