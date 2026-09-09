import { describe, expect, it } from 'vitest';
import { merchantSettingsSchema } from './validationSchemas';

const validSettings = {
  name: 'Warung Maju',
  phone: '081234567890',
  address: 'Jalan Mawar nomor 10 dekat pasar',
  google_maps_url: 'https://maps.google.com/?q=Warung+Maju',
  business_category: 'kuliner',
  business_description: 'Menyediakan makanan rumahan.',
  open_time: '08:00',
  close_time: '17:00',
  is_open: true,
  classification_price: 'FROM_5K_TO_10K',
  order_mode: 'ADMIN_ASSISTED',
  bank_name: '',
  bank_account_number: '',
  bank_account_name: '',
  payment_cod_enabled: true,
  payment_transfer_enabled: true,
  notification_sound_enabled: true,
  slug: 'warung-maju',
};

describe('merchantSettingsSchema', () => {
  it('accepts valid settings and optional admin payment fallback', () => {
    expect(merchantSettingsSchema.safeParse(validSettings).success).toBe(true);
  });

  it('rejects invalid phone numbers and partial bank details', () => {
    const result = merchantSettingsSchema.safeParse({
      ...validSettings,
      phone: '123',
      bank_name: 'BCA',
    });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.map((issue) => issue.path.join('.'))).toEqual(
        expect.arrayContaining(['phone', 'bank_account_number']),
      );
    }
  });

  it('requires at least one payment method', () => {
    const result = merchantSettingsSchema.safeParse({
      ...validSettings,
      payment_cod_enabled: false,
      payment_transfer_enabled: false,
    });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.some((issue) => issue.path[0] === 'payment_transfer_enabled')).toBe(true);
    }
  });

  it('accepts a Google Maps URL and rejects non-URL values', () => {
    expect(merchantSettingsSchema.safeParse(validSettings).success).toBe(true);
    expect(merchantSettingsSchema.safeParse({
      ...validSettings,
      google_maps_url: 'lokasi toko',
    }).success).toBe(false);
  });
});