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
  { id: 'kesehatan', name: 'Kesehatan', icon: 'heart-pulse', colorClass: 'bg-rose-100 text-rose-700 border-rose-200' },
  { id: 'ojek', name: 'Ojek & Kurir', icon: 'motorcycle', colorClass: 'bg-emerald-100 text-emerald-700 border-emerald-200', route: '/ride' },
];

export const SECONDARY_HOME_CATEGORIES: HomepageCategory[] = [
  { id: 'fashion', name: 'Fashion', icon: 'shirt', colorClass: 'bg-purple-100 text-purple-700 border-purple-200' },
  { id: 'elektronik', name: 'Elektronik', icon: 'smartphone', colorClass: 'bg-slate-100 text-slate-700 border-slate-200' },
  { id: 'otomotif', name: 'Otomotif', icon: 'car', colorClass: 'bg-red-100 text-red-700 border-red-200' },
  { id: 'properti', name: 'Properti & Kos', icon: 'house', colorClass: 'bg-indigo-100 text-indigo-700 border-indigo-200' },
  { id: 'event', name: 'Event Desa', icon: 'calendar', colorClass: 'bg-pink-100 text-pink-700 border-pink-200' },
  { id: 'lowongan', name: 'Lowongan Kerja', icon: 'briefcase', colorClass: 'bg-yellow-100 text-yellow-700 border-yellow-200' },
];

export const ALL_HOME_CATEGORIES = [...PRIMARY_HOME_CATEGORIES, ...SECONDARY_HOME_CATEGORIES];

export function normalizeCategorySlug(value: string | null | undefined): string {
  return (value || '').trim().toLowerCase().replace(/&/g, 'dan').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function getHomepageCategoryHref(category: HomepageCategory): string {
  return category.route || `/products?category=${encodeURIComponent(category.id)}`;
}
