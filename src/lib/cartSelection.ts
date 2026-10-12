import type { CartItem } from '@/types';

export interface MerchantSelectionPlan {
  allSelected: boolean;
  productIdsToToggle: string[];
}

/**
 * Builds an idempotent toggle plan for every unique product in a merchant group.
 * Cart variants (for example, different topping combinations) can create multiple
 * rows for the same product, but selection is intentionally tracked per product.
 */
export function getMerchantSelectionPlan(
  merchantProductIds: readonly string[],
  selectedProductIds: readonly string[],
): MerchantSelectionPlan {
  const uniqueProductIds = [...new Set(merchantProductIds)];
  const selected = new Set(selectedProductIds);
  const allSelected = uniqueProductIds.length > 0 && uniqueProductIds.every((id) => selected.has(id));

  return {
    allSelected,
    productIdsToToggle: allSelected
      ? uniqueProductIds
      : uniqueProductIds.filter((id) => !selected.has(id)),
  };
}

export function getCheckoutMerchantIds(items: readonly CartItem[]): string[] {
  return [...new Set(items.map((item) => item.product.merchantId))].sort();
}

export function hasMultipleCheckoutMerchants(merchantIds: readonly string[]): boolean {
  return new Set(merchantIds).size > 1;
}
