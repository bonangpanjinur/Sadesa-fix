import { describe, expect, it } from 'vitest';
import {
  EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES,
  HOMEPAGE_SERVICE_CARDS,
  parseHomepageServiceCardImageOverrides,
} from './homeServiceCards';

describe('homepage service cards', () => {
  it('keeps the three requested primary categories and their routes', () => {
    expect(HOMEPAGE_SERVICE_CARDS.map(({ title, href }) => ({ title, href }))).toEqual([
      { title: 'Makanan & Minuman', href: '/products?type=kuliner' },
      { title: 'Ojek', href: '/ride' },
      { title: 'Belanja', href: '/products?type=belanja' },
    ]);
  });

  it('does not define local image fallbacks for homepage cards', () => {
    expect(HOMEPAGE_SERVICE_CARDS.every((card) => !('fallbackImage' in card))).toBe(true);
  });

  it('uses no overrides when admin settings are absent or malformed', () => {
    expect(parseHomepageServiceCardImageOverrides(null)).toEqual(EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES);
    expect(parseHomepageServiceCardImageOverrides(['not', 'an', 'object'])).toEqual(EMPTY_HOMEPAGE_SERVICE_CARD_IMAGE_OVERRIDES);
  });

  it('accepts only non-empty image URLs for known card IDs', () => {
    expect(parseHomepageServiceCardImageOverrides({
      food: ' https://example.com/food.webp ',
      ojek: '',
      shopping: 7,
      unknown: 'https://example.com/ignored.webp',
    })).toEqual({
      food: 'https://example.com/food.webp',
      ojek: null,
      shopping: null,
    });
  });
});
