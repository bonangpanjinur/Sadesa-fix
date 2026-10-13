import type { ShippingFeeSettings, ShippingZonesSettings } from '@/types/admin';

const shippingFeeFields: Array<keyof ShippingFeeSettings> = [
  'base_fee',
  'per_km_fee',
  'min_fee',
  'max_fee',
  'free_shipping_min_order',
];

export function validateShippingFeeSettings(settings: ShippingFeeSettings): string[] {
  const errors: string[] = [];

  if (shippingFeeFields.some((field) => !Number.isSafeInteger(settings[field]) || settings[field] < 0)) {
    errors.push('Semua tarif harus berupa bilangan rupiah bulat dan tidak boleh negatif.');
  }
  if (
    Number.isSafeInteger(settings.min_fee) &&
    Number.isSafeInteger(settings.max_fee) &&
    settings.min_fee > settings.max_fee
  ) {
    errors.push('Biaya minimum tidak boleh melebihi biaya maksimum.');
  }

  return errors;
}

export function validateShippingZonesSettings(settings: ShippingZonesSettings): string[] {
  const errors: string[] = [];
  if (!Array.isArray(settings.zones) || settings.zones.length === 0) {
    return ['Tambahkan minimal satu zona pengiriman.'];
  }

  let previousDistance = 0;
  let invalidOrder = false;

  settings.zones.forEach((zone, index) => {
    if (!zone.name.trim()) errors.push(`Nama zona ${index + 1} wajib diisi.`);

    if (!Number.isFinite(zone.max_distance_km) || zone.max_distance_km <= 0) {
      errors.push(`Batas jarak zona ${index + 1} harus lebih dari 0 km.`);
    } else {
      if (zone.max_distance_km <= previousDistance) invalidOrder = true;
      previousDistance = zone.max_distance_km;
    }

    if (!Number.isSafeInteger(zone.fee) || zone.fee < 0) {
      errors.push(`Surcharge zona ${index + 1} harus berupa bilangan rupiah bulat dan tidak boleh negatif.`);
    }
  });

  if (invalidOrder) {
    errors.push('Urutkan zona dari batas jarak terkecil ke terbesar; batas harus unik agar zona tidak tumpang tindih.');
  }

  return errors;
}
