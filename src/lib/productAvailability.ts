export interface ProductAvailabilityInput {
  isActive: boolean;
  stock: number;
  hasQuota?: boolean;
  isMerchantOpen?: boolean;
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