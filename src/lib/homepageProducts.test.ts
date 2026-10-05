import { describe, expect, it } from 'vitest';
import { selectNewestProducts, selectTopSellingProducts } from './homepageProducts';

describe('selectNewestProducts', () => {
  it('keeps stored products visible regardless of active or orderable status', () => {
    const products = [
      { id: 'open', isActive: true, isAvailable: true },
      { id: 'closed', isActive: true, isAvailable: false, unavailableReason: 'Toko Tutup' },
      { id: 'out-of-stock', isActive: true, isAvailable: false, unavailableReason: 'Stok Habis' },
      { id: 'inactive', isActive: false, isAvailable: false, unavailableReason: 'Produk Nonaktif' },
    ];

    expect(selectNewestProducts(products, new Set()).map((product) => product.id)).toEqual([
      'open',
      'closed',
      'out-of-stock',
      'inactive',
    ]);
  });

  it('does not repeat products already shown in the promo section', () => {
    const products = [
      { id: 'promo', isActive: true },
      { id: 'newest', isActive: true },
    ];

    expect(selectNewestProducts(products, new Set(['promo'])).map((product) => product.id)).toEqual(['newest']);
  });

  it('limits the section to the requested number of products', () => {
    const products = Array.from({ length: 8 }, (_, index) => ({ id: `product-${index}`, isActive: true }));

    expect(selectNewestProducts(products, new Set(), 3)).toHaveLength(3);
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
