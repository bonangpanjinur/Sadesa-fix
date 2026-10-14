import { describe, expect, it } from 'vitest';
import { normalizeRidePickupLandmark, RIDE_PICKUP_LANDMARK_MAX_LENGTH } from './ridePickupLandmark';

describe('normalizeRidePickupLandmark', () => {
  it('requires a useful non-empty landmark and trims surrounding whitespace', () => {
    expect(normalizeRidePickupLandmark('   ')).toBeNull();
    expect(normalizeRidePickupLandmark('AB')).toBeNull();
    expect(normalizeRidePickupLandmark('  Depan madrasah, pagar biru  ')).toBe('Depan madrasah, pagar biru');
  });

  it('rejects landmarks longer than the database contract', () => {
    expect(normalizeRidePickupLandmark('a'.repeat(RIDE_PICKUP_LANDMARK_MAX_LENGTH))).toHaveLength(RIDE_PICKUP_LANDMARK_MAX_LENGTH);
    expect(normalizeRidePickupLandmark('a'.repeat(RIDE_PICKUP_LANDMARK_MAX_LENGTH + 1))).toBeNull();
  });
});
