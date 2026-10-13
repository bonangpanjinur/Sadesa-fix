interface HomepageProduct {
  id: string;
  createdAt?: string | null;
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
export const HOMEPAGE_ROTATION_INTERVAL_MS = 60 * 60 * 1000;
export const HOMEPAGE_NEW_PRODUCT_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;

export function getHomepageRotationBucket(
  timestamp = Date.now(),
  intervalMs = HOMEPAGE_ROTATION_INTERVAL_MS,
) {
  return Math.floor(timestamp / intervalMs);
}

export function getHomepageProductCutoffISO(
  timestamp = Date.now(),
  windowMs = HOMEPAGE_NEW_PRODUCT_WINDOW_MS,
) {
  return new Date(timestamp - windowMs).toISOString();
}

function rotationScore(productId: string, rotationBucket: number) {
  let hash = 2166136261;
  const key = `${rotationBucket}:${productId}`;
  for (let index = 0; index < key.length; index += 1) {
    hash ^= key.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

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

export function selectRotatingProducts<T extends HomepageProduct>(
  products: T[],
  featuredProductIds: ReadonlySet<string>,
  options: { limit?: number; rotationBucket?: number; now?: number; windowMs?: number } = {},
): T[] {
  const {
    limit = 48,
    rotationBucket = getHomepageRotationBucket(),
    now = Date.now(),
    windowMs = HOMEPAGE_NEW_PRODUCT_WINDOW_MS,
  } = options;
  const cutoff = now - windowMs;

  return products
    .filter(isCompleteProduct)
    .filter((product) => !featuredProductIds.has(product.id))
    .filter((product) => {
      const createdAt = product.createdAt ? Date.parse(product.createdAt) : Number.NaN;
      return Number.isFinite(createdAt) && createdAt >= cutoff && createdAt <= now;
    })
    .sort((a, b) => rotationScore(a.id, rotationBucket) - rotationScore(b.id, rotationBucket))
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
