import type { CartItem } from '@/types';

/** Stable identity for one cart line, including its topping composition. */
export function getCartItemKey(item: Pick<CartItem, 'product' | 'toppings'>): string {
  const toppingKey = (item.toppings ?? [])
    .map((topping) => `${topping.product.id}:${Math.max(1, Math.trunc(topping.quantity || 1))}`)
    .sort()
    .join('|');
  return `${item.product.id}::${toppingKey || 'base'}`;
}
