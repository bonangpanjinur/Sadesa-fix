export interface ProductCategory {
  id: string;
  name: string;
  slug: string;
  parent_id: string | null;
  icon: string | null;
  is_active?: boolean;
  description?: string | null;
  sort_order?: number | null;
}

export function hideRedundantFoodRootCategories(categories: ProductCategory[], hasCombinedFoodCategory = categories.some((category) => {
  if (category.parent_id) return false;
  const slug = category.slug.trim().toLowerCase();
  return ['kuliner', 'makanan-minuman', 'makanan-dan-minuman'].includes(slug)
    || /makanan\s*(?:&|dan)\s*minuman/i.test(category.name);
})): ProductCategory[] {
  if (!hasCombinedFoodCategory) return categories;
  return categories.filter((category) => (
    category.parent_id || !['makanan', 'minuman'].includes(category.slug.trim().toLowerCase())
  ));
}

export function sortProductCategories(categories: ProductCategory[]): ProductCategory[] {
  const compare = (a: ProductCategory, b: ProductCategory) => (
    (a.sort_order ?? 0) - (b.sort_order ?? 0) || a.name.localeCompare(b.name, 'id')
  );
  const byParent = new Map<string | null, ProductCategory[]>();
  categories.forEach((category) => {
    const items = byParent.get(category.parent_id) || [];
    items.push(category);
    byParent.set(category.parent_id, items);
  });

  const result: ProductCategory[] = [];
  const append = (parentId: string | null) => {
    const children = [...(byParent.get(parentId) || [])].sort(compare);
    children.forEach((category) => {
      result.push(category);
      append(category.id);
    });
  };
  append(null);
  return result;
}

export function getCategoryBySlug(categories: ProductCategory[], slug: string | null | undefined) {
  return categories.find((category) => category.slug === slug) || null;
}

export function getCategoryChildren(categories: ProductCategory[], parentId: string | null | undefined) {
  if (!parentId) return [];
  return sortProductCategories(categories.filter((category) => category.parent_id === parentId));
}

export function getCategoryParent(categories: ProductCategory[], category: ProductCategory | null) {
  return category?.parent_id ? categories.find((item) => item.id === category.parent_id) || null : null;
}

export function getCategoryPath(categories: ProductCategory[], category: ProductCategory | null) {
  if (!category) return '';
  const parent = getCategoryParent(categories, category);
  return parent ? `${parent.name} › ${category.name}` : category.name;
}

export function getCategoryDisplayLabel(categories: ProductCategory[], category: ProductCategory) {
  const path = getCategoryPath(categories, category);
  return `${category.icon ? `${category.icon} ` : ''}${path}`;
}

export function getLeafCategories(categories: ProductCategory[]) {
  const parentIds = new Set(categories.map((category) => category.parent_id).filter(Boolean));
  return sortProductCategories(categories.filter((category) => !parentIds.has(category.id)));
}

export function getCategoryDescendantSlugs(categories: ProductCategory[], categoryId: string): string[] {
  const descendants: string[] = [];
  const append = (parentId: string) => {
    categories.filter((category) => category.parent_id === parentId).forEach((category) => {
      descendants.push(category.slug);
      append(category.id);
    });
  };
  append(categoryId);
  return descendants;
}

/** Resolve Belanja to the canonical Kelontongan category, with legacy fallback. */
export function getShoppingCategorySlugs(categories: ProductCategory[]): string[] {
  const root = ['kelontongan', 'sembako']
    .map((slug) => categories.find((category) => category.slug === slug))
    .find(Boolean);

  if (root) return [root.slug, ...getCategoryDescendantSlugs(categories, root.id)];

  const legacySlugs = ['kelontongan', 'sembako', 'sayuran', 'buah', 'rumah-tangga', 'elektronik'];
  const configuredSlugs = legacySlugs.filter((slug) => categories.some((category) => category.slug === slug));
  return configuredSlugs.length ? configuredSlugs : ['kelontongan', 'sembako'];
}

export function getInitialProductCategory(categories: ProductCategory[]) {
  return getLeafCategories(categories)[0]?.slug || sortProductCategories(categories)[0]?.slug || '';
}
