import type { HomepageLayoutSettings, HomepageSection } from '@/hooks/useHomepageLayout';

/**
 * Safe first-paint defaults used only when the optional homepage_layout setting
 * has not been saved yet. Runtime ordering and visibility come from Supabase.
 */
export const DEFAULT_HOMEPAGE_SECTIONS: HomepageSection[] = [
  { id: 'categories', name: 'Menu Utama', enabled: true, order: 0 },
  { id: 'hero', name: 'Hero Banner', enabled: true, order: 1 },
  { id: 'popular_tourism', name: 'Wisata Populer', enabled: false, order: 2 },
  { id: 'promo', name: 'Promo Spesial', enabled: true, order: 3 },
  { id: 'recommendations', name: 'Rekomendasi Pilihan', enabled: true, order: 4 },
  { id: 'villages', name: 'Jelajahi Desa', enabled: false, order: 5 },
];

export const DEFAULT_HOMEPAGE_LAYOUT: HomepageLayoutSettings = {
  sections: DEFAULT_HOMEPAGE_SECTIONS,
  visible_categories: ['kuliner', 'ojek'],
};

export function cloneDefaultHomepageLayout(): HomepageLayoutSettings {
  return {
    sections: DEFAULT_HOMEPAGE_SECTIONS.map((section) => ({ ...section })),
    visible_categories: [...DEFAULT_HOMEPAGE_LAYOUT.visible_categories],
  };
}
