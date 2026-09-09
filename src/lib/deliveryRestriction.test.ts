import { describe, expect, it } from 'vitest';
import { getDeliveryRestriction } from './deliveryRestriction';

const sameRegion = {
  cityId: '32.01',
  cityName: 'Kabupaten Bogor',
  districtId: '32.01.01',
  districtName: 'Kecamatan Ciawi',
};

describe('getDeliveryRestriction', () => {
  it('allows local delivery at exactly the 10 km limit', () => {
    expect(getDeliveryRestriction(10, sameRegion, sameRegion)).toEqual({
      requiresExpedition: false,
      reasons: [],
    });
  });

  it('requires expedition when distance is more than 10 km', () => {
    const result = getDeliveryRestriction(10.01, sameRegion, sameRegion);

    expect(result.requiresExpedition).toBe(true);
    expect(result.reasons).toContain('jarak lebih dari 10 km');
  });

  it('requires expedition for a different district', () => {
    const result = getDeliveryRestriction(
      4,
      { ...sameRegion, districtId: '32.01.02', districtName: 'Kecamatan Megamendung' },
      sameRegion,
    );

    expect(result.requiresExpedition).toBe(true);
    expect(result.reasons).toContain('berbeda kecamatan');
  });

  it('requires expedition for a different regency or city', () => {
    const result = getDeliveryRestriction(
      4,
      { ...sameRegion, cityId: '32.02', cityName: 'Kabupaten Sukabumi' },
      sameRegion,
    );

    expect(result.requiresExpedition).toBe(true);
    expect(result.reasons).toContain('berbeda kabupaten/kota');
  });

  it('compares names when merchant region ids are not available', () => {
    expect(getDeliveryRestriction(
      4,
      { cityName: 'Bogor', districtName: 'Ciawi' },
      { cityName: 'Kabupaten Bogor', districtName: 'Kecamatan Ciawi' },
    ).requiresExpedition).toBe(false);
  });
});
