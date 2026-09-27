// Kept as FoodType for backwards compatibility; values now come from the
// active categories configured by the admin.
export type FoodType = string;

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
