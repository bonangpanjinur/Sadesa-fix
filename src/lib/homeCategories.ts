export interface HomepageCategory {
  id: string;
  name: string;
  icon: string;
  colorClass: string;
  route?: string;
}

export const PRIMARY_HOME_CATEGORIES: HomepageCategory[] = [
  { id: 'kuliner', name: 'Kuliner', icon: 'utensils', colorClass: 'bg-orange-100 text-orange-700 border-orange-200' },
  { id: 'ojek', name: 'Ojek & Kurir', icon: 'bike', colorClass: 'bg-emerald-100 text-emerald-700 border-emerald-200', route: '/ride' },
  { id: 'wisata', name: 'Wisata', icon: 'map-location-dot', colorClass: 'bg-cyan-100 text-cyan-700 border-cyan-200', route: '/tourism' },
  { id: 'kriya', name: 'Produk Desa', icon: 'shapes', colorClass: 'bg-teal-100 text-teal-700 border-teal-200' },
];

export const ALL_HOME_CATEGORIES = PRIMARY_HOME_CATEGORIES;

export function normalizeCategorySlug(value: string | null | undefined): string {
  return (value || '').trim().toLowerCase().replace(/&/g, 'dan').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function getHomepageCategoryHref(category: HomepageCategory): string {
  return category.route || `/products?category=${encodeURIComponent(category.id)}`;
}
