export interface HomepageCategory {
  id: string;
  name: string;
  icon: string;
  colorClass: string;
  route?: string;
}

export const PRIMARY_HOME_CATEGORIES: HomepageCategory[] = [
  { id: 'kuliner', name: 'Kuliner', icon: 'utensils', colorClass: 'bg-orange-100 text-orange-700 border-orange-200' },
  { id: 'sembako', name: 'Sembako', icon: 'shopping-basket', colorClass: 'bg-amber-100 text-amber-700 border-amber-200' },
  { id: 'kriya', name: 'Produk Desa', icon: 'shapes', colorClass: 'bg-teal-100 text-teal-700 border-teal-200' },
  { id: 'wisata', name: 'Wisata', icon: 'map-location-dot', colorClass: 'bg-cyan-100 text-cyan-700 border-cyan-200', route: '/tourism' },
  { id: 'jasa', name: 'Jasa', icon: 'wrench', colorClass: 'bg-blue-100 text-blue-700 border-blue-200' },
  { id: 'pertanian', name: 'Pertanian', icon: 'sprout', colorClass: 'bg-green-100 text-green-700 border-green-200' },
  { id: 'peternakan', name: 'Peternakan & Perikanan', icon: 'wheat', colorClass: 'bg-lime-100 text-lime-700 border-lime-200' },
  { id: 'ojek', name: 'Ojek & Kurir', icon: 'bike', colorClass: 'bg-emerald-100 text-emerald-700 border-emerald-200', route: '/ride' },
];

export const ALL_HOME_CATEGORIES = PRIMARY_HOME_CATEGORIES;

export function normalizeCategorySlug(value: string | null | undefined): string {
  return (value || '').trim().toLowerCase().replace(/&/g, 'dan').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function getHomepageCategoryHref(category: HomepageCategory): string {
  return category.route || `/products?category=${encodeURIComponent(category.id)}`;
}
