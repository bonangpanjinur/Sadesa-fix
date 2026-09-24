# Audit Kesiapan Merchant dan Admin

**Repository:** `bonangpanjinur/Sadesa-fix`  
**Commit yang diaudit:** `605183e` (`main`)  
**Tanggal audit:** 24 September 2026  
**Ruang lingkup:** produk/katalog, pembayaran, stok, pesanan/fulfillment, kuota/subscription, fitur operasional lain, serta kontrol dari sisi merchant dan admin.

## Ringkasan eksekutif

Aplikasi sudah memiliki fondasi yang luas untuk marketplace, merchant, admin, POS, kurir, pembayaran, refund, notifikasi, dan kuota. Pemeriksaan statis menunjukkan **30 deployment SQL** tervalidasi dalam urutan leksikal dan seluruh tabel yang terdeteksi oleh audit RLS telah mengaktifkan RLS. Sejumlah kontrol penting juga sudah berada di database, termasuk reservasi stok marketplace, idempotensi webhook pembayaran, pembatasan berbasis role, serta RPC untuk beberapa mutasi kritis.

Namun, berdasarkan kode aktif dan audit terdahulu di repository, sistem **belum layak dinyatakan siap go-live penuh**. Status yang paling aman saat ini adalah **siap untuk pilot terbatas dengan guardrail operasional**, bukan peluncuran marketplace terbuka tanpa pembatasan. Blocker terbesar adalah checkout online multi-merchant, pemulihan reservation/invoice saat worker atau request gagal, konsistensi jam operasional merchant, serta ketergantungan pada proses manual untuk sejumlah pembayaran dan operasi admin.

### Penilaian keseluruhan

| Area | Status | Penilaian singkat |
|---|---|---|
| Produk/katalog merchant | **Kuning** | CRUD dan banyak fitur katalog tersedia; kesiapan discoverability dan konfigurasi operasional belum konsisten. |
| Pembayaran | **Merah-kuning** | Webhook memiliki kontrol kuat, tetapi multi-merchant dan recovery invoice masih berisiko; beberapa jalur memakai bukti transfer/manual approval. |
| Stok | **Kuning** | Reservasi/consume/release sudah tersedia secara database; perlu pengujian race condition dan rekonsiliasi end-to-end. |
| Pesanan/fulfillment | **Kuning** | Lifecycle merchant/kurir cukup lengkap; perlu validasi staging untuk semua transisi dan kompensasi kegagalan checkout multi-langkah. |
| Kuota/subscription | **Kuning** | Paket, approval, usage log, dan konsumsi kuota tersedia; perlu memastikan enforcement konsisten pada setiap fitur yang dibatasi. |
| Admin operations | **Kuning** | Banyak layar kontrol tersedia; observability dan beberapa proses masih berbasis query client/manual. |
| Merchant operations | **Kuning** | Dashboard, produk, stok, order, finance, refund, POS, promo, dan subscription tersedia; jam operasional dan kesiapan katalog publik masih menjadi gap. |
| Security/RLS | **Hijau-kuning** | Static RLS audit dan migration validation lulus; belum diuji terhadap database live dan skenario abuse end-to-end. |
| Build/test/release | **Merah** | Validasi awal tidak dapat dijalankan karena tool tidak terpasang; `npm ci` gagal karena lockfile tidak sinkron dengan `package.json`. |

## Temuan prioritas

### P0 — Wajib sebelum marketplace online dibuka luas

#### 1. Checkout multi-merchant belum memiliki model pembayaran yang aman

Audit terdahulu menyatakan cart berisi produk dari dua merchant dengan metode `ONLINE` harus ditolak sebelum order pertama dibuat, atau menggunakan satu parent payment yang mencakup seluruh child order. Tanpa keputusan ini, satu checkout dapat menghasilkan order terpisah dengan status/payment intent yang tidak konsisten, partial payment, atau settlement yang sulit direkonsiliasi.

**Dampak:** order dan pembayaran dapat terpecah; merchant pertama dapat menerima order sementara merchant kedua gagal dibayar; refund dan ongkir menjadi ambigu.

**Keputusan yang diperlukan:**

1. Untuk pilot, **blokir cart online lintas merchant** dengan pesan yang jelas dan arahkan buyer ke checkout per merchant; atau
2. Implementasikan parent payment intent/order aggregator sebelum mengizinkan checkout lintas merchant.

**Bukti:** `docs/audit-checkout-end-to-end-2026-09-18.md` dan `docs/audit-alur-checkout-2026-09-18-r2.md`.

#### 2. Jam operasional merchant belum menjadi sumber kebenaran tunggal

Tabel `merchant_operating_hours` sudah tersedia, tetapi audit terdahulu mencatat pengaturan merchant belum merender komponen jadwal harian dan alur publik masih menghitung status buka dari `open_time`/`close_time` tunggal. Perbedaan weekday/weekend, hari tutup, dan jadwal melewati tengah malam berpotensi tidak tampil sama antara admin, merchant, dan buyer.

**Dampak:** buyer dapat melakukan order ketika toko sebenarnya tutup; merchant tidak dapat mengatur jadwal operasional yang realistis; status toko dan validasi checkout tidak konsisten.

**Rekomendasi:** jadikan jadwal mingguan + zona waktu Asia/Jakarta sebagai sumber kebenaran; pertahankan kolom legacy hanya untuk kompatibilitas; tambahkan smoke test publik dan checkout berdasarkan hari serta jam.

**Bukti:** `docs/audit-rencana-jam-operasional-multi-kategori-2026-09-20.md`, khususnya temuan pada baris 9–16.

#### 3. Katalog multi-kategori merchant belum konsisten

Audit mencatat `merchants.business_category` hanya menyimpan satu slug, sementara kebutuhan operasional memungkinkan satu merchant berada di beberapa kategori. Relasi baru dan backfill harus dipastikan benar-benar menjadi sumber data publik, bukan hanya tersedia di migrasi/dokumen.

**Dampak:** produk/toko tidak ditemukan di kategori yang semestinya; laporan kategori dan discovery buyer tidak lengkap.

**Rekomendasi:** verifikasi bahwa relasi `merchant_categories` aktif di halaman pengaturan, slug publik, pencarian, dan laporan admin; jalankan backfill dan hitung merchant yang kehilangan kategori.

## P1 — Wajib sebelum pilot diperluas

### Pembayaran dan rekonsiliasi

- **Recovery payment invoice reservation:** jika proses berhenti setelah reservation tetapi sebelum pemanggilan provider, row dapat tertinggal dalam status processing. Tambahkan lease (`locked_at`, `locked_by`, expiry) atau sweeper retry.
- **Invoice expired:** alur bayar ulang harus membuat invoice aktif baru atau melakukan reconciliation yang eksplisit. Jangan biarkan order tertahan pada invoice expired tanpa jalur recovery.
- **Manual payment untuk subscription merchant:** halaman subscription merchant mengunggah bukti pembayaran dan membuat `merchant_subscriptions` dengan `PENDING_APPROVAL`; ini operasional tetapi bukan settlement otomatis. Admin harus memiliki SLA, audit trail keputusan, pencegahan bukti duplikat, dan notifikasi hasil approval/rejection.
- **Payment provider production:** webhook Xendit sudah memiliki kontrol yang baik menurut audit terdahulu—validasi token, kecocokan invoice/order, amount check, row lock, dan deduplikasi event—tetapi belum ada transaksi nyata provider dalam audit ini. Wajib uji di staging dengan callback duplikat, amount mismatch, callback out-of-order, timeout, dan expired invoice.

### Stok dan inventory

- Fungsi database `reserve_marketplace_stock`, `release_marketplace_stock_reservation`, dan `consume_marketplace_stock_reservation` tersedia. Ini adalah fondasi yang benar, tetapi perlu pengujian konkurensi: dua buyer membeli SKU terakhir, payment timeout, cancel sebelum fulfillment, refund setelah consume, dan order tidak aktif yang melewati TTL reservation.
- Merchant membutuhkan satu rekonsiliasi yang jelas antara stok katalog marketplace dan stok POS/multi-outlet. Hindari dua sumber stok yang dapat berubah tanpa event sinkronisasi.
- Tambahkan alert admin untuk reservation yang kedaluwarsa, stok negatif, mismatch antara `products.stock` dan ledger/mutasi, serta item yang gagal di-consume.

### Pesanan dan fulfillment

- Lifecycle order sudah memuat status seperti `NEW/PENDING_PAYMENT → PROCESSED → READY → ASSIGNED/COURIER_ACCEPTED → PICKED_UP → DELIVERING → DELIVERED → DONE`, dan index fulfillment merchant/courier tersedia di bootstrap.
- Wajib uji bahwa merchant hanya dapat melihat/mengubah order miliknya, perubahan status hanya valid sesuai state machine, dan status terminal tidak dapat diturunkan secara sembarangan.
- Checkout multi-langkah perlu RPC transaction atau compensation cleanup. Jika order berhasil dibuat tetapi payment invoice atau reservasi stok gagal, sistem harus melepaskan semua resource dan meninggalkan audit record yang dapat ditindaklanjuti.
- Refund/dispute sudah memiliki halaman dan tabel settlement, tetapi perlu memastikan refund benar-benar mengembalikan stok sesuai status fulfillment dan tidak menggandakan settlement ketika admin mengklik ulang.

### Kuota, subscription, dan entitlement

- Paket transaksi, quota tiers, usage logs, subscription merchant, approval admin, dan fungsi `consume_subscription_usage` tersedia.
- Risiko utama adalah enforcement tersebar di banyak fitur. Buat matriks entitlement terpusat untuk setiap fitur yang memakai kuota: marketplace order, promo/iklan, WhatsApp, POS, dan fitur lain. Setiap konsumsi harus atomic, idempotent, dan menghasilkan usage log.
- Subscription merchant pada UI membaca paket, subscription, dan payment settings secara terpisah. Pastikan paket nonaktif tidak dapat dipilih, subscription pending/rejected tidak membuka akses, dan expired subscription tidak dapat dikonsumsi.
- Admin harus memiliki laporan reconciliation: quota granted, consumed, reversed, expired, dan saldo per merchant.

### Notifikasi dan operasi background

Audit terdahulu menemukan tiga risiko P1: job notification `processing` dapat tertinggal tanpa lease recovery; status `dead_letter` dapat membuat campaign terbaca `sent`; serta tipe channel mencakup `push`/`email` sementara worker yang ditemukan hanya menangani `whatsapp`/`in_app`. Pagination notifikasi juga masih terbatas pada window 100/20 item.

**Rekomendasi:** tambah lease/sweeper, agregasi campaign yang membedakan success/partial failure/dead-letter, validasi channel saat enqueue, dan cursor pagination. Admin System Health perlu memonitor queue backlog, dead-letter, oldest processing job, webhook lag, reservation expiry, dan reconciliation mismatch.

## Audit perspektif merchant

| Kapabilitas | Yang sudah tersedia | Gap/risk sebelum go-live |
|---|---|---|
| Onboarding | Dashboard menangani toko belum terdaftar, pending, rejected, dan approved; migrasi profil terbaru menambah integritas KTP unik. | Perlu smoke test pendaftaran baru, daftar ulang, approval/rejection reason, dan pembatasan fitur sebelum approved. |
| Produk | Halaman products, product detail, gallery, bundle, grosir, price book, promo, voucher, flash sale, import/export. | Perlu verifikasi semua mutasi memakai merchant scope; status publish, gambar, variasi, harga, pajak, dan stok harus konsisten ke katalog buyer. |
| Stok | Merchant stock dan POS stock/gudang/mutasi tersedia. | Rekonsiliasi marketplace vs POS dan race test belum dibuktikan dalam audit live. |
| Pesanan | Merchant orders, fulfillment, refund, chat, review, printer/POS tersedia. | State transition, SLA response, cancellation, partial fulfillment, refund-after-shipment, dan notifikasi harus diuji skenario penuh. |
| Pembayaran/penghasilan | Finance, dues, withdrawal, subscription dengan bukti pembayaran. | Sebagian masih manual; perlu approval SLA, rekonsiliasi, settlement ledger, dan bukti payout yang dapat diaudit. |
| Kuota | Subscription menampilkan kuota, pemakaian, saldo, dan payment status. | Enforcement lintas fitur dan expired/pending behavior harus dikunci di server/RPC. |
| Operasional | Settings, POS, jam operasi, promo, iklan, loyalty, analytics. | Jadwal harian/multi-kategori belum konsisten menurut audit terdahulu; konfigurasi yang memengaruhi checkout harus memiliki preview status publik. |

### Checklist acceptance merchant

- Merchant approved dapat membuat produk dengan harga, stok, foto, kategori, dan status publish.
- Merchant pending/rejected tidak dapat menerima order online.
- Buyer melihat harga, stok, kategori, jam buka, ongkir, dan metode bayar yang sama dengan yang merchant lihat.
- Dua buyer tidak dapat menjual SKU terakhir secara bersamaan.
- Merchant menerima notifikasi order baru satu kali dan dapat memproses status hingga selesai.
- Cancel/refund melepaskan atau menyesuaikan stok sesuai rule.
- Saldo, fee, komisi, dan withdrawal merchant dapat direkonsiliasi ke order selesai.
- Kuota tidak berkurang pada payment gagal, order dibatalkan, atau retry idempotent.

## Audit perspektif admin

| Kapabilitas | Yang sudah tersedia | Gap/risk sebelum go-live |
|---|---|---|
| Approval dan user management | Admin users, roles, merchant detail, merchant registration controls, verifier commerce. | Semua keputusan penting harus memiliki audit log, actor, reason, before/after, dan idempotency; uji role separation admin vs verifikator. |
| Produk dan stok | Admin products/store products, quota tiers, package management, system health. | Perlu guard terhadap penghapusan paket/produk yang sudah dipakai dan alert stok/reservation mismatch. |
| Order dan dispute | Admin orders, finance, dispute center, refund-related tables. | Pastikan keputusan refund menghasilkan settlement satu kali dan status order/refund tetap konsisten. |
| Pembayaran | Payment settings, payment proof review, webhook/reconciliation tables. | Manual proof flow memerlukan SOP, aging queue, escalation, dan rekonsiliasi provider; belum ada bukti transaksi provider live pada audit. |
| Kuota | Admin dapat membaca subscription, paket, tier, dan usage. | Perlu dashboard saldo/usage anomaly dan pemisahan paket aktif, pending, rejected, expired. |
| Monitoring | System Health menghitung users, merchants, orders, products, couriers, dan recent orders. | Metrik saat ini belum cukup untuk readiness: tambahkan queue, webhook, stuck payments, reservation, failed notification, error rate, dan freshness data. |
| Security | RLS audit lulus untuk tabel yang terdeteksi; deployment SQL tervalidasi. | Belum diuji pada database live, belum ada negative test sistematis untuk cross-merchant read/write, dan beberapa tabel sensitif memiliki zero policy eksplisit sehingga akses harus diverifikasi lewat RPC/service role. |

### Checklist acceptance admin

- Admin dapat approve/reject merchant dengan alasan dan audit trail.
- Admin dapat melihat queue: merchant pending, payment pending, refund/dispute pending, payout pending, expired reservation, stuck notification.
- Admin dapat memblokir merchant/order secara reversible dengan alasan.
- Admin dapat mengubah paket/fee/komisi tanpa mengubah snapshot transaksi historis.
- Admin dapat merekonsiliasi total paid provider, order paid, refund, merchant payable, platform fee, courier fee, dan outstanding.
- Admin dashboard dapat membedakan data realtime, stale, dan error; kegagalan satu query tidak membuat angka terlihat nol tanpa peringatan.
- Admin role tidak otomatis berarti akses ke data yang seharusnya hanya service/RPC; uji least privilege dengan akun terpisah.

## Kontrol yang sudah baik

1. **RLS dan migration hygiene:** `npm run audit:rls` lulus; tabel yang terdeteksi memiliki RLS aktif. `npm run validate:migrations` memvalidasi 30 deployment SQL dalam urutan lexical.
2. **Payment webhook:** audit terdahulu mencatat constant-time callback token check, order/invoice matching, amount validation, row lock, dan deduplikasi event.
3. **Stock primitives:** fungsi reserve/release/consume marketplace tersedia di bootstrap SQL, sehingga arah desain sudah atomic di database.
4. **Role-scoped UX:** aplikasi memiliki route dan layout terpisah untuk admin, merchant, buyer, courier, desa, verifikator, serta POS.
5. **Operational breadth:** merchant memiliki modul produk, stok, order, fulfillment, refund, finance, subscription, analytics, POS, promo, loyalty, gallery, dan import/export.

## Release gate yang direkomendasikan

### Gate A — sebelum pilot terbatas

- Tetapkan kebijakan checkout: single-merchant only atau parent payment.
- Jalankan staging smoke test buyer → payment → merchant → courier → delivered → settlement.
- Uji concurrency stok terakhir dan cleanup ketika payment gagal/timeout.
- Verifikasi RLS negative test untuk buyer/merchant/admin/verifikator.
- Pastikan jam buka dan status checkout memakai jadwal harian yang sama.
- Sediakan SOP manual payment approval, refund, dispute, payout, dan incident escalation.

### Gate B — sebelum pilot diperluas

- Tambahkan payment reservation lease/recovery dan expired invoice renewal.
- Pastikan worker notification memiliki lease recovery dan channel consumer yang lengkap.
- Tambahkan observability dan alert untuk stuck queue, payment mismatch, reservation expiry, dan quota anomaly.
- Buktikan reconciliation harian: provider ↔ order ↔ settlement ↔ merchant payout.
- Perbaiki lockfile dan buat CI clean install yang reproducible.

### Gate C — sebelum marketplace publik penuh

- Dukung atau blokir secara eksplisit semua kombinasi cart lintas merchant, payment method, delivery type, promo, voucher, refund, dan stock reservation.
- Lulus regression suite end-to-end termasuk duplicate callbacks, retries, out-of-order events, refunds, cancellation, and partial failures.
- Uji load pada checkout, webhook, order queue, stock reservation, dan admin dashboard.
- Lakukan security review live database dan production configuration: secrets, cron, worker, storage, webhook, backup/restore, and alerting.

## Validasi yang dijalankan dan batasannya

- **Berhasil:** `npm run audit:rls`.
- **Berhasil:** `npm run validate:migrations` — 30 deployment SQL tervalidasi.
- **Gagal sebelum lint/test/build:** `eslint`, `vitest`, dan `vite` tidak ditemukan karena dependency belum terpasang.
- **Gagal memasang dependency dengan `npm ci`:** `package.json` dan `package-lock.json` tidak sinkron; output menyebut `@googlemaps/js-api-loader` dan `@types/google.maps` hilang dari lockfile serta versi `tsx` tidak cocok. Ada pula engine warning `@zxing/library` memerlukan Node `>=24`, sedangkan environment audit memakai Node `22.13.0`.
- **Belum dilakukan:** transaksi nyata Xendit/provider, RLS terhadap database live, load test production-like, verifikasi cron/worker di deployment, dan smoke test dengan akun role nyata.

## Kesimpulan

**Rekomendasi keputusan:** jangan menyatakan merchant marketplace siap go-live penuh pada commit ini. Nyatakan sebagai **pilot terbatas** hanya setelah Gate A terpenuhi, dengan checkout lintas merchant diblokir atau dibatasi dan proses manual payment/refund/payout memiliki SOP serta monitoring. Prioritas teknis tertinggi adalah: (1) model checkout/payment lintas merchant, (2) recovery invoice/worker, (3) konsistensi jam operasional dan kategori publik, (4) rekonsiliasi stok/order/payment, dan (5) reproducible CI/build.

Dokumen ini merupakan audit kesiapan berbasis repository dan dokumentasi yang tersedia; ia bukan pengganti staging certification, penetration test, atau sign-off operasional/keuangan.

## Referensi internal

- `docs/audit-checkout-end-to-end-2026-09-18.md`
- `docs/audit-alur-checkout-2026-09-18-r2.md`
- `docs/audit-payment-notification-2026-09-11.md`
- `docs/audit-rencana-jam-operasional-multi-kategori-2026-09-20.md`
- `docs/audit-refund-2026-09-18.md`
- `docs/audit-pengelolaan-pesanan-merchant-pembeli-2026-09-12.md`
- `docs/audit-product-cart-checkout-2026-09-11.md`
- `supabase/bootstrap/21_20260924100000_merchant_profile_requirements.sql`
- `supabase/bootstrap/30_20260924150000_verifikator_admin_sales_commission.sql`
- `src/pages/merchant/MerchantSubscriptionPage.tsx`
- `src/pages/admin/AdminTransactionQuotaPage.tsx`
- `src/pages/admin/AdminSystemHealthPage.tsx`
- `scripts/audit-rls-static.py`
- `scripts/validate-migrations.sh`

*Dihasilkan dari pemeriksaan commit `605183e` pada repository yang dipilih.*
