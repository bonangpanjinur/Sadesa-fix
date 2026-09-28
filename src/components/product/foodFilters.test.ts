import { describe, expect, it } from 'vitest';
import { getCatalogTypeFromSearchParams } from './foodFilters';

describe('getCatalogTypeFromSearchParams', () => {
  it('uses all when the URL does not specify a category', () => {
    expect(getCatalogTypeFromSearchParams(new URLSearchParams())).toBe('all');
    expect(getCatalogTypeFromSearchParams(new URLSearchParams('type=all'))).toBe('all');
  });

  it.each(['kuliner', 'pertanian', 'kelontongan', 'makanan', 'minuman'])('preserves selected category %s from the URL', (type) => {
    expect(getCatalogTypeFromSearchParams(new URLSearchParams(`type=${type}`))).toBe(type);
  });

  it('normalizes the legacy Belanja alias to the category used by products', () => {
    expect(getCatalogTypeFromSearchParams(new URLSearchParams('type=belanja'))).toBe('kelontongan');
    expect(getCatalogTypeFromSearchParams(new URLSearchParams('type=%20BELANJA%20'))).toBe('kelontongan');
  });
});
