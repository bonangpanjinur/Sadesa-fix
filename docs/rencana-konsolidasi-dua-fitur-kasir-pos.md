# Rencana Perbaikan dan Konsolidasi Dua Fitur Kasir POS

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Status:** Draft rencana implementasi  
**Tanggal:** 4 September 2026  
**Pemilik:** Tim Produk dan Engineering SaDesa

## 1. Ringkasan Eksekutif

Aplikasi saat ini memiliki dua entry point kasir yang berbeda: `/merchant/pos` dan `/pos/kasir`. Keduanya menyediakan keranjang, checkout, pembayaran, pengurangan stok, dan pencetakan struk, tetapi menggunakan model data, kontrol akses, dan alur transaksi yang berbeda. Halaman `/pos/transaksi` bukan kasir kedua; halaman tersebut adalah riwayat transaksi dan detail transaksi.

Rencana ini menetapkan **`/pos/kasir` sebagai kasir POS utama** karena halaman tersebut sudah menggunakan arsitektur POS SaaS dengan tenant, outlet, role kasir, atomic sale, offline sync, barcode scanner, loyalty, promosi, voucher, dan integrasi printer. Halaman `/merchant/pos` akan dipensiunkan secara bertahap melalui redirect kompatibilitas, bukan langsung dihapus, untuk mencegah kerusakan bookmark dan kehilangan akses pengguna.

> **Prinsip utama:** satu proses checkout, satu sumber kebenaran transaksi, satu sumber kebenaran stok, dan satu model akses POS.

## 2. Kondisi Saat Ini

| Area | Implementasi lama | Implementasi utama yang dituju |
|---|---|---|
| Entry point | `/merchant/pos` | `/pos/kasir` |
| Halaman | `src/pages/merchant/MerchantPOSPage.tsx` | `src/pages/pos/POSKasirPage.tsx` |
| Layout | `MerchantLayout` | `POSLayout` dan `POSSidebar` |
| Produk | `products` | `pos_products` |
| Transaksi | `orders`, `order_items`, `pos_transactions` | `pos_sales`, `pos_sale_items` |
| Identitas usaha | `merchants` | `pos_tenants` |
| Lokasi operasi | Tidak mendukung outlet POS secara eksplisit | `pos_outlets` dengan outlet aktif |
| Akses | Protected route untuk user merchant | `POSAccessRoute` dan role POS |
| Pembayaran | Tunai, QRIS, transfer | Alur pembayaran POS dengan validasi dan dukungan split payment |
| Offline | Tidak tersedia sebagai alur utama | `usePOSOfflineSync` |
| Promosi dan loyalty | Tidak menjadi bagian utama checkout | Terintegrasi pada keranjang dan pricing POS |
| Riwayat | Terikat pada data lama | `/pos/transaksi` membaca `pos_sales` |

Route lama masih terdaftar di `src/App.tsx`, sedangkan menu **Kasir POS** masih tersedia pada `src/components/merchant/MerchantSidebar.tsx`. Route modern `/pos/kasir` dan riwayat `/pos/transaksi` berada di kelompok route POS SaaS. [1] [2] [3]

## 3. Tujuan Perbaikan

Perbaikan harus mencapai tujuan berikut:

1. Menjadikan `/pos/kasir` sebagai satu-satunya alur checkout aktif.
2. Mempertahankan kompatibilitas URL lama melalui redirect sementara.
3. Menyatukan transaksi baru ke `pos_sales` dan `pos_sale_items`.
4. Menentukan sumber kebenaran stok dan memastikan stok marketplace tidak tertinggal.
5. Memetakan merchant lama ke `pos_tenants`, `pos_outlets`, pengguna POS, produk POS, dan sesi kas.
6. Menyediakan jalur migrasi atau rekonsiliasi untuk data `pos_transactions` lama.
7. Menghapus ambiguitas menu dan dokumentasi sehingga pengguna hanya melihat satu menu **Kasir**.
8. Menjamin bahwa perubahan tidak menggandakan transaksi, mengurangi stok dua kali, atau menghilangkan histori penjualan.

## 4. Keputusan Arsitektur yang Diusulkan

### 4.1 Kasir utama

`/pos/kasir` ditetapkan sebagai implementasi kanonis. Semua transaksi kasir baru wajib menggunakan `processAtomicPOSSale` atau jalur transaksi POS resmi yang setara. Checkout tidak boleh lagi membuat `orders` dan `pos_transactions` secara terpisah dari browser untuk transaksi kasir baru.

### 4.2 Route kompatibilitas

Route `/merchant/pos` dipertahankan sementara sebagai redirect ke `/pos/kasir`. Redirect ini diperlukan untuk bookmark lama, dokumentasi lama, dan link eksternal. Setelah masa transisi selesai dan telemetry menunjukkan tidak ada ketergantungan aktif, halaman lama dapat dihapus.

Contoh target perubahan:

```tsx
<Route path="/merchant/pos" element={<Navigate to="/pos/kasir" replace />} />
```

Redirect harus tetap berada di balik autentikasi dan tidak boleh memberikan akses POS kepada user yang tidak lolos pemeriksaan `POSAccessRoute`.

### 4.3 Menu

Link **Kasir POS** pada `MerchantSidebar` diubah menjadi **Kasir** yang mengarah ke `/pos/kasir`, atau dihapus apabila navigasi merchant tidak lagi menjadi tempat masuk POS. Pada `POSSidebar`, label **Kasir (POS)** disederhanakan menjadi **Kasir**. Link **Transaksi** tetap dipertahankan sebagai riwayat transaksi, tetapi diberi deskripsi yang jelas bila diperlukan.

## 5. Tahapan Implementasi

### Fase 0 — Baseline dan pembekuan perubahan

Sebelum migrasi dimulai, tim harus mencatat jumlah merchant aktif, jumlah tenant POS, jumlah outlet, jumlah produk aktif, jumlah `pos_transactions`, jumlah `pos_sales`, dan nilai stok pada kedua sistem. Selama periode migrasi, perubahan struktur checkout lama harus dibekukan agar hasil rekonsiliasi tidak berubah di tengah proses.

**Output fase:** snapshot database, daftar merchant terdampak, dan laporan perbedaan data.

### Fase 1 — Validasi kesiapan POS modern

Untuk setiap merchant aktif, validasi keberadaan dan konsistensi objek berikut:

| Objek | Pemeriksaan |
|---|---|
| `pos_tenants` | Satu tenant aktif yang terhubung ke merchant atau pemilik yang benar |
| `pos_outlets` | Minimal satu outlet aktif |
| `pos_users` | Pemilik atau kasir memiliki membership aktif |
| `pos_products` | Produk aktif memiliki tenant dan outlet/stock yang sesuai |
| `pos_stock` | Stok tersedia dan tidak bernilai negatif tanpa alasan audit |
| `pos_categories` | Kategori produk dapat ditampilkan pada kasir |
| Sesi kas | Kasir dapat membuka atau melanjutkan sesi sesuai aturan POS |
| Hak akses | User merchant dapat melewati `POSAccessRoute` jika memang berhak menggunakan POS |

Merchant yang gagal validasi tidak boleh dipaksa masuk ke checkout modern tanpa perbaikan mapping. Mereka harus masuk ke halaman setup atau daftar pengecualian untuk ditangani admin.

### Fase 2 — Konsolidasi master data

Buat proses idempotent untuk memetakan merchant lama ke tenant dan outlet POS. Proses ini harus menggunakan identifier yang stabil, mencatat mapping lama-baru, dan tidak membuat tenant duplikat ketika dijalankan ulang.

Produk lama pada `products` perlu dipetakan ke `pos_products`. Setiap mapping harus menyimpan referensi sumber, status, dan waktu sinkronisasi. Stok tidak boleh langsung disalin berulang kali tanpa aturan rekonsiliasi karena hal tersebut dapat menggandakan atau menghapus perubahan stok yang terjadi setelah snapshot.

**Aturan rekomendasi:**

- Produk aktif yang hanya ada di marketplace dibuat sebagai produk POS dengan status perlu ditinjau.
- Produk yang sudah memiliki mapping POS diperbarui secara idempotent.
- Perbedaan harga, SKU, kategori, dan stok dicatat sebagai exception.
- Setiap perubahan stok selama cutover harus memiliki audit trail.

### Fase 3 — Migrasi dan rekonsiliasi histori transaksi

`pos_transactions` dan `pos_sales` tidak boleh dianggap identik tanpa pemeriksaan skema. Data lama perlu diklasifikasikan sebagai berikut:

| Kategori data | Perlakuan |
|---|---|
| Transaksi lama yang belum ada di `pos_sales` | Migrasikan atau tampilkan melalui tabel histori legacy yang terpisah, sesuai keputusan audit finansial |
| Transaksi yang sudah memiliki pasangan | Tandai dengan mapping idempotent dan jangan duplikasi |
| Transaksi dengan status atau total tidak valid | Masukkan ke exception queue untuk review manual |
| Transaksi tanpa merchant/outlet yang dapat dipetakan | Jangan migrasikan otomatis; simpan sebagai data exception |
| Transaksi yang sudah tercermin pada `orders` | Hindari pembuatan order baru; simpan referensi sumber |

Jika migrasi fisik ke `pos_sales` berisiko mengubah laporan atau trigger, gunakan pendekatan **unified reporting view** terlebih dahulu. View tersebut dapat menggabungkan data modern dan legacy untuk kebutuhan histori, sementara transaksi baru tetap hanya masuk ke `pos_sales`.

### Fase 4 — Cutover checkout

Setelah tenant, outlet, produk, stok, dan akses tervalidasi, ubah navigasi dan route lama. Checkout modern harus menjadi satu-satunya alur aktif.

Checklist cutover:

1. `/merchant/pos` melakukan redirect ke `/pos/kasir`.
2. `MerchantSidebar` tidak lagi menampilkan halaman kasir lama.
3. Semua tombol checkout baru memanggil alur POS modern.
4. Nomor transaksi dan idempotency key berasal dari domain POS modern.
5. Pengurangan stok dilakukan satu kali dan dicatat pada transaksi POS.
6. Pembayaran, kembalian, split payment, pajak, diskon, voucher, dan loyalty mengikuti aturan POS modern.
7. Receipt dan reprint membaca format `pos_sales`.
8. Offline queue hanya memproses transaksi yang belum berhasil diselesaikan.

### Fase 5 — Masa observasi

Selama minimal satu siklus operasional penuh, pantau error checkout, transaksi duplikat, mismatch stok, transaksi offline yang gagal sinkron, kegagalan cetak, dan akses user yang ditolak secara tidak semestinya.

Gunakan feature flag atau allowlist merchant untuk melakukan rollout bertahap. Jangan menghapus halaman legacy sebelum metrik cutover stabil dan semua exception kritis ditutup.

### Fase 6 — Pensiun implementasi lama

Setelah masa observasi selesai:

- Hapus import `MerchantPOSPage` dari `src/App.tsx`.
- Hapus route `/merchant/pos` atau pertahankan redirect permanen bila diperlukan.
- Hapus `src/pages/merchant/MerchantPOSPage.tsx` setelah tidak ada referensi aktif.
- Hapus `src/components/merchant/POSInvoice.tsx` bila tidak dipakai halaman lain.
- Hapus utilitas khusus legacy yang tidak lagi digunakan.
- Pertahankan migration/reporting compatibility yang masih dibutuhkan untuk histori.
- Perbarui dokumentasi onboarding dan bantuan pengguna.

## 6. Perubahan File yang Direncanakan

| File/area | Perubahan |
|---|---|
| `src/App.tsx` | Ubah `/merchant/pos` menjadi redirect kompatibilitas; pertahankan `/pos/kasir` dan `/pos/transaksi`. |
| `src/components/merchant/MerchantSidebar.tsx` | Hapus atau arahkan ulang menu kasir lama ke `/pos/kasir`. |
| `src/components/pos/POSSidebar.tsx` | Ubah label menjadi **Kasir** dan pastikan link aktif konsisten. |
| `src/pages/pos/POSKasirPage.tsx` | Pertahankan sebagai checkout kanonis; tutup gap yang ditemukan dalam pengujian. |
| `src/pages/pos/POSTransaksiPage.tsx` | Jadikan histori modern; tambahkan sumber legacy bila unified reporting diperlukan. |
| `src/pages/merchant/MerchantPOSPage.tsx` | Jadikan deprecated selama transisi, lalu hapus setelah cutover. |
| `src/components/merchant/POSInvoice.tsx` | Hapus setelah seluruh pencetakan memakai receipt domain POS modern. |
| `src/lib/posCheckout.ts` | Tetapkan sebagai jalur transaksi baru dan idempotent. |
| `src/lib/posOfflineDB.ts` dan `src/hooks/usePOSOfflineSync.ts` | Validasi retry, deduplikasi, dan rekonsiliasi transaksi offline. |
| `supabase/bootstrap/` | Tambahkan migration idempotent hanya jika mapping tenant, produk, stok, atau histori membutuhkan schema/data migration. |
| `docs/` | Perbarui runbook, role matrix, dan dokumentasi pengguna setelah cutover. |

## 7. Keamanan dan Integritas Data

Konsolidasi harus mempertahankan kontrol pada level database. Redirect route tidak boleh menjadi pengganti RLS. Semua RPC transaksi harus memvalidasi tenant, outlet, kasir, total, item, stok, dan idempotency key di server/database.

Halaman lama saat ini melakukan beberapa operasi berurutan dari browser, termasuk pengurangan kuota, insert order, insert item, insert transaksi POS, dan update stok. Pola tersebut berisiko meninggalkan data setengah jadi ketika salah satu operasi gagal. Karena itu, transaksi baru wajib menggunakan alur atomic POS modern dan tidak boleh mempertahankan checkout legacy sebagai fallback diam-diam.

Aturan keamanan minimum:

- Jangan menggunakan service-role key di browser.
- Terapkan RLS berdasarkan tenant, outlet, user, dan role POS.
- Pastikan void/refund memiliki permission dan audit trail.
- Jangan menganggap `orders` dan `pos_sales` sebagai dua transaksi terpisah untuk satu checkout.
- Gunakan idempotency key untuk mencegah retry offline membuat transaksi ganda.
- Catat setiap migrasi dan koreksi stok.

## 8. Strategi Pengujian

### Pengujian otomatis

Tambahkan atau perbarui pengujian untuk memastikan:

| Skenario | Hasil yang diharapkan |
|---|---|
| Akses `/merchant/pos` | Redirect ke `/pos/kasir` tanpa membuat checkout legacy |
| User merchant tanpa tenant POS | Masuk ke setup/error state yang jelas |
| User kasir dengan satu outlet | Outlet aktif dipilih otomatis |
| User kasir dengan banyak outlet | Hanya outlet yang diizinkan yang tersedia |
| Checkout tunai | Total, bayar, dan kembalian valid |
| Checkout split payment | Jumlah metode pembayaran sama dengan total |
| Retry request yang sama | Tidak membuat transaksi duplikat |
| Stok tidak mencukupi | Transaksi gagal secara atomik tanpa perubahan parsial |
| Offline sale | Tersimpan di queue dan tersinkron satu kali |
| Legacy history | Transaksi lama tidak hilang dari laporan |
| Reprint | Membaca transaksi dari sumber kanonis |
| Role auditor/finance | Hanya mengakses halaman dan operasi yang diizinkan |

### Pengujian manual/UAT

UAT harus melibatkan minimal satu merchant satu outlet, satu merchant multi-outlet, satu kasir non-owner, satu transaksi offline, satu retur/void, satu transaksi dengan voucher, dan satu transaksi dengan cetak struk. Hasil UAT harus dicatat bersama screenshot atau nomor transaksi uji.

### Quality gates

Sebelum deployment, jalankan:

```sh
pnpm exec tsc --noEmit
pnpm run test -- --run
pnpm build
git diff --check
```

Error TypeScript yang sudah ada pada test POS receipt harus dibereskan atau diberi tiket terpisah sebelum gate tipe dinyatakan hijau. Error tersebut tidak boleh disamarkan sebagai bagian dari migrasi.

## 9. Observability dan Rollback

Tambahkan telemetry untuk route lama, redirect, checkout source, transaction source, tenant, outlet, dan hasil sinkronisasi. Setiap transaksi sebaiknya dapat dilacak dari request key ke `pos_sales`, item, perubahan stok, pembayaran, dan receipt job.

Rollback tidak boleh mengaktifkan kembali dua checkout secara bersamaan. Bila cutover bermasalah, rollback harus dilakukan dengan salah satu dari dua cara berikut:

1. Hentikan feature flag POS modern untuk merchant yang terdampak dan arahkan ke halaman setup, atau
2. Pulihkan versi aplikasi sebelumnya hanya setelah memastikan tidak ada transaksi modern yang akan hilang atau diproses ulang.

Jangan menghidupkan kembali `/merchant/pos` untuk membuat transaksi baru setelah `pos_sales` menjadi sumber kebenaran, karena hal tersebut akan mengembalikan masalah data terpisah.

## 10. Kriteria Selesai

Konsolidasi dianggap selesai apabila seluruh kondisi berikut terpenuhi:

- Pengguna hanya melihat satu menu **Kasir**.
- `/merchant/pos` tidak lagi menjalankan checkout legacy.
- Semua transaksi baru tersimpan pada `pos_sales` dan `pos_sale_items`.
- Tidak ada transaksi baru yang menulis ke `pos_transactions`.
- Stok POS dan stok marketplace memiliki aturan sinkronisasi yang terdokumentasi.
- Histori transaksi lama tetap dapat ditelusuri.
- Tidak ada mismatch kritis pada total transaksi atau stok selama masa observasi.
- Role POS dan RLS telah diuji untuk owner, manager, kasir, finance, dan auditor.
- Test suite, build produksi, dan UAT lulus.
- Implementasi legacy sudah dihapus atau diberi status archived dengan alasan yang terdokumentasi.

## 11. Urutan Prioritas

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Redirect `/merchant/pos` dan hentikan checkout legacy setelah kesiapan POS tervalidasi | Mencegah transaksi baru masuk ke dua sumber data |
| P0 | Validasi mapping tenant, outlet, produk, dan stok | Mencegah user masuk ke POS modern dengan data tidak lengkap |
| P0 | Pastikan idempotency dan atomic checkout | Mencegah transaksi ganda dan data parsial |
| P1 | Unified reporting untuk histori legacy dan modern | Menjaga kontinuitas laporan selama migrasi |
| P1 | Konsolidasi menu, label, dan dokumentasi | Menghilangkan kebingungan pengguna |
| P1 | Migrasi atau arsip `pos_transactions` | Menyederhanakan operasi dan audit |
| P2 | Hapus file legacy dan komponen invoice lama | Mengurangi beban pemeliharaan setelah stabil |

## 12. Referensi Repository

[1]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/App.tsx "SaDesa App routes"
[2]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/merchant/MerchantPOSPage.tsx "Legacy merchant POS page"
[3]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/pos/POSKasirPage.tsx "Modern POS cashier page"
[4]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/pages/pos/POSTransaksiPage.tsx "Modern POS transaction history"
[5]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/components/merchant/MerchantSidebar.tsx "Merchant navigation"
[6]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/components/pos/POSSidebar.tsx "POS navigation"
[7]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/lib/posCheckout.ts "Atomic POS checkout helper"
[8]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/src/contexts/POSContext.tsx "POS tenant and outlet context"

## 13. Keputusan yang Perlu Disetujui

Sebelum implementasi, pemilik produk perlu menyetujui tiga hal: pertama, `/pos/kasir` menjadi satu-satunya checkout resmi; kedua, histori `pos_transactions` akan dimigrasikan ke `pos_sales` atau disajikan melalui unified reporting view; dan ketiga, `products.stock` atau `pos_stock` yang menjadi sumber kebenaran akhir untuk stok operasional. Tanpa keputusan ini, implementasi teknis dapat memindahkan masalah duplikasi dari UI ke database dan laporan.

---

**Dokumen ini adalah rencana perbaikan, bukan perubahan kode.** Implementasi harus dilakukan bertahap dengan backup, staging, rekonsiliasi, dan persetujuan cutover.
