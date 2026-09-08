export interface BusinessCategoryOption {
  value: string;
  label: string;
  icon: string;
}

/**
 * Kategori usaha yang dapat didaftarkan sebagai pelaku usaha desa.
 * Slug `kriya` dipertahankan agar produk kerajinan lama tetap terbaca,
 * tetapi ditampilkan sebagai Produk Desa di UI.
 */
export const BUSINESS_CATEGORY_OPTIONS: readonly BusinessCategoryOption[] = [
  { value: 'kuliner', label: 'Kuliner & Makanan', icon: '🍜' },
  { value: 'sembako', label: 'Sembako', icon: '🛒' },
  { value: 'kriya', label: 'Produk Desa & Kerajinan', icon: '🎨' },
  { value: 'wisata', label: 'Wisata & Pengalaman', icon: '🗺️' },
  { value: 'jasa', label: 'Jasa & Tukang', icon: '🔧' },
  { value: 'pertanian', label: 'Pertanian (Petani)', icon: '🌾' },
  { value: 'peternakan', label: 'Peternakan & Perikanan', icon: '🐟' },
];

export const BUSINESS_CATEGORY_VALUES = BUSINESS_CATEGORY_OPTIONS.map(({ value }) => value);