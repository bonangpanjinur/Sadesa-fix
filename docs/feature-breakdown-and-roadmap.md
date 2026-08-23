# Breakdown Fitur dan Roadmap DesaMart UMKM

**Tanggal audit:** 23 Agustus 2026  
**Basis audit:** static review repository `remix-of-umkm-sadesa`, route React, page/component inventory, referensi tabel Supabase, migration RLS, test suite, dan hasil hardening sebelumnya.

> Dokumen ini memetakan fitur yang terlihat di codebase. Status **tersedia** berarti terdapat route/page/component yang mengimplementasikan fitur tersebut; status **perlu verifikasi** berarti keberadaan UI belum cukup untuk membuktikan seluruh aturan bisnis, transaksi atomik, RLS, dan integrasi production sudah benar.

## 1. Gambaran bisnis

DesaMart adalah platform ekosistem ekonomi desa yang menggabungkan marketplace produk UMKM, operasional merchant, POS multi-outlet, logistik/courier, layanan wisata desa, administrasi desa, verifikator, komunikasi, promosi, dan fungsi back-office administrator. Modelnya bukan hanya toko online; aplikasi juga berperan sebagai **operating system untuk merchant dan desa**.

Alur nilai utamanya adalah sebagai berikut: pembeli menemukan produk atau paket wisata, membuat pesanan dan pembayaran, merchant memproses order melalui dashboard atau POS, courier menangani pengantaran, pembeli memberikan ulasan atau mengajukan sengketa, sementara admin/desa/verifikator mengawasi kualitas, ekonomi lokal, komisi, promosi, dan pelaporan.

## 2. Aktor dan tanggung jawab

| Aktor | Kapabilitas utama yang terlihat | Catatan kontrol |
|---|---|---|
| Pembeli/customer | Browse, search, wishlist, compare, cart, checkout, payment, order tracking, review, cashback, loyalty, voucher, referral, chat, support | Perlu verifikasi konsistensi ownership order pada semua endpoint dan halaman |
| Merchant | Kelola produk, varian, kategori, stok, pesanan, refund, promo, voucher, flash sale, grosir, preorder, gallery, keuangan, subscription, iklan, chat, delivery | Merchant isolation dan akses lintas outlet perlu diuji dengan data nyata |
| Kasir/POS user | POS checkout, customer, loyalty, promo, voucher, held bills, QR Pay, printer, shift/absensi, KDS, meja, stok, laporan | Akses outlet sudah menjadi fokus RLS; perlu pengujian mutation dan concurrency |
| Courier | Ride/order delivery, status, location, POD image, earnings, deposit, withdrawal, performance, history, chat | Perlu idempotency update status dan perlindungan spoofing lokasi/POD |
| Desa | Profil desa, ekonomi, event, membership, tourism, guides, packages, maps, financial/tourism reports, broadcast, merchants | Perlu definisi ownership user-to-village yang konsisten |
| Verifikator | Verifikasi ekonomi/event/merchant, assignment, kas report, earnings, withdrawal | Perlu workflow approval yang audit-able dan anti-self-approval |
| Admin | User/role, merchant/village/courier/order/refund/withdrawal, reports, finance, commissions, backups, audit logs, POS, SEO, WhatsApp, notification, system health | Admin adalah trust boundary tertinggi; MFA, least privilege, dan audit coverage perlu diperkuat |
| Public/guest | Home, product/tourism discovery, merchant pages, search, terms, privacy, auth, install | Perlu rate limit dan abuse protection pada search, auth, checkout initiation |

## 3. Breakdown fitur berdasarkan domain

### A. Marketplace dan discovery

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| Home, katalog produk, kategori, merchant storefront | Tersedia | Perlu ranking/search relevance, empty/error states, SEO metadata konsisten, dan observability untuk query lambat |
| Search dan filter shops | Tersedia | Perlu pagination/server-side filtering, debounce yang terukur, typo tolerance, dan proteksi query abuse |
| Product detail, variant, image gallery, compare | Tersedia | Perlu validasi stock real-time, handling produk tidak aktif, image optimization, dan canonical URL |
| Wishlist dan recently viewed | Tersedia | Perlu batas storage, sinkronisasi lintas device, deduplikasi, dan privacy policy yang eksplisit |
| Recommendation | Tersedia | Perlu penjelasan sumber rekomendasi, fallback ketika data minim, dan metrik conversion yang tervalidasi |
| Flash sale, bundle, wholesale, preorder | Tersedia | Perlu atomic stock reservation, batas per customer, schedule timezone yang jelas, dan test race condition |

### B. Cart, checkout, payment, dan order

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| Cart dan checkout | Tersedia | Perlu server-side price revalidation, cart expiry, stock reservation, dan proteksi duplicate submit |
| Voucher, promotion, cashback, loyalty | Tersedia | Perlu satu pricing engine terpusat agar aturan stacking, rounding, minimum purchase, dan expiry konsisten |
| COD security | Tersedia | Perlu fraud scoring, address verification, retry/return policy, dan monitoring abuse |
| Payment transfer/QR/payment proof | Tersedia | Perlu idempotency key, webhook reconciliation, state machine formal, dan quarantine untuk proof mencurigakan |
| Order status dan tracking | Tersedia | Perlu transition matrix server-side, actor authorization per transition, SLA timer, dan dead-letter handling |
| Invoice, receipt, review | Tersedia | Perlu immutable invoice snapshot, tax/fee breakdown, correction workflow, dan audit trail |
| Dispute, refund, withdrawal | Tersedia | Perlu case management, evidence timeline, escalation SLA, partial refund, dan segregation of duties |
| Chat buyer-merchant | Tersedia | Perlu moderation, attachment scanning, retention policy, unread/read consistency, dan anti-spam |

### C. Merchant operations

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| Merchant dashboard dan analytics/insight/visitor stats | Tersedia | Perlu definisi KPI baku, period comparison, export reproducibility, dan privacy-safe aggregation |
| Product, variant, category, gallery | Tersedia | Perlu bulk edit, draft/publish workflow, validation SKU/barcode, image compression, dan audit perubahan |
| Stock dan inventory history | Tersedia | Perlu stock ledger immutable, reservation/commit/release, negative stock guard, dan reconciliation |
| Merchant orders, delivery tracker, refund | Tersedia | Perlu SLA dashboard, partial fulfillment, cancellation reason taxonomy, dan retry-safe actions |
| Promo, scheduled promo, voucher, flash sale | Tersedia | Perlu preview simulator, conflict detection, usage analytics, dan approval untuk campaign berisiko |
| Grosir dan preorder | Tersedia | Perlu contract-like terms, deposit/payment schedule, fulfillment milestone, dan cancellation rules |
| Finance, dues, tax, subscription, ads | Tersedia | Perlu ledger double-entry atau minimal immutable journal, reconciliation payout, invoice subscription, dan billing failure handling |
| Import/export | Tersedia | Perlu schema versioning, dry-run validation, row-level error report, dan upload size/type enforcement |

### D. POS multi-tenant dan multi-outlet

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| POS dashboard, setup, users, access, outlets | Tersedia | Perlu policy matrix terdokumentasi untuk owner/manager/cashier dan outlet-level permission UI |
| Kasir checkout | Tersedia | Perlu transaksi atomik melalui RPC/server function, concurrency-safe stock deduction, dan recovery ketika network terputus |
| Held bills, split payment, QR Pay, receipt printer | Tersedia | Perlu expiry held bill, QR session idempotency, printer fallback queue, dan status pembayaran yang dapat direkonsiliasi |
| Customer, loyalty, promotion, voucher | Tersedia | Perlu anti-double redemption, optimistic concurrency, dan audit perhitungan diskon/poin |
| Stok, purchase order, supplier, transfer, bahan baku, resep | Tersedia | Perlu unified inventory ledger, approval transfer, BOM versioning, wastage reason, dan unit conversion |
| Shift, attendance, schedule, payroll | Tersedia | Perlu timezone/pay-period rules, approval payroll, adjustment audit, dan separation antara attendance dan payroll |
| KDS, meja, kiosk, menu QR | Tersedia | Perlu order queue state machine, table locking, printer/display failure handling, dan public QR abuse protection |
| Accounting dan laporan POS | Tersedia | Perlu rekonsiliasi sales-to-cash, closing session, void/return journal, export checksum, dan timezone consistency |
| Offline sync | Tersedia secara komponen | Perlu conflict resolution formal, outbox retry/backoff, device registration, encryption at rest, dan duplicate event protection |

### E. Desa dan pariwisata

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| Profil, ekonomi, membership, merchant desa | Tersedia | Perlu workflow perubahan data, verifikasi sumber data, dan hak akses per desa yang eksplisit |
| Event dan broadcast | Tersedia | Perlu RSVP/capacity, schedule timezone, moderation, delivery receipt, dan template notification |
| Tourism packages, guides, booking, map | Tersedia | Perlu availability calendar, booking hold, cancellation/refund policy, guide assignment, dan emergency contact |
| Laporan wisata dan keuangan desa | Tersedia | Perlu source-of-truth ledger, period locking, approval, export audit, dan role separation |
| Donasi/campaign | Tersedia | Perlu donor receipt, campaign verification, progress reconciliation, misuse monitoring, dan refund policy |

### F. Courier dan mobility

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| Ride booking/history/tracking | Tersedia | Perlu dispatch algorithm, cancellation fee rules, driver timeout, dan state transition tests |
| GPS/location updater dan ETA | Tersedia | Perlu anti-spoofing, sampling/battery policy, stale-location handling, dan privacy controls |
| POD image dan delivery status | Tersedia | Perlu signed upload URL, malware/content validation, immutable evidence timestamp, dan retry queue |
| Earnings, deposit, withdrawal, performance | Tersedia | Perlu payout reconciliation, ledger audit, dispute handling, dan anti-fraud controls |

### G. Platform administration dan governance

| Fitur | Status | Kekurangan atau penyempurnaan |
|---|---|---|
| User/role/merchant/village/courier administration | Tersedia | Perlu RBAC/ABAC matrix yang terdokumentasi, approval flow, MFA, dan emergency access review |
| Audit log, admin logs, system health, realtime | Tersedia | Perlu tamper-evident log, correlation ID end-to-end, alert thresholds, retention, dan PII redaction review |
| Backup dan scheduled backup | Tersedia | Perlu restore drill berkala, backup encryption/key rotation, RPO/RTO target, dan tenant-scoped restore |
| SEO, banners, public assets, WhatsApp, push | Tersedia | Perlu secret rotation, template approval, delivery status, unsubscribe preference, dan safe HTML sanitization |
| Support tickets | Tersedia | Perlu SLA, assignment, escalation, attachment scanning, dan customer-visible status timeline |

## 4. Kekurangan lintas sistem yang paling penting

Pertama, banyak proses bisnis kritis masih tampak dilakukan melalui rangkaian query client-side. Untuk checkout POS, pengurangan stok, voucher usage, loyalty, dan bahan baku, pendekatan ini berisiko menghasilkan partial success jika salah satu query gagal atau dua kasir bertransaksi bersamaan. Proses tersebut sebaiknya dipindahkan ke database RPC atau service server-side yang atomic, idempotent, dan memiliki audit event.

Kedua, keberadaan route guard di frontend bukan pengganti RLS. Karena sistem menyimpan data tenant, outlet, desa, merchant, dan role, setiap tabel sensitif perlu memiliki policy `SELECT`, `INSERT`, `UPDATE`, dan `DELETE` yang diuji lintas tenant. Test saat ini sudah mencakup regression dan RLS integration skeleton, tetapi 11 test staging masih perlu dijalankan terhadap Supabase staging.

Ketiga, state machine belum terlihat sebagai satu abstraksi lintas order, payment, refund, ride, delivery, QR session, held bill, dan booking. Tanpa transition matrix terpusat, status dapat melompat, diulang, atau berubah oleh aktor yang tidak berwenang. Setiap domain transaksi memerlukan daftar state, actor, precondition, side effect, dan idempotency key.

Keempat, observability sudah tersedia untuk payment, upload, realtime, dan webhook, tetapi perlu dikembangkan menjadi tracing lintas request. Minimal setiap order/payment/POS sale perlu memiliki correlation ID, structured event, latency, actor role, tenant/outlet identifier yang sudah dipseudonimkan, dan outcome tanpa merekam secret atau data pembayaran sensitif.

Kelima, test coverage masih tidak seimbang. Regression test sudah ada untuk payment countdown, payment proof, order status, i18n cart, file validation, courier components, dan reorder hook. Namun belum terlihat coverage kuat untuk checkout end-to-end, pricing rules, voucher/cashback stacking, POS concurrency, offline sync conflict, refunds, delivery transition, tourism booking, admin authorization, dan negative RLS mutations.

## 5. Kandidat bug dan risiko yang perlu diverifikasi

| Risiko | Dampak | Cara verifikasi |
|---|---|---|
| Partial POS transaction | Sale tercatat tetapi stok, loyalty, voucher, atau bahan baku tidak sinkron | Simulasikan failure setiap query dan concurrent cashier checkout |
| Double payment/webhook | Order dibayar dua kali atau status mundur | Kirim webhook duplikat/out-of-order dengan idempotency test |
| Cross-tenant leakage | Data merchant/outlet/desa terlihat tenant lain | Jalankan matrix RLS read/write/delete dengan dua tenant dan dua outlet |
| Unauthorized status transition | Order/refund/ride berubah oleh actor yang salah | Test semua transition per role dan actor ownership |
| Negative/oversold inventory | Stok menjadi negatif atau terjual melebihi stok | Jalankan concurrent sale, return, transfer, dan offline replay |
| Coupon/promotion abuse | Diskon/poin digunakan berkali-kali atau stacking salah | Test boundary dates, timezone, usage limit, duplicate redemption |
| Stale GPS/POD abuse | Lokasi atau bukti antar dipalsukan | Test stale timestamp, invalid file, replay upload, dan role mismatch |
| Backup tidak dapat dipulihkan | Kehilangan data saat insiden | Lakukan restore drill ke environment terisolasi dan checksum validation |
| Notification/privacy leak | PII atau isi chat terkirim ke penerima salah | Test recipient resolution, unsubscribe, tenant filter, dan redaction |
| Bundle/runtime regression | Initial load ringan tetapi dialog gagal di browser tertentu | E2E buka payment, held bill, QR, barcode, printer fallback |

## 6. Fitur baru yang paling bernilai

Fitur tambahan yang paling strategis bukan sekadar menambah halaman, melainkan memperkuat reliability dan operasional bisnis:

| Prioritas | Fitur baru | Nilai bisnis |
|---|---|---|
| P0 | Transaction orchestration/RPC untuk checkout dan POS | Mencegah transaksi setengah berhasil dan overselling |
| P0 | Idempotency service untuk payment, webhook, refund, booking, dan POS sale | Mencegah duplikasi finansial |
| P0 | RBAC/ABAC permission matrix dengan UI access review | Mengurangi risiko akses berlebihan |
| P0 | Staging RLS test harness otomatis di CI | Menjaga isolasi tenant setiap perubahan migration |
| P1 | Unified immutable ledger untuk stock, cash, commission, loyalty, cashback, dan payout | Mempermudah rekonsiliasi dan audit |
| P1 | Order/payment/refund/delivery state machine dashboard | Mengurangi status macet dan mempercepat support |
| P1 | Offline POS outbox dengan conflict center | Menjaga operasional ketika koneksi buruk |
| P1 | Reconciliation center payment dan payout | Mempercepat pencocokan gateway, bank, merchant, courier, dan admin |
| P1 | Customer service case management | Menyatukan dispute, refund, ticket, chat, dan evidence |
| P2 | Advanced inventory forecasting dan reorder suggestion | Mengurangi stockout dan dead stock |
| P2 | Merchant CRM dan segmentation | Meningkatkan repeat purchase dan campaign effectiveness |
| P2 | Tourism availability/booking calendar dan guide dispatch | Mengubah katalog wisata menjadi operasional booking yang reliable |
| P2 | Data warehouse/KPI layer | Menyatukan analytics merchant, desa, admin, dan verifikator |
| P2 | Feature flags dan controlled rollout | Mengurangi risiko saat merilis fitur besar |

## 7. Roadmap implementasi yang disarankan

### P0 — Reliability, money flow, dan tenant isolation

Tahap pertama harus memprioritaskan hal yang dapat menyebabkan kerugian finansial atau kebocoran data. Implementasinya mencakup RPC checkout POS yang atomic, idempotency key payment/webhook, order/payment transition matrix, RLS mutation tests staging, permission matrix, dan negative-path tests. Target selesai adalah tidak ada duplicate sale/payment, tidak ada cross-tenant read/write, dan seluruh state transition kritis ditolak jika precondition salah.

### P1 — Operasional dan rekonsiliasi

Tahap kedua membangun unified ledger, closing session POS, payment reconciliation, payout reconciliation, refund/dispute case management, offline conflict center, serta delivery/tourism booking reliability. Targetnya adalah setiap perbedaan saldo, stok, payout, atau status memiliki sumber data dan event audit yang dapat ditelusuri.

### P2 — Growth dan automation

Tahap ketiga mengembangkan CRM, segmentation, recommendation quality, campaign simulator, inventory forecasting, tourism calendar, notification orchestration, dan data warehouse KPI. Fitur growth harus dibangun setelah pricing, ledger, order, dan permission foundation stabil agar metrik tidak menyesatkan.

### P3 — Experience dan scale

Tahap terakhir memprioritaskan UX polish, accessibility, mobile/offline improvements, advanced search, performance profiling per route, image/CDN optimization, feature flags, and controlled rollout. Optimasi bundle seperti lazy-loading POS dialog sudah menunjukkan pola yang dapat diterapkan pada modul berat lain.

## 8. Urutan eksekusi praktis berikutnya

1. Membuat dokumen state machine untuk `order`, `payment`, `refund`, `POS sale`, `stock`, `ride`, dan `tourism booking`.
2. Menyelesaikan RLS staging integration test dan menambahkan negative mutation matrix lintas tenant/outlet.
3. Memindahkan checkout POS dan payment reconciliation ke atomic server-side/RPC flow dengan idempotency.
4. Menambahkan test coverage untuk pricing, voucher/cashback, concurrent stock, offline replay, refund, dan role authorization.
5. Membuat unified audit event schema dan dashboard operational alerts.
6. Baru setelah itu mengembangkan fitur growth seperti CRM, forecasting, segmentation, dan tourism automation.

## 9. Kesimpulan

Repository sudah memiliki cakupan fitur yang luas dan ambisi produk yang kuat: marketplace, merchant operating tools, POS, logistics, village economy, tourism, dan administration berada dalam satu platform. Kekurangan terbesar bukan jumlah halaman, melainkan **kedalaman reliability pada transaksi lintas tabel, konsistensi state, rekonsiliasi finansial, isolasi tenant yang diuji berulang, dan coverage test untuk skenario gagal**.

Dengan demikian, rekomendasi strategisnya adalah tidak langsung menambah banyak fitur permukaan. Prioritas terbaik adalah memperkuat fondasi P0 terlebih dahulu, kemudian membangun ledger, reconciliation, dan case management. Setelah fondasi tersebut stabil, fitur growth akan lebih aman, metrik lebih terpercaya, dan operasional DesaMart lebih siap digunakan pada skala merchant, outlet, desa, dan transaksi yang lebih besar.
