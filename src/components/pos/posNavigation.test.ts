import { describe, expect, it } from 'vitest';
import { POS_MENU_CATEGORIES } from './posNavigation';

describe('POS menu terminology', () => {
  it('uses the same product-catalog label as the merchant workspace for the shared route', () => {
    const catalogItem = POS_MENU_CATEGORIES
      .flatMap((category) => category.items)
      .find((item) => item.href === '/merchant/products');

    expect(catalogItem?.label).toBe('Katalog Produk');
  });
});
