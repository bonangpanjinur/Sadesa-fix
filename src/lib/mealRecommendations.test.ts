import { describe, expect, it } from 'vitest';
import { DEFAULT_MEAL_RECOMMENDATIONS, getMealPeriod, normalizeMealRecommendations } from './mealRecommendations';

describe('meal recommendations', () => {
  it('maps local clock hours to the four meal periods', () => {
    expect([4, 5, 10, 14, 18, 23].map(getMealPeriod)).toEqual(['malam', 'pagi', 'siang', 'sore', 'malam', 'malam']);
  });

  it('uses defaults for missing or malformed settings and bounds configured text', () => {
    const normalized = normalizeMealRecommendations({
      pagi: { title: '  Menu pagi  ', body: 'Pesan baru', suggestion: 'Saran baru', enabled: false },
      siang: { title: 'x'.repeat(100), enabled: 'yes' },
    });
    expect(normalized.pagi).toEqual({ title: 'Menu pagi', body: 'Pesan baru', suggestion: 'Saran baru', enabled: false });
    expect(normalized.siang.title).toHaveLength(80);
    expect(normalized.siang.enabled).toBe(true);
    expect(normalized.sore).toEqual(DEFAULT_MEAL_RECOMMENDATIONS.sore);
  });
});
