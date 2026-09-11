import { describe, expect, it } from 'vitest';
import { merchantSchema, productFormSchema, productDetailSchema } from '@/lib/commerceSchemas';

const validMerchant = {
  referralCode: '',
  name: 'Warung Berkah',
  businessCategory: 'kuliner',
  businessDescription: 'Usaha makanan rumahan',
  province: '31',
  city: '3171',
  district: '317101',
  subdistrict: '3171011',
  addressDetail: 'Jalan Mawar nomor 10 dekat pasar',
  phone: '081234567890',
  openTime: '08:00',
  closeTime: '21:00',
};

describe('commerce form validation', () => {
  it('accepts a complete merchant registration', () => {
    expect(merchantSchema.safeParse(validMerchant).success).toBe(true);
  });

  it('rejects incomplete merchant registration', () => {
    const result = merchantSchema.safeParse({ ...validMerchant, name: 'A', phone: '123' });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.map((issue) => issue.path[0])).toEqual(expect.arrayContaining(['name', 'phone']));
    }
  });

  it('rejects invalid product price, stock, and category', () => {
    const result = productFormSchema.safeParse({
      name: 'Produk valid',
      description: '',
      price: '-100',
      stock: '-1',
      category: '',
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.map((issue) => issue.path[0])).toEqual(expect.arrayContaining(['price', 'stock', 'category']));
    }
  });

  it('accepts numeric product fields supplied by HTML inputs as strings', () => {
    const result = productDetailSchema.safeParse({
      name: 'Produk valid',
      description: 'Deskripsi',
      price: '15000',
      stock: '10',
      category: 'kuliner',
      discount_percent: '25',
      min_stock_alert: '5',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.price).toBe(15000);
      expect(result.data.stock).toBe(10);
      expect(result.data.discount_percent).toBe(25);
    }
  });

  it('rejects discount outside 0 to 100 percent', () => {
    const result = productDetailSchema.safeParse({
      name: 'Produk valid',
      description: '',
      price: '15000',
      stock: '10',
      category: 'kuliner',
      discount_percent: '101',
      min_stock_alert: '5',
    });
    expect(result.success).toBe(false);
  });
});
