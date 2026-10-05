interface HomepageProduct {
  id: string;
}

interface HomepageSalesProduct extends HomepageProduct {
  sold_count?: number | null;
}

export function selectNewestProducts<T extends HomepageProduct>(
  products: T[],
  featuredProductIds: ReadonlySet<string>,
  limit = 6,
): T[] {
  return products
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
