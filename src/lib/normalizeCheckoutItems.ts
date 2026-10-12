export interface CheckoutProductQuantity {
  product_id: string;
  quantity: number;
}

/** Combine repeated product/topping rows into one positive integer quantity. */
export const normalizeCheckoutProductQuantities = (
  entries: CheckoutProductQuantity[],
): CheckoutProductQuantity[] => {
  const quantities = new Map<string, number>();
  for (const entry of entries) {
    if (!entry.product_id || !Number.isSafeInteger(entry.quantity) || entry.quantity <= 0) continue;
    quantities.set(entry.product_id, (quantities.get(entry.product_id) || 0) + entry.quantity);
  }
  return [...quantities.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([product_id, quantity]) => ({ product_id, quantity }));
};
