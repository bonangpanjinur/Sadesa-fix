export type SearchResultsCategory = 'all' | 'products';

export function getExploreCategoryFromSearchParams(searchParams: URLSearchParams): SearchResultsCategory {
  return searchParams.get('category') === 'products' ? 'products' : 'all';
}

export function updateSearchResultsCategoryParams(searchParams: URLSearchParams, category: SearchResultsCategory): URLSearchParams {
  const nextParams = new URLSearchParams(searchParams);
  if (category === 'all') nextParams.delete('category');
  else nextParams.set('category', category);
  return nextParams;
}

export function updateSearchResultsQueryParams(searchParams: URLSearchParams, query: string): URLSearchParams {
  const nextParams = new URLSearchParams(searchParams);
  if (query) nextParams.set('q', query);
  else nextParams.delete('q');
  return nextParams;
}
