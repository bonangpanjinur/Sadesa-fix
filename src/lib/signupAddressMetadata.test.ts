import { describe, expect, it } from 'vitest';
import { getSignupAddressBackfill, restoreSignupAddress, toRegistrationAddressPrefill } from './signupAddressMetadata';

describe('restoreSignupAddress', () => {
  const signupMetadata = {
    full_name: 'Dewi Lestari',
    address: 'Jl. Melati, Sukamaju, Cihideung, Kota Tasikmalaya, Jawa Barat',
    province_id: '32',
    province_name: 'Jawa Barat',
    city_id: '3278',
    city_name: 'Kota Tasikmalaya',
    district_id: '3278010',
    district_name: 'Cihideung',
    village_id: '3278010001',
    village_name: 'Sukamaju',
    address_detail: 'Jl. Melati',
  };

  it('restores a complete signup address when profile provisioning did not copy metadata', () => {
    const result = restoreSignupAddress(null, signupMetadata, 'Dewi');

    expect(result).toMatchObject({
      full_name: 'Dewi Lestari',
      province_id: '32',
      province_name: 'Jawa Barat',
      city_id: '3278',
      district_id: '3278010',
      village_id: '3278010001',
      address_detail: 'Jl. Melati',
    });
  });

  it('fills missing legacy profile fields without overwriting values edited in profile', () => {
    const result = restoreSignupAddress(
      { full_name: 'Nama Baru', province_name: 'Banten', province_id: null, city_id: null },
      signupMetadata,
    );

    expect(result).toMatchObject({
      full_name: 'Nama Baru',
      province_name: 'Banten',
      province_id: '32',
      city_id: '3278',
      village_id: '3278010001',
    });
  });

  it('does not invent an address when neither profile nor auth metadata has one', () => {
    expect(restoreSignupAddress(null, { full_name: 'Dewi' }, 'Pengguna')).toBeNull();
  });

  it('creates a backfill for a complete signup address without replacing profile values', () => {
    const backfill = getSignupAddressBackfill(
      { province_name: 'Banten', province_id: '36' },
      signupMetadata,
    );
    expect(backfill).toMatchObject({
      address: signupMetadata.address,
      city_id: '3278',
      village_id: '3278010001',
    });
    expect(backfill.province_id).toBeUndefined();
    expect(backfill.province_name).toBeUndefined();
  });

  it('does not backfill an incomplete signup hierarchy', () => {
    expect(getSignupAddressBackfill(null, { ...signupMetadata, village_id: '' })).toEqual({});
  });

  it('maps a complete profile address into registration dropdown and detail values', () => {
    expect(toRegistrationAddressPrefill(signupMetadata)).toEqual({
      provinceCode: '32',
      provinceName: 'Jawa Barat',
      cityCode: '3278',
      cityName: 'Kota Tasikmalaya',
      districtCode: '3278010',
      districtName: 'Cihideung',
      villageCode: '3278010001',
      villageName: 'Sukamaju',
      addressDetail: 'Jl. Melati',
    });
  });

  it('does not prefill a registration address unless every hierarchy code exists', () => {
    expect(toRegistrationAddressPrefill({ ...signupMetadata, district_id: null })).toBeNull();
  });
});
