import { describe, expect, it } from 'vitest';
import {
  hasEnoughBestSellingHistory,
  filterOpenMerchantProducts,
  isCompleteProduct,
  selectShoppingProductsWithFallback,
  selectRotatingProducts,
  selectNewestProducts,
  selectTopSellingProducts,
} from './homepageProducts';

describe('filterOpenMerchantProducts', () => {
  it('keeps only products whose merchant is currently open', () => {
    const products = [
      { id: 'open', isMerchantOpen: true },
      { id: 'closed', isMerchantOpen: false },
      { id: 'unknown', isMerchantOpen: null },
    ];

    expect(filterOpenMerchantProducts(products).map((product) => product.id)).toEqual(['open']);
  });
});

describe('selectNewestProducts', () => {
  const complete = (id: string, overrides: Record<string, unknown> = {}) => ({
    id,
    name: 'Produk lengkap',
    description: 'Deskripsi produk lengkap',
    price: 15000,
    category: 'makanan',
    hasImage: true,
    ...overrides,
  });

  it('only includes products with complete data and a photo', () => {
    const products = [
      complete('open', { isActive: true, isAvailable: true }),
      complete('closed', { isActive: true, isAvailable: false, unavailableReason: 'Toko Tutup' }),
      complete('out-of-stock', { isActive: true, isAvailable: false, unavailableReason: 'Stok Habis' }),
      complete('inactive', { isActive: false, isAvailable: false, unavailableReason: 'Produk Nonaktif' }),
      complete('no-photo', { hasImage: false }),
      complete('no-description', { description: '' }),
    ];

    expect(selectNewestProducts(products, new Set()).map((product) => product.id)).toEqual([
      'open',
      'closed',
      'out-of-stock',
      'inactive',
    ]);
  });

  it('recognizes the required listing fields', () => {
    expect(isCompleteProduct(complete('valid'))).toBe(true);
    expect(isCompleteProduct(complete('missing-image', { hasImage: false }))).toBe(false);
    expect(isCompleteProduct(complete('missing-category', { category: '' }))).toBe(false);
  });

  it('does not repeat products already shown in the promo section', () => {
    const products = [
      complete('promo', { isActive: true }),
      complete('newest', { isActive: true }),
    ];

    expect(selectNewestProducts(products, new Set(['promo'])).map((product) => product.id)).toEqual(['newest']);
  });

  it('limits the section to the requested number of products', () => {
    const products = Array.from({ length: 8 }, (_, index) => complete(`product-${index}`, { isActive: true }));

    expect(selectNewestProducts(products, new Set(), 3)).toHaveLength(3);
  });
});

describe('selectRotatingProducts', () => {
  const complete = (id: string, createdAt: string) => ({
    id,
    name: 'Produk lama',
    description: 'Deskripsi produk lama',
    price: 15000,
    category: 'makanan',
    hasImage: true,
    createdAt,
  });
  const now = Date.parse('2026-10-13T12:00:00.000Z');
  const recent = '2026-10-01T12:00:01.000Z';
  const tooOld = '2026-09-29T11:59:59.000Z';

  it('only includes products registered in the last fourteen days', () => {
    expect(selectRotatingProducts([
      complete('recent', recent),
      complete('too-old', tooOld),
    ], new Set(), { now, rotationBucket: 1 }).map((product) => product.id)).toEqual(['recent']);
  });

  it('keeps one hourly bucket stable while changing the order in another bucket', () => {
    const products = ['a', 'b', 'c', 'd'].map((id) => complete(id, recent));
    const first = selectRotatingProducts(products, new Set(), { now, rotationBucket: 10 }).map((product) => product.id);
    const repeat = selectRotatingProducts(products, new Set(), { now, rotationBucket: 10 }).map((product) => product.id);
    const next = selectRotatingProducts(products, new Set(), { now, rotationBucket: 11 }).map((product) => product.id);
    expect(repeat).toEqual(first);
    expect(next).not.toEqual(first);
  });
});

describe('selectShoppingProductsWithFallback', () => {
  const now = Date.parse('2026-10-14T12:00:00.000Z');
  const product = (id: string, createdAt: string) => ({
    id,
    name: `Produk ${id}`,
    description: 'Deskripsi produk lengkap',
    price: 15000,
    category: 'sembako',
    hasImage: true,
    createdAt,
  });

  it('shows only the newest products from the last fourteen days when any are available', () => {
    const selected = selectShoppingProductsWithFallback([
      product('old', '2026-09-01T12:00:00.000Z'),
      product('recent-oldest', '2026-10-03T12:00:00.000Z'),
      product('recent-newest', '2026-10-13T12:00:00.000Z'),
    ], { now, limit: 4 });

    expect(selected.map(({ id }) => id)).toEqual(['recent-newest', 'recent-oldest']);
  });

  it('falls back to the newest older shopping products when none were added in fourteen days', () => {
    const selected = selectShoppingProductsWithFallback([
      product('older', '2026-08-01T12:00:00.000Z'),
      product('newest-old', '2026-09-29T12:00:00.000Z'),
    ], { now, limit: 4 });

    expect(selected.map(({ id }) => id)).toEqual(['newest-old', 'older']);
  });

  it('returns no products when no usable shopping products exist', () => {
    expect(selectShoppingProductsWithFallback([], { now })).toEqual([]);
    expect(selectShoppingProductsWithFallback([product('future', '2026-10-15T12:00:00.000Z')], { now })).toEqual([]);
  });
});

describe('selectTopSellingProducts', () => {
  it('orders products by completed sales and excludes items with no sales', () => {
    const products = [
      { id: 'zero-sales', sold_count: 0 },
      { id: 'middle', sold_count: 8 },
      { id: 'top', sold_count: 21 },
    ];

    expect(selectTopSellingProducts(products, new Set()).map((product) => product.id)).toEqual([
      'top',
      'middle',
    ]);
  });

  it('prefers products not already shown in promos or newest rows, then fills with best sellers', () => {
    const products = [
      { id: 'newest-top-seller', sold_count: 30 },
      { id: 'other-top-seller', sold_count: 25 },
      { id: 'third', sold_count: 12 },
      { id: 'fourth', sold_count: 9 },
      { id: 'fifth', sold_count: 5 },
    ];

    expect(selectTopSellingProducts(products, new Set(['newest-top-seller']), 4).map((product) => product.id)).toEqual([
      'other-top-seller',
      'third',
      'fourth',
      'fifth',
    ]);
    expect(selectTopSellingProducts(products.slice(0, 1), new Set(['newest-top-seller'])).map((product) => product.id)).toEqual([
      'newest-top-seller',
    ]);
  });
});

describe('hasEnoughBestSellingHistory', () => {
  it('hides the section until the active catalog reaches ten total sold units', () => {
    expect(hasEnoughBestSellingHistory([
      { id: 'item-a', sold_count: 6 },
      { id: 'item-b', sold_count: 3 },
    ])).toBe(false);
    expect(hasEnoughBestSellingHistory([
      { id: 'item-a', sold_count: 6 },
      { id: 'item-b', sold_count: 4 },
    ])).toBe(true);
  });
});
