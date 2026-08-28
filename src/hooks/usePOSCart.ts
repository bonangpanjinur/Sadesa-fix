import { useCallback, useState } from 'react';
import type { CartItem } from '@/components/pos/kasir/types';

export function usePOSCart(initialItems: CartItem[] = []) {
  const [cart, setCart] = useState<CartItem[]>(initialItems);

  const addItem = useCallback((item: CartItem) => {
    setCart((current) => {
      const index = current.findIndex((entry) => entry.productId === item.productId && entry.variantId === item.variantId);
      if (index < 0) return [...current, item];
      return current.map((entry, entryIndex) => (
        entryIndex === index ? { ...entry, qty: entry.qty + item.qty } : entry
      ));
    });
  }, []);

  const updateQty = useCallback((index: number, delta: number) => {
    if (!Number.isFinite(delta) || delta === 0) return;
    setCart((current) => current.flatMap((item, itemIndex) => {
      if (itemIndex !== index) return [item];
      const nextQty = item.qty + delta;
      return nextQty > 0 ? [{ ...item, qty: nextQty }] : [];
    }));
  }, []);

  const removeItem = useCallback((index: number) => {
    setCart((current) => current.filter((_, itemIndex) => itemIndex !== index));
  }, []);

  const updateDiscount = useCallback((index: number, value: number) => {
    setCart((current) => current.map((item, itemIndex) => {
      if (itemIndex !== index) return item;
      const discount = Number.isFinite(value) ? Math.max(0, Math.min(value, item.price * item.qty)) : 0;
      return { ...item, discount };
    }));
  }, []);

  const clear = useCallback(() => setCart([]), []);

  return { cart, setCart, addItem, updateQty, removeItem, updateDiscount, clear };
}
