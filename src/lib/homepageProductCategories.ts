import {
  getCategoryDescendantIds,
  getCategoryDisplayLabel,
  getCategoryFilterIds,
  getShoppingCategorySlugs,
  isCombinedFoodCategory,
  sortProductCategories,
  type ProductCategory,
} from './productCategories';

interface CategorizedProduct {
  id: string;
  category: string;
  categoryId?: string | null;
  createdAt?: string | null;
}

export interface HomepageCategorySelectionOptions {
  now?: number;
  windowMs?: number;
  rotationBucket?: number;
}

export interface HomepageProductCategoryRow<T extends CategorizedProduct> {
  id: string;
  label: string;
  slug: string;
  products: T[];
}

const normalizeSlug = (slug: string) => slug.trim().toLowerCase();

function rotationScore(productId: string, rotationBucket: number) {
  let hash = 2166136261;
  const key = `${rotationBucket}:${productId}`;
  for (let index = 0; index < key.length; index += 1) {
    hash ^= key.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function matchesCategoryIds(
  product: CategorizedProduct,
  categoryIds: ReadonlySet<string>,
  categorySlugs: ReadonlySet<string>,
) {
  if (product.categoryId) return categoryIds.has(product.categoryId);
  return categorySlugs.has(normalizeSlug(product.category));
}

function getCategoryIdsForRoots(categories: ProductCategory[], roots: ProductCategory[]) {
  const ids = new Set<string>();
  roots.forEach((root) => {
    ids.add(root.id);
    getCategoryDescendantIds(categories, root.id).forEach((id) => ids.add(id));
  });
  return ids;
}

function getSlugsForCategoryIds(categories: ProductCategory[], categoryIds: ReadonlySet<string>) {
  return new Set(
    categories
      .filter((category) => categoryIds.has(category.id))
      .map((category) => normalizeSlug(category.slug)),
  );
}

function getFoodCategoryIds(categories: ProductCategory[]) {
  const ids = new Set(getCategoryFilterIds(categories, 'kuliner') ?? []);
  if (ids.size > 0) return ids;

  const foodRoots = categories.filter((category) => {
    if (category.parent_id) return false;
    const slug = normalizeSlug(category.slug);
    return isCombinedFoodCategory(category)
      || ['makanan', 'minuman', 'kuliner'].includes(slug)
      || /makanan|minuman|kuliner/.test(`${slug} ${category.name.toLowerCase()}`);
  });
  return getCategoryIdsForRoots(categories, foodRoots);
}

function getShoppingCategoryIds(categories: ProductCategory[]) {
  const shoppingSlugs = new Set(getShoppingCategorySlugs(categories).map(normalizeSlug));
  const ids = new Set(
    categories
      .filter((category) => shoppingSlugs.has(normalizeSlug(category.slug)))
      .map((category) => category.id),
  );

  const shoppingRoots = categories.filter((category) => (
    !category.parent_id && normalizeSlug(category.slug) === 'belanja'
  ));
  getCategoryIdsForRoots(categories, shoppingRoots).forEach((id) => ids.add(id));
  return ids;
}

function getFoodCategorySlugs(categories: ProductCategory[], foodIds: ReadonlySet<string>) {
  return new Set([
    ...getSlugsForCategoryIds(categories, foodIds),
    'kuliner',
    'makanan',
    'minuman',
    'makanan-minuman',
    'makanan-dan-minuman',
  ]);
}

function getCategorySubtreeFilter(categories: ProductCategory[], slug: string) {
  const categoryIds = new Set<string>();
  categories
    .filter((category) => normalizeSlug(category.slug) === slug)
    .forEach((root) => {
      categoryIds.add(root.id);
      getCategoryDescendantIds(categories, root.id).forEach((id) => categoryIds.add(id));
    });

  return {
    categoryIds,
    categorySlugs: new Set([...getSlugsForCategoryIds(categories, categoryIds), slug]),
  };
}

/** Selects the newest products under an active Makanan or Minuman category tree. */
export function selectNewestFoodDrinkProducts<T extends CategorizedProduct>(
  products: T[],
  categories: ProductCategory[],
  type: 'makanan' | 'minuman',
  limit = 4,
): T[] {
  if (limit <= 0) return [];
  const filter = getCategorySubtreeFilter(categories, type);
  return products
    .filter((product) => matchesCategoryIds(product, filter.categoryIds, filter.categorySlugs))
    .sort((a, b) => {
      const aDate = Date.parse(a.createdAt || '');
      const bDate = Date.parse(b.createdAt || '');
      return (Number.isFinite(bDate) ? bDate : 0) - (Number.isFinite(aDate) ? aDate : 0);
    })
    .slice(0, limit);
}

function getShoppingCategorySlugsForRows(
  categories: ProductCategory[],
  shoppingIds: ReadonlySet<string>,
  foodSlugs: ReadonlySet<string>,
) {
  const slugs = new Set([
    ...getShoppingCategorySlugs(categories).map(normalizeSlug),
    ...getSlugsForCategoryIds(categories, shoppingIds),
    'kelontongan',
  ]);
  foodSlugs.forEach((slug) => slugs.delete(slug));
  return slugs;
}

/** Returns active Belanja IDs and legacy slugs for fetching its full product pool. */
export function getShoppingCategoryQueryFilter(categories: ProductCategory[]) {
  const categoryIds = getShoppingCategoryIds(categories);
  const foodIds = getFoodCategoryIds(categories);
  categoryIds.forEach((id) => {
    if (foodIds.has(id)) categoryIds.delete(id);
  });
  if (categoryIds.size === 0) return { categoryIds: [], categorySlugs: [] };

  const foodSlugs = getFoodCategorySlugs(categories, foodIds);
  const categorySlugs = getShoppingCategorySlugsForRows(categories, categoryIds, foodSlugs);

  return {
    categoryIds: [...categoryIds],
    categorySlugs: [...categorySlugs],
  };
}

/**
 * Group the newest products using active, admin-managed categories. Combined
 * food and shopping rows collect their full category trees; remaining
 * categories are shown individually in the configured admin order. Keep the
 * shopping row visible when its 14-day candidate set is empty.
 */
export function groupNewestProductsByCategory<T extends CategorizedProduct>(
  products: T[],
  categories: ProductCategory[],
  productsPerCategory = 4,
  shoppingProducts: T[] = products,
  selectionOptions: HomepageCategorySelectionOptions = {},
): HomepageProductCategoryRow<T>[] {
  const rows: HomepageProductCategoryRow<T>[] = [];
  const assignedProductIds = new Set<string>();
  const sortedCategories = sortProductCategories(categories);
  const foodIds = getFoodCategoryIds(categories);
  const shoppingIds = getShoppingCategoryIds(categories);
  const foodSlugs = getFoodCategorySlugs(categories, foodIds);
  const shoppingSlugs = getShoppingCategorySlugsForRows(categories, shoppingIds, foodSlugs);
  shoppingIds.forEach((id) => {
    if (foodIds.has(id)) shoppingIds.delete(id);
  });

  const appendGroup = (
    id: string,
    label: string,
    slug: string,
    categoryIds: Set<string>,
    categorySlugs: Set<string> = new Set(),
    keepVisibleWhenEmpty = false,
    newestFirst = false,
    sourceProducts: T[] = products,
  ) => {
    if (categoryIds.size === 0 && categorySlugs.size === 0) return;
    const resolvedSlugs = new Set([
      ...categorySlugs,
      ...getSlugsForCategoryIds(categories, categoryIds),
    ]);
    const matchingProducts = sourceProducts.filter((product) => (
      matchesCategoryIds(product, categoryIds, resolvedSlugs)
    ));
    matchingProducts.forEach((product) => assignedProductIds.add(product.id));
    if (matchingProducts.length > 0 || keepVisibleWhenEmpty) {
      const now = selectionOptions.now;
      const windowMs = selectionOptions.windowMs;
      const rotationBucket = selectionOptions.rotationBucket;
      const hasFreshnessRule = now !== undefined && windowMs !== undefined;
      const recentProducts = hasFreshnessRule
        ? matchingProducts.filter((product) => {
          const timestamp = Date.parse(product.createdAt || '');
          return Number.isFinite(timestamp) && timestamp >= now - windowMs && timestamp <= now;
        })
        : matchingProducts;
      const candidates = recentProducts.length > 0 ? recentProducts : matchingProducts;
      const orderedProducts = recentProducts.length > 0 || rotationBucket === undefined
        ? (newestFirst
          ? [...candidates].sort((a, b) => {
            const aTimestamp = Date.parse(a.createdAt || '');
            const bTimestamp = Date.parse(b.createdAt || '');
            return (Number.isFinite(bTimestamp) ? bTimestamp : 0) - (Number.isFinite(aTimestamp) ? aTimestamp : 0);
          })
          : candidates)
        : [...candidates].sort((a, b) => rotationScore(a.id, rotationBucket) - rotationScore(b.id, rotationBucket));
      rows.push({
        id,
        label,
        slug,
        products: orderedProducts.slice(0, productsPerCategory),
      });
    }
  };

  appendGroup('food-and-drinks', 'Makanan & Minuman', 'kuliner', foodIds, foodSlugs);
  appendGroup('shopping', 'Belanja', 'belanja', shoppingIds, shoppingSlugs, shoppingIds.size > 0, true, shoppingProducts);

  const groupedCategoryIds = new Set([...foodIds, ...shoppingIds]);
  sortedCategories.forEach((category) => {
    if (groupedCategoryIds.has(category.id)) return;
    const categoryIds = new Set([category.id]);
    const categorySlugs = new Set([normalizeSlug(category.slug)]);
    const matchingProducts = products.filter((product) => (
      matchesCategoryIds(product, categoryIds, categorySlugs)
    ));
    matchingProducts.forEach((product) => assignedProductIds.add(product.id));
    if (matchingProducts.length > 0) {
      rows.push({
        id: category.id,
        label: getCategoryDisplayLabel(categories, category),
        slug: category.slug,
        products: matchingProducts.slice(0, productsPerCategory),
      });
    }
  });

  const uncategorizedProducts = products.filter((product) => !assignedProductIds.has(product.id));
  if (uncategorizedProducts.length > 0) {
    rows.push({
      id: 'other-products',
      label: 'Lainnya',
      slug: 'all',
      products: uncategorizedProducts.slice(0, productsPerCategory),
    });
  }

  return rows;
}
