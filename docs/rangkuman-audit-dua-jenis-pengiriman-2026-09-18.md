# Rangkuman Audit Dua Jenis Pengiriman

**Tanggal:** 18 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`

## Kesimpulan Utama

Aplikasi memiliki dua layanan yang berbeda secara bisnis:

1. **Pesanan toko menggunakan kurir.** Pembeli membeli produk dari merchant. Merchant menyiapkan barang, kemudian kurir mengambilnya dari toko dan mengantar kepada pembeli.
2. **Antar Barang.** Pemesan meminta kurir mengambil barang dari lokasi pickup dan mengantarkannya kepada penerima. Layanan ini tidak memiliki merchant dan tidak memiliki item produk.

Kedua layanan tetap menggunakan infrastruktur order, pembayaran, notifikasi, tracking, assignment kurir, bukti serah-terima, dan riwayat yang sama. Namun, entry point, data, lifecycle, chat, rating, serta laporan harus tetap dipisahkan.

## Keputusan Data

| Jenis layanan | `service_type` | Merchant | Item produk | Pickup |
|---|---|---|---|---|
| Pesanan toko | `MARKETPLACE` | Wajib | Wajib | Toko |
| Antar Barang | `COURIER_DELIVERY` | Tidak ada | Tidak ada | Lokasi pemesan |

`service_type` menjadi identitas utama transaksi. Sistem tidak boleh menentukan order kurir hanya dari kondisi `merchant_id` kosong. Untuk data lama, fallback dilakukan secara konservatif agar order yang tidak jelas tetap dianggap marketplace.

## Jalur Operasional

### Pesanan toko

Pembeli memilih produk → checkout marketplace → order `MARKETPLACE` dibuat → merchant memproses → kurir menerima tugas → kurir pickup di toko → kurir mengantar ke pembeli → bukti serah-terima → order selesai.

### Antar Barang

Pemesan membuka layanan Antar Barang → memilih pickup dan tujuan → mengisi penerima, jenis barang, dan berat → order `COURIER_DELIVERY` dibuat → kurir ditawarkan atau ditugaskan → kurir pickup di lokasi pemesan → kurir mengantar ke penerima → bukti serah-terima → order selesai.

UI kini menggunakan satu layanan **Antar Barang**. Pilihan **Kirim barang** dan **Ambil barang** dihapus karena keduanya memiliki operasi yang sama: kurir mengambil dari pickup dan mengantarkan ke tujuan.

## Implementasi yang Sudah Selesai

- Menambahkan kontrak flow terpusat pada `src/lib/deliveryFlow.ts`.
- Menambahkan guard untuk membedakan marketplace dan direct courier.
- Menghubungkan riwayat buyer ke kontrak flow tersebut.
- Memastikan detail direct courier tidak menampilkan merchant, item produk, subtotal, chat merchant, atau tombol `Pesan Lagi`.
- Menghapus selector Kirim/Ambil dari halaman booking kurir.
- Mengubah kartu navigasi dan copy halaman transport menjadi **Antar Barang**.
- Mempertahankan backend `create_courier_order` dan `service_type = COURIER_DELIVERY`.
- Menambahkan test regresi untuk klasifikasi, service type, pickup owner, dan policy item produk.

## Rencana Perbaikan Lanjutan

### P0 — Wajib sebelum produksi

- Terapkan migration `service_type` dan seluruh migration courier ke staging.
- Uji checkout marketplace dan booking Antar Barang menggunakan user buyer.
- Pastikan marketplace memiliki merchant dan item produk.
- Pastikan Antar Barang tidak memiliki merchant dan item produk.

### P1 — Validasi lintas modul

- Audit laporan merchant, invoice, export, notifikasi, dan deep link.
- Pastikan order `COURIER_DELIVERY` tidak masuk omzet merchant.
- Uji RLS untuk buyer, merchant, courier, dan admin.
- Uji state transition marketplace dan courier secara terpisah.

### P2 — Observability

- Tambahkan metrik berdasarkan `service_type`.
- Bandingkan error dispatch, cancellation, completion, dan payout antara dua layanan.

## Checklist Staging

1. Buat satu order marketplace.
2. Buat satu order Antar Barang.
3. Verifikasi `service_type` masing-masing.
4. Verifikasi riwayat buyer menampilkan konteks yang benar.
5. Verifikasi detail Antar Barang menampilkan pickup, tujuan, penerima, jenis barang, berat, biaya layanan, dan status kurir.
6. Pastikan tidak ada chat merchant, subtotal produk, atau `Pesan Lagi` pada Antar Barang.
7. Jalankan order kurir dari assignment sampai proof of delivery.
8. Pastikan laporan merchant hanya menghitung order `MARKETPLACE`.
9. Uji data legacy tanpa `service_type` dan catat hasil backfill.

## Status Verifikasi Lokal

- 11 test regresi lulus.
- TypeScript lulus.
- ESLint lulus.
- Production build lulus.
- PWA build lulus.

Verifikasi database staging dan RLS belum dijalankan dari lingkungan lokal.

## Dokumen Utama

- Audit lengkap: `docs/audit-pemisahan-dua-jenis-pengiriman-2026-09-18.md`
- Kontrak flow: `src/lib/deliveryFlow.ts`
- Test kontrak: `src/lib/deliveryFlow.test.ts`
