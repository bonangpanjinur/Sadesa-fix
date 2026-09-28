// Kept as FoodType for backwards compatibility; values now come from the
// active categories configured by the admin.
export type FoodType = string;

/** Read the currently selected catalog category from the URL. */
export function getCatalogTypeFromSearchParams(searchParams: URLSearchParams): FoodType {
  const type = searchParams.get('type')?.trim().toLowerCase();
  if (!type || type === 'all') return 'all';
  // "Belanja" is a legacy public alias; product rows use "kelontongan".
  return type === 'belanja' ? 'kelontongan' : type;
}

export interface CategoryFilterOption {
  slug: string;
  name: string;
}

export interface FoodFilters {
  type: FoodType;
  openNow: boolean;
  inStockOnly: boolean;
  promoOnly: boolean;
  halalOnly: boolean;
  maxPrice: number;
}

export const defaultFoodFilters: FoodFilters = {
  type: 'all',
  openNow: false,
  inStockOnly: false,
  promoOnly: false,
  halalOnly: false,
  maxPrice: 100000,
};
