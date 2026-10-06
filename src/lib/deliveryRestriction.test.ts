import { describe, expect, it } from 'vitest';
import { getDeliveryRestriction, MAX_OJEK_DELIVERY_DISTANCE_KM } from './deliveryRestriction';

describe('getDeliveryRestriction', () => {
  it('allows delivery at exactly the 20 km Ojek limit', () => {
    expect(getDeliveryRestriction(MAX_OJEK_DELIVERY_DISTANCE_KM)).toEqual({
      exceedsMaxDistance: false,
      reasons: [],
    });
  });

  it('blocks routes that are more than 20 km', () => {
    const result = getDeliveryRestriction(20.01);

    expect(result.exceedsMaxDistance).toBe(true);
    expect(result.reasons).toContain('jarak rute lebih dari 20 km');
  });

  it('allows a nearby destination across an administrative boundary', () => {
    expect(getDeliveryRestriction(8).exceedsMaxDistance).toBe(false);
  });

  it('does not classify a missing route distance as over the limit', () => {
    expect(getDeliveryRestriction(null)).toEqual({
      exceedsMaxDistance: false,
      reasons: [],
    });
  });
});
