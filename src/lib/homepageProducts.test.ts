import { describe, expect, it } from 'vitest';
import { selectNewestProducts } from './homepageProducts';

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
