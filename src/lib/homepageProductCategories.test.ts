import { describe, expect, it } from 'vitest';
import { getShoppingCategoryQueryFilter, groupNewestProductsByCategory, selectNewestFoodDrinkProducts } from './homepageProductCategories';
import type { ProductCategory } from './productCategories';

const categories: ProductCategory[] = [
  { id: 'food', name: 'Makanan & Minuman', slug: 'kuliner', parent_id: null, icon: null, sort_order: 1 },
  { id: 'food-root', name: 'Makanan', slug: 'makanan', parent_id: 'food', icon: null, sort_order: 1 },
  { id: 'drink-root', name: 'Minuman', slug: 'minuman', parent_id: 'food', icon: null, sort_order: 2 },
  { id: 'rice', name: 'Nasi dan Mi', slug: 'nasi-dan-mi', parent_id: 'food-root', icon: null, sort_order: 1 },
  { id: 'drink-sub', name: 'Es Teh', slug: 'es-teh', parent_id: 'drink-root', icon: null, sort_order: 1 },
  { id: 'shop', name: 'Belanja', slug: 'belanja', parent_id: null, icon: null, sort_order: 2 },
  { id: 'grocery', name: 'Sembako', slug: 'sembako', parent_id: 'shop', icon: null, sort_order: 1 },
  { id: 'crafts', name: 'Kerajinan', slug: 'kerajinan', parent_id: null, icon: null, sort_order: 3 },
  { id: 'crafts-sub', name: 'Anyaman', slug: 'anyaman', parent_id: 'crafts', icon: null, sort_order: 1 },
];

const products = [
  { id: 'craft', category: 'anyaman', categoryId: 'crafts-sub' },
  { id: 'grocery-item', category: 'sembako', categoryId: 'grocery' },
  { id: 'legacy-shopping', category: 'kelontongan', categoryId: null },
  { id: 'rice-item', category: 'nasi-dan-mi', categoryId: 'rice' },
  { id: 'legacy-food', category: 'nasi-dan-mi', categoryId: null },
  { id: 'unknown', category: 'unmapped', categoryId: null },
];

describe('groupNewestProductsByCategory', () => {
  it('builds shopping query filters from active admin categories only', () => {
    const filter = getShoppingCategoryQueryFilter(categories);
    expect(filter.categoryIds).toContain('shop');
    expect(filter.categoryIds).toContain('grocery');
    expect(filter.categorySlugs).toContain('sembako');
    expect(getShoppingCategoryQueryFilter([])).toEqual({ categoryIds: [], categorySlugs: [] });
  });

  it('places combined food and shopping first, then other active categories', () => {
    const rows = groupNewestProductsByCategory(products, categories);

    expect(rows.map((row) => row.label)).toEqual([
      'Makanan & Minuman',
      'Belanja',
      'Kerajinan › Anyaman',
      'Lainnya',
    ]);
    expect(rows[0].products.map((product) => product.id)).toEqual(['rice-item', 'legacy-food']);
    expect(rows[1].products.map((product) => product.id)).toEqual(['grocery-item', 'legacy-shopping']);
    expect(rows[2].slug).toBe('anyaman');
    expect(rows[3].products.map((product) => product.id)).toEqual(['unknown']);
  });

  it('uses category IDs when present so a stale product slug cannot move a product', () => {
    const rows = groupNewestProductsByCategory([
      { id: 'mismatched', category: 'nasi-dan-mi', categoryId: 'crafts-sub' },
    ], categories);

    expect(rows.map((row) => row.id)).toEqual(['shopping', 'crafts-sub']);
    expect(rows[1].slug).toBe('anyaman');
  });

  it('filters the admin-managed Makanan and Minuman trees and orders matches newest first', () => {
    const foodDrinkProducts = [
      { id: 'old-drink', category: 'es-teh', categoryId: 'drink-sub', createdAt: '2026-10-01T10:00:00.000Z' },
      { id: 'new-food', category: 'nasi-dan-mi', categoryId: 'rice', createdAt: '2026-10-13T10:00:00.000Z' },
      { id: 'new-drink', category: 'es-teh', categoryId: 'drink-sub', createdAt: '2026-10-14T10:00:00.000Z' },
      { id: 'legacy-drink', category: 'es-teh', categoryId: null, createdAt: '2026-10-12T10:00:00.000Z' },
      { id: 'stale-id', category: 'minuman', categoryId: 'grocery', createdAt: '2026-10-15T10:00:00.000Z' },
    ];

    expect(selectNewestFoodDrinkProducts(foodDrinkProducts, categories, 'makanan').map(({ id }) => id)).toEqual(['new-food']);
    expect(selectNewestFoodDrinkProducts(foodDrinkProducts, categories, 'minuman').map(({ id }) => id)).toEqual([
      'new-drink', 'legacy-drink', 'old-drink',
    ]);
  });

  it('keeps the Belanja category visible when there are no products in the fourteen-day candidate set', () => {
    const rows = groupNewestProductsByCategory([], categories);

    expect(rows.map((row) => row.label)).toEqual(['Belanja']);
    expect(rows[0].products).toEqual([]);
  });

  it('does not add an empty shopping row when no shopping category is active in admin settings', () => {
    const rows = groupNewestProductsByCategory([], [
      { id: 'crafts', name: 'Kerajinan', slug: 'kerajinan', parent_id: null, icon: null, sort_order: 3 },
    ]);

    expect(rows).toEqual([]);
  });

  it('shows the newest shopping products first when new products exist', () => {
    const rows = groupNewestProductsByCategory([
      { id: 'older-shopping', category: 'sembako', categoryId: 'grocery', createdAt: '2026-10-01T10:00:00.000Z' },
      { id: 'newer-shopping', category: 'sembako', categoryId: 'grocery', createdAt: '2026-10-13T10:00:00.000Z' },
    ], categories);

    expect(rows[0].products.map((product) => product.id)).toEqual(['newer-shopping', 'older-shopping']);
  });

  it('shows the newest older shopping products from the fallback pool when no recent ones exist', () => {
    const rows = groupNewestProductsByCategory([], categories, 4, [
      { id: 'older-shopping', category: 'sembako', categoryId: 'grocery', createdAt: '2026-09-01T10:00:00.000Z' },
      { id: 'newest-old-shopping', category: 'sembako', categoryId: 'grocery', createdAt: '2026-09-30T10:00:00.000Z' },
    ]);

    expect(rows[0].products.map((product) => product.id)).toEqual(['newest-old-shopping', 'older-shopping']);
  });

  it('falls back independently for a category without recent products', () => {
    const rows = groupNewestProductsByCategory([
      { id: 'recent-food', category: 'nasi-dan-mi', categoryId: 'rice', createdAt: '2026-10-13T10:00:00.000Z' },
      { id: 'old-craft', category: 'anyaman', categoryId: 'crafts-sub', createdAt: '2026-08-01T10:00:00.000Z' },
    ], categories, 4, [], {
      now: Date.parse('2026-10-14T12:00:00.000Z'),
      windowMs: 14 * 24 * 60 * 60 * 1000,
      rotationBucket: 1,
    });

    expect(rows.find((row) => row.id === 'food-and-drinks')?.products.map((product) => product.id)).toEqual(['recent-food']);
    expect(rows.find((row) => row.slug === 'anyaman')?.products.map((product) => product.id)).toEqual(['old-craft']);
  });

  it('uses closed-merchant products when a category has no open merchant', () => {
    const closedProducts = [
      { id: 'closed-shopping', category: 'sembako', categoryId: 'grocery', createdAt: '2026-10-13T10:00:00.000Z', isMerchantOpen: false },
    ];
    const rows = groupNewestProductsByCategory(closedProducts, categories, 4, closedProducts, {
      now: Date.parse('2026-10-14T12:00:00.000Z'),
      windowMs: 14 * 24 * 60 * 60 * 1000,
      rotationBucket: 1,
    });

    expect(rows.find((row) => row.id === 'shopping')?.products.map((product) => product.id)).toEqual(['closed-shopping']);
  });

  it('limits each category row independently and preserves products without categories', () => {
    const manyProducts = Array.from({ length: 6 }, (_, index) => ({
      id: `food-${index}`,
      category: 'nasi-dan-mi',
      categoryId: 'rice',
    }));
    const rows = groupNewestProductsByCategory([
      ...manyProducts,
      { id: 'orphan', category: 'deleted-category', categoryId: 'deleted-id' },
    ], categories, 3);

    expect(rows[0].products).toHaveLength(3);
    expect(rows.at(-1)?.products.map((product) => product.id)).toEqual(['orphan']);
  });

  it('keeps uncategorized products visible when there are no active categories', () => {
    const rows = groupNewestProductsByCategory(products, []);

    expect(rows.map((row) => row.label)).toEqual(['Belanja', 'Lainnya']);
    expect(rows[0].products.map((product) => product.id)).toEqual(['legacy-shopping']);
    expect(rows[1].products.map((product) => product.id)).toEqual(['craft', 'grocery-item', 'rice-item', 'legacy-food']);
  });
});
