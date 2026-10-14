import { describe, expect, it } from 'vitest';
import { groupNewestProductsByCategory } from './homepageProductCategories';
import type { ProductCategory } from './productCategories';

const categories: ProductCategory[] = [
  { id: 'food', name: 'Makanan & Minuman', slug: 'kuliner', parent_id: null, icon: null, sort_order: 1 },
  { id: 'rice', name: 'Nasi dan Mi', slug: 'nasi-dan-mi', parent_id: 'food', icon: null, sort_order: 1 },
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
