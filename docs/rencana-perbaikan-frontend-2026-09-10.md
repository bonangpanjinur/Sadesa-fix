# Rencana Perbaikan Frontend SaDesa

**Tanggal:** 10 September 2026  
**Dasar:** [Audit Frontend SaDesa 2026-09-10](./audit-frontend-2026-09-10.md)  
**Tujuan:** meningkatkan keamanan alur transaksi, konsistensi keranjang, kejelasan feedback UI, responsivitas mobile, dan aksesibilitas tanpa mengubah ruang lingkup fitur bisnis secara tidak perlu.

## Sasaran utama

Perbaikan akan dilakukan dari risiko transaksi tertinggi menuju polish antarmuka. **Checkout dan keranjang menjadi prioritas pertama** karena kesalahan pada kedua area tersebut dapat menyebabkan nominal tidak konsisten, order parsial, atau pengguna gagal menyelesaikan pembelian. Perbaikan visual dan aksesibilitas dilakukan setelah kontrak state dan transaksi stabil.

## Prinsip implementasi

1. **Satu sumber kebenaran untuk state belanja.** Selection, subtotal, ongkir, biaya layanan, dan total harus berasal dari model yang sama.
2. **Backend tetap menjadi otoritas transaksi.** Frontend boleh memberi estimasi, tetapi harga, stok, kuota, dan status pembayaran harus divalidasi ulang saat order dibuat.
3. **Tidak ada kegagalan yang disamarkan sebagai data kosong.** Error jaringan, data kosong, dan data belum dimuat harus memiliki state UI yang berbeda.
4. **Perubahan bertahap dan dapat diuji.** Setiap fase harus menghasilkan commit kecil dengan test yang relevan.
5. **Mobile-first.** Setiap fixed action bar harus memperhitungkan safe-area dan tidak menutupi konten atau navigasi.

## Prioritas dan fase pekerjaan

### Fase 0 — Persiapan kontrak dan baseline

**Tujuan:** membuat batas perilaku yang eksplisit sebelum mengubah implementasi.

| ID | Pekerjaan | File/area utama | Hasil selesai |
|---|---|---|---|
| F0-01 | Tetapkan dukungan checkout satu toko atau multi-toko. | `CheckoutPage.tsx`, kontrak order | Keputusan tertulis dan disepakati di codebase. |
| F0-02 | Buat model kalkulasi checkout murni tanpa side effect. | `src/lib/checkout/` | Subtotal, ongkir, voucher, COD fee, dan total dapat diuji terpisah. |
| F0-03 | Tambahkan fixture cart untuk satu toko, multi-toko, stok berubah, harga berubah, toko tutup, dan pembayaran online. | `src/lib/checkout/*.test.ts` | Skenario risiko utama memiliki test regression. |
| F0-04 | Dokumentasikan keputusan kompatibilitas data order yang sudah ada. | `docs/` | Status migration dan fallback jelas. |

**Keputusan yang disarankan:** untuk rilis perbaikan tercepat, checkout dibatasi ke satu merchant. Item merchant lain tetap tersimpan di keranjang dan diberi pesan bahwa checkout dilakukan per toko.

### Fase 1 — Stabilkan keranjang dan checkout

**Tujuan:** mencegah order parsial dan perbedaan nominal.

#### F1-01 — Batasi checkout satu merchant secara aman

- Tambahkan `merchantIds` terpilih dari `selectedItems`.
- Jika lebih dari satu merchant dipilih, tampilkan dialog atau inline warning.
- Sediakan aksi `Checkout toko ini` pada setiap grup merchant.
- Jangan menghapus item merchant lain dari cart.
- Pastikan tombol checkout disabled ketika pilihan merchant belum valid.

**Acceptance criteria:** pengguna tidak dapat membuat satu checkout yang menggabungkan merchant berbeda sebelum kontrak multi-toko tersedia.

#### F1-02 — Satukan perhitungan total

- Tambahkan selector `selectedSubtotal` pada `CartContext`.
- Ubah `FloatingCartButton` agar menggunakan total item terpilih atau label yang secara eksplisit menyatakan total seluruh cart.
- Gunakan formatter nominal yang sama pada floating cart, cart summary, dan checkout.
- Tampilkan subtotal, diskon, ongkir, biaya layanan, dan total secara konsisten.

**Acceptance criteria:** pada setiap state selection, semua komponen menampilkan nominal yang sama.

#### F1-03 — Perbaiki grouping dan selection per merchant

- Group cart berdasarkan `merchantId`, bukan nama toko.
- Tambahkan `selectMerchantItems(merchantId)` dan `clearMerchantItems(merchantId)`.
- Ubah checkbox grup menjadi tri-state: semua terpilih, sebagian terpilih, atau tidak terpilih.
- Ganti label `Pilih semua` sesuai cakupan aksinya.

**Acceptance criteria:** memilih semua item pada satu toko tidak mengubah pilihan toko lain.

#### F1-04 — Validasi harga dan stok dengan jalur pemulihan

- Tampilkan harga lokal dan harga server jika berbeda.
- Sediakan aksi `Perbarui harga`.
- Sediakan aksi `Sesuaikan ke stok tersedia`.
- Hapus atau nonaktifkan item hanya setelah pengguna memahami penyebabnya.
- Pertahankan validasi atomik di backend sebagai pemeriksaan terakhir.

**Acceptance criteria:** pengguna dapat memulihkan keranjang yang berubah tanpa harus menghapus seluruh cart.

#### F1-05 — Perbaiki flow Beli Langsung

- Jangan memakai selection cart biasa untuk flow Beli Langsung.
- Buat checkout intent sementara berisi satu product ID dan quantity, atau gunakan route checkout dengan state terisolasi.
- Setelah berhasil atau batal, jangan mengubah selection item lain.

**Acceptance criteria:** Beli Langsung hanya memproses produk yang dipilih dari halaman detail.

### Fase 2 — Perbaiki checkout dan pembayaran

**Tujuan:** memastikan konfigurasi toko dan pembayaran tidak tercampur.

#### F2-01 — Validasi merchant sebelum checkout

- Muat jam operasional dan status setiap merchant terpilih.
- Tampilkan status per grup merchant.
- Blokir hanya merchant yang tutup jika checkout multi-toko telah didukung, atau blokir seluruh submit jika kebijakan satu merchant digunakan.
- Berikan tombol `Hapus item toko tutup`.

#### F2-02 — Benahi sumber pengaturan pembayaran

- Jangan memakai `firstMerchantId` sebagai sumber global untuk multi-merchant.
- Untuk mode satu merchant, tampilkan bank, QRIS, COD, dan transfer dari merchant tersebut.
- Untuk mode multi-merchant, hitung opsi pembayaran per merchant atau buat satu payment session yang mendukung semua order.

#### F2-03 — Cegah order parsial untuk pembayaran online

- Jangan redirect ke invoice di tengah loop pembuatan order.
- Pilih satu strategi:
  - mode satu merchant: buat satu order dan satu invoice; atau
  - mode multi-merchant: buat payment session terpusat dengan relasi ke semua order.
- Jika salah satu insert gagal, gunakan transaksi backend atau mekanisme kompensasi yang membatalkan order yang sudah dibuat.

**Acceptance criteria:** tidak ada checkout sukses sebagian tanpa status yang terlihat oleh pengguna.

#### F2-04 — Sediakan state persiapan checkout

- Bedakan `loading konfigurasi`, `error konfigurasi`, dan `siap submit`.
- Tampilkan skeleton untuk ongkir, metode pembayaran, dan ringkasan.
- Jangan menampilkan opsi pembayaran yang belum dikonfirmasi oleh server.
- Disable tombol submit sampai data wajib tersedia.

### Fase 3 — Discovery, katalog, dan detail produk

**Tujuan:** membuat fitur pencarian dan filter sesuai perilaku yang ditampilkan.

#### F3-01 — Implementasikan filter rating

- Tentukan sumber rating: merchant, produk, atau destinasi.
- Terapkan `minRating` pada query/filter data.
- Jika rating tidak tersedia untuk tipe konten tertentu, sembunyikan opsi tersebut.
- Tambahkan test bahwa perubahan filter mengubah hasil.

#### F3-02 — Implementasikan pagination server-side

- Ganti `.limit(200)` dengan pagination cursor atau page size 20–40.
- Gunakan `useInfiniteQuery` pada Explore.
- Expose `hasMore` dari API.
- Tampilkan error dan retry pada setiap feed.

#### F3-03 — Pisahkan error dan empty state

Terapkan pola yang sama pada Home, Products, Explore, Product Detail, Cart, Account, dan Orders:

| State | Tampilan |
|---|---|
| Loading | Skeleton sesuai struktur konten. |
| Empty | Pesan bahwa data memang belum tersedia. |
| Error | Penjelasan singkat, detail opsional, dan tombol `Coba lagi`. |
| Partial data | Konten yang berhasil tetap tampil dan bagian gagal diberi retry lokal. |

#### F3-04 — Perbaiki product card

- Hindari tombol interaktif bersarang di dalam `Link`.
- Jadikan gambar/nama sebagai link terpisah.
- Pertahankan tombol wishlist dan tambah cart sebagai sibling.
- Pastikan focus ring terlihat dan label aksesibel tersedia.

#### F3-05 — Perbaiki Product Detail

- Bedakan produk tidak ditemukan dari error jaringan.
- Tambahkan tombol retry.
- Batasi quantity berdasarkan stok server terbaru.
- Tampilkan warning saat detail sudah stale.

### Fase 4 — Navigasi mobile dan konsistensi visual

**Tujuan:** menyatukan aturan fixed element dan memperbaiki usability pada layar kecil.

#### F4-01 — Satukan token fixed bar

Buat CSS variable bersama untuk:

- tinggi bottom navigation;
- tinggi floating cart;
- tinggi sticky checkout summary;
- safe-area bottom;
- padding konten bawah.

Gunakan variable tersebut pada `BottomNav`, `FloatingCartButton`, `CartPage`, `ProductDetail`, dan `CheckoutPage`.

#### F4-02 — Audit breakpoint 320, 375, 424, dan 480 px

Periksa bahwa:

- header tidak overflow;
- search, filter, dan sort tetap dapat digunakan;
- CTA tidak menutupi input;
- label kategori tidak terpotong tanpa tooltip atau line clamp yang tepat;
- dialog dan drawer tidak keluar layar.

#### F4-03 — Tambahkan feedback aksi

- Add-to-cart menampilkan jumlah yang ditambahkan dan CTA menuju cart.
- Quantity update menampilkan disabled state yang jelas saat stok maksimum.
- Remove item memiliki undo singkat bila memungkinkan.
- Checkout menampilkan progress dan mencegah double submit.

### Fase 5 — Aksesibilitas dan quality gate

**Tujuan:** mengurangi regresi dan meningkatkan penggunaan keyboard/screen reader.

- Audit nama, role, dan value untuk tombol icon, checkbox, drawer, dialog, dan tab.
- Pastikan semua tombol memiliki focus state.
- Pastikan kontras status buka/tutup, warning stok, dan error memenuhi standar yang ditargetkan.
- Tambahkan test komponen CartPage untuk selection, quantity, stock warning, dan checkout guard.
- Tambahkan test CheckoutPage untuk satu merchant, multi-merchant, closed merchant, price change, online payment, dan partial failure.
- Jalankan lint, build, dan test sebagai quality gate sebelum push.

## Urutan commit yang disarankan

| Commit | Isi |
|---|---|
| `test: add checkout and cart regression fixtures` | Fixture dan test sebelum perubahan behavior. |
| `fix: normalize cart merchant grouping and selection` | Group berdasarkan ID dan selection per merchant. |
| `fix: align cart totals with selected items` | Satu sumber total untuk floating cart dan cart page. |
| `fix: isolate buy now checkout intent` | Flow Beli Langsung tidak mencampur selection cart. |
| `fix: guard checkout against multi-merchant orders` | Guard satu merchant atau kontrak multi-merchant. |
| `fix: separate catalog error and empty states` | Error state dan retry. |
| `fix: implement server pagination for discovery` | Pagination dan infinite query. |
| `fix: align mobile fixed actions with safe area` | Token fixed bar dan responsivitas. |
| `test: enforce frontend quality gate` | Test, lint, build, dan dokumentasi final. |

## Definition of Done

Rencana ini dianggap terlaksana apabila seluruh kondisi berikut terpenuhi:

1. Checkout tidak dapat membuat order parsial.
2. Total floating cart, cart page, dan checkout konsisten untuk selection yang sama.
3. Cart tidak mencampur merchant berbeda karena nama yang sama.
4. Tombol pilih semua bekerja sesuai cakupan merchant yang terlihat.
5. Perubahan stok dan harga memiliki jalur pemulihan.
6. Beli Langsung tidak membawa item lain secara tidak sengaja.
7. Error API memiliki state dan retry yang jelas.
8. Filter yang tampil benar-benar memengaruhi hasil.
9. Katalog tidak terhenti pada 200 produk.
10. Fixed bar aman pada viewport mobile dan safe-area.
11. Test, lint, dan build lulus sebelum deploy.

## File yang diperkirakan terdampak

- `src/contexts/CartContext.tsx`
- `src/pages/CartPage.tsx`
- `src/pages/CheckoutPage.tsx`
- `src/pages/ProductDetail.tsx`
- `src/pages/ProductsPage.tsx`
- `src/pages/ExplorePage.tsx`
- `src/components/ProductCard.tsx`
- `src/components/layout/FloatingCartButton.tsx`
- `src/components/layout/BottomNav.tsx`
- `src/lib/api.ts`
- `src/lib/checkout/` — direktori baru bila kalkulasi dipisahkan
- `src/hooks/` — bila query pagination atau selection dipisahkan
- `src/index.css`
- `src/**/*.test.ts` dan `src/**/*.test.tsx`

## Referensi

[1]: ./audit-frontend-2026-09-10.md "Audit Frontend SaDesa 2026-09-10"
[2]: https://tanstack.com/query/latest/docs/framework/react/guides/infinite-queries "TanStack Query Infinite Queries"
[3]: https://www.w3.org/WAI/WCAG22/Understanding/name-role-value.html "WCAG 2.2 Name, Role, Value"
[4]: https://developer.mozilla.org/en-US/docs/Web/CSS/env "MDN CSS env() function"
