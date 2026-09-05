# Rencana Perbaikan dan Konsolidasi Dua Fitur Kasir POS

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Status:** Implementasi cutover kanonis dan hardening migration diterapkan; quality gate lokal lulus, sedangkan deployment database target, observability production, dan UAT tetap tertunda karena environment target belum tersedia
**Tanggal:** 4 September 2026  
**Pemilik:** Tim Produk dan Engineering SaDesa
**Audit status:** 5 September 2026

### Legenda status

- **✅ SELESAI** — sudah diterapkan di kode dan/atau sudah diverifikasi dengan test/build.
- **🟡 SEBAGIAN** — fondasi sudah ada, tetapi masih memerlukan migrasi database, konfigurasi, observasi, atau verifikasi environment.
- **⬜ BELUM** — belum diterapkan atau belum ada bukti pelaksanaan.

### Ringkasan status saat ini

| Area | Status | Catatan |
|---|---|---|
| Konsolidasi route ke Merchant | **✅ SELESAI** | Route kanonik berada di `/merchant/pos/*`; `/pos/*` dan `/merchant/pos` hanya redirect kompatibilitas terukur ke kasir kanonis. |
| Kasir satu alur | **✅ SELESAI** | Checkout memakai `POSKasirPage` dan `processAtomicPOSSale`. |
| Produk Merchant sebagai katalog utama | **🟡 SEBAGIAN** | Projection POS, mapping idempotent, manifest deployment, dan migration-history file sudah tersedia; SQL belum diverifikasi diterapkan di environment target. |
| Stok per outlet | **🟡 SEBAGIAN** | Backfill row `pos_stock` per outlet aktif sudah ditambahkan secara idempotent dengan kuantitas existing tidak ditimpa; deployment dan UAT masih belum selesai. |
| Test dan build | **✅ SELESAI** | 31 file test lulus, 86 test lulus, 20 dilewati; build berhasil. |
| UAT, observability, rekonsiliasi production | **🟡 SEBAGIAN / TERBLOKIR ENVIRONMENT** | Telemetry checkout kini membawa source, tenant, outlet, kasir, request key prefix, dan status offline; quality gate lokal lulus, tetapi deployment, rekonsiliasi, telemetry production, dan UAT target belum dapat dieksekusi tanpa akses environment. |

## 1. Ringkasan Eksekutif

### Hasil audit repository — 5 September 2026

Quality gate lokal pada commit yang diaudit berhasil dijalankan setelah dependensi dipasang: `pnpm exec tsc --noEmit`, `pnpm run test -- --run`, `pnpm build`, dan `git diff --check` seluruhnya lulus. Tidak ada kredensial atau koneksi database Supabase target yang tersedia pada sesi ini, sehingga fase yang mensyaratkan deployment, query rekonsiliasi, observasi telemetry production, dan UAT tidak boleh ditandai selesai hanya berdasarkan verifikasi lokal.

| Item tertunda | Status eksekusi audit | Tindakan berikutnya |
|---|---|---|
| Deployment migrasi bootstrap/history | **TERTUNDA** | Jalankan runbook deployment pada staging, lalu verifikasi smoke test database. |
| Baseline dan rekonsiliasi target | **TERTUNDA** | Jalankan `pnpm run pos:baseline` dengan role read-only dan simpan report sebelum/sesudah migrasi. |
| Masa observasi checkout | **TERTUNDA** | Rollout allowlist merchant dan pantau event telemetry selama satu siklus operasional penuh. |
| UAT P0 dan non-P0 | **TERTUNDA** | Lengkapi `docs/pos-consolidation-uat-runbook.md` dengan bukti transaksi, screenshot, dan hasil tiap skenario. |



Pada awalnya terdapat dua entry point kasir: `/merchant/pos` dan `/pos/kasir`. Implementasi telah dikonsolidasikan sehingga **kasir berada di area Merchant** dengan route kanonik `/merchant/pos/kasir`. Route lama `/pos/*` tetap dipertahankan hanya sebagai redirect kompatibilitas.

Kasir Merchant menggunakan arsitektur POS SaaS dengan tenant, outlet, role kasir, atomic sale, offline sync, barcode scanner, loyalty, promosi, voucher, dan integrasi printer. Halaman `/merchant/pos/transaksi` adalah histori transaksi, bukan mesin checkout kedua.

> **Prinsip utama:** satu area Merchant, satu proses checkout, satu sumber kebenaran transaksi, stok operasional per outlet, dan satu model akses POS.

### Keputusan implementasi — **✅ SELESAI DI KODE / 🟡 MENUNGGU DEPLOYMENT**

Route kanonik saat ini adalah `/merchant/pos/kasir`. Seluruh transaksi baru menggunakan `process_pos_sale`/`processAtomicPOSSale`, tersimpan di `pos_sales` dan `pos_sale_items`, dengan `pos_stock` pada outlet aktif sebagai sumber stok operasional. Mode kiosk mengarah ke kasir yang sama.

Fitur kasir yang sudah tersedia meliputi barcode, varian POS, customer, promo, voucher, loyalty, split payment, pembayaran tunai/non-tunai, hold bill, printer/PDF/WhatsApp, offline queue, sinkronisasi idempotent, dan histori POS. Integrasi katalog produk Merchant melalui projection dan migrasi database sudah disiapkan, tetapi perlu dijalankan serta diverifikasi pada database target.

## 2. Kondisi Saat Ini

| Area | Status | Implementasi saat ini |
|---|---|---|
| Entry point | **✅** | `/merchant/pos` dan `/merchant/pos/kasir`; `/pos/*` hanya redirect kompatibilitas. |
| Halaman kasir | **✅** | `src/pages/pos/POSKasirPage.tsx` dipakai pada route Merchant kanonik. |

| Layout | **✅** | Kasir kanonis memakai navigasi `MerchantSidebar`; engine checkout tetap memakai konteks, akses, dan komponen POS modern. |

| Layout | **✅ DI KODE** | `POSKasirPage` memakai `POSLayout`, dan `POSLayout` kini mendelegasikan sidebar, header, notifikasi, responsive drawer, serta shell visual ke `MerchantLayout`; mode `fullWidth` menjaga area checkout tetap memenuhi viewport. |

| Produk | **🟡** | `products` Merchant menjadi sumber katalog; `pos_products` dipertahankan sebagai projection kompatibilitas. Migrasi belum diverifikasi di target. |
| Transaksi | **✅** | Transaksi baru memakai `pos_sales` dan `pos_sale_items` melalui atomic checkout. |
| Identitas usaha | **🟡** | `pos_tenants.merchant_id` dan backfill mapping sudah disiapkan; deployment migrasi belum diverifikasi. |
| Lokasi operasi | **✅** | `pos_outlets` dengan outlet aktif digunakan oleh kasir dan `pos_stock`. |
| Akses | **✅** | `POSAccessRoute` dan role POS tetap diterapkan. |
| Pembayaran | **✅** | Validasi pembayaran dan split payment tersedia serta diuji oleh test suite. |
| Offline | **✅** | `usePOSOfflineSync` dan outbox tersedia; UAT offline belum dilakukan. |
| Promosi dan loyalty | **✅** | Terintegrasi pada keranjang dan pricing POS. |
| Riwayat | **🟡** | Histori POS tersedia; rekonsiliasi histori legacy dan unified reporting production belum diverifikasi. |

Route lama dipertahankan hanya sebagai redirect kompatibilitas. Menu Merchant dan POS sekarang mengarah ke satu area Merchant, yaitu `/merchant/pos/kasir`; route `/pos/kasir` bukan lagi URL kanonik.

## 3. Tujuan Perbaikan

Perbaikan harus mencapai tujuan berikut:

1. **✅** Menjadikan `/merchant/pos/kasir` sebagai satu-satunya alur checkout aktif.
2. **✅** Mempertahankan kompatibilitas URL lama melalui redirect sementara.
3. **✅** Menyatukan transaksi baru ke `pos_sales` dan `pos_sale_items`.
4. **🟡** Menentukan sumber kebenaran stok per outlet; sinkronisasi marketplace belum diverifikasi end-to-end.
5. **🟡** Memetakan Merchant ke `pos_tenants`, `pos_outlets`, pengguna POS, dan projection produk; deployment mapping belum diverifikasi.
6. **🟡** Menyediakan fondasi unified history/mapping, tetapi rekonsiliasi data legacy belum dibuktikan di environment target.
7. **✅** Mengurangi ambiguitas menu dan mengarahkan entry Kasir ke area Merchant.
8. **🟡** Atomic checkout dan idempotency sudah ada; bukti UAT tidak menggandakan transaksi atau stok masih belum tersedia.

## 4. Keputusan Arsitektur yang Diusulkan

### 4.1 Kasir utama

`/merchant/pos/kasir` ditetapkan sebagai implementasi kanonis. **✅** Semua transaksi kasir baru menggunakan `processAtomicPOSSale` atau jalur transaksi POS resmi yang setara. Checkout tidak membuat `orders` dan `pos_transactions` secara terpisah dari browser untuk transaksi kasir baru.

### 4.2 Route kompatibilitas

Route `/pos/*` dipertahankan sementara sebagai redirect ke prefix kanonik `/merchant/pos/*`. Redirect ini diperlukan untuk bookmark lama, dokumentasi lama, dan link eksternal. Route `/merchant/pos` sendiri menjadi dashboard POS Merchant, sedangkan `/merchant/pos/kasir` menjadi checkout. Setelah masa observasi selesai dan telemetry menunjukkan tidak ada ketergantungan aktif, compatibility route dapat dipensiunkan.

Contoh target perubahan:

```tsx
<Route path="/pos/*" element={<LegacyPOSRedirect />} />
<Route path="/merchant/pos/kasir" element={<POSKasirPage />} />
```

Redirect harus tetap berada di balik autentikasi dan tidak boleh memberikan akses POS kepada user yang tidak lolos pemeriksaan `POSAccessRoute`.

### 4.3 Menu

**✅** Link **Kasir POS** pada `MerchantSidebar` sudah menjadi **Kasir** dan mengarah ke `/merchant/pos/kasir`. Pada `POSSidebar`, link internal juga memakai prefix `/merchant/pos/*`. Link **Transaksi** dipertahankan sebagai riwayat transaksi.

## 5. Tahapan Implementasi

### Fase 0 — Baseline dan pembekuan perubahan — **🟡 SEBAGIAN**

Sebelum migrasi dimulai, tim harus mencatat jumlah merchant aktif, jumlah tenant POS, jumlah outlet, jumlah produk aktif, jumlah `pos_transactions`, jumlah `pos_sales`, dan nilai stok pada kedua sistem. Selama periode migrasi, perubahan struktur checkout lama harus dibekukan agar hasil rekonsiliasi tidak berubah di tengah proses.

**Output fase:** snapshot database, daftar merchant terdampak, dan laporan perbedaan data. Script `pnpm run pos:baseline` kini menyediakan snapshot hitungan dan total yang dapat diulang; eksekusi pada database target dan pembekuan perubahan masih harus dilakukan oleh operator.

### Fase 1 — Validasi kesiapan POS modern — **🟡 SEBAGIAN**

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

### Fase 2 — Konsolidasi master data — **🟡 SEBAGIAN**

Buat proses idempotent untuk memetakan merchant lama ke tenant dan outlet POS. Proses ini harus menggunakan identifier yang stabil, mencatat mapping lama-baru, dan tidak membuat tenant duplikat ketika dijalankan ulang.

Produk lama pada `products` perlu dipetakan ke `pos_products`. Setiap mapping harus menyimpan referensi sumber, status, dan waktu sinkronisasi. Stok tidak boleh langsung disalin berulang kali tanpa aturan rekonsiliasi karena hal tersebut dapat menggandakan atau menghapus perubahan stok yang terjadi setelah snapshot.

**Aturan rekomendasi:**

- Produk aktif yang hanya ada di marketplace dibuat sebagai produk POS dengan status perlu ditinjau.
- Produk yang sudah memiliki mapping POS diperbarui secara idempotent.
- Perbedaan harga, SKU, kategori, dan stok dicatat sebagai exception.
- Setiap perubahan stok selama cutover harus memiliki audit trail.

### Fase 3 — Migrasi dan rekonsiliasi histori transaksi — **🟡 SEBAGIAN**

`pos_transactions` dan `pos_sales` tidak boleh dianggap identik tanpa pemeriksaan skema. Data lama perlu diklasifikasikan sebagai berikut:

| Kategori data | Perlakuan |
|---|---|
| Transaksi lama yang belum ada di `pos_sales` | Migrasikan atau tampilkan melalui tabel histori legacy yang terpisah, sesuai keputusan audit finansial |
| Transaksi yang sudah memiliki pasangan | Tandai dengan mapping idempotent dan jangan duplikasi |
| Transaksi dengan status atau total tidak valid | Masukkan ke exception queue untuk review manual |
| Transaksi tanpa merchant/outlet yang dapat dipetakan | Jangan migrasikan otomatis; simpan sebagai data exception |
| Transaksi yang sudah tercermin pada `orders` | Hindari pembuatan order baru; simpan referensi sumber |

Jika migrasi fisik ke `pos_sales` berisiko mengubah laporan atau trigger, gunakan pendekatan **unified reporting view** terlebih dahulu. View tersebut dapat menggabungkan data modern dan legacy untuk kebutuhan histori, sementara transaksi baru tetap hanya masuk ke `pos_sales`.

### Fase 4 — Cutover checkout — **✅ SELESAI DI KODE / 🟡 MENUNGGU VALIDASI ENVIRONMENT**

Perubahan lokal bertahap pada audit ini menyatukan shell `POSKasirPage` dan `POSLayout` dengan `MerchantLayout`, menghapus sidebar/header wrapper POS yang duplikat, menambahkan mode `fullWidth` untuk checkout, dan mempertahankan alur checkout, dialog, serta panel produk/keranjang. Typecheck, test suite, dan build tetap lulus setelah perubahan.

Setelah tenant, outlet, produk, stok, dan akses tervalidasi, ubah navigasi dan route lama. Checkout modern harus menjadi satu-satunya alur aktif.

Checklist cutover:

1. **✅** `/pos/*` melakukan redirect ke prefix `/merchant/pos/*`; `/merchant/pos/kasir` menjadi checkout kanonik.
2. **✅** `MerchantSidebar` tidak lagi menampilkan halaman kasir lama.
3. **✅** Tombol checkout baru memanggil alur POS modern.
4. **✅** Nomor transaksi dan idempotency key berasal dari domain POS modern.
5. **✅ di kode / 🟡 UAT belum** Pengurangan stok dilakukan satu kali melalui `pos_stock` outlet aktif.
6. **✅** Pembayaran, kembalian, split payment, pajak, diskon, voucher, dan loyalty mengikuti aturan POS modern.
7. **✅ di kode / 🟡 rekonsiliasi belum** Receipt dan reprint membaca format POS modern.
8. **✅ di kode / 🟡 UAT belum** Offline queue hanya memproses transaksi yang belum berhasil diselesaikan.

### Fase 5 — Masa observasi — **🟡 TERTUNDA ENVIRONMENT**

Selama minimal satu siklus operasional penuh, pantau error checkout, transaksi duplikat, mismatch stok, transaksi offline yang gagal sinkron, kegagalan cetak, dan akses user yang ditolak secara tidak semestinya. Implementasi telemetry dan checklist observasi sudah tersedia di kode/runbook; eksekusi observasi belum dapat dilakukan pada audit ini karena environment target dan sumber telemetry production tidak tersedia.

Gunakan feature flag atau allowlist merchant untuk melakukan rollout bertahap. Jangan menghapus halaman legacy sebelum metrik cutover stabil dan semua exception kritis ditutup.

### Fase 6 — Pensiun implementasi lama — **✅ SELESAI DI KODE / 🟡 DOKUMENTASI DAN OBSERVASI LANJUTAN**

Setelah masa observasi selesai:

- Hapus import `MerchantPOSPage` dari `src/App.tsx`.
- Hapus route `/merchant/pos` atau pertahankan redirect permanen bila diperlukan.
- Hapus `src/pages/merchant/MerchantPOSPage.tsx` setelah tidak ada referensi aktif.
- Hapus `src/components/merchant/POSInvoice.tsx` bila tidak dipakai halaman lain.
- Hapus utilitas khusus legacy yang tidak lagi digunakan.
- Pertahankan migration/reporting compatibility yang masih dibutuhkan untuk histori.
- Perbarui dokumentasi onboarding dan bantuan pengguna.

## 6. Perubahan File yang Direncanakan

| File/area | Status | Hasil aktual |
|---|---|---|
| `src/App.tsx` | **✅** | Route kanonik POS berada di `/merchant/pos/*`; `/pos/*` dan dashboard `/merchant/pos` menjadi redirect kompatibilitas, dengan telemetry route legacy. |
| `src/components/merchant/MerchantSidebar.tsx` | **✅** | Link Kasir diarahkan ke area Merchant. |
| `src/components/pos/POSSidebar.tsx` | **✅ KOMPATIBILITAS** | Link internal memakai prefix `/merchant/pos/*`; layout kanonik Merchant sekarang menggunakan `MerchantSidebar`. |
| `src/pages/pos/POSKasirPage.tsx` | **✅** | Dipakai sebagai checkout kanonik pada route Merchant dan menggunakan `POSLayout` yang terintegrasi dengan `MerchantLayout`. |
| `src/pages/pos/POSTransaksiPage.tsx` | **🟡** | Histori modern tersedia; rekonsiliasi histori legacy belum divalidasi production. |
| `src/pages/merchant/MerchantPOSPage.tsx` | **✅** | File legacy sudah tidak ada dan tidak memiliki referensi aktif di `src`. |
| `src/components/merchant/POSInvoice.tsx` | **✅** | File legacy sudah tidak ada dan tidak memiliki referensi aktif di `src`. |
| `src/lib/posCheckout.ts` | **✅** | Atomic checkout dan idempotency digunakan. |
| `src/lib/posOfflineDB.ts` dan `src/hooks/usePOSOfflineSync.ts` | **✅ DI KODE / 🟡 UAT BELUM** | Outbox, retry, dan sinkronisasi tersedia; belum diuji pada environment target. |
| `supabase/bootstrap/10_20260905000000_merchant_pos_product_catalog.sql` | **🟡** | Migrasi mapping Merchant–POS, projection produk, dan backfill row stok per outlet sudah dibuat; manifest serta smoke test kini memeriksa mapping tenant, projection produk, dan stok outlet, tetapi belum dijalankan pada database target. |
| `archive/supabase/migrations/20260905000000_merchant_pos_product_catalog.sql` | **🟡** | Representasi untuk environment yang memakai histori migration; jangan diterapkan bersamaan dengan bootstrap bundle pada database yang sama. Readiness tetap harus diverifikasi setelah deployment. |
| `scripts/audit-rls-static.py` | **✅ DI KODE / 🟡 TARGET** | Audit lokal kini mengenali `pos_sale_requests` dan `payment_invoice_requests` sebagai tabel server-only serta memvalidasi RLS, pencabutan akses `anon/authenticated`, dan grant `service_role`; hasil database target tetap belum diverifikasi. |
| `docs/` | **🟡** | Status implementasi, baseline report, readiness smoke test, dan [runbook UAT](pos-consolidation-uat-runbook.md) tersedia; quality gate lokal telah diverifikasi, sementara eksekusi deployment, observasi, rekonsiliasi, serta hasil UAT target masih tertunda karena akses environment belum tersedia. |

## 7. Keamanan dan Integritas Data — **🟡 SEBAGIAN**

Konsolidasi harus mempertahankan kontrol pada level database. Redirect route tidak boleh menjadi pengganti RLS. Semua RPC transaksi harus memvalidasi tenant, outlet, kasir, total, item, stok, dan idempotency key di server/database. Audit RLS lokal sekarang membedakan tabel server-only yang sengaja tidak memiliki policy authenticated dari tabel yang benar-benar belum memiliki perlindungan.

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
| Akses `/merchant/pos` | Redirect ke `/merchant/pos/kasir` tanpa membuat checkout legacy |
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

Quality gate saat audit:

| Gate | Status | Bukti |
|---|---|---|
| `pnpm exec tsc --noEmit` | **✅** | Typecheck berhasil setelah dependensi dipasang. |
| `pnpm run test -- --run` | **✅** | 31 file lulus; 86 test lulus; 20 dilewati. |
| `pnpm build` | **✅** | Build production berhasil. |
| `git diff --check` | **✅** | Tidak ada whitespace error pada perubahan yang diaudit. |

Typecheck terpisah berhasil pada verifikasi lanjutan; tidak ada error TypeScript yang menghalangi gate tipe.

## 9. Observability dan Rollback — **🟡 SEBAGIAN**

Telemetry checkout sudah mencatat checkout source, transaction source, tenant, outlet, kasir, request key prefix, status offline, duplicate result, error code, dan durasi. Redirect route legacy kini mencatat source path, target path, dan keberadaan query. Sinkronisasi end-to-end serta korelasi database ke item/stok/pembayaran/receipt masih memerlukan verifikasi environment target.

Rollback tidak boleh mengaktifkan kembali dua checkout secara bersamaan. Bila cutover bermasalah, rollback harus dilakukan dengan salah satu dari dua cara berikut:

1. Hentikan feature flag POS modern untuk merchant yang terdampak dan arahkan ke halaman setup, atau
2. Pulihkan versi aplikasi sebelumnya hanya setelah memastikan tidak ada transaksi modern yang akan hilang atau diproses ulang.

Jangan menghidupkan kembali `/merchant/pos` untuk membuat transaksi baru setelah `pos_sales` menjadi sumber kebenaran, karena hal tersebut akan mengembalikan masalah data terpisah.

## 10. Kriteria Selesai

Konsolidasi dianggap selesai apabila seluruh kondisi berikut terpenuhi:

- **✅** Pengguna diarahkan ke satu area/menu **Kasir**.
- **✅** `/merchant/pos` tidak menjalankan checkout legacy; `/pos/*` hanya compatibility redirect.
- **✅ di kode** Semua transaksi baru diarahkan ke `pos_sales` dan `pos_sale_items`.
- **🟡** Tidak ada transaksi baru yang menulis ke `pos_transactions` belum diverifikasi melalui telemetry/database target.
- **🟡** Stok POS per outlet sudah memiliki backfill idempotent yang membuat row nol hanya jika belum ada; migrasi database dan UAT belum diverifikasi diterapkan.
- **🟡** Histori transaksi lama sudah memiliki migration map dan unified reporting view; rekonsiliasi serta verifikasi end-to-end belum dijalankan pada target.
- **🟡 tertunda environment** Runbook UAT dan telemetry observasi tersedia; tidak ada mismatch kritis belum dapat dinyatakan sebelum observasi target dijalankan.
- **✅ di kode / 🟡 target** Role POS dan permission diuji oleh test suite; audit RLS lokal memvalidasi tabel server-only dan policy statis, tetapi pengujian RLS production dan UAT masih belum selesai.
- **✅ lokal / 🟡 UAT** Test suite dan build produksi lulus pada audit lokal; UAT target belum lulus.
- **✅** File implementasi legacy yang tercantum dalam rencana sudah tidak ada dan tidak memiliki referensi aktif di `src`.
- **✅ di kode / 🟡 validasi visual browser** `MerchantLayout` menjadi shell visual kanonik POS; validasi interaksi visual pada browser target tetap perlu dilakukan sebagai bagian UAT.

## 11. Urutan Prioritas

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Redirect `/merchant/pos` dan hentikan checkout legacy setelah kesiapan POS tervalidasi | Mencegah transaksi baru masuk ke dua sumber data |
| P0 | Validasi mapping tenant, outlet, produk, dan stok | Mencegah user masuk ke POS modern dengan data tidak lengkap; eksekusi target masih tertunda environment |
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
[9]: https://github.com/bonangpanjinur/Sadesa-fix/blob/main/supabase/bootstrap/10_20260905000000_merchant_pos_product_catalog.sql "Merchant product catalog and outlet stock integration"

## 13. Keputusan yang Sudah Ditetapkan

Keputusan yang sebelumnya menunggu persetujuan kini diterapkan sebagian besar pada kode: `/merchant/pos/kasir` menjadi checkout resmi; `/pos/*` hanya compatibility redirect; `pos_stock` pada outlet aktif menjadi sumber kebenaran stok POS; dan produk Merchant menjadi sumber katalog dengan projection kompatibilitas pada `pos_products`. Quality gate lokal telah lulus, shell visual POS kini memakai `MerchantLayout`, dan audit RLS lokal telah diperkuat untuk memvalidasi tabel server-only. Migrasi database produk/tenant tetap harus dijalankan melalui staging dan runbook deployment sebelum dianggap aktif di environment target. Rekonsiliasi histori legacy, observability, dan UAT tetap **TERTUNDA ENVIRONMENT**, bukan dianggap selesai berdasarkan test suite lokal.

---

**Dokumen ini menjadi acuan keputusan dan checklist cutover.** Perubahan kode utama dan hardening migration sudah diterapkan di repository dan ditandai statusnya di atas. Quality gate lokal telah lulus pada audit 5 September 2026. Deployment database, backup, rekonsiliasi, observability, dan UAT tetap harus dijalankan bertahap pada environment target. Connector Supabase pada sesi ini belum aktif dan variabel koneksi target tidak tersedia, sehingga verifikasi langsung terhadap target tidak dilakukan.
