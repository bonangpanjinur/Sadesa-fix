import { describe, expect, it } from 'vitest';
import { getRecommendedPOSModules } from './posModuleRecommendations';

describe('POS module recommendations', () => {
  it('recommends food-service modules for cafes', () => {
    expect(getRecommendedPOSModules('cafe')).toEqual(
      expect.arrayContaining(['cashier', 'tables', 'qr_menu', 'kds', 'ingredients', 'recipes']),
    );
  });

  it('does not recommend restaurant modules for retail', () => {
    expect(getRecommendedPOSModules('retail')).not.toEqual(expect.arrayContaining(['tables', 'kds', 'recipes']));
  });

  it('keeps online-only merchants out of POS activation', () => {
    expect(getRecommendedPOSModules('online')).toEqual([]);
  });
});