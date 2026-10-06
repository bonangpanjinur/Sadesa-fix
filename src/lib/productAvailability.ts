export interface ProductAvailabilityInput {
  isActive: boolean;
  stock: number;
  hasQuota?: boolean;
  isMerchantOpen?: boolean;
}

export interface OrderQuantityProduct {
  stock: number;
}

export interface OrderQuantityTopping {
  product: OrderQuantityProduct;
  quantity: number;
}

export interface StockDemandItem {
  product: { id: string };
  quantity: number;
  toppings?: Array<{ product: { id: string }; quantity: number }>;
}

/** Aggregate demand because one product may occur in multiple topping lines. */
export function getCartStockDemand(items: StockDemandItem[]): Map<string, number> {
  const demand = new Map<string, number>();
  const add = (productId: string, quantity: number) => {
    const safeQuantity = Math.max(0, Math.trunc(Number(quantity) || 0));
    demand.set(productId, (demand.get(productId) || 0) + safeQuantity);
  };

  items.forEach((item) => {
    const parentQuantity = Math.max(0, Math.trunc(Number(item.quantity) || 0));
    add(item.product.id, parentQuantity);
    (item.toppings || []).forEach((topping) => add(
      topping.product.id,
      parentQuantity * Math.max(0, Math.trunc(Number(topping.quantity) || 0)),
    ));
  });
  return demand;
}

/** Largest parent quantity supported by the currently known database stock. */
export function getMaxOrderQuantity(
  product: OrderQuantityProduct,
  toppings: OrderQuantityTopping[] = [],
): number {
  const productStock = Math.max(0, Math.trunc(Number(product.stock) || 0));
  return toppings.reduce((limit, topping) => {
    const toppingPerProduct = Math.max(1, Math.trunc(Number(topping.quantity) || 1));
    const toppingStock = Math.max(0, Math.trunc(Number(topping.product.stock) || 0));
    return Math.min(limit, Math.floor(toppingStock / toppingPerProduct));
  }, productStock);
}

export function getProductUnavailableReason({
  isActive,
  stock,
  hasQuota = true,
  isMerchantOpen = true,
}: ProductAvailabilityInput): string | undefined {
  if (!isActive) return 'Produk Nonaktif';
  if (!hasQuota) return 'Kuota Habis';
  if (!isMerchantOpen) return 'Toko Tutup';
  if (stock <= 0) return 'Stok Habis';
  return undefined;
}
