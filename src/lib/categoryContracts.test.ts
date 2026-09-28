import { describe, expect, it } from 'vitest';
import { canTransitionCategory, getCategoryTemplate } from './categoryContracts';
import { getShoppingCategorySlugs, hideRedundantFoodRootCategories, type ProductCategory } from './productCategories';

const category = (slug: string, id = slug, parent_id: string | null = null): ProductCategory => ({
  id,
  slug,
  name: slug,
  parent_id,
  icon: null,
});

describe('category listing and workflow contracts', () => {
  it('resolves category aliases without changing the shared ledger boundary', () => {
    expect(getCategoryTemplate('makanan')).toMatchObject({ key: 'food', workflow: 'order' });
    expect(getCategoryTemplate('jasa')).toMatchObject({ key: 'service', workflow: 'service_request' });
    expect(getCategoryTemplate('wisata')).toMatchObject({ key: 'experience', workflow: 'booking' });
    expect(getCategoryTemplate('unknown')).toMatchObject({ key: 'product', workflow: 'order' });
  });

  it('keeps category-specific fulfillment states explicit', () => {
    expect(canTransitionCategory('food', 'accepted', 'preparing')).toBe(true);
    expect(canTransitionCategory('service', 'accepted', 'in_progress')).toBe(true);
    expect(canTransitionCategory('rental', 'checked_out', 'returned')).toBe(true);
    expect(canTransitionCategory('wisata', 'confirmed', 'checked_in')).toBe(true);
  });

  it('does not allow a category to skip its operational states', () => {
    expect(canTransitionCategory('food', 'pending', 'completed')).toBe(false);
    expect(canTransitionCategory('rental', 'pending', 'returned')).toBe(false);
    expect(canTransitionCategory('service', 'completed', 'pending')).toBe(false);
  });

  it('maps Belanja to Kelontongan and includes its descendants', () => {
    expect(getShoppingCategorySlugs([
      category('kelontongan'),
      category('sembako'),
      category('beras', 'beras', 'kelontongan'),
    ])).toEqual(['kelontongan', 'beras']);
  });

  it('falls back to the legacy Sembako category when Kelontongan is absent', () => {
    expect(getShoppingCategorySlugs([category('sembako')])).toEqual(['sembako']);
  });

  it('keeps the catalog usable while categories are still loading', () => {
    expect(getShoppingCategorySlugs([])).toEqual(['kelontongan', 'sembako']);
  });

  it('hides duplicate food roots when a combined food category exists but keeps its subcategories', () => {
    const categories = [
      category('kuliner'),
      category('makanan'),
      category('minuman'),
      category('makanan', 'makanan-sub', 'kuliner'),
      category('minuman', 'minuman-sub', 'kuliner'),
      category('pertanian'),
    ];

    expect(hideRedundantFoodRootCategories(categories).map(({ id }) => id)).toEqual([
      'kuliner', 'makanan-sub', 'minuman-sub', 'pertanian',
    ]);
  });

  it('keeps standalone food roots when no combined category exists', () => {
    expect(hideRedundantFoodRootCategories([category('makanan'), category('minuman'), category('pertanian')]).map(({ slug }) => slug)).toEqual([
      'makanan', 'minuman', 'pertanian',
    ]);
  });

  it('recognizes a combined category by its display name', () => {
    const combined = { ...category('menu-lokal'), name: 'Makanan & Minuman' };
    expect(hideRedundantFoodRootCategories([combined, category('makanan'), category('minuman')]).map(({ id }) => id)).toEqual(['menu-lokal']);
  });
});
