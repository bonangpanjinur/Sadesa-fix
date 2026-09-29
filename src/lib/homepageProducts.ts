interface HomepageProduct {
  id: string;
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
