interface HomepageProduct {
  id: string;
  name?: string | null;
  description?: string | null;
  price?: number | null;
  category?: string | null;
  hasImage?: boolean;
}

interface HomepageSalesProduct extends HomepageProduct {
  sold_count?: number | null;
}

export const HOMEPAGE_BEST_SELLER_MIN_UNITS = 10;

export function isCompleteProduct(product: HomepageProduct): boolean {
  return Boolean(
    product.hasImage
    && product.name?.trim()
    && product.description?.trim()
    && Number(product.price) > 0
    && product.category?.trim(),
  );
}

export function selectNewestProducts<T extends HomepageProduct>(
  products: T[],
  featuredProductIds: ReadonlySet<string>,
  limit = 6,
): T[] {
  return products
    .filter(isCompleteProduct)
    .filter((product) => !featuredProductIds.has(product.id))
    .slice(0, limit);
}

export function selectTopSellingProducts<T extends HomepageSalesProduct>(
  products: T[],
  alreadyHighlightedIds: ReadonlySet<string>,
  limit = 4,
): T[] {
  if (limit <= 0) return [];

  const rankedProducts = products
    .filter((product) => Number(product.sold_count ?? 0) > 0)
    .sort((a, b) => Number(b.sold_count ?? 0) - Number(a.sold_count ?? 0));
  const notAlreadyHighlighted = rankedProducts.filter(
    (product) => !alreadyHighlightedIds.has(product.id),
  );
  const alreadyHighlighted = rankedProducts.filter(
    (product) => alreadyHighlightedIds.has(product.id),
  );

  // Prefer products not shown elsewhere, but keep this section populated when
  // the best sellers are also among the newest or current promotions.
  return [...notAlreadyHighlighted, ...alreadyHighlighted].slice(0, limit);
}

export function hasEnoughBestSellingHistory<T extends HomepageSalesProduct>(
  products: T[],
  minimumUnits = HOMEPAGE_BEST_SELLER_MIN_UNITS,
): boolean {
  const totalUnitsSold = products.reduce((total, product) => {
    const soldCount = Number(product.sold_count ?? 0);
    return total + (Number.isFinite(soldCount) ? Math.max(0, soldCount) : 0);
  }, 0);

  return totalUnitsSold >= minimumUnits;
}
