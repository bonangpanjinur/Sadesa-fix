interface HomepageProduct {
  id: string;
  isActive: boolean;
}

export function selectNewestProducts<T extends HomepageProduct>(
  products: T[],
  featuredProductIds: ReadonlySet<string>,
  limit = 6,
): T[] {
  return products
    .filter((product) => product.isActive && !featuredProductIds.has(product.id))
    .slice(0, limit);
}
