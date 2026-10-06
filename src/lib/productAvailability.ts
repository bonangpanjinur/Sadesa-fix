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
