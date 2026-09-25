# Analisis Kebutuhan dan Audit Fitur Merchant

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit yang diaudit:** `4bd6b32` (`main`, 25 September 2026)  
**Tanggal audit:** 25 September 2026  
**Ruang lingkup:** fitur merchant marketplace, order/fulfillment, katalog-stok, keuangan, promosi, komunikasi, POS, entitlement, dan kesiapan operasi.

## 1. Ringkasan eksekutif

SaDesa sudah memiliki **cakupan fitur merchant yang luas**. Merchant dapat mendaftar, mengelola toko dan produk, menerima order, menjalankan fulfillment, mengelola promosi, melihat analitik, mengajukan withdrawal/refund, berkomunikasi dengan pembeli, serta mengaktifkan POS dengan katalog, stok outlet, kasir, laporan, QR meja, dan mode offline.

Namun, **keluasan menu belum sama dengan kesiapan operasional**. Sebagian besar fondasi sudah tersedia di source code dan migration/bootstrap, tetapi audit repository berulang kali mencatat bahwa validasi staging, concurrency, recovery nyata, rekonsiliasi uang, perangkat, dan pilot merchant belum lengkap. Kesimpulan audit:

> **Status: siap masuk validasi staging dan pilot terbatas dengan guardrail; belum layak dinyatakan siap go-live penuh.**

Prioritas tertinggi bukan menambah halaman baru, melainkan memastikan merchant tidak mengalami:

1. checkout/order parsial atau pembayaran yang tidak dapat dipulihkan;
2. harga, voucher, promo, atau item order yang dapat dimanipulasi dari client;
3. stok marketplace dan POS yang berbeda;
4. status order yang berbeda antar layar merchant;
5. saldo, refund, withdrawal, dan laporan yang tidak dapat direkonsiliasi;
6. toko yang terlihat buka ketika sebenarnya tutup;
7. transaksi offline yang terduplikasi atau hilang;
8. fitur berbayar/POS yang mengunci marketplace saat entitlement berubah.

## 2. Profil kebutuhan merchant

### 2.1 Persona utama

| Persona | Kebutuhan inti | Bukti dukungan di aplikasi | Gap utama |
|---|---|---|---|
| Merchant marketplace-only | Toko publik, katalog, order, fulfillment, chat, refund, review, payout | Route `/merchant/*`, `MerchantProductsPage`, `MerchantOrdersPage`, `MerchantFulfillmentPage` | Harus dibuktikan end-to-end tanpa tenant/entitlement POS |
| Merchant retail | SKU/varian, stok, harga, order, ekspor, promo | Product detail, stock, price book, import/export, POS inventory | Rekonsiliasi lintas kanal dan concurrency belum tervalidasi staging |
| Merchant makanan/minuman | Modifier/topping, waktu siapkan, KDS, meja/QR, pickup/delivery | `ProductToppingManager`, `POSKDSPage`, `POSMenuQRPage`, `POSMejaPage` | Uji device/PWA/printer, QR revoke, dan order meja nyata masih terbuka |
| Merchant jasa terjadwal | Slot, durasi, kapasitas, booking, cancel/no-show, bukti selesai | Kontrak kategori dan service marketplace tersedia di source/docs | Kontrak booking, settlement, dispute, dan kapasitas belum menjadi gate pilot utama |
| Merchant sewa/wisata | Kalender aset, deposit, kondisi barang, peserta, no-show | Halaman booking wisata dan template kategori tersedia | Belum cukup evidence untuk double-booking, deposit, refund, dan settlement |
| Merchant multi-outlet | Outlet, user/kasir, stok per outlet, transfer, laporan per outlet | POS outlet, akses, gudang, transfer stok, laporan outlet | Limit/entitlement dan tenant/outlet isolation perlu runtime staging |
| Merchant yang beroperasi dengan internet buruk | POS offline, queue, retry, conflict center, receipt pending | `usePOSOfflineSync`, `POSOfflineConflictPage`, recovery contract/tests | Uji fisik perangkat, listrik mati, printer, konflik lintas kanal belum selesai |

### 2.2 Journey minimum merchant

1. Registrasi dan verifikasi merchant.
2. Melengkapi profil, lokasi, kategori, jam operasional, dan rekening/payout.
3. Membuat produk pertama dengan harga, foto, varian, stok, dan status aktif.
4. Membagikan toko/QR dan menerima order.
5. Mengonfirmasi, menyiapkan, mengirim/menyerahkan order.
6. Melihat status pembayaran, saldo, fee, refund, dan payout.
7. Menangani komplain, review, chat, dan masalah fulfillment.
8. Mengukur penjualan serta mengekspor data.
9. Jika memakai POS: membuat outlet, user, stok, kasir, shift, dan laporan.
10. Pulih dari kegagalan jaringan, invoice kedaluwarsa, konflik stok, atau perangkat restart.

## 3. Inventaris fitur merchant yang sudah ada

### 3.1 Marketplace merchant

| Domain | Fitur yang sudah tersedia |
|---|---|
| Identitas toko | Registrasi merchant, approval/verifikasi, status active/inactive, badge terverifikasi, slug publik, profil dan lokasi |
| Katalog | Produk, detail produk, kategori, multi-image/gallery, varian, topping/modifier, SKU/barcode, pre-order, grosir, bundle |
| Jam dan kategori | `MerchantOperatingHoursCard`, kontrak jam operasional, kontrak multi-kategori, relasi `merchant_categories` pada bundle terbaru |
| Order | Inbox order, filter/pencarian/tanggal, detail order, status transition, invoice, export penjualan, notifikasi realtime/suara |
| Fulfillment | Antar sendiri, kurir, pickup/delivery, tracking, assignment/offer kurir, fulfillment workspace |
| Komunikasi | Chat merchant-pembeli, notifikasi, template/fitur WhatsApp notification |
| Kepercayaan | Review merchant, balasan review, rating, refund request, dispute/komplain |
| Monetisasi penjualan | Withdrawal, merchant finance, fee/ledger terkait, subscription/kuota, promosi onboarding |
| Growth | Promo, voucher, flash sale, scheduled promo, iklan merchant, loyalty, visitor stats, analytics/insight |
| Operasional | Settings, import/export, stock page, dues, pajak, gallery, price book |

### 3.2 POS merchant

Route POS utama berada di bawah `/merchant/pos/*`, dengan redirect legacy dari `/pos/*` dan akses dilindungi `POSAccessRoute`.

| Kelompok | Fitur yang sudah tersedia |
|---|---|
| Kasir | Kasir, cart, held bills, barcode scanner, pembayaran, QR pay, receipt dan reprint |
| Katalog/stok | Produk, kategori, stok, gudang, bahan baku, resep, varian, supplier, pembelian, retur, transfer stok |
| Outlet/team | Outlet, pengguna, permission, akses, absensi, penggajian, jadwal |
| Penjualan restoran | Meja, menu QR, KDS, order meja, topping, status produksi |
| Finansial | Kas, hutang/piutang, akuntansi, cashflow, laba-rugi, laporan kasir/stok/outlet, target omzet |
| Growth/CRM | Loyalty, promosi, harga, analitik, analitik produk, integrasi |
| Reliability | Offline queue, durable checkpoint, retry/lease, conflict/dead-letter, recovery contract, device policy |
| Subscription | POS subscribe, paket, entitlement, trial/grace/suspended/cancelled, limit outlet/user/device pada bundle terbaru |

### 3.3 Fondasi backend dan security

- Supabase Auth, RLS, Storage, Realtime, dan Edge Functions.
- RPC untuk transition order, checkout atomic, refund, payment webhook, entitlement, reservation, settlement, dan laporan canonical.
- Bootstrap/migration terurut; repository mencatat 28 ordered bundles dan 213 migration pada audit terdahulu.
- Static RLS audit dan test contract tersedia.
- Xendit payment/invoice dan webhook idempotency sudah memiliki implementasi.
- Stock reservation/projection dan QR table-order scoped sudah memiliki kontrak backend.
- Audit trail dan workflow verifikasi merchant/admin/verifikator tersedia sebagian.

## 4. Hasil audit per area

| Area | Status | Penilaian |
|---|---|---|
| Profil, katalog, dan toko publik | **Sebagian siap** | UI dan schema luas, tetapi jam operasional/kategori harus dibuktikan konsisten di publik, search, checkout, dan admin |
| Inbox order merchant | **Sebagian siap** | `MerchantOrdersPage` kuat, tetapi masih ada surface kedua (`OrderStatusManager`) dengan implementasi/status berbeda |
| Fulfillment | **Sebagian siap** | RPC dan alur kurir tersedia; state canonical, freshness, recovery, dan E2E lintas aktor perlu ditutup |
| Checkout/payment | **Belum siap go-live** | Risiko multi-merchant, partial order, invoice recovery, dan authoritative pricing perlu staging proof |
| Harga/promo/voucher | **Belum cukup aman** | Audit sebelumnya menemukan ketergantungan pada input client dan konsumsi voucher yang perlu dikunci server-side |
| Stok | **Sebagian siap** | Contract reservation/projection bagus; concurrency, stale projection, mapping varian, dan rekonsiliasi nyata belum lulus |
| Refund/review/dispute | **Belum siap go-live** | Audit sebelumnya menemukan authorization, amount integrity, atomic settlement, evidence storage, dan review authenticity sebagai risiko tinggi |
| Payout/withdrawal/finance | **Sebagian siap** | Ledger/report canonical tersedia di repository; payout hold, settlement, adjustment, dan finance sign-off masih perlu evidence |
| POS online | **Siap validasi staging** | Modul lengkap dan memiliki test contract; runtime database, device, printer, dan shift-close belum cukup dibuktikan |
| POS offline | **Beta/internal** | Queue, lease, recovery, conflict center tersedia; belum boleh dijanjikan sebagai operasi produksi tanpa device pilot |
| Subscription/entitlement | **Sebagian siap** | Lifecycle POS dan pemisahan marketplace/POS sudah dirancang; penerapan migration dan runtime test staging terbuka |
| Notifikasi/background jobs | **Risiko P1** | Audit terdahulu mencatat job processing tanpa lease recovery, dead-letter yang dapat salah terbaca sukses, channel mismatch, dan pagination terbatas |
| Observability/support | **Belum lengkap** | Health dashboard dan SLA support ada; control tower dengan owner untuk queue, payment, reservation, payout, dispute belum lengkap |

## 5. Temuan prioritas

### P0 — Tutup sebelum marketplace dibuka luas

#### M-P0-01 — Checkout multi-merchant dan payment intent belum aman sebagai kontrak bisnis

Audit terdahulu menemukan checkout multi-merchant dapat membuat child order/invoice per merchant, sementara redirect/payment dan kegagalan antar tahap berpotensi membuat partial order atau hanya menyelesaikan merchant pertama. Merchant membutuhkan satu status pembayaran dan rekonsiliasi yang jelas untuk seluruh checkout.

**Kebutuhan:** pilih salah satu dan dokumentasikan:

- blokir cart multi-merchant untuk sementara; atau
- buat parent checkout/payment intent dengan child order, idempotency, compensation, expiry, dan rekonsiliasi yang eksplisit.

**Acceptance:** failure pada merchant kedua tidak meninggalkan reservation/order/invoice yang tidak terdeteksi; retry tidak menggandakan order maupun invoice.

#### M-P0-02 — Harga, subtotal, voucher, fee, dan item order harus authoritative di server

Audit `audit-product-cart-checkout-2026-09-11.md` mencatat risiko order nominal dikendalikan client, voucher usage belum selalu dikonsumsi atomic, order item belum cukup mengikat product/merchant/harga, dan flash-sale price dapat berbeda dari cart/checkout.

**Kebutuhan:** satu RPC checkout menghitung ulang harga, promo, voucher, shipping, fee, stok/reservation, order, item, dan snapshot fee; cabut atau batasi direct INSERT buyer ke `orders`/`order_items`.

**Acceptance:** request yang mengubah nominal, merchant, harga, voucher actor, quantity negatif, atau item merchant lain ditolak; dua checkout concurrent tidak melampaui limit voucher/stok.

#### M-P0-03 — Jam operasional dan kategori publik harus memakai sumber kebenaran yang sama

Audit jam operasional/multi-kategori mencatat legacy `open_time/close_time` dan `business_category` masih dibaca di beberapa area, sedangkan kebutuhan merchant adalah jadwal harian/multi-kategori yang konsisten.

**Acceptance:** profil publik, status buka/tutup, search, checkout, dan admin menggunakan kontrak yang sama; timezone ditetapkan eksplisit; perubahan jadwal tidak membuat toko menerima order di luar jam.

#### M-P0-04 — Refund dan review harus membuktikan ownership dan pembelian

Audit refund/review menemukan policy yang tidak cukup membuktikan order milik buyer, status order yang eligible, product/merchant yang sesuai, batas nominal refund, dan uniqueness review.

**Acceptance:** buyer hanya dapat refund/review untuk order-item miliknya yang eligible; amount dihitung/capped server-side; approval refund atomic dan memiliki ledger settlement/audit.

### P1 — Tutup sebelum pilot diperluas

1. **Satukan inbox order merchant.** Jadikan `MerchantOrdersPage` sebagai surface canonical; dashboard memakai komponen/query yang sama, bukan workflow status kedua.
2. **Tetapkan satu `OrderStatus` dictionary dan transition matrix.** Selaraskan SQL, TypeScript, filter, progress, fulfillment, buyer, merchant, dan courier.
3. **Perkuat payment recovery.** Tambahkan lease/sweeper untuk reservation invoice `processing`, regenerasi invoice expired, dan rekonsiliasi webhook/duplicate event.
4. **Perkuat reservation/projection.** Uji concurrency POS-online/offline/marketplace/QR, stale alert, retry, expiry, release, consume, dan manual reconcile.
5. **Uji payout dan saldo.** Bedakan available/pending/held/shortfall; semua koreksi melalui adjustment ledger, bukan set saldo langsung.
6. **Perbaiki notifikasi background.** Lease recovery, status partial/dead-letter yang benar, validasi channel, cursor pagination, dan monitoring oldest job.
7. **Tutup gap device/PWA/printer.** Tetapkan matriks supported browser/device, policy cache lokal, logout/reset device, print failure, duplicate reprint, dan receipt pending.
8. **Lengkapi control tower.** Satu antrean untuk merchant onboarding, catalog sync, order exception, payment, refund, payout, dispute, entitlement, QR, dan support dengan owner/SLA.
9. **Validasi entitlement.** POS suspended/cancelled harus membatasi POS sesuai policy tanpa menutup storefront, katalog, histori, dan inbox marketplace.
10. **Selesaikan category contract prioritas.** Retail, food, dan jasa terjadwal harus memiliki field, state, cancellation, fulfillment, kapasitas, dan settlement yang berbeda namun ledger tetap bersama.

### P2 — Setelah fondasi transaksi stabil

- Cursor pagination untuk order, notification, dan laporan volume besar.
- Bulk edit katalog/stok/harga dengan preview dan rollback.
- Import/export dengan validation report per baris dan idempotent re-import.
- Forecast demand, low-stock automation, dan rekomendasi promo.
- Customer segmentation, CRM, dan loyalty yang lebih terukur.
- Marketplace SEO/content tools dan storefront customization.
- Category builder configurable dengan versioning, approval, dan rollback.
- Abuse/risk scoring, identity link, payout hold rule, dan maker-checker lebih luas.

## 6. Kebutuhan minimum product/operations yang belum boleh diabaikan

| Kebutuhan | Mengapa penting untuk merchant | Output yang harus tersedia |
|---|---|---|
| Status data yang terlihat | Merchant perlu tahu apakah order/stok/payment final atau pending | Badge/status `synced`, `pending`, `conflict`, `failed`, `dead-letter` dengan tindakan |
| Rekonsiliasi harian | Mencegah kepercayaan rusak akibat saldo/order berbeda | Daily reconciliation per merchant/outlet dengan alasan selisih |
| Support dan escalation | Merchant pilot tidak bisa mengatasi error DB/payment sendiri | SLA, owner, request/order ID, incident log, runbook |
| Kill switch/rollback | Fitur payment, offline, promo, QR dapat berdampak finansial | Feature flag, rollback SQL/app, backup point, approval |
| Audit tindakan berisiko | Refund, payout, entitlement, delete, dan override harus dapat ditelusuri | Actor, timestamp, before/after, reason, approval |
| Onboarding sampai value pertama | Signup bukan indikator merchant berhasil | Profil lengkap → produk terbit → order pertama → fulfillment pertama → payout pertama |
| Privacy dan data lifecycle | Merchant menyimpan alamat, kontak, bukti refund, dan data operasional | Data inventory, access boundary, retention, deletion/export |

## 7. Release gate yang direkomendasikan

### Gate A — Staging sebelum pilot

- Migration/bootstrap Fase 1–5 diterapkan pada staging kosong dan berisi data.
- Auth, Storage, Realtime, Edge Functions, webhook, secret, backup, dan rollback tervalidasi.
- Test dua buyer, dua merchant, dua courier untuk tenant isolation dan concurrency.
- Checkout hanya mengizinkan kontrak multi-merchant yang sudah dipilih dan diuji.
- Harga, item, voucher, refund, review, dan payout diuji dengan request adversarial.
- Tidak ada defect P0 terbuka.

### Gate B — Pilot terbatas 10–20 merchant

Mulai dari retail, makanan/minuman, dan jasa terjadwal. Gunakan feature flag untuk sewa, wisata, jasa panggilan, dan ojek sampai booking/settlement matang.

Kriteria minimum:

- merchant dapat menerbitkan produk dan menerima order tanpa membeli POS;
- POS suspended tidak menutup marketplace;
- order, stok, payment, refund, dan payout dapat direkonsiliasi;
- offline hanya diaktifkan pada matriks device yang didukung;
- semua incident memiliki owner dan response target;
- QR meja dapat dicabut, scoped outlet/meja, dan tidak mengubah toko publik biasa.

### Gate C — Go-live lebih luas

- Tidak ada P0/P1 finansial/security terbuka.
- Golden dataset finance lulus dan ditandatangani finance.
- Device/PWA/printer/recovery evidence lulus.
- Payment, webhook, refund, payout, reservation, dan notification recovery terukur.
- Metrik pilot stabil: activation, product-first-publish, first-order, fulfillment success, sync success, conflict rate, refund rate, support SLA, dan churn awal.
- Privacy/terms, support escalation, incident response, dan rollback disetujui.

## 8. Rencana eksekusi 30 hari

| Periode | Fokus | Deliverable |
|---|---|---|
| Hari 1–5 | Kunci kontrak transaksi | Decision record multi-merchant checkout, pricing authoritative, status matrix, refund/review ownership |
| Hari 6–12 | Backend integrity | RPC checkout/cancel/refund/review, voucher usage atomic, order-item validation, invoice recovery |
| Hari 13–18 | Merchant operations | Inbox canonical, fulfillment state, jam/kategori canonical, sync/conflict visibility, control-tower queue |
| Hari 19–23 | Staging hardening | Apply bundle, seed golden dataset, RLS/concurrency/security/API smoke, backup/restore rehearsal |
| Hari 24–30 | Pilot terbatas | 10–20 merchant, daily reconciliation, support log, device/PWA/printer test, GO/HOLD decision |

## 9. Kesimpulan keputusan

1. **Pertahankan arah produk:** marketplace gratis sebagai acquisition channel dan POS sebagai kapabilitas operasional berbayar.
2. **Jangan menambah banyak menu/paket sebelum transaksi inti tervalidasi.** Repository sudah luas; bottleneck saat ini adalah trust, consistency, dan evidence.
3. **Prioritaskan checkout authoritative, payment recovery, stok reservation, refund/review authorization, dan satu inbox order.**
4. **Marketplace-only harus tetap menjadi use case kelas satu.** POS tidak boleh menjadi syarat untuk upload produk, menerima order, fulfillment, dan payout marketplace.
5. **Nyatakan POS offline sebagai beta/internal sampai uji device dan recovery nyata selesai.**
6. **Jangan mengaktifkan fee provider, payout otomatis, atau klaim laporan resmi sebelum ledger, approval, rekonsiliasi, dan staging sign-off tersedia.**
7. **Keputusan saat ini: HOLD untuk go-live luas; GO terbatas untuk validasi staging/pilot setelah Gate A terpenuhi.**

## 10. Referensi bukti repository

- `docs/audit-kesiapan-merchant-admin-2026-09-24.md`
- `docs/audit-pengelolaan-pesanan-merchant-pembeli-2026-09-12.md`
- `docs/audit-product-cart-checkout-2026-09-11.md`
- `docs/audit-review-rating-refund-2026-09-11.md`
- `docs/audit-rencana-jam-operasional-multi-kategori-2026-09-20.md`
- `docs/audit-services-end-to-end-2026-09-25.md`
- `docs/audit-services-gap-2026-09-25.md`
- `docs/sop-onboarding-merchant-pilot.md`
- `docs/ringkasan-eksekutif-pilot-merchant.md`
- `src/App.tsx` — route merchant dan POS canonical
- `src/pages/merchant/` — workspace merchant marketplace
- `src/pages/pos/` — modul POS
- `src/lib/marketplaceOrderContract.ts`
- `src/lib/merchantOperatingHours.ts`
- `src/lib/orderStatus.ts`
- `src/lib/posCheckout.ts`
- `src/lib/posOfflineRecovery.ts`
- `src/lib/posCanonicalReports.ts`
- `src/hooks/usePOSOfflineSync.ts`
- `supabase/bootstrap/` dan `supabase/migrations/` — kontrak backend, RLS, RPC, ledger, entitlement, reservation, dan audit

## Batasan audit

Audit ini adalah **static repository audit** berbasis source, migration/bootstrap, dokumentasi, route, dan test contract. Dependency belum dipasang pada sandbox saat audit ini, sehingga typecheck/lint/test/build belum dieksekusi ulang pada checkout ini. Audit juga tidak mengklaim runtime staging/production, data live, webhook provider, concurrency database, perangkat fisik, printer, atau rekonsiliasi keuangan nyata telah lulus. Semua klaim “tersedia” harus dibedakan dari “terbukti siap produksi”.
