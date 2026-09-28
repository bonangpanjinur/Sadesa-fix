import { describe, expect, it } from 'vitest';
import { getExploreCategoryFromSearchParams, updateSearchResultsCategoryParams, updateSearchResultsQueryParams } from './searchResultsFilters';

describe('getExploreCategoryFromSearchParams', () => {
  it('restores the products tab from the URL', () => {
    expect(getExploreCategoryFromSearchParams(new URLSearchParams('q=kopi&category=products'))).toBe('products');
  });

  it.each([
    new URLSearchParams(),
    new URLSearchParams('q=kopi'),
    new URLSearchParams('q=kopi&category=all'),
    new URLSearchParams('q=kopi&category=unknown'),
  ])('defaults to all when no supported category is selected', (searchParams) => {
    expect(getExploreCategoryFromSearchParams(searchParams)).toBe('all');
  });

  it('stores the products tab without removing the search query', () => {
    const nextParams = updateSearchResultsCategoryParams(new URLSearchParams('q=kopi'), 'products');
    expect(nextParams.get('q')).toBe('kopi');
    expect(nextParams.get('category')).toBe('products');
  });

  it('clears the category filter while preserving the search query', () => {
    const nextParams = updateSearchResultsCategoryParams(new URLSearchParams('q=kopi&category=products'), 'all');
    expect(nextParams.get('q')).toBe('kopi');
    expect(nextParams.has('category')).toBe(false);
  });

  it('preserves the active category when the search query changes', () => {
    const nextParams = updateSearchResultsQueryParams(new URLSearchParams('q=kopi&category=products'), 'teh');
    expect(nextParams.get('q')).toBe('teh');
    expect(nextParams.get('category')).toBe('products');
  });
});
