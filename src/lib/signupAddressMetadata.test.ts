import { describe, expect, it } from 'vitest';
import { restoreSignupAddress } from './signupAddressMetadata';

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
});
