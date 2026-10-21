# Audit dan penyesuaian homepage — menu ikon

Tanggal: 21 Oktober 2026

## Temuan

- Kartu menu utama sebelumnya memakai rasio gambar banner `1,12:1` dan gambar memenuhi seluruh kartu. Ini tidak sesuai referensi yang memakai satu panel putih, tiga kolom, ikon dalam lingkaran hijau muda, label tebal, dan pembatas vertikal.
- Admin masih menampilkan copy `Gambar Menu Utama`, memvalidasi rasio banner, dan mengompres ke JPEG. Perilaku tersebut berisiko merusak ikon PNG transparan.
- Konfigurasi remote `app_settings.homepage_service_card_images` sudah menjadi sumber data yang dipakai beranda. Key ini dipertahankan agar konfigurasi lama tidak putus.
- Default urutan layout sebelumnya menampilkan hero sebelum menu utama. Default sekarang menempatkan menu utama lebih dulu.

## Perubahan

- `HomeServiceCards` kini memakai panel putih rounded dengan tiga kolom, pembatas vertikal, ikon fallback Lucide, dan ikon upload dalam lingkaran `4.4rem`.
- Admin Branding & Tampilan kini menggunakan label **Ikon Menu Utama**, upload persegi 1:1, batas 5 MB, kompresi maksimal 512×512, dan preview `object-contain`.
- Ikon PNG dipertahankan sebagai PNG (`outputFormat: 'png'`) supaya transparansi tidak berubah menjadi kotak putih.
- `ImageUpload` mendapat opsi `objectFit="contain"` tanpa mengubah perilaku upload gambar lain.
- Latar homepage diselaraskan menjadi hijau sangat muda dan menu utama dipindahkan sebelum `MealTimeReminder` agar elemen navigasi utama terlihat lebih cepat.
- Pengaturan lama tetap dibaca dari key dan path Supabase yang sama. Admin perlu mengganti aset lama dengan ikon baru; tidak ada migrasi database yang diperlukan.

## Validasi

- `pnpm exec eslint` pada 7 file yang berubah: lulus.
- `pnpm test -- src/lib/homeServiceCards.test.ts src/lib/mobileCommerceResponsive.test.ts`: lulus, 8 test.
- `pnpm build`: lulus, termasuk build Workbox service worker.
- Inspeksi browser Sandbox pada viewport mobile: menu Makanan & Minuman, Ojek, dan Belanja tampil setelah header dan sebelum pengingat/promo.
- `pnpm test` penuh: 202 file lulus, 3 test gagal pada `MealTimeReminder` yang tidak tersentuh perubahan ini; dua kegagalan berasal dari ketidakstabilan/copy accessibility yang sudah ada dan satu kontrak responsive sempat menuntut daftar srcset lama, lalu sudah dipulihkan dan test terkait lulus.
