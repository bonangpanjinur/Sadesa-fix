import type { CartItem } from '@/types';

/** Price for one cart line, including every topping multiplied by line quantity. */
export function getCartItemSubtotal(item: CartItem): number {
  const toppingPricePerItem = (item.toppings ?? []).reduce(
    (sum, topping) => sum + topping.product.price * topping.quantity,
    0,
  );
  return (item.product.price + toppingPricePerItem) * item.quantity;
}

/** Consistent subtotal for cart and checkout displays. */
export function getCartItemsSubtotal(items: readonly CartItem[]): number {
  return items.reduce((sum, item) => sum + getCartItemSubtotal(item), 0);
}
