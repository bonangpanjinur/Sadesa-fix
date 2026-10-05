import foodImage from '@/assets/home/service-food-optimized.jpg';
import ojekImage from '@/assets/home/service-ojek-optimized.jpg';
import shoppingImage from '@/assets/home/service-shopping-optimized.jpg';

export const HOMEPAGE_SERVICE_CARDS = [
  { id: 'food', title: 'Makanan & Minuman', href: '/products?type=kuliner', fallbackImage: foodImage, imageAlt: 'Aneka makanan dan minuman' },
  { id: 'ojek', title: 'Ojek', href: '/ride', fallbackImage: ojekImage, imageAlt: 'Layanan ojek desa' },
  { id: 'shopping', title: 'Belanja', href: '/products?type=belanja', fallbackImage: shoppingImage, imageAlt: 'Sayuran dan kebutuhan belanja' },
] as const;

export type HomepageServiceCardId = (typeof HOMEPAGE_SERVICE_CARDS)[number]['id'];
export type HomepageServiceCardImageOverrides = Record<HomepageServiceCardId, string | null>;

export const EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES: HomepageServiceCardImageOverrides = {
  food: null,
  ojek: null,
  shopping: null,
};

export function parseHomepageServiceCardImageOverrides(value: unknown): HomepageServiceCardImageOverrides {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return { ...EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES };
  }

  const stored = value as Partial<Record<HomepageServiceCardId, unknown>>;
  const readImage = (id: HomepageServiceCardId) =>
    typeof stored[id] === 'string' && stored[id].trim() ? stored[id].trim() : null;

  return {
    food: readImage('food'),
    ojek: readImage('ojek'),
    shopping: readImage('shopping'),
  };
}
