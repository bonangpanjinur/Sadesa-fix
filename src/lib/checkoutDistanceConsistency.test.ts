import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const checkout = readFileSync(resolve(process.cwd(), 'src/pages/CheckoutPage.tsx'), 'utf8');

describe('checkout shipping distance consistency contract', () => {
  it('sends the same calculated distance used by the shipping summary', () => {
    expect(checkout).toContain('p_distance_km: deliveryType === \'PICKUP\' ? null : distanceKm');
    expect(checkout).not.toContain('p_distance_km: null');
  });

  it('blocks non-pickup checkout until a positive route distance is ready', () => {
    expect(checkout).toContain('const distanceCalculationRequired = deliveryType !== \'PICKUP\'');
    expect(checkout).toContain('const distanceReady = !distanceCalculationRequired');
    expect(checkout).toContain('if (!distanceReady)');
    expect(checkout).toContain('|| !distanceReady ||');
  });
});
