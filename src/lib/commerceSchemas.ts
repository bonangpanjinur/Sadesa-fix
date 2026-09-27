import { z } from 'zod';

export const merchantSchema = z.object({
  referralCode: z.string().max(50).optional(),
  name: z.string().min(3, 'Nama usaha minimal 3 karakter').max(100),
  businessCategory: z.string().min(1, 'Pilih minimal satu kategori usaha'),
  businessDescription: z.string().max(500).optional(),
  province: z.string().min(1, 'Pilih provinsi'),
  city: z.string().min(1, 'Pilih kabupaten/kota'),
  district: z.string().min(1, 'Pilih kecamatan'),
  subdistrict: z.string().min(1, 'Pilih kelurahan/desa'),
  addressDetail: z.string().min(10, 'Alamat detail minimal 10 karakter').max(200),
  phone: z.string().min(10, 'Nomor telepon minimal 10 digit').max(15),
  openTime: z.string().min(1, 'Pilih jam buka'),
  closeTime: z.string().min(1, 'Pilih jam tutup'),
});

export const productFormSchema = z.object({
  name: z.string().trim().min(2, 'Nama produk minimal 2 karakter').max(150, 'Nama produk maksimal 150 karakter'),
  description: z.string().trim().max(2000, 'Deskripsi maksimal 2.000 karakter'),
  price: z.coerce.number({ invalid_type_error: 'Harga wajib diisi' }).int('Harga harus berupa angka bulat').min(1_000, 'Harga minimal Rp1.000 agar tidak salah input').max(1_000_000_000, 'Harga terlalu besar'),
  stock: z.coerce.number({ invalid_type_error: 'Stok wajib berupa angka' }).int('Stok harus berupa angka bulat').min(0, 'Stok tidak boleh negatif').max(1_000_000, 'Stok terlalu besar'),
  category: z.string().min(1, 'Pilih kategori produk'),
});

export const productDetailSchema = z.object({
  name: z.string().trim().min(2, 'Nama produk minimal 2 karakter').max(150, 'Nama produk maksimal 150 karakter'),
  description: z.string().trim().max(2000, 'Deskripsi maksimal 2.000 karakter'),
  price: z.coerce.number({ invalid_type_error: 'Harga wajib diisi' }).int('Harga harus berupa angka bulat').min(1_000, 'Harga minimal Rp1.000 agar tidak salah input').max(1_000_000_000, 'Harga terlalu besar'),
  stock: z.coerce.number({ invalid_type_error: 'Stok wajib berupa angka' }).int('Stok harus berupa angka bulat').min(0, 'Stok tidak boleh negatif').max(1_000_000, 'Stok terlalu besar'),
  category: z.string().min(1, 'Pilih kategori produk'),
  discount_percent: z.coerce.number({ invalid_type_error: 'Diskon wajib berupa angka' }).int('Diskon harus berupa angka bulat').min(0, 'Diskon minimal 0%').max(100, 'Diskon maksimal 100%').optional(),
  min_stock_alert: z.coerce.number({ invalid_type_error: 'Batas stok wajib berupa angka' }).int('Batas stok harus berupa angka bulat').min(0, 'Batas stok tidak boleh negatif').max(1_000_000, 'Batas stok terlalu besar'),
});
