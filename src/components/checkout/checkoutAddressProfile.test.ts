import { describe, expect, it } from 'vitest';
import { createEmptyCheckoutAddress } from './checkoutAddressDefaults';
import { createCheckoutProfileAddressPayload, hasCompleteRegionAddress } from './checkoutAddressProfile';

describe('checkout profile address synchronization', () => {
  it('requires every administrative region before syncing an address', () => {
    const address = createEmptyCheckoutAddress().address;
    expect(hasCompleteRegionAddress(address)).toBe(false);
    expect(hasCompleteRegionAddress({ ...address, province: '32', city: '3206', district: '320612' })).toBe(false);
    expect(hasCompleteRegionAddress({ ...address, province: '32', city: '3206', district: '320612', village: '3206122001' })).toBe(true);
  });

  it('preserves recipient, full region, detail, and map coordinates in the profile payload', () => {
    const data = createEmptyCheckoutAddress();
    data.name = 'Budi Pembeli';
    data.phone = '081234567890';
    data.address = {
      province: '32', provinceName: 'Jawa Barat',
      city: '3206', cityName: 'Kabupaten Tasikmalaya',
      district: '320612', districtName: 'Taraju',
      village: '3206122001', villageName: 'Raksasari',
      detail: 'Kp. Cilangla 002/001',
    };
    data.detailAddress = 'Kp. Cilangla 002/001';
    data.location = { lat: -7.2, lng: 108.1 };

    expect(createCheckoutProfileAddressPayload('user-1', data)).toEqual({
      user_id: 'user-1',
      full_name: 'Budi Pembeli',
      phone: '081234567890',
      address: 'Kp. Cilangla 002/001, Raksasari, Taraju, Kabupaten Tasikmalaya, Jawa Barat\nGoogle Maps: https://maps.google.com/?q=-7.2,108.1',
      province_id: '32',
      province_name: 'Jawa Barat',
      city_id: '3206',
      city_name: 'Kabupaten Tasikmalaya',
      district_id: '320612',
      district_name: 'Taraju',
      village_id: '3206122001',
      village_name: 'Raksasari',
      address_detail: 'Kp. Cilangla 002/001',
    });
  });
});
