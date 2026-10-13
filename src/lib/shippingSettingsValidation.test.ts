import { describe, expect, it } from 'vitest';
import { validateShippingFeeSettings, validateShippingZonesSettings } from './shippingSettingsValidation';

describe('shipping fee settings validation', () => {
  it('accepts non-negative integer rupiah values with a valid range', () => {
    expect(validateShippingFeeSettings({
      base_fee: 5000,
      per_km_fee: 2000,
      min_fee: 5000,
      max_fee: 50000,
      free_shipping_min_order: 100000,
    })).toEqual([]);
  });

  it('rejects negative, fractional, unsafe, and inverted rate values', () => {
    expect(validateShippingFeeSettings({
      base_fee: -1,
      per_km_fee: 1.5,
      min_fee: 60000,
      max_fee: 50000,
      free_shipping_min_order: Number.MAX_SAFE_INTEGER + 1,
    })).toEqual(expect.arrayContaining([
      'Semua tarif harus berupa bilangan rupiah bulat dan tidak boleh negatif.',
      'Biaya minimum tidak boleh melebihi biaya maksimum.',
    ]));
  });
});

describe('shipping zone validation', () => {
  const validZones = {
    zones: [
      { name: 'Dalam Desa', max_distance_km: 5, fee: 5000 },
      { name: 'Antar Desa', max_distance_km: 15, fee: 10000 },
      { name: 'Luar Kecamatan', max_distance_km: 30, fee: 20000 },
    ],
  };

  it('accepts ordered, positive distance bands and non-negative integer surcharges', () => {
    expect(validateShippingZonesSettings(validZones)).toEqual([]);
  });

  it('rejects blank names, non-positive distance, negative fees, and overlapping or unordered bands', () => {
    expect(validateShippingZonesSettings({
      zones: [
        { name: '   ', max_distance_km: 5, fee: -1 },
        { name: 'Duplikat', max_distance_km: 5, fee: 1000 },
        { name: 'Zona Tidak Valid', max_distance_km: 0, fee: 0 },
      ],
    })).toEqual(expect.arrayContaining([
      'Nama zona 1 wajib diisi.',
      'Surcharge zona 1 harus berupa bilangan rupiah bulat dan tidak boleh negatif.',
      'Urutkan zona dari batas jarak terkecil ke terbesar; batas harus unik agar zona tidak tumpang tindih.',
      'Batas jarak zona 3 harus lebih dari 0 km.',
    ]));
  });

  it('requires at least one zone', () => {
    expect(validateShippingZonesSettings({ zones: [] })).toEqual(['Tambahkan minimal satu zona pengiriman.']);
  });
});
