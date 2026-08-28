import { act, renderHook } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { usePOSCart } from './usePOSCart';
import type { CartItem } from '@/components/pos/kasir/types';

const item: CartItem = {
  productId: 'p1', variantId: 'v1', name: 'Produk', variantName: 'Merah',
  price: 10000, costPrice: 5000, unit: 'pcs', qty: 1, discount: 0, taxRate: 0, notes: '',
};

describe('usePOSCart', () => {
  it('merges duplicate product variants without mutating previous state', () => {
    const { result } = renderHook(() => usePOSCart());
    act(() => result.current.addItem(item));
    const firstState = result.current.cart;
    act(() => result.current.addItem({ ...item, qty: 2 }));
    expect(result.current.cart).toHaveLength(1);
    expect(result.current.cart[0].qty).toBe(3);
    expect(firstState[0].qty).toBe(1);
  });

  it('removes an item when decrement reaches zero', () => {
    const { result } = renderHook(() => usePOSCart([item]));
    act(() => result.current.updateQty(0, -1));
    expect(result.current.cart).toEqual([]);
  });

  it('clamps discount to the current line total and rejects invalid values', () => {
    const { result } = renderHook(() => usePOSCart([item]));
    act(() => result.current.updateDiscount(0, 999999));
    expect(result.current.cart[0].discount).toBe(10000);
    act(() => result.current.updateDiscount(0, Number.NaN));
    expect(result.current.cart[0].discount).toBe(0);
  });
});
