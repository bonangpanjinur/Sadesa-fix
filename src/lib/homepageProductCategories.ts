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
}

export interface HomepageProductCategoryRow<T extends CategorizedProduct> {
  id: string;
  label: string;
  slug: string;
  products: T[];
}

const normalizeSlug = (slug: string) => slug.trim().toLowerCase();

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

/**
 * Group the newest products using active, admin-managed categories. Combined
 * food and shopping rows collect their full category trees; remaining
 * categories are shown individually in the configured admin order.
 */
export function groupNewestProductsByCategory<T extends CategorizedProduct>(
  products: T[],
  categories: ProductCategory[],
  productsPerCategory = 4,
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
  ) => {
    if (categoryIds.size === 0 && categorySlugs.size === 0) return;
    const resolvedSlugs = new Set([
      ...categorySlugs,
      ...getSlugsForCategoryIds(categories, categoryIds),
    ]);
    const matchingProducts = products.filter((product) => (
      matchesCategoryIds(product, categoryIds, resolvedSlugs)
    ));
    matchingProducts.forEach((product) => assignedProductIds.add(product.id));
    if (matchingProducts.length > 0) {
      rows.push({
        id,
        label,
        slug,
        products: matchingProducts.slice(0, productsPerCategory),
      });
    }
  };

  appendGroup('food-and-drinks', 'Makanan & Minuman', 'kuliner', foodIds, foodSlugs);
  appendGroup('shopping', 'Belanja', 'belanja', shoppingIds, shoppingSlugs);

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
