# Rencana Bisnis Marketplace Gratis + POS Berbayar

> **Status implementasi — 8 September 2026:** Pekerjaan marketplace-only **selesai dikerjakan di repository**: checkout tidak lagi bergantung pada quota marketplace, tenant POS, atau subscription POS; kontrak payload dan test sudah lulus. Fase QR/menu/meja menjadi fase aktif berikutnya: RPC publik scoped tenant–outlet–meja dan halaman pelanggan sudah diimplementasikan di repository, sedangkan penerapan migration, staging, dan uji konflik masih terbuka. Fase 0, Fase 1, dan Fase 4 tersedia secara teknis di repository. Fase 2 tetap sebagian tersedia untuk mapping katalog, projection stok, reservation ledger, rekonsiliasi server-side, alert kegagalan/stale projection, identitas SKU/barcode tenant-scoped, stok varian/outlet, dan alur QR/menu/meja. Fase 3 tersedia secara teknis untuk alur offline dasar; Fase 5 sebagian tersedia untuk entitlement komersial, promo partner, dan SLA support. Migration baru belum diterapkan ke staging/production.

> **Catatan audit dokumen:** status “selesai secara teknis di repository” hanya berarti kontrak, kode, atau migration tersedia di source control. Status tersebut **bukan** bukti bahwa alur sudah terpasang di Supabase, aman di staging, diterima merchant, atau boleh dijual di produksi. Gunakan matriks tugas dan gate di bagian 9 sebagai acuan eksekusi.

## 0. Analisis kesiapan saat ini

### 0.1 Kesimpulan audit dan kekurangan yang harus ditutup

Dokumen sudah mencakup model bisnis, pemisahan marketplace–POS, katalog/stok, offline, laporan, monetisasi, KPI, risiko, dan roadmap. Kekurangan utamanya bukan lagi daftar fitur, melainkan **bukti kesiapan, kepemilikan keputusan, dan kontrol operasi**. Pekerjaan berikut wajib ditambahkan ke rencana sebelum pilot:

| Kekurangan | Risiko bila dibiarkan | Tugas penutupan | Gate |
|---|---|---|---|
| Status repository, staging, pilot, dan produksi belum memakai definisi yang seragam | Fitur dianggap siap hanya karena halaman/RPC/migration sudah ada | Terapkan definisi status dan evidence wajib pada bagian 0.2; setiap fase memiliki checklist evidence | Sebelum Fase 6 |
| Source of truth migration dan prosedur penerapan belum menjadi deliverable tersendiri | Staging/production dapat berbeda dari source code; rollback sulit | Tetapkan bundle release, checksum/versi, urutan penerapan, backup, dry-run, rollback, dan hasil validasi | Sebelum migration staging |
| Environment readiness belum memiliki checklist owner | Auth, Edge Function, webhook payment, storage, realtime, dan redirect dapat gagal saat pilot | Buat matriks environment dev/staging/production, secrets, URL, role, webhook, backup, dan akses operator | Sebelum Fase 6 |
| Kesiapan pembayaran, payout, pajak, KYC/provider, refund, dan dispute belum memiliki keputusan operasional final | Saldo tertahan, payout salah, sengketa, atau pelanggaran kewajiban lokal | Tetapkan policy owner, ledger yang menjadi sumber kebenaran, approval, rekonsiliasi, dan prosedur manual darurat | Sebelum transaksi berbayar |
| Tugas belum konsisten memiliki owner, output, dependensi, dan kriteria go/no-go | Pekerjaan terlihat selesai tetapi tidak ada pihak yang menerima hasilnya | Gunakan matriks eksekusi fase di bagian 9.1–9.8 dan tunjuk satu accountable owner per tugas | Mulai Fase 0 |
| SLO, backup/restore, incident response, dan RTO/RPO belum menjadi gate | Gangguan realtime, payment, atau offline dapat membesar tanpa pemulihan terukur | Tetapkan SLO pilot, RTO/RPO, backup restore drill, alert, on-call, status page, dan runbook | Sebelum pilot |
| Data analytics belum dikunci sebagai kontrak event dan definisi metrik | Attach rate, MRR, churn, GMV, dan activation dapat berbeda antar layar/laporan | Buat metric dictionary, event schema, timezone, deduplication, periode, dan reconciliation report | Sebelum dashboard dipakai untuk keputusan |
| Legal, privasi, consent, retensi, penghapusan data, dan terms per vertikal belum menjadi output fase | Data booking, alamat, peserta, provider, dan pembayaran dapat diproses tanpa batas yang jelas | Review kebijakan privasi, terms, refund, payout, consent, retensi, dan data subject request bersama owner yang berwenang | Sebelum pilot publik |
| Pilot belum memiliki desain eksperimen dan kriteria berhenti | Tim dapat memperluas rollout berdasarkan anekdot atau jumlah signup | Tetapkan cohort, baseline, target, guardrail, feedback protocol, kill switch, dan keputusan 30/60/90 hari | Sebelum memilih merchant pilot |

### 0.2 Definisi status dan evidence wajib

Gunakan status berikut secara konsisten di seluruh dokumen. Satu fitur dapat memiliki beberapa status berbeda; jangan menaikkan status hanya karena status sebelumnya sudah tercapai.

| Status | Arti | Evidence minimum |
|---|---|---|
| **Tersedia di repository** | Kode, konfigurasi, test, atau migration ada di branch yang akan dirilis | Link/path perubahan, hasil build/lint/test yang relevan |
| **Siap diuji di staging** | Dependensi environment tersedia dan data uji dapat dibuat ulang | Migration/bootstrap berhasil, smoke test, fixture, log tanpa error kritis |
| **Lulus staging** | Skenario sukses, gagal, permission, idempotensi, dan rollback telah dijalankan | Test report bertanggal, bukti rekonsiliasi, defect P0/P1 tertutup |
| **Siap pilot** | Lulus staging dan dapat dipakai oleh cohort terbatas dengan support/runbook | Sign-off product, engineering, operations, finance bila terkait uang, dan privacy/security bila terkait data |
| **Siap produksi** | Pilot memenuhi target dan guardrail; rollback serta monitoring sudah aktif | Go/no-go record, SLO dashboard, incident/runbook, backup restore drill, approval release |

**Aturan evidence:** setiap item `[x]` di roadmap harus menunjuk pada evidence yang dapat ditemukan, bukan hanya pada keberadaan file. Jika evidence belum ada, gunakan `[~]` untuk “implementasi ada tetapi validasi belum selesai”, dan `[ ]` untuk pekerjaan yang belum dimulai.

### 0.3 Keputusan lintas fungsi yang belum boleh diasumsikan

Sebelum ada transaksi uang nyata atau data pilot, pemilik bisnis harus menandatangani keputusan berikut:

- siapa yang menjadi merchant of record, pihak penerima pembayaran, dan pihak yang bertanggung jawab atas refund/payout;
- metode payment dan payout yang benar-benar tersedia untuk tiap kategori, termasuk webhook, retry, idempotensi, settlement, dan rekonsiliasi manual;
- status pajak yang boleh ditampilkan, siapa yang menghitung/menyetorkan, dan batas bahwa laporan pajak masih estimasi;
- verifikasi merchant/provider, data minimum yang dikumpulkan, akses admin, retensi, penghapusan, dan jalur permintaan subjek data;
- policy pembatalan/no-show/deposit/kerusakan untuk jasa, sewa, wisata, makanan, dan transportasi;
- owner operasional untuk support, dispute, fraud, payment failure, stale projection, offline conflict, serta insiden keamanan;
- batas pilot, kill switch, komunikasi insiden, serta kondisi otomatis untuk menghentikan rollout.

| Area | Status | Catatan |
|---|---|---|
| Fondasi aplikasi | **Siap untuk development** | SPA Vite/React/TypeScript, halaman merchant dan POS, serta bootstrap Supabase sudah tersedia. |
| Entitlement POS | **Siap diuji di staging** | Guard server-side, lifecycle trial/paid/grace/suspended/cancelled, audit, export, dan reaktivasi sudah ada di repository. |
| Katalog dan stok non-varian | **Siap diuji di staging** | POS outlet stock menjadi sumber operasional, marketplace menjadi projection, reservation ledger dan rekonsiliasi sudah tersedia. |
| Identitas katalog | **Siap setelah migration diterapkan** | Constraint database dan validasi form untuk SKU/barcode unik per tenant sudah tersedia; validasi konsistensi produk–varian–outlet tetap perlu staging. |
| Projection stale | **Siap setelah migration diterapkan** | Alert warning berbasis umur sinkronisasi dipindai saat halaman Integrasi POS dibuka dan tampil bersama alert error. |
| POS offline | **Siap untuk uji staging/pilot terbatas** | Queue, retry/dead-letter, conflict center, cache stale, dan receipt offline sudah ada; skenario perangkat ditutup, refresh, listrik mati, dan konflik stok masih perlu diuji menyeluruh. |
| Laporan resmi | **Siap diuji di staging; belum boleh dipasarkan sebagai laporan resmi** | Kontrak laporan canonical, ledger hutang/piutang, jurnal posted, dan rekonsiliasi harian sudah tersedia; penerapan bundle dan validasi staging/production masih terbuka. |
| Produksi | **Belum siap** | Migration harus diterapkan dan diuji di staging; variabel Supabase publik, Edge Functions, Auth redirect, dan pilot merchant masih perlu dikonfigurasi. |

**Prioritas kerja:** terapkan migration Fase 2–5 ke staging, validasi konflik dan perangkat Fase 2–3, lalu jalankan pilot merchant sebelum membuka POS secara luas. Jangan menandai fase sebagai siap produksi hanya karena halaman, KPI, atau RPC sudah ada di repository.

## 0.4 Audit silang repository: SQL, UI, dan layanan runtime

Audit ini dilakukan pada source code yang tersedia di repository pada 8 September 2026. Audit ini **bukan** pemeriksaan langsung terhadap project Supabase staging/production karena belum ada bukti bahwa bundle telah diterapkan di sana. Karena itu, “ada di repository” tidak boleh dibaca sebagai “siap dijual”.

Gunakan empat tingkat bukti berikut:

- **Ada di repository:** file, halaman, test, RPC, atau migration dapat ditemukan;
- **Berfungsi secara lokal:** alur tidak langsung diblokir oleh stub atau service yang sengaja tidak tersedia;
- **Siap diuji di staging:** bundle, environment, fixture, dan test matrix dapat dijalankan;
- **Siap pilot/produksi:** ada sign-off, monitoring, rollback, support, dan bukti operasional.

### Ringkasan status audit

| Domain | Bukti repository | Status paling jujur | Hambatan utama |
|---|---|---|---|
| Marketplace gratis — katalog | `/merchant/products`, detail produk, form CRUD `products`, kategori, gambar, varian | **Implementasi marketplace-only selesai di repository; belum lulus staging** | Perlu uji RLS, quota, moderasi, storage, dan merchant marketplace-only |
| Marketplace gratis — inbox order | `/merchant/orders`, `/merchant/fulfillment`, realtime order hook, invoice marketplace | **Ada di repository; independensi dari POS belum terbukti** | E2E tanpa `pos_tenant`/entitlement POS harus diuji dengan fixture |
| POS entitlement | `/merchant/pos/subscribe`, `/merchant/pos/*`, `POSAccessRoute`, bundle 12–14 dan 19–20 | **Kontrak kuat di repository; belum terbukti di environment** | Migration, payment, webhook, expiry, grace, suspend, reaktivasi, dan audit |
| Katalog POS dan stok | Merchant catalog, POS projection, outlet/varian stock, reservation/ledger pada bundle 10–17 dan 21–23 | **Sebagian siap diuji** | Concurrency, multi-outlet, varian, stale projection, dan reconcile nyata |
| Laporan canonical | Halaman laba-rugi, cashflow, akuntansi, hutang/piutang, kas; bundle 24–25 | **Ada di repository; belum boleh dianggap laporan resmi** | Bundle belum diterapkan, golden dataset dan rekonsiliasi staging belum ditandatangani |
| Offline POS | Queue, lease, retry, conflict center, recovery test, receipt contract | **Ada untuk alur dasar; belum siap pilot** | Device/PWA nyata, storage lokal, konflik lintas kanal, printer, dan recovery operasional |
| QR/meja/menu publik | `/merchant/pos/meja`, `/merchant/pos/menu-qr`, `/menu/:tenantId/:tableId`, `MenuPublicPage` | **Kontrak RPC dan UI tersedia di repository; belum lulus staging** | Migration 28 belum diterapkan; perlu uji entitlement POS, tenant/outlet/table isolation, stok, dan order ke KDS |
| Pricing dan POS subscription | `/pricing`, POS subscribe, admin POS, promo partner, priority support; bundle 26–27 | **UI/schema sebagian ada; billing belum production-grade** | Payment provider, add-on, fee ledger, refund, payout, dan rekonsiliasi |
| Multi-vertikal | Tourism, ride, desa, kategori produk dan halaman operasional | **Vertikal terpisah ada; platform template belum ada** | Belum ada category builder, kontrak listing versioned, state machine booking/rental/service |
| Admin control tower | Admin POS, dashboard KPI, approval, dispute, refund, support, audit, backup | **Banyak layar ada; control tower terpadu belum ada** | Queue lintas domain, owner/SLA, maker-checker, dan approval matrix |

### Temuan SQL dan migration

1. **Bootstrap adalah artefak release database.** `supabase/bootstrap/manifest.json` menyatakan 28 bundle yang bersumber dari 210 migration arsip plus bundle kontrak QR/menu/meja. Bundle 10–28 berisi kontrak tambahan POS, stok, lifecycle, reporting, komersial, partner, support, dan order publik.
2. **Manifest belum memiliki integritas lengkap.** Bundle 11, 12, 13, 18, 19, 20, 21, 22, 24, 25, 26, dan 27 masih memiliki `sha256: "pending"` serta `bytes: 0`. Ini tidak membuktikan SQL-nya salah, tetapi checksum dan verifikasi release belum dapat dipercaya.
3. **Belum ada bukti penerapan environment.** Repository memiliki SQL, namun belum ada apply log, checksum yang cocok dengan staging, `supabase db diff`, backup point, atau rehearsal rollback yang membuktikan staging/production sama dengan bundle.
4. **Entitlement POS sudah memiliki arah server-side yang benar.** Bundle 14, 19, dan 20 menyediakan activation gate, resolver entitlement berbasis waktu, grace, suspend/cancel, history, export, audit, dan reaktivasi. Statusnya tetap “siap diuji”, bukan “siap dijual”, sampai diuji dengan auth role, expiry, duplicate event, dan payment failure.
5. **Kontrak stok lebih kuat daripada bukti UI marketplace-nya.** Bundle 15–17 dan 21–23 memisahkan POS outlet stock, marketplace projection, reservation, allocation varian/outlet, stale alert, dan reconciliation. Merchant tetap perlu melihat error/mapping yang dapat ditindaklanjuti, dan database perlu diuji pada transaksi bersamaan lintas outlet.
6. **Reporting canonical tersedia tetapi belum menjadi bukti laporan resmi.** Bundle 24–25 memusatkan report, debt payment, journal, cash mutation, dan daily reconciliation pada server. Semua perbedaan angka harus diuji memakai golden dataset sebelum angka dipakai untuk keputusan keuangan atau pajak.
7. **Fase 5 belum merupakan fee engine marketplace.** Bundle 26–27 terutama menambah limit entitlement POS, add-on kapasitas, promo onboarding, partner, dan SLA support. Belum ditemukan implementasi server-side untuk komisi dinamis lintas kategori, effective-date fee rule, fee snapshot per order/payout, usage-fee provider, wallet fee, atau payout hold.

### Temuan UI dan layanan runtime

1. **Marketplace dan POS dipisahkan pada routing.** Rute `/merchant/products`, `/merchant/orders`, dan `/merchant/fulfillment` hanya memakai `ProtectedRoute`, sedangkan `/merchant/pos/*` memakai `POSAccessRoute`. Ini mendukung prinsip marketplace independen, tetapi tetap harus dibuktikan dengan merchant tanpa tenant POS.
2. **Katalog Merchant sudah menjadi entry point bersama.** `MerchantProductsPage` mengelola `products`; URL POS lama `/merchant/pos/produk` diarahkan kembali ke katalog Merchant. UI mencegah perubahan stok produk yang tertaut POS. Guard browser bukan pengganti guard database; keduanya harus diuji.
3. **Inbox marketplace tersedia dan kontrak marketplace-only sudah diterapkan di checkout.** `MerchantOrdersPage` membaca `orders`, `order_items`, realtime, fulfillment, payment proof, dan invoice. Yang masih harus dibuktikan di staging adalah pembuatan order end-to-end, reservation, payout, refund, dispute, dan akses merchant tanpa `pos_tenant`.
4. **Ada dua domain subscription yang tidak boleh disamakan.** `/merchant/subscription` mengelola paket/quota lama melalui `merchant_subscriptions` dan `transaction_packages`; `/merchant/pos/subscribe` mengelola `pos_subscriptions` dan `pos_packages`. Copy, navigasi, analytics, dan support harus menyebut domain yang benar.
5. **Customer flow QR/meja sekarang memiliki kontrak Supabase langsung.** Migration 28 menyediakan RPC publik yang memvalidasi POS aktif, tenant, outlet, meja aktif/non-cleaning, produk aktif, dan stok; `MenuPublicPage` membuat order melalui RPC tersebut, sedangkan `OrderStatusPage` membaca status melalui RPC tenant-scoped. `posBridgeFetch` tidak lagi dipakai untuk menu dan tracking order. Status tetap menunggu penerapan migration dan validasi staging.
6. **Laporan memiliki banyak halaman, tetapi angka wajib berasal dari RPC canonical.** Keberadaan halaman tidak membuktikan query yang dipakai konsisten. Setiap halaman dan export harus dicocokkan dengan function/report contract bundle 24–25, timezone, status transaksi, outlet scope, retur, pembayaran aktual, dan jurnal posted.
7. **Admin memiliki banyak layar operasional, bukan satu control tower.** Admin POS, approval, dispute, refund, support, backup, audit, dan dashboard sudah menjadi fondasi. Namun antrean lintas domain, owner, SLA, risk flag, payout aging, stale stock, incident, dan maker-checker belum terbukti menjadi satu alur keputusan.

### 0.5 Matriks readiness sebelum menyebut “siap”

| Capability | Bukti SQL minimum | Bukti UI minimum | Bukti runtime/staging | Status 8 Sep 2026 |
|---|---|---|---|---|
| Merchant marketplace-only | Kontrak checkout/order tidak mensyaratkan `pos_tenant`; reservation marketplace memiliki fallback tanpa POS | Produk → order → fulfillment → refund/dispute tanpa menu POS | Fixture merchant tanpa tenant POS, order sukses, tidak ada error entitlement | **Implementasi repository selesai; E2E staging payout/refund/dispute masih terbuka** |
| Aktivasi POS | Entitlement aktif, approval, expiry, grace, suspend/cancel, audit | Subscribe, status, trial, promo, warning, blocked state, export | Transisi dan duplicate/retry payment | **Kontrak ada; uji terbuka** |
| Satu katalog dua kanal | Mapping product/variant, constraint SKU/barcode tenant, source stok, mutation guard | Linked/synced/error, edit produk, mapping failure, retry/reconcile | Multi-outlet, varian, konkurensi | **Sebagian ada; uji terbuka** |
| POS online/offline | Atomic checkout, idempotency, reservation/ledger, server revalidation | Kasir, pending/synced/conflict, retry/dead-letter, conflict center | Crash, refresh, listrik mati, pergantian device, reconnect | **Alur dasar ada; pilot terbuka** |
| QR order meja | RPC scoped tenant/outlet/table, validasi server, reservation stock lifecycle, source `table_qr` | Generate, preview, customer menu, order status, KDS | Tamper ID, nonaktif, duplicate order, suspend POS, staging | **Implementasi repository selesai; belum lulus staging** |
| Laporan dan kas | Canonical report, payment/cash ledger, posted journal, reconciliation | Screen dan export dengan definisi/periode sama | Golden dataset dan daily reconciliation | **Siap diuji; belum resmi** |
| Monetisasi marketplace/provider | Fee rule effective date, snapshot, adjustment, payout, dispute, wallet | Simulasi tarif, disclosure, fee detail, payout hold, appeal | Order lama vs tarif baru, refund, batch, waiver, fraud | **Belum dibangun** |
| Control tower | Action RPC, approval/audit, queue state, SLA, idempotency | Satu antrean owner/status/next action | Escalation, incident, maker-checker, rollback | **Fondasi ada; belum terpadu** |

### 0.6 Kontrak status UI yang harus diseragamkan

Setiap halaman harus membedakan status berikut, bukan hanya menampilkan toast “berhasil”:

- **Draft/configured:** konfigurasi tersimpan tetapi belum aktif;
- **Active:** entitlement atau operasi aktif dan dapat dipakai;
- **Pending:** menunggu pembayaran, sinkronisasi, approval, atau validasi server;
- **Stale:** data ada tetapi umur projection/cache melewati ambang;
- **Conflict:** transaksi tidak dapat diterapkan otomatis dan membutuhkan keputusan;
- **Blocked:** ditolak oleh entitlement, role, policy, atau validasi;
- **Failed/dead-letter:** gagal setelah retry dan harus diberi tindakan;
- **Final/posted:** sudah masuk ledger canonical dan tidak boleh diubah dengan update biasa.

UI harus menampilkan alasan, timestamp, scope merchant/outlet, request atau idempotency key bila relevan, tindakan berikutnya, dan jalur support. Jangan menampilkan status “sukses” ketika yang terjadi baru queue lokal atau request diterima browser.

### 0.7 Urutan penutupan gap

| Prioritas | Pekerjaan | Alasan urutan | Exit evidence |
|---|---|---|---|
| P0 | Lengkapi hash/bytes manifest, tetapkan bundle release, apply ke Supabase staging, backup, diff, dan rollback rehearsal | Tanpa database yang diketahui versinya, audit UI/SQL tidak dapat dipercaya | Manifest lengkap, apply log, checksum, backup/restore, diff kosong |
| P0 | Validasi kontrak marketplace-only di staging | Implementasi repository sudah memisahkan marketplace dari POS; bukti environment masih belum ada | E2E tanpa tenant POS sampai fulfillment/payout/refund/dispute |
| P0 | Terapkan dan validasi RPC QR/menu/meja | Customer flow sudah tidak bergantung pada bridge lama; migration dan evidence staging masih terbuka | Menu publik, order meja, KDS/status, reservation stock, revoke/nonaktif lulus |
| P0 | Uji entitlement dan payment lifecycle | POS berbayar tidak boleh bergantung pada state browser/admin manual | Webhook idempotent, retry, signature, expiry, grace, suspend, reaktivasi, rekonsiliasi |
| P1 | Uji stok concurrency dan offline device nyata | Risiko terbesar adalah overselling, transaksi ganda, atau data lokal bocor | Conflict matrix, device matrix, recovery evidence, support runbook |
| P1 | Rekonsiliasi report/cash/journal dan batasi label laporan | Kesalahan angka merusak keputusan merchant dan kewajiban keuangan | Golden dataset, daily reconciliation, export parity, disclaimer sign-off |
| P1 | Bangun category builder, fee engine, payout/dispute, dan provider ledger | Multi-vertikal dan monetisasi belum punya kontrak data yang dapat dieksekusi | Versioned config, fee snapshot, adjustment, payout aging, dispute evidence |
| P2 | Gabungkan admin control tower dan maker-checker | Mengurangi operasi manual tersebar setelah transaksi stabil | Queue lintas domain, owner/SLA, dual approval, audit sample |
| P2 | Pilot cohort dan ukur unit economics | Validasi bisnis baru berarti setelah alur teknis dan support aman | 10–20 merchant, baseline, guardrail, 30/60/90-day decision |

### 0.8 Pertanyaan wajib setiap release

1. Bundle database apa yang diterapkan, checksum berapa, dan pada environment mana?
2. Apakah merchant tanpa POS dapat membuat produk dan menerima order sampai fulfillment tanpa error entitlement?
3. Apakah perubahan stok pada produk tertaut hanya boleh lewat POS outlet stock, termasuk varian dan multi-outlet?
4. Apakah subscription, payment, webhook, promo, add-on, grace, suspend, dan reaktivasi konsisten jika request dikirim dua kali?
5. Apakah QR/menu/order meja benar-benar memanggil layanan aktif, bukan stub atau endpoint lama?
6. Apakah transaksi offline dapat dipulihkan tanpa duplikasi dan tanpa membuka data tenant/outlet lain?
7. Apakah angka layar, export, jurnal, cash, hutang/piutang, dan rekonsiliasi berasal dari definisi yang sama?
8. Apakah fee, payout, refund, dispute, dan adjustment memiliki ledger, approval, snapshot aturan, dan audit?
9. Siapa owner setiap alert, apa SLA-nya, dan apa tindakan rollback/kill switch?
10. Apa bukti merchant pilot memahami batas fitur gratis, batas POS, data yang diproses, dan jalur support?

### 0.9 Kesimpulan audit per 8 September 2026

Repository sudah memiliki fondasi teknis yang luas: routing terpisah, katalog Merchant, POS projection, stock ledger, entitlement server-side, offline queue, laporan canonical, admin approval, promo partner, dan support SLA. Namun fondasi tersebut belum sama dengan produk siap dijual.

Keputusan operasional yang berlaku:

- **Marketplace gratis:** boleh dilanjutkan sebagai target produk, tetapi klaim “mandiri dari POS” harus ditutup dengan E2E staging merchant tanpa tenant POS.
- **POS berbayar:** belum boleh dibuka luas; entitlement dan UI tersedia, tetapi migration, payment lifecycle, staging, dan pilot belum menjadi bukti produksi.
- **QR/menu meja:** jangan dipasarkan sebagai fitur aktif sampai migration RPC diterapkan dan diuji dengan token scope tenant/outlet/table, meja nonaktif, reservation stock, serta recovery status order.
- **Laporan:** boleh dipakai sebagai kandidat laporan operasional setelah golden dataset dan rekonsiliasi staging; jangan disebut laporan pajak/keuangan resmi tanpa approval.
- **Marketplace multi-vertikal dan monetisasi provider:** masih tahap desain/kontrak; UI atau tabel yang sudah ada tidak cukup untuk mengaktifkan komisi, booking fee, usage fee, payout, atau risk blocking.

Dengan penilaian ini, status keseluruhan produk adalah **siap dilanjutkan ke hardening staging, belum siap pilot transaksi uang nyata, dan belum siap produksi**.

## 1. Ringkasan keputusan

Model yang paling sehat untuk platform ini adalah **freemium berbasis dua produk yang saling menguatkan**:

1. **Marketplace SaDesa**
   - Gratis untuk semua merchant yang telah memiliki role `merchant`.
   - Merchant dapat menampilkan produk, menerima pesanan online, dan membangun reputasi.
   - Admin mengatur batas pemakaian dan kualitas konten, bukan mengunci akses dasar secara sewenang-wenang.

2. **POS SaDesa**
   - Produk berbayar untuk transaksi toko fisik, outlet, kasir, stok operasional, pembelian, dan laporan.
   - Harga, paket, trial, diskon, suspend, dan override ditentukan admin/super admin.
   - POS terhubung ke marketplace melalui katalog dan ledger stok, bukan melalui dua stok yang berjalan sendiri-sendiri.

3. **Omnichannel**
   - Penjualan offline di POS dan penjualan online di marketplace masuk ke satu model produk dan satu riwayat stok.
   - POS dirancang **offline-first** sehingga kasir tetap dapat menjual ketika internet terputus.
   - Marketplace membutuhkan koneksi internet; pesanan online tidak boleh dibuat seolah-olah sudah mengurangi stok offline sebelum reservasi server berhasil.

4. **Marketplace tidak bergantung pada POS**
   - Upload produk, halaman toko, inbox pesanan, konfirmasi pesanan, dan fulfillment dasar harus tetap tersedia tanpa subscription POS.
   - Subscription POS hanya menambahkan kemampuan operasional toko fisik dan projection katalog ke tenant/outlet POS.
   - POS suspended atau cancelled tidak boleh menutup toko marketplace, menghapus produk, atau menghentikan penerimaan pesanan marketplace.

5. **SaDesa adalah marketplace multi-vertikal**
   - Platform harus dapat melayani barang, makanan/minuman, jasa, sewa, pengalaman wisata, dan transportasi lokal tanpa memaksa semua kategori memakai alur order yang sama.
   - Admin mengatur kategori, template listing, atribut wajib, jenis fulfillment, aturan komisi, dan fitur yang tersedia melalui konfigurasi.
   - Setiap kategori memakai kontrak order dan settlement yang sesuai, tetapi tetap menggunakan identitas merchant, pelanggan, pembayaran, dispute, dan audit platform yang konsisten.

**Rekomendasi utama:** jangan menjual “fitur POS sebagai add-on kecil” saja. Jual POS sebagai **sistem operasional usaha** yang menghemat stok, waktu kasir, dan kesalahan pencatatan, sementara marketplace gratis menjadi jalur akuisisi merchant dan sumber nilai tambahan.

**Keputusan produk:** POS offline bukan sekadar fitur tambahan. Untuk target UMKM, POS harus tetap bisa dipakai untuk transaksi kasir dasar saat koneksi terputus, lalu melakukan sinkronisasi dan rekonsiliasi ketika online kembali.

---

## 2. Alasan model ini cocok untuk SaDesa

### Masalah merchant yang ingin diselesaikan

Pedagang kecil biasanya memiliki tiga kebutuhan berbeda:

- **Ditemukan pelanggan:** etalase online, foto produk, lokasi, ulasan, dan pesanan online.
- **Menjual cepat di toko:** kasir, barcode, pembayaran, struk, shift, dan pelanggan.
- **Mengendalikan usaha:** stok, pembelian, margin, kas, hutang/piutang, dan laporan.

Marketplace gratis menjawab kebutuhan pertama dengan hambatan masuk rendah. POS berbayar menjawab kebutuhan kedua dan ketiga yang memiliki nilai berulang setiap hari.

### Mengapa marketplace sebaiknya gratis

- Menambah jumlah merchant dan variasi produk.
- Menciptakan efek jaringan antara pembeli, desa, kurir, dan pedagang.
- Menjadi jalur trial alami untuk mengedukasi merchant tentang manfaat pencatatan.
- Mengurangi hambatan bagi UMKM yang belum siap membayar software.

Gratis tidak berarti tanpa kendali. Admin tetap perlu mengatur kuota, moderasi, status verifikasi, komisi atau biaya transaksi bila kelak diperlukan, serta perlindungan dari spam dan penyalahgunaan.

### Mengapa POS layak berbayar

POS memiliki manfaat yang lebih terukur:

- transaksi dan stok harian,
- jumlah kasir dan outlet,
- perangkat/printer,
- sinkronisasi marketplace,
- laporan usaha,
- dukungan dan pemulihan data,
- kontrol akses staf.

Merchant yang sudah bergantung pada POS memiliki willingness-to-pay lebih tinggi daripada merchant yang baru membuat etalase online.

### Cakupan usaha multi-vertikal

SaDesa sebaiknya menggunakan **template kategori**, bukan satu formulir produk yang dipaksakan untuk semua usaha:

| Vertikal | Contoh merchant | Model listing/order | Data penting |
|---|---|---|---|
| Barang retail | kaos, baju, kelontongan, oleh-oleh kering | beli produk, pickup atau kirim | varian, ukuran, warna, stok, SKU, berat, pengiriman |
| Makanan/minuman | warung, kafe, katering, minuman | pesan sekarang, pickup, delivery, atau order meja | modifier, level/topping, waktu siapkan, jam tersedia, stok bahan |
| Jasa terjadwal | barbershop, pijat, fotografer, photobox, servis | booking slot atau request jadwal | durasi, tenaga kerja, lokasi, jadwal, deposit, pembatalan |
| Jasa panggilan | tukang listrik, tukang air, tukang cuci, teknisi | request pekerjaan dan penawaran | area layanan, biaya kunjungan, estimasi, bukti pekerjaan, status provider |
| Sewa | alat, kendaraan, perlengkapan acara, studio | booking rentang waktu dengan deposit | kalender ketersediaan, durasi, deposit, denda, kondisi barang |
| Wisata/pengalaman | paket desa, pemandu, ojek wisata, tur lokal | booking kapasitas atau rute | jadwal, titik temu, kapasitas, peserta, tarif rute, operator |

Fitur bersama tetap harus tersedia untuk semua vertikal: profil merchant, katalog/listing, pencarian, checkout atau booking, notifikasi, pembayaran, status order, chat atau instruksi, ulasan, refund, dispute, payout, dan audit. Perbedaannya berada pada template listing, state machine order, fulfillment, dan settlement.

### Strategi peluncuran multi-vertikal

Jangan meluncurkan semua kategori sekaligus hanya karena sistem dapat menampungnya. Gunakan pendekatan bertahap:

1. **Gelombang awal:** barang retail, makanan/minuman, dan jasa terjadwal karena kebutuhan lokalnya mudah dipahami dan frekuensi order dapat diukur.
2. **Gelombang kedua:** jasa panggilan, sewa, dan photobox/fotografi setelah scheduling, area layanan, deposit, dan dispute stabil.
3. **Gelombang ketiga:** wisata, paket pengalaman, dan ojek wisata setelah kapasitas, operator, rute, keselamatan, serta settlement partner tervalidasi.

Setiap gelombang harus memiliki owner bisnis, target supply merchant, target demand pelanggan, SLA fulfillment, aturan pembatalan, dan metrik unit economics sendiri. Kategori baru tidak cukup hanya ditambahkan ke dropdown.

---

## 3. Batas produk yang harus tegas

### Marketplace gratis

Fitur dasar yang sebaiknya tersedia untuk seluruh merchant aktif:

- profil toko dan jam operasional;
- katalog produk;
- kategori, foto, harga, varian, dan stok;
- halaman toko publik;
- pesanan marketplace;
- konfirmasi pesanan dan status fulfillment dasar;
- inbox pesanan marketplace yang dapat dipakai tanpa POS;
- ulasan dan rating;
- promosi dasar yang dibatasi;
- statistik ringan;
- penarikan saldo sesuai aturan platform.

### Batasan marketplace yang dapat dikendalikan admin

Batasan harus transparan dan mudah dipahami. Contoh:

| Area | Paket marketplace gratis yang disarankan |
|---|---|
| Produk aktif | 50–100 produk, dapat diubah admin per segmen |
| Foto produk | Batas ukuran/kuota penyimpanan yang wajar |
| Pesanan | Tidak dibatasi secara keras; gunakan rate limit dan proteksi abuse |
| Promosi | Promo dasar; kampanye besar memerlukan eligibility |
| Statistik | Ringkasan 7/30 hari; analitik lanjutan menjadi nilai POS |
| Outlet | 1 lokasi marketplace utama |
| Pengguna staf | Pemilik saja |
| Import/export | Export dasar; import massal dapat dibatasi |
| Dukungan | Self-service dan pusat bantuan |

**Prinsip penting:** jangan membatasi jumlah order sukses hanya untuk mendorong upgrade. Itu merusak marketplace dan menghukum merchant yang sedang tumbuh. Batasi fitur operasional lanjutan, kapasitas, analitik, dan automasi.

### POS berbayar

Fitur POS yang menjadi alasan upgrade:

- tenant usaha dan multi-outlet;
- kasir dan role staf;
- PIN kasir;
- barcode scanner;
- checkout tunai, QRIS, transfer, debit, dan metode lain;
- hold/resume bill;
- struk dan reprint;
- sesi kas dan tutup shift;
- stok per outlet;
- stok opname, mutasi, transfer, dan pembelian;
- retur;
- pelanggan dan loyalty;
- laporan kasir, outlet, stok, penjualan, laba rugi, dan cashflow;
- mode offline untuk penjualan kas;
- sinkronisasi POS–marketplace;
- QR menu dan pemesanan sesuai meja per outlet;
- audit log dan kontrol akses.

### Pesanan meja melalui QR POS

Pemesanan meja adalah fitur POS opsional, bukan perilaku default semua toko marketplace:

- QR dibuat oleh tenant POS untuk kombinasi outlet dan meja tertentu.
- Untuk kebutuhan meja, gunakan **QR code**, bukan barcode satu dimensi, karena pelanggan akan memindainya dengan kamera ponsel.
- Scan QR membuka toko Merchant yang sama, tetapi membawa konteks outlet dan meja yang telah divalidasi server.
- Toko yang dibuka dari marketplace atau tautan biasa tetap menjadi toko online normal tanpa konteks meja.
- Tombol atau alur “pesan untuk meja” hanya boleh muncul setelah konteks QR meja berhasil diverifikasi; parameter meja yang diketik atau diubah manual dari URL tidak cukup.
- Order meja dan order marketplace boleh memakai katalog, harga, reservasi, dan ledger stok yang sama, tetapi harus menyimpan kanal/sumber order yang berbeda agar fulfillment dan laporan tidak tercampur.
- QR harus memiliki scope tenant/outlet/meja, dapat dinonaktifkan atau dicabut, tidak mengekspos ID internal secara langsung, dan dilindungi dari penyalahgunaan serta order berulang.
- Jika POS tidak aktif, outlet atau meja tidak tersedia, atau QR sudah dicabut, sistem harus menolak konteks meja dengan jelas dan tidak diam-diam menganggapnya sebagai order meja.

Fitur ini memberikan nilai tambahan yang jelas untuk POS tanpa mengurangi akses marketplace gratis. Satu merchant tetap memiliki satu toko publik; QR hanya menambahkan mode pemesanan berbasis meja.

---

## 4. Model paket dan harga

Harga berikut adalah **hipotesis awal untuk diuji**, bukan harga final. Admin/super admin perlu dapat mengubah harga tanpa perubahan kode.

### Paket yang disarankan

| Paket | Target | Harga uji | Isi utama |
|---|---|---:|---|
| Marketplace | Semua merchant | Gratis | Etalase online, pesanan, katalog dasar, statistik ringan |
| POS Starter | Warung/toko kecil, 1 outlet | Rp49.000–79.000/bulan | 1 outlet, 2 pengguna, kasir, stok dasar, transaksi, laporan dasar |
| POS Growth | Toko berkembang | Rp129.000–199.000/bulan | 1–3 outlet, lebih banyak kasir, pembelian, retur, loyalty, laporan lanjutan, offline sync |
| POS Business | Retail/multi-outlet | Rp299.000–499.000/bulan | multi-outlet lebih luas, akses granular, analitik, audit, prioritas dukungan |
| Add-on outlet | Merchant multi-outlet | Rp25.000–75.000/outlet/bulan | outlet tambahan sesuai batas paket |

### Aturan monetisasi

- Sediakan **trial POS 14 atau 30 hari** setelah merchant aktif.
- Saat trial berakhir, blokir operasi POS baru secara bertahap, tetapi jangan menghapus data.
- Izinkan merchant melihat dan mengekspor data historis setelah suspend.
- Data marketplace tetap aktif selama merchant memenuhi aturan marketplace.
- Jangan menjual paket dengan kuota yang tidak jelas.
- Harga, periode tagihan, pajak, status pembayaran, grace period, dan suspend harus terlihat di halaman langganan.
- Perubahan harga hanya berlaku untuk periode berikutnya dan harus memberi notifikasi.
- Berikan diskon onboarding untuk desa, koperasi, atau program pemerintah secara terukur dan memiliki tanggal berakhir.

### Mesin monetisasi yang dapat dikonfigurasi admin

Admin/super admin boleh mengubah status gratis, berbayar, tarif, komisi, dan eligibility tanpa perubahan kode, tetapi semua aturan harus memiliki versi, tanggal efektif, scope, dan audit. Jenis monetisasi yang dapat digunakan:

| Sumber pendapatan | Cara kerja | Cocok untuk |
|---|---|---|
| Langganan POS | biaya bulanan berdasarkan outlet, pengguna, modul, atau kapasitas | semua merchant yang membutuhkan operasional toko |
| Komisi order | persentase dari nilai barang/jasa setelah aturan diskon yang ditentukan | barang, makanan, jasa, wisata |
| Biaya transaksi tetap | nominal per order atau booking | order bernilai kecil, booking jasa, tiket |
| Biaya lead/booking | biaya saat pelanggan mengirim request atau booking terkonfirmasi | jasa panggilan, fotografer, tukang, ojek wisata |
| Listing atau promosi | biaya untuk featured placement, kampanye, atau slot promosi | merchant yang ingin meningkatkan jangkauan |
| Add-on operasional | outlet, pengguna, printer, analitik, loyalty, atau dukungan prioritas | merchant POS dan merchant profesional |
| Layanan platform | biaya delivery, payment handling, escrow, atau proteksi tertentu | order yang memakai layanan tambahan platform |
| Program partner | paket khusus desa, koperasi, sponsor, atau institusi | akuisisi merchant dan distribusi lokal |

#### Model ojek: daftar dan ambil order gratis, bayar fee per batch

Ojek dapat bergabung dan menerima order tanpa subscription atau deposit di muka. Platform memperoleh pendapatan dari fee penggunaan yang hanya terbentuk setelah order selesai:

1. Admin membuat aturan aktif, misalnya `fee_rate = 5%`, `batch_size = 5 order`, dan masa akses setelah batch dibayar.
2. Ojek mendaftar gratis, menyelesaikan verifikasi provider, lalu dapat menerima order sesuai area dan kapasitasnya.
3. Setiap order yang berstatus selesai mencatat fee pada **usage fee ledger**. Order yang dibatalkan sebelum selesai tidak dihitung sebagai order berbayar.
4. Setelah lima order selesai, sistem menutup satu batch dan menerbitkan tagihan/ringkasan yang dapat dibayar oleh ojek.
5. Pembayaran batch memperpanjang entitlement menggunakan platform atau membuka batch berikutnya sesuai aturan admin.
6. Sebelum jatuh tempo, ojek tetap melihat order, pendapatan, fee, dan sisa kuota batch secara transparan. Setelah grace period berakhir, order baru dapat dihentikan sementara tanpa menghapus histori atau saldo yang sah.

**Contoh perhitungan:**

| Komponen | Nilai |
|---|---:|
| Order selesai | 5 |
| Nilai per order | Rp50.000 |
| Total nilai order | Rp250.000 |
| Fee platform | 5% per order |
| Fee per order | Rp2.500 |
| Total fee batch | **Rp12.500** |
| Pendapatan kotor ojek setelah fee platform | Rp237.500 |

Fee dihitung per order lalu dijumlahkan pada batch, bukan diperkirakan dari total secara tidak transparan. Jika tarif, ukuran batch, minimum fee, atau masa akses berubah, aturan baru hanya berlaku untuk order berikutnya/batch berikutnya. Refund, koreksi, atau sengketa membuat adjustment ledger yang dapat diaudit; sistem tidak boleh menagih fee dua kali.

Model ini menjaga hambatan masuk tetap rendah bagi ojek, tetapi mencegah akses gratis tanpa batas. Ojek membayar setelah memperoleh pendapatan, sedangkan platform mendapat pendapatan berulang dari aktivitas nyata. Pola yang sama dapat digunakan untuk jasa panggilan atau provider lain yang lebih cocok membayar berdasarkan order selesai daripada subscription bulanan.

#### Pengaman anti-akun ganda dan order fiktif

Gratis di muka tidak boleh berarti bebas membuat akun tanpa batas. Pengaman harus berlapis dan tetap menyediakan jalur banding:

- verifikasi identitas provider, nomor telepon, email, dan untuk ojek data kendaraan/izin yang relevan;
- satu identitas terverifikasi hanya memiliki satu provider aktif, kecuali akun fleet atau akun perusahaan yang disetujui;
- instrumen payout, nomor kendaraan, dan identifier penting ditandai sebagai sudah terhubung; data sensitif disimpan terbatas/terlindungi, bukan ditampilkan ke admin umum;
- sinyal perangkat, lokasi, jaringan, dan pola pendaftaran boleh dipakai sebagai sinyal risiko, tetapi tidak boleh menjadi satu-satunya alasan pemblokiran;
- deteksi self-order, buyer dan provider yang berulang dalam pola tidak wajar, rute/impossible travel, penyelesaian terlalu cepat, pembatalan terkoordinasi, order berputar, dan eksploitasi promo;
- fee batch hanya dihitung dari order yang lolos aturan validasi dan fulfillment; order berisiko dapat ditahan untuk review sebelum masuk batch final;
- akun yang ditutup tidak boleh langsung membuat akun baru untuk mengulang masa gratis; identity link, cooldown, dan proses banding harus dicatat;
- admin dapat menggabungkan akun duplikat, menahan batch, menonaktifkan provider, atau memulihkan akses melalui action resmi dengan alasan dan audit;
- model risiko harus memiliki false-positive review, notifikasi yang tidak membocorkan rule sensitif, dan jalur banding agar provider sah tidak kehilangan penghasilan tanpa pemeriksaan.

#### Dimensi aturan tarif

Mesin tarif harus dapat menentukan aturan berdasarkan:

- kategori atau template usaha;
- kanal order: marketplace, POS, QR meja, booking, atau rental;
- merchant, tier merchant, wilayah, partner, atau program subsidi;
- nilai order, jenis pembayaran, biaya delivery, dan status fulfillment;
- tanggal efektif, masa promosi, minimum fee, maksimum fee, ukuran batch, masa akses, grace period, dan kuota;
- siapa yang menanggung biaya: merchant, pelanggan, partner, atau dibagi.

Tarif tidak boleh dihitung ulang secara berbeda di layar, checkout, payout, dan laporan. Saat order dibuat, sistem menyimpan snapshot harga, komisi, pajak, diskon, biaya layanan, dan net payout yang berlaku pada saat itu.

#### Admin boleh mengubah gratis menjadi berbayar, dengan guardrail

Fleksibilitas bisnis penting, tetapi perubahan mendadak dapat merusak kepercayaan dan membuat dispute. Setiap perubahan monetisasi harus:

1. dibuat sebagai aturan baru dengan tanggal efektif di masa depan;
2. menampilkan simulasi dampak terhadap merchant, pelanggan, GMV, dan payout;
3. tidak mengubah order, booking, sewa, atau transaksi yang sudah dibuat;
4. memberi notifikasi dan ringkasan biaya sebelum berlaku;
5. memiliki masa transisi atau grandfathering bila dampaknya besar;
6. memiliki owner, alasan, approval, dan audit trail;
7. dapat di-rollback atau diganti dengan aturan koreksi tanpa menghapus histori;
8. menampilkan rincian fee secara jelas sebelum checkout dan pada laporan payout.

Dengan aturan ini, admin dapat mengubah Marketplace dari gratis menjadi berkomisi, membuat kategori tertentu berbayar, atau menguji tarif baru kapan saja secara bisnis—tanpa merusak transaksi yang sedang berjalan.

#### Rekomendasi tahap monetisasi

1. Awali marketplace dengan akses gratis dan fee rendah atau nol untuk kategori prioritas agar supply tumbuh.
2. Ukur order sukses, biaya support, fraud, payment, delivery, dan payout sebelum menetapkan take rate.
3. Terapkan komisi atau biaya booking pada kategori yang sudah menghasilkan nilai nyata.
4. Monetisasi POS berdasarkan penghematan operasional, bukan dengan mengunci inbox marketplace.
5. Tambahkan featured listing dan layanan premium setelah pencarian organik serta kualitas katalog cukup sehat.

### Settlement, payout, dan dispute lintas vertikal

Settlement tidak boleh memakai satu aturan untuk semua kategori:

- **Barang:** payout setelah fulfillment atau delivery berhasil dan periode komplain yang ditentukan.
- **Makanan/minuman:** payout setelah order selesai; pembatalan sebelum diproses mengikuti kebijakan merchant.
- **Jasa:** payout setelah provider menandai selesai dan pelanggan atau timer penyelesaian mengonfirmasi.
- **Sewa:** deposit ditahan sampai aset kembali dan pemeriksaan kerusakan selesai.
- **Ojek:** payout pendapatan order dicatat setelah perjalanan selesai; fee platform dicatat per order dan ditagihkan saat batch mencapai ukuran yang ditentukan.
- **Wisata:** payout setelah jadwal atau perjalanan selesai, dengan aturan no-show dan pembatalan.

Semua kategori tetap membutuhkan fee ledger, payout ledger, refund, dispute, adjustment, dan audit yang dapat direkonsiliasi. Platform tidak boleh menganggap order berhasil sebagai pendapatan bersih sebelum kewajiban kepada merchant, provider, pelanggan, pajak, dan partner dihitung.

### Kontrak usage fee ojek

Usage fee ojek harus dipisahkan dari pendapatan perjalanan:

- `gross_fare`: nilai perjalanan yang dibayar pelanggan;
- `provider_earnings`: pendapatan kotor provider sebelum fee platform;
- `platform_fee`: persentase atau nominal yang diambil platform;
- `batch_id`: kelompok order yang ditagihkan bersama;
- `fee_status`: `accrued`, `invoiced`, `paid`, `grace`, `disputed`, atau `waived`;
- `access_status`: `active`, `grace`, `restricted`, `suspended`, atau `under_review`.

Order selesai hanya boleh menghasilkan satu fee melalui idempotency key. Pembayaran batch tidak boleh mengubah nilai perjalanan lama; pembayaran hanya menyelesaikan kewajiban fee dan memperbarui entitlement provider. Admin perlu dapat memberi waiver atau koreksi terbatas dengan approval, alasan, dan audit.

### Trial dan grace period

Alur yang disarankan:

1. Merchant yang disetujui memilih “Coba POS”.
2. Admin/super admin mengaktifkan entitlement trial.
3. Merchant menyelesaikan setup usaha, outlet, produk, dan kasir.
4. H-7 dan H-1, sistem mengirim pengingat.
5. Saat jatuh tempo, masuk **grace period 3–7 hari**.
6. Selama grace period, transaksi masih dapat berjalan dengan peringatan.
7. Setelah suspend:
   - transaksi POS baru dihentikan;
   - data dan laporan tetap dapat dibaca;
   - export tetap tersedia;
   - marketplace tetap mengikuti status marketplace;
   - reaktivasi tidak boleh menggandakan tenant, outlet, atau produk.

Struktur yang sudah ada (`pos_subscriptions`, status tenant POS, trial, entitlement activation, dan enabled modules) dapat menjadi fondasi alur ini.

---

## 5. Arsitektur bisnis: satu katalog, dua kanal, satu ledger stok

### Sumber kebenaran yang direkomendasikan

Untuk seluruh merchant, **Katalog Merchant** adalah tempat membuat dan mengelola produk master:

- identitas produk, foto, kategori, SKU, barcode, varian, dan informasi jual dibuat dari katalog Merchant;
- merchant tanpa POS menggunakan katalog tersebut langsung untuk halaman marketplace dan pesanan online;
- inbox pesanan marketplace tidak boleh membutuhkan `pos_tenant`, subscription POS, atau status operasional POS.

Untuk merchant yang memakai POS:

- **Produk master:** identitas produk, SKU, barcode, varian, harga dasar, dan HPP.
- **POS catalog projection:** salinan operasional yang menunjuk kembali ke produk master Merchant; bukan produk baru yang dibuat ulang.
- **POS stock:** stok fisik per outlet; ini sumber kebenaran operasional.
- **Marketplace stock:** projection dari stok POS yang tersedia untuk dijual online.
- **Reservation ledger:** reservasi stok online yang sedang menunggu pembayaran/konfirmasi.
- **Sales ledger:** transaksi POS dan transaksi marketplace yang sudah final.
- **Cash/payment ledger:** pembayaran aktual, settlement, retur, dan mutasi kas.

Untuk merchant marketplace-only:

- katalog dan stok marketplace tetap dapat berjalan tanpa tenant POS.
- Jika merchant kemudian berlangganan POS, produk yang sama harus diproyeksikan atau di-link secara terkontrol ke katalog/stok POS.
- Sistem tidak boleh membuat produk duplikat hanya karena merchant mengaktifkan POS.

### Aturan penting integrasi katalog

1. Satu produk memiliki satu identitas lintas kanal.
2. SKU dan barcode harus unik di dalam tenant, kecuali ada aturan varian yang jelas.
3. Perubahan produk di marketplace harus menjelaskan apakah perubahan itu juga memengaruhi POS.
4. Produk yang sudah terhubung POS tidak boleh mengubah stoknya dari dua tempat.
5. Harga online dan harga toko boleh berbeda, tetapi sumber aturan harga harus terlihat.
6. Nonaktif di marketplace tidak boleh otomatis menghapus histori POS.
7. Unlink produk memerlukan konfirmasi dan aturan stok yang jelas.
8. Setiap kegagalan sinkronisasi harus terlihat oleh merchant dan dapat direkonsiliasi.
9. Status subscription POS tidak boleh menjadi syarat untuk membuat produk atau menerima order marketplace.
10. Katalog yang belum diproyeksikan ke POS tetap sah untuk marketplace dan tidak boleh dianggap gagal hanya karena merchant belum memilih POS.

Fondasi projection `pos_stock` ke `products.stock`, mapping `pos_marketplace_sync`, dan reservasi stok marketplace sudah searah dengan prinsip ini. Yang perlu dipastikan selanjutnya adalah idempotensi, monitoring, dan pengalaman merchant ketika mapping gagal.

### Kontrak kanal pesanan

- **Marketplace order:** dibuat dari toko publik atau marketplace, tidak membutuhkan POS, dan masuk ke inbox pesanan Merchant gratis.
- **POS sale:** dibuat oleh kasir atau alur operasional POS, membutuhkan entitlement POS aktif dan outlet yang valid.
- **Table order:** dibuat setelah QR meja POS berhasil diverifikasi; memakai toko/katalog yang sama, tetapi membawa konteks meja dan outlet.

Ketiga kanal tersebut boleh menggunakan produk master dan ledger stok yang sama, tetapi sumber order, hak akses, status fulfillment, dan metriknya harus dapat dibedakan. Menonaktifkan POS hanya menghentikan POS sale dan table order baru; marketplace order tetap diterima sesuai aturan marketplace.

---

## 6. POS Offline-First dan Cara Kerja Online

### Keputusan offline

POS **boleh digunakan offline**, tetapi tidak semua operasi boleh dilakukan tanpa koneksi. Batasan ini diperlukan agar merchant tetap bisa berjualan tanpa memberi kesempatan pada transaksi ganda, stok negatif, atau laporan palsu.

| Operasi | Saat offline | Aturan |
|---|---|---|
| Membuka layar kasir | Boleh | Harus memakai tenant, outlet, dan user yang sudah tersimpan di perangkat |
| Melihat katalog | Boleh | Menampilkan waktu terakhir sinkronisasi dan status data stale |
| Penjualan tunai | Boleh | Masuk antrean lokal dengan idempotency key |
| Cetak struk | Boleh | Struk diberi penanda offline/pending bila belum tersinkron |
| Hold/resume bill | Boleh | Hanya pada perangkat dan outlet yang sama |
| Pembayaran QRIS/transfer online | Tidak | Memerlukan validasi provider/server |
| Order marketplace | Tidak | Marketplace memerlukan koneksi dan reservation server |
| Perubahan harga massal | Tidak | Harus online dan memiliki otorisasi |
| Penyesuaian stok besar | Tidak | Harus online agar tercatat atomic dan diaudit |
| Tutup shift final | Sebaiknya online | Dapat membuat draft offline, tetapi finalisasi memerlukan rekonsiliasi |
| Laporan final | Tidak | Offline hanya menampilkan ringkasan lokal sementara |

### Syarat agar offline aman

- Cache katalog dan stok dipisahkan berdasarkan `tenant_id` dan `outlet_id`.
- Cache memiliki waktu kedaluwarsa dan indikator “terakhir diperbarui”.
- Setiap transaksi offline memiliki ID unik yang tidak berubah saat retry.
- Transaksi tidak boleh dikirim dua kali ketika perangkat reconnect atau halaman dibuka ulang.
- Harga dan status produk divalidasi ulang oleh server saat sinkronisasi.
- Transaksi offline tidak boleh memaksa stok server menjadi negatif.
- Semua konflik masuk ke daftar yang bisa ditinjau merchant, bukan hilang atau otomatis diabaikan.
- Queue lokal harus dibersihkan secara aman setelah transaksi benar-benar tersimpan di server.
- Perangkat yang logout, hilang, atau berganti outlet tidak boleh membaca antrean tenant/outlet lain.
- Data lokal sensitif perlu dilindungi dan memiliki kebijakan penghapusan perangkat.

Fondasi proyek saat ini sudah mengarah ke model ini melalui cache katalog per tenant/outlet, antrean transaksi lokal, `processAtomicPOSSale`, serta sinkronisasi ketika koneksi kembali. Fondasi tersebut perlu diselesaikan dengan rekonsiliasi konflik, indikator stale data, pemulihan perangkat, dan pengujian kehilangan koneksi sebelum dipasarkan sebagai offline POS.

### Saat online

Alur POS:

1. Kasir memilih produk dari katalog tenant dan outlet aktif.
2. Server memvalidasi harga, diskon, pajak, stok, hak kasir, dan status subscription.
3. Checkout atomic membuat transaksi, item, pengurangan stok, dan audit.
4. Jika produk terhubung marketplace, projection stok diperbarui.
5. Jika ada order marketplace, reservation ledger mencegah overselling.

Alur marketplace:

1. Pembeli melihat projection stok yang tersedia.
2. Saat checkout, server membuat reservation dengan expiry.
3. Pembayaran/konfirmasi menentukan apakah reservation dikonsumsi atau dilepas.
4. Order marketplace tidak boleh hanya mengandalkan angka stok dari browser.

Alur order meja:

1. Merchant POS membuat QR untuk outlet dan meja yang aktif.
2. Pelanggan memindai QR dan server memverifikasi token tenant, outlet, meja, serta status POS.
3. Pelanggan melihat katalog toko yang sama dalam konteks meja.
4. Saat checkout, server membuat reservation dan order dengan sumber `table_qr`.
5. POS/outlet menerima order meja melalui inbox operasional yang sesuai; status meja tidak mengubah perilaku toko publik.

### Saat offline

Offline hanya untuk operasi yang memang aman ditunda:

- transaksi kasir lokal;
- pembayaran tunai;
- cetak struk lokal;
- membaca katalog dan stok cache;
- menyimpan antrean transaksi terenkripsi/terisolasi per tenant dan outlet.

Offline tidak boleh mengklaim secara langsung bahwa:

- pembayaran online sudah berhasil;
- stok marketplace sudah berkurang;
- settlement sudah terjadi;
- order marketplace sudah diterima;
- laporan keuangan final sudah tersinkron.

### Saat tersambung kembali

1. Cek identitas tenant, outlet, dan kasir.
2. Kirim transaksi berdasarkan idempotency key.
3. Server memvalidasi harga dan aturan saat transaksi dibuat.
4. Jika harga/produk berubah, tandai konflik; jangan diam-diam mengubah total.
5. Jika stok online dan offline berbenturan, gunakan aturan server dan tampilkan konflik.
6. Simpan status `queued`, `synced`, `failed`, atau `conflict`.
7. Merchant dapat melihat dan menyelesaikan konflik.
8. Setelah sync, projection marketplace dijalankan ulang dan hasilnya dicatat.

Implementasi antrean offline dan `processAtomicPOSSale` sudah menyediakan arah teknis yang baik. Sebelum dianggap siap komersial, tambahkan rekonsiliasi konflik, batas umur cache, indikator stale data, dan prosedur pemulihan perangkat rusak/hilang.

### Kebijakan konflik stok

Prioritas yang disarankan:

1. Transaksi online yang sudah memiliki reservation valid.
2. Transaksi POS yang sudah tersimpan server.
3. Transaksi offline yang baru diantrekan.

Transaksi offline yang datang terlambat tidak boleh memaksa stok menjadi negatif. Sistem harus menandainya sebagai konflik untuk keputusan merchant, misalnya:

- batalkan item;
- ganti jumlah;
- ubah menjadi hutang/pesanan;
- tandai sebagai transaksi manual yang perlu rekonsiliasi.

---

## 7. Peran admin dan super admin

### Admin operasional

- menyetujui dan menonaktifkan merchant;
- mengatur kuota marketplace;
- mengelola paket, harga, trial, grace period, dan modul;
- menangani refund/kompensasi sesuai kewenangan;
- melihat kegagalan sinkronisasi;
- membantu onboarding dan support.

### Super admin

- mengubah katalog paket dan harga;
- memberi override entitlement dengan alasan dan tanggal berakhir;
- mengatur rule global marketplace;
- mengelola admin dan audit;
- melihat metrik pendapatan, churn, penggunaan, dan kesehatan sinkronisasi;
- menyetujui kebijakan diskon desa/koperasi;
- tidak mengubah histori transaksi secara langsung.

### Guardrail admin

Setiap perubahan berikut wajib memiliki actor, alasan, waktu, nilai sebelum, nilai sesudah, dan expiry bila relevan:

- perubahan harga paket;
- pemberian trial/discount/override;
- suspend/reaktivasi POS;
- perubahan kuota merchant;
- koreksi saldo;
- perubahan rekening payout;
- pembatalan atau koreksi transaksi.

### Panel admin yang disarankan

Dashboard admin sebaiknya menjadi **control tower operasional**, bukan hanya halaman KPI. Admin perlu dapat melihat antrean yang membutuhkan tindakan, dampak bisnisnya, dan siapa yang bertanggung jawab:

1. **Lifecycle merchant**
   - antrean pendaftaran, verifikasi identitas/usaha, aktivasi, merchant yang belum memasang produk, dan merchant yang belum menerima order pertama;
   - checklist onboarding dan alasan merchant berhenti di setiap tahap;
   - kemampuan meminta perbaikan data tanpa menghapus draft merchant.
2. **Moderasi katalog dan toko**
   - review foto, kategori, harga tidak wajar, produk terlarang, duplikasi, dan konten spam;
   - status `draft`, `pending_review`, `published`, `rejected`, `suspended` dengan alasan yang dapat dipahami merchant;
   - bulk action harus memiliki preview, batas scope, dan audit.
3. **Order control tower**
   - order baru yang belum diterima, terlambat diproses, dibatalkan, direfund, atau berpotensi sengketa;
   - filter berdasarkan kanal marketplace, POS, dan QR meja;
   - admin membantu perubahan status melalui action resmi, bukan mengedit histori transaksi langsung.
4. **Entitlement dan billing POS**
   - trial yang akan berakhir, pembayaran tertunda, grace period, suspend, reaktivasi, limit outlet/pengguna, dan add-on;
   - setiap override wajib memiliki alasan, tanggal mulai, tanggal berakhir, dan actor.
5. **Usage fee provider dan akses platform**
   - jumlah order selesai, batch berjalan, fee terakumulasi, tagihan, grace period, pembayaran, dan akses provider;
   - admin dapat mengatur fee per kategori, ukuran batch, minimum/maksimum fee, masa akses, waiver, dan status review;
   - sistem menampilkan simulasi dampak sebelum aturan diterbitkan dan tidak boleh menagih fee dua kali.
6. **Category and pricing builder**
   - admin dapat membuat/mengarsipkan kategori dan subkategori;
   - admin memilih template listing, atribut wajib, tipe order, fulfillment, SLA, aturan pembatalan, dan status moderasi;
   - admin mengatur paket gratis/berbayar, komisi, biaya tetap, minimum/maksimum fee, siapa yang menanggung biaya, dan tanggal efektif;
   - setiap perubahan memiliki preview dampak, approval, versi, dan rollback.
7. **Operasional outlet dan QR meja**
   - daftar tenant, outlet, meja, QR aktif, QR dicabut, dan order meja yang belum ditangani;
   - kemampuan menonaktifkan QR tertentu tanpa menutup toko publik atau menghapus histori.
8. **Payout, refund, dan dispute**
   - saldo tertahan, payout gagal, refund yang menunggu persetujuan, sengketa pembeli, dan aging penyelesaian;
   - aturan agar payout tidak dilepas sebelum order memenuhi status fulfillment dan periode risiko yang ditetapkan.
9. **Trust, abuse, dan keamanan**
   - lonjakan order palsu, refund berulang, akun merchant ganda, penggunaan promo yang tidak wajar, QR yang dipindai terlalu sering, dan login/perangkat mencurigakan;
   - flag risiko harus dapat ditinjau tanpa langsung menghapus data atau memblokir merchant secara permanen.
10. **Support dan insiden**
   - tiket dengan SLA, sinkronisasi gagal, stale projection, konflik POS offline, dan insiden pembayaran;
   - incident timeline, owner, status, komunikasi ke merchant, dan postmortem untuk masalah berulang.

### Pemisahan peran admin

Minimal gunakan pemisahan berikut:

- **Admin operasional:** onboarding, moderasi, order, support, dan monitoring sinkronisasi;
- **Admin keuangan:** payout, refund, kompensasi, dan rekonsiliasi saldo;
- **Admin produk/POS:** kategori, template listing, paket, modul, limit, trial, promo, fee engine, dan QR/table-order policy;
- **Super admin:** akses lintas area, approval tindakan berisiko, konfigurasi global, dan audit.

Refund besar, koreksi saldo, perubahan payout, penghapusan merchant, override entitlement, dan perubahan aturan tarif sebaiknya memakai **maker-checker**: satu admin mengajukan, admin lain yang berwenang menyetujui. Ini mengurangi risiko kesalahan tunggal tanpa memperlambat tindakan rutin.

### Alur merchant dan order yang disarankan

#### A. Onboarding marketplace gratis

1. Merchant mendaftar dan melengkapi profil usaha.
2. Merchant dapat membuat draft produk dan memperbaiki data sebelum publikasi.
3. Sistem memeriksa kualitas minimum dan aturan konten.
4. Produk yang lolos tampil di toko publik; merchant memperoleh checklist menuju order pertama.
5. Order masuk ke inbox marketplace merchant tanpa memerlukan tenant atau subscription POS.
6. Merchant menerima, menyiapkan, menyerahkan/mengirim, dan menyelesaikan order.
7. Setelah order selesai, sistem mengatur payout, ulasan, dan metrik merchant.

#### B. Konversi ke POS

1. Merchant menerima edukasi berbasis masalah, misalnya stok outlet, kasir, barcode, atau laporan; bukan dipaksa membayar untuk menerima order marketplace.
2. Merchant memilih trial atau paket POS.
3. Sistem memproyeksikan katalog Merchant ke POS tanpa membuat produk kedua.
4. Merchant menyelesaikan setup outlet, kasir, stok awal, dan bila perlu meja.
5. Aktivasi POS dihitung setelah setup selesai dan transaksi pertama berhasil, bukan hanya setelah subscription dibuat.

#### C. QR meja

1. Merchant POS membuat outlet, meja, dan QR yang aktif.
2. Pelanggan memindai QR; server membuat sesi konteks meja yang memiliki expiry.
3. Pelanggan memilih menu dari katalog Merchant yang sama.
4. Order diberi source `table_qr`, outlet, meja, dan status fulfillment yang jelas.
5. Outlet menerima dan memproses order; perubahan status terlihat oleh pelanggan bila fitur tersebut diaktifkan.
6. Sesi meja ditutup setelah order selesai, dibatalkan, atau melewati expiry; order lama tetap tersimpan.

#### D. POS berhenti berlangganan

1. Sistem mengirim peringatan sebelum trial atau grace berakhir.
2. Saat suspend, POS sale dan QR/table-order baru dihentikan sesuai kebijakan.
3. Marketplace tetap aktif: produk, toko, inbox order, fulfillment, dan histori tidak dihapus.
4. Merchant dapat membaca/mengekspor data dan mengaktifkan kembali POS tanpa duplikasi tenant, outlet, produk, atau order.

Alur ini membuat marketplace menjadi pintu masuk yang bernilai sejak hari pertama, sementara POS memiliki momen upgrade yang jelas ketika merchant sudah merasakan kebutuhan operasional.

---

## 8. KPI bisnis yang harus diukur

### Marketplace

- merchant aktif mingguan/bulanan;
- jumlah produk aktif;
- jumlah order berhasil;
- GMV marketplace;
- conversion rate halaman produk ke checkout;
- merchant activation rate;
- waktu dari pendaftaran ke produk pertama terbit;
- merchant yang menerima order pertama;
- acceptance rate dan fulfillment-on-time rate;
- cancellation, refund, dispute, dan repeat-order rate;
- umur payout tertunda dan payout failure rate;
- merchant yang tetap aktif setelah 30/90 hari.

### POS

- jumlah trial dimulai;
- activation rate: setup selesai dan transaksi pertama;
- trial-to-paid conversion;
- MRR/ARR;
- churn bulanan;
- jumlah transaksi per tenant;
- jumlah outlet dan kasir aktif;
- attach rate: merchant marketplace yang membeli POS;
- penggunaan modul berbayar;
- QR scan-to-order conversion dan table-order completion rate;
- persentase merchant POS yang memakai lebih dari satu modul;
- waktu dari signup sampai transaksi pertama.

### Multi-vertikal dan monetisasi

- merchant aktif per kategori dan template;
- waktu dari onboarding ke listing/order pertama per kategori;
- GMV, jumlah order, booking, rental, dan jasa selesai per kategori;
- gross take rate, net take rate, revenue platform, dan contribution margin per kategori;
- biaya pembayaran, support, refund, fraud, delivery, dan payout per kategori;
- average order value, repeat order, cancellation, no-show, dan dispute per kategori;
- provider ojek terverifikasi, aktif, menyelesaikan order pertama, dan menyelesaikan batch;
- total fee ojek terakumulasi, fee tertagih, fee tertunda, batch gagal bayar, dan collection rate;
- provider yang masuk grace/restricted/under review serta waktu pemulihan akses;
- duplicate-account rate, self-order rate, false-positive rate, dan kerugian fraud;
- conversion dari marketplace gratis ke POS, featured listing, atau layanan berbayar;
- fee rule yang aktif, merchant terdampak perubahan tarif, dan hasil eksperimen harga;
- jumlah merchant yang menerima fee baru dengan sukses versus yang churn atau mengajukan dispute.

### Kesehatan operasional

- persentase sync sukses;
- jumlah konflik offline;
- jumlah stock mismatch;
- checkout failure rate;
- waktu pemulihan saat POS offline;
- selisih kas saat tutup shift;
- refund/retur rate;
- laporan yang gagal generate/export.
- waktu antrean approval merchant dan moderasi katalog;
- waktu penyelesaian dispute dan tiket berdasarkan SLA;
- jumlah QR/table order invalid atau berulang;
- jumlah merchant marketplace yang terdampak insiden POS.
- jumlah listing pending moderasi dan umur antreannya;
- jumlah perubahan tarif tanpa approval atau tanpa notifikasi;
- payout tertahan berdasarkan alasan dan umur;
- dispute terbuka berdasarkan kategori, status, dan SLA;
- kategori dengan order tinggi tetapi margin kontribusi negatif.

**North Star metric yang disarankan:** merchant aktif yang berhasil mencatat transaksi valid pada bulan berjalan, dengan kanal marketplace atau POS. Jumlah signup saja tidak cukup.

**Guardrail metric yang wajib dipantau:** cancellation rate, refund/dispute rate, payout aging, fulfillment terlambat, stock mismatch, dan merchant yang kehilangan akses marketplace karena kesalahan status POS.

---

## 9. Roadmap implementasi

### 9.0 Urutan fase dan status pekerjaan

Gunakan urutan ini sebagai sumber kebenaran kerja. Status **selesai** di bawah berarti implementasi atau keputusan sudah tersedia di repository; status tersebut **belum berarti lulus staging, siap pilot, atau siap produksi**.

1. **Fase 0 — Keputusan produk dan aturan komersial — SELESAI DI REPOSITORY**
   - [x] aturan marketplace gratis, trial, POS berbayar, grace, suspend, refund, upgrade, dan downgrade;
   - [x] batas katalog bersama, quota marketplace, QR meja, multi-vertikal, pricing, FAQ, dan KPI;
   - [ ] sign-off bisnis/legal/finance dan validasi keputusan pada environment staging.

2. **Fase 1 — Entitlement dan billing — SELESAI DI REPOSITORY**
   - [x] entitlement server-side, lifecycle trial/paid/grace/suspended/cancelled, role, audit, export, dan reaktivasi;
   - [x] marketplace tetap terpisah dari subscription POS;
   - [ ] penerapan migration, payment provider, webhook, expiry, retry, dan rekonsiliasi di staging.

3. **Fase 2 — Katalog, stok, inbox marketplace-only, dan QR meja — SEBAGIAN SELESAI DI REPOSITORY**
   - [x] mapping katalog, SKU/barcode tenant-scoped, stok outlet/varian, projection, reservation, rekonsiliasi, dan stale alert;
   - [x] marketplace-only tidak mensyaratkan `pos_tenant` atau subscription POS;
   - [x] menu publik, konteks meja, order QR, status order, source `table_qr`, dan reservation stock lifecycle;
   - [ ] template listing/state machine kategori, validasi concurrency, tenant isolation, meja invalid/nonaktif, revoke, dan recovery di staging.

4. **Fase 3 — POS online/offline — SEBAGIAN SELESAI DI REPOSITORY**
   - [x] cache tenant/outlet, queue, idempotency, retry, dead-letter, conflict center, checkpoint durable, dan simulasi recovery;
   - [x] kontrak receipt POS dipisahkan dari invoice marketplace;
   - [ ] uji device/PWA/printer nyata, konflik lintas kanal, dan recovery di staging/pilot.

5. **Fase 4 — Laporan dan rekonsiliasi — SELESAI DI REPOSITORY, BELUM LULUS STAGING**
   - [x] canonical report, payment/cash ledger, hutang/piutang atomic, posted journal, export, dan daily reconciliation;
   - [x] laporan pajak diberi label estimasi;
   - [ ] golden dataset, rekonsiliasi staging, dan sign-off finance.

6. **Fase 5 — Pertumbuhan dan monetisasi lanjutan — SEBAGIAN SELESAI DI REPOSITORY**
   - [x] limit outlet/pengguna, add-on, loyalty, analitik, printer, akuntansi, partner, promo onboarding, dan SLA support;
   - [ ] category builder, fee engine, fee snapshot, usage fee provider/ojek, wallet, risk scoring, payout hold, maker-checker, abuse flag, dan control tower.

7. **Fase 6 — Validasi staging dan pilot merchant — BELUM DIMULAI**
   - [ ] siapkan staging parity, secrets/config, Auth, webhook, Storage, Realtime, backup, dan rollback;
   - [ ] terapkan bundle Fase 2–5 dan jalankan test matrix permission, concurrency, security, performance, recovery, serta QR;
   - [ ] jalankan pilot merchant, ukur guardrail/KPI, dan buat keputusan go/no-go.

8. **Fase 7 — Partner, support, dan rollout — SEBAGIAN SELESAI DI REPOSITORY**
   - [x] partner program, redemption promo, SLA support, dan dashboard KPI;
   - [ ] rollout bertahap berdasarkan hasil pilot, incident response, rekonsiliasi dashboard, dan review 30/60/90 hari.

**Urutan kerja berikutnya:** mulai dari Fase 6, bukan membuat fitur baru. Fase 6 harus menerapkan dan menguji hasil Fase 2–5 secara berurutan sebelum Fase 7 rollout.

### Fase 0 — Keputusan produk dan aturan komersial — **SELESAI DI REPOSITORY**

**Tujuan:** semua pihak memahami perbedaan marketplace dan POS.

- [x] tetapkan definisi gratis, trial, active, grace, suspended, cancelled;
- [x] tetapkan paket awal dan harga uji;
- [x] tetapkan kuota marketplace;
- [x] tetapkan modul POS per paket;
- [x] tetapkan refund, upgrade, downgrade, dan grace period;
- [x] tetapkan marketplace tetap dapat upload produk dan menerima pesanan tanpa POS;
- [x] tetapkan POS sebagai pilihan berbayar yang memproyeksikan katalog Merchant, bukan membuat katalog kedua;
- [x] tetapkan QR meja sebagai fitur POS yang hanya aktif setelah scan dan validasi konteks meja;
- [x] tetapkan marketplace sebagai platform multi-vertikal dengan template kategori dan order;
- [x] tetapkan jenis monetisasi yang dapat dikonfigurasi per kategori, kanal, merchant, dan tanggal efektif;
- [x] tetapkan bahwa perubahan tarif tidak retroaktif dan harus menyimpan snapshot fee pada order;
- [x] buat halaman pricing dan FAQ;
- [x] sepakati KPI dan dashboard admin.

**Kriteria selesai:** admin dapat menjelaskan kapan merchant boleh memakai marketplace, kapan POS aktif, dan apa yang terjadi saat pembayaran terlambat.

**Status saat ini:** **Selesai secara teknis di repository.** Aturan produk dan harga uji terdokumentasi di halaman `/pricing`, FAQ menjelaskan lifecycle marketplace/POS, trial, grace, suspend, dan offline, sedangkan dashboard admin menampilkan North Star metric, activation rate, order completion, GMV periode, serta gap metrik billing yang belum memiliki agregat canonical. Harga di halaman diberi label harga uji dan belum dianggap konfigurasi produksi.

### Fase 1 — Entitlement dan billing yang dapat dipercaya — **SELESAI DI REPOSITORY**

**Tujuan:** akses berbayar tidak hanya dikontrol oleh frontend.

- [x] jadikan subscription/entitlement sebagai sumber izin server-side;
- [x] pisahkan status merchant marketplace dari status POS;
- [x] dukung trial, paid, grace, suspended, cancelled pada model entitlement POS;
- [x] simpan riwayat perubahan harga/paket;
- [x] pastikan suspend tidak menghapus data POS maupun marketplace;
- [x] sediakan export data subscription dan reaktivasi idempotent yang lengkap;
- [x] batasi operasi POS berdasarkan entitlement dan role;
- [x] tambahkan audit untuk override admin.

**Status saat ini:** **Selesai secara teknis di repository.** Perubahan yang sudah diterapkan:

- migration `19_20260907050000_pos_entitlement_lifecycle.sql` menambahkan `grace_ends_at`, status `grace`, resolver entitlement, dan validasi subscription pada `is_pos_tenant_active`;
- migration `20_20260907060000_pos_subscription_history_export_audit.sql` menambahkan snapshot riwayat paket/harga, export subscription, audit lifecycle admin, dan reaktivasi/approval idempotent;
- edit paket admin menggunakan RPC server-side atomik yang menyimpan alasan perubahan pada history dan audit log;
- merchant dapat mengunduh export data subscription dalam format JSON;
- jalur mutasi POS yang memakai guard tenant, termasuk checkout atomic, tidak lagi hanya mempercayai status tenant dari browser;
- approval/reactivation/extension admin mengatur kembali status tenant dan membersihkan masa tenggang;
- UI langganan menampilkan status masa tenggang dan tanggal akhirnya;
- marketplace tetap terpisah dari status operasional POS ketika POS suspended/cancelled.

**Kriteria selesai fase:** tercapai untuk implementasi teknis di repository. Migration database perlu diterapkan dan diuji di staging sebelum dinyatakan siap produksi.

### Fase 2 — Katalog terpadu dan sinkronisasi stok — **SEBAGIAN SELESAI DI REPOSITORY**

**Tujuan:** mencegah produk ganda dan overselling.

- [x] tetapkan mapping produk marketplace–POS;
- [x] gunakan satu SKU/barcode per tenant;
- [x] tampilkan status linked/synced/error di UI;
- [x] gunakan POS outlet stock sebagai sumber operasional merchant POS;
- [x] gunakan reservation ledger untuk order online;
- [x] buat rekonsiliasi manual dan otomatis;
- [x] tambahkan alert jika projection gagal;
- [x] tambahkan alert jika projection terlalu lama/stale;
- [x] selesaikan definisi stok varian dan multi-outlet.
- [x] pastikan inbox pesanan marketplace dapat digunakan tanpa `pos_tenant` atau entitlement POS;
- [x] implementasikan QR per outlet/meja dengan token yang scoped, dapat dicabut, dan tervalidasi server-side;
- [x] bedakan toko publik biasa dari table-order context; URL toko biasa tidak boleh mengaktifkan mode meja;
- [x] masukkan order meja ke pipeline reservation/stock yang sama dengan kanal lain, dengan source dan fulfillment state yang berbeda;
- [ ] dukung template listing dan atribut berbeda untuk produk, makanan, jasa, sewa, dan pengalaman;
- [ ] bedakan state machine order, booking, rental, dan service request tanpa menggandakan payment/dispute ledger;

**Status saat ini:** **Sebagian selesai secara teknis di repository.** Migration `21_20260907070000_pos_stock_reconciliation_alerts.sql` menambahkan alert projection durable, retry metadata, safe sync wrapper, dan RPC rekonsiliasi stok. Migration `22_20260907080000_pos_catalog_identity_stale_projection.sql` menambahkan keunikan SKU/barcode lintas produk-varian, validasi tenant/outlet/varian, dan deteksi alert stale berbasis umur. Bootstrap `23_20260907100000_pos_variant_outlet_stock_contract.sql` menetapkan identitas stok sebagai `(produk POS, varian POS opsional, outlet)`, mapping varian marketplace–POS, satu row stok per identitas/outlet, projection varian, dan allocation/reservation lintas outlet. Bootstrap `28_20260908140000_public_qr_menu_table_order.sql` menambahkan RPC menu publik, order meja anonim, status order tenant-scoped, validasi meja/produk/stok, serta source `table_qr`. Test kontrak aplikasi memverifikasi URL toko biasa tidak membawa konteks meja dan payload pelanggan tidak dapat memasok harga/status. Template listing/state machine kategori belum dikerjakan; migration, uji tenant isolation, invalid/nonaktif table, concurrency, dan recovery di staging masih terbuka.

**Kriteria selesai:** bagian katalog, stok, marketplace-only, dan QR tercapai untuk implementasi teknis di repository. Fase penuh belum selesai karena template listing/state machine kategori dan validasi staging belum dikerjakan.

### Fase 3 — POS online/offline yang aman — **SEBAGIAN SELESAI DI REPOSITORY**

**Tujuan:** kasir tetap dapat bekerja saat internet tidak stabil tanpa merusak ledger.

- [x] cache katalog per tenant/outlet;
- [x] queue transaksi offline dengan idempotency key;
- [x] validasi ulang di server saat sync;
- [x] deteksi dan tampilkan konflik harga, produk/stok, serta subscription melalui status conflict/dead-letter;
- [x] tampilkan usia cache dan jumlah transaksi belum tersinkron;
- [x] sediakan retry, dead-letter/conflict queue, dan conflict center untuk rekonsiliasi manual;
- [x] uji recovery durable untuk perangkat/tab ditutup, browser refresh, listrik mati, dan koneksi putus di tengah checkout;
- [ ] jalankan uji fisik pada device/PWA staging dan pilot merchant;
- [x] bedakan receipt POS dengan invoice marketplace.

**Status saat ini:** **Sebagian selesai secara teknis di repository untuk alur offline dasar dan simulasi recovery.** Cache sekarang diganti sebagai snapshot tenant/outlet dan membawa varian beserta stok outlet; antrean menyimpan status `queued`, `syncing`, `failed`, `conflict`, atau `synced`, memakai lease agar klaim yang macet dapat dipulihkan, dan merangkum dead-letter/conflict untuk kasir. Checkout menulis checkpoint durable sebelum RPC, lalu memulihkannya ke queue dengan request key yang sama setelah tab/perangkat ditutup, refresh, listrik mati, atau koneksi putus. Test recovery mencakup keempat skenario tersebut dan memastikan transaksi yang sudah tersinkron tidak diputar ulang. Uji fisik device/PWA, printer, konflik lintas kanal, serta penerapan migration di staging belum dikerjakan.

**Kriteria selesai:** kasir dapat bekerja offline secara terbatas dan merchant selalu tahu transaksi mana yang sudah final dan mana yang masih menunggu sync.

### Fase 4 — Laporan yang layak dipercaya — **SELESAI DI REPOSITORY, BELUM LULUS STAGING**

**Tujuan:** merchant tidak mengambil keputusan dari angka yang salah.

- [x] samakan definisi omzet, diskon, pajak, retur, HPP, beban, dan settlement di kontrak laporan server-side;
- [x] gunakan payment ledger dan transaksi canonical sebagai dasar cashflow, tanpa menjumlahkan penjualan dua kali dari mutasi `sales_cash`;
- [x] hubungkan hutang/piutang ke pembayaran dan kas melalui RPC atomic dan mutasi kas canonical;
- [x] scope laporan berdasarkan tenant dan outlet aktif;
- [x] pastikan posting jurnal memvalidasi debit=kredit dan laporan mendeteksi jurnal tidak seimbang;
- [x] tandai laporan pajak sebagai estimasi sampai memenuhi kebutuhan resmi;
- [x] export laporan laba-rugi dan cashflow memakai state dataset yang sama dengan layar;
- [x] tambahkan snapshot audit dan rekonsiliasi harian yang menjelaskan selisih sesi, mutasi, pembayaran supplier, dan jurnal.

**Status saat ini:** **Selesai secara teknis di repository; siap diuji di staging.** Bundle `24_20260907110000_phase4_canonical_reporting.sql` dan `25_20260907130000_phase4_debt_reconciliation.sql` menyediakan kontrak laporan canonical tenant/outlet-scoped, pembayaran hutang/piutang atomic yang membuat mutasi kas, pembayaran supplier berdasarkan tanggal pembayaran aktual, jurnal posted server-side, dan snapshot rekonsiliasi harian. Halaman laba-rugi, cashflow, akuntansi, hutang/piutang, dan Kas memakai alur canonical tersebut. Laporan pajak tetap estimasi; bundle belum diterapkan dan rekonsiliasi nyata belum diuji di staging/production.

**Kriteria selesai:** merchant dapat menutup shift, merekonsiliasi kas, dan memahami mengapa angka laporan berbeda atau sama dengan saldo aktual. **Tercapai secara teknis di repository; status resmi tetap menunggu staging.**

### Fase 5 — Pertumbuhan dan monetisasi lanjutan — **SEBAGIAN SELESAI DI REPOSITORY**

**Status saat ini:** **Sebagian selesai secara teknis di repository; migration dan verifikasi staging masih terbuka.** Fase ini dimulai setelah fondasi Fase 4 dan menambahkan kontrol komersial yang dapat ditegakkan server-side, bukan sekadar label paket di UI.

- [x] paket multi-outlet;
- [x] add-on pengguna/kasir;
- [x] loyalty lanjutan;
- [x] analitik lanjutan;
- [x] integrasi printer/perangkat;
- [x] integrasi akuntansi setelah jurnal canonical stabil;
- [x] program partner desa/koperasi;
- [x] promo onboarding dengan expiry — admin dapat membuat kode partner berkuota, merchant dapat preview dan redeem satu kali, dan kode ditolak setelah expiry;
- [x] dukungan prioritas — tiket merchant paket prioritas mendapat target SLA 4 jam, tiket standar 24 jam, dan admin dapat melihat status SLA/overdue.
- [ ] category builder untuk template listing, atribut, fulfillment, SLA, dan kebijakan pembatalan;
- [ ] fee engine untuk komisi, biaya tetap, booking fee, featured listing, dan siapa yang menanggung biaya;
- [ ] simulasi dampak tarif sebelum publish serta snapshot fee pada setiap order/payout;
- [ ] usage fee ojek dengan batch order, invoice fee, grace period, dan perpanjangan entitlement;
- [ ] identity link dan risk scoring untuk mencegah akun provider ganda serta order fiktif;
- [ ] provider wallet/fee ledger yang memisahkan pendapatan perjalanan dari kewajiban fee platform;
- [ ] checklist onboarding merchant sampai produk pertama dan order pertama;
- [ ] control tower admin untuk antrean merchant, katalog, order, payout, dispute, entitlement, dan QR meja;
- [ ] maker-checker untuk refund besar, koreksi saldo, perubahan payout, penghapusan merchant, dan override entitlement;
- [ ] aturan payout berdasarkan fulfillment dan periode risiko yang dapat dikonfigurasi;
- [ ] flag abuse untuk order palsu, refund berulang, promo tidak wajar, dan QR yang disalahgunakan.

**Perubahan teknis yang sudah tersedia:** bundle `26_20260908100000_phase5_commercial_entitlements.sql` menambahkan limit `max_outlets` dan `max_users`, harga add-on pengguna, flag dukungan prioritas, konfigurasi diskon onboarding ber-expiry, tabel promosi onboarding, entitlement summary, serta RPC guard untuk membuat outlet dan pengguna. Bundle `27_20260908120000_partner_promotions_priority_support.sql` menambahkan preview dan redemption promo yang atomic/idempotent, pencatatan nominal asli dan diskon pada subscription, program partner desa/koperasi di admin, serta schema dan RPC SLA support. Form admin menampilkan paket dan promo partner; halaman langganan merchant menghitung harga setelah promo; tiket baru otomatis mendapat prioritas dan due time berdasarkan paket.

**Kriteria selesai sementara:** paket dapat menjelaskan kapasitas outlet/pengguna dan harga add-on, operasi create outlet/user menolak limit melalui RPC, promo partner memiliki redemption serta audit end-to-end, dan SLA support tersimpan pada tiket. Fase belum dinyatakan siap produksi sampai bundle diterapkan di staging dan alur pembayaran/add-on/support diuji.

### Fase 6 — Validasi staging dan pilot merchant — **BELUM DIMULAI**

**Status saat ini:** Belum dimulai; ini menjadi gate sebelum fitur pertumbuhan dipasarkan.

- [ ] terapkan bundle Fase 2–5 ke project Supabase staging;
- [ ] uji upgrade/downgrade paket, limit outlet/pengguna, add-on, dan promo expired;
- [ ] uji loyalty, analitik, printer, dan ekspor akuntansi pada merchant dengan data nyata sintetis;
- [ ] uji konflik lintas outlet dan pemulihan POS offline pada perangkat fisik;
- [ ] pilot minimal satu merchant dari barang retail, makanan/minuman, jasa terjadwal, dan jasa panggilan/sewa/wisata;
- [ ] uji template listing, booking slot, deposit sewa, no-show, pembatalan, dan settlement per kategori;
- [ ] uji perubahan marketplace gratis menjadi berkomisi dengan aturan efektif, notifikasi, snapshot fee, rollback, dan order lama;
- [ ] uji contoh ojek: 5 order selesai senilai Rp50.000/order, fee dinamis 5%, batch fee Rp12.500, dan akses batch berikutnya;
- [ ] uji refund, order dibatalkan, fee adjustment, pembayaran batch, grace period, dan pembatasan order baru;
- [ ] uji provider dengan identitas, kendaraan, payout account, perangkat, dan pola order yang terhubung;
- [ ] uji false positive, banding provider, waiver fee, merge akun, dan audit tindakan admin;
- [ ] hitung unit economics per kategori sebelum memperluas gelombang peluncuran;
- [ ] uji merchant marketplace-only: upload produk, order masuk, fulfillment, payout, refund, dan dispute tanpa tenant POS;
- [ ] uji transisi marketplace-only ke POS tanpa produk, tenant, outlet, atau histori order duplikat;
- [ ] uji suspend POS: marketplace tetap menerima order, sedangkan transaksi POS dan QR meja mengikuti kebijakan suspend;
- [ ] uji QR meja lintas outlet, QR dicabut, sesi expired, scan berulang, dan order yang sudah berjalan;
- [ ] uji approval maker-checker serta audit untuk refund, payout, moderasi, dan entitlement;
- [ ] jalankan pilot 10–20 merchant dan catat activation, transaksi pertama, sync success, konflik, serta churn awal;
- [ ] dokumentasikan rollback dan prosedur support.

### Fase 7 — Partner, dukungan, dan rollout bertahap — **SEBAGIAN SELESAI DI REPOSITORY**

**Status saat ini:** Sebagian selesai secara teknis di repository; rollout tetap menunggu Fase 6.

- [x] program partner desa/koperasi dengan eligibility, tanggal berakhir, kuota, dan audit redemption;
- [x] redemption promo onboarding yang idempotent dan tidak dapat dipakai lintas merchant;
- [x] dukungan prioritas berbasis paket dengan SLA 4 jam dan indikator overdue untuk admin;
- [x] dashboard attach rate, trial-to-paid, MRR, churn, dan kesehatan sync;
- [ ] rollout bertahap berdasarkan hasil pilot, bukan hanya halaman yang sudah tersedia.

Dashboard Fase 7 menggunakan subscription berstatus `PAID`, tenant POS yang memiliki `merchant_id`, dan RPC kesehatan integrasi sebagai sumber metrik. MRR dan churn tetap merupakan metrik operasional sampai migration diterapkan dan angka direkonsiliasi dengan pembayaran nyata di staging.

### 9.1 Matriks eksekusi Fase 0 — keputusan produk dan komersial

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F0.1 | Kunci gelombang vertikal pertama dan batas MVP tiap kategori | Decision register berisi kategori, persona, alur order, fulfillment, dan fitur yang ditunda | Product | — | Tidak ada fitur baru di sprint pilot yang belum masuk register |
| F0.2 | Validasi paket, harga uji, diskon, trial, grace, suspend, dan aturan downgrade | Price card, asumsi unit economics, simulasi skenario merchant kecil/multi-outlet | Product + Finance | F0.1 | Harga diberi label hipotesis dan dapat diubah tanpa deploy kode |
| F0.3 | Tetapkan policy payout, refund, dispute, cancellation, no-show, deposit, dan pajak estimasi | Policy matrix per kategori dengan escalation path dan owner | Operations + Finance | F0.1 | Tidak ada status order tanpa policy penyelesaian |
| F0.4 | Tetapkan privacy, consent, KYC/provider verification, retensi, penghapusan, dan akses admin | Data inventory, retention schedule, terms/privacy checklist | Privacy/Legal owner | F0.1 | Data yang dikumpulkan memiliki tujuan dan masa simpan |
| F0.5 | Kunci metric dictionary dan event contract | Definisi North Star, guardrail, funnel, timezone, dedupe key, source of truth | Product/Data | F0.1–F0.3 | Angka yang sama dapat direkonsiliasi antar dashboard dan export |
| F0.6 | Rilis pricing, FAQ, dan runbook komunikasi perubahan tarif | Halaman publik, FAQ, template notifikasi, approval record | Product + Operations | F0.2–F0.4 | Merchant dapat memahami biaya dan perubahan sebelum berlaku |

**Go/no-go Fase 0:** scope, policy uang, policy data, metric dictionary, owner, dan kriteria pilot telah disetujui. Tanpa keputusan ini, pekerjaan teknis hanya boleh berupa spike non-produksi.

### 9.2 Matriks eksekusi Fase 1 — entitlement dan billing

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F1.1 | Susun release bundle migration/ bootstrap beserta urutan dan checksum | Release manifest, dry-run log, backup point, rollback note | Backend/DBA | F0 selesai | Bundle dapat diterapkan ulang pada staging kosong dan staging berisi data |
| F1.2 | Uji state machine trial → paid → grace → suspended/cancelled | Skenario transisi, expiry, retry, reaktivasi, dan idempotensi | Backend + QA | F1.1 | Tidak ada akses POS tanpa entitlement valid |
| F1.3 | Verifikasi payment provider, webhook, signature, retry, duplicate event, dan rekonsiliasi | Webhook test report dan payment reconciliation report | Finance/Payments | F0.3, F1.1 | Status pembayaran server-side konsisten dengan ledger |
| F1.4 | Uji pemisahan marketplace dan POS saat suspend/cancel | E2E evidence: marketplace tetap aktif, POS dibatasi sesuai policy | QA + Product | F1.2 | Tidak ada produk/order marketplace yang terhapus atau tertutup |
| F1.5 | Uji audit, export, override, approval, dan reaktivasi admin | Audit sample, export fixture, approval record | Operations + Security | F1.2 | Tindakan berisiko dapat ditelusuri dan tidak menggandakan data |

**Go/no-go Fase 1:** staging menolak akses POS yang tidak sah, menerima lifecycle yang sah, mencatat setiap perubahan uang/entitlement, dan membuktikan marketplace tidak ikut terkunci.

### 9.3 Matriks eksekusi Fase 2 — katalog, stok, dan kanal order

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F2.1 | Seed dan validasi mapping produk, varian, SKU/barcode, outlet, dan source of truth | Fixture multi-tenant/multi-outlet serta mapping report | Backend/DBA | F1.1 | Tidak ada identitas produk ganda atau scope tenant bocor |
| F2.2 | Uji reservation, projection, expiry, retry, stale alert, dan rekonsiliasi | Conflict matrix dan hasil before/after reconciliation | Backend + QA | F2.1 | Tidak ada overselling pada skenario konkurensi yang disepakati |
| F2.3 | Selesaikan inbox marketplace-only tanpa `pos_tenant`/entitlement POS | E2E merchant marketplace-only dari upload hingga fulfillment/payout/dispute | Marketplace owner | F0.1, F1.4 | POS tidak menjadi syarat order marketplace |
| F2.4 | Implementasikan QR outlet/meja dan konteks table-order yang dapat dicabut | Token scope test, expiry/revoke test, audit, source `table_qr` | POS owner + Security | F2.1–F2.2 | URL toko biasa tidak dapat mengaktifkan mode meja |
| F2.5 | Implementasikan template listing dan state machine kategori prioritas | Contract per kategori untuk listing, order/booking, fulfillment, cancel, settlement | Product + Backend | F0.1, F0.3 | Kategori tidak dipaksa memakai state machine yang salah |
| F2.6 | Tampilkan error mapping/sync kepada merchant dan admin | UI evidence, alert ownership, retry/reconcile runbook | Operations + Frontend | F2.2 | Kegagalan tidak hilang atau hanya tercatat di log |

**Go/no-go Fase 2:** mapping, reservation, projection, inbox marketplace-only, QR, dan kategori prioritas lulus test tenant isolation, concurrency, permission, dan recovery di staging.

### 9.4 Matriks eksekusi Fase 3 — POS online/offline

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F3.1 | Tetapkan matriks device/browser/PWA/printer dan batas operasi offline | Compatibility matrix, supported/unsupported list, merchant notice | POS owner | F2.1 | Pilot hanya memakai kombinasi device yang didukung |
| F3.2 | Uji queue, idempotency, lease, retry, dead-letter, dan conflict center | Test report untuk retry/duplicate/timeout/refresh | Backend + QA | F2.2 | Tidak ada transaksi ganda atau queue tenant lain terbaca |
| F3.3 | Uji device crash, tab close, refresh, listrik mati, logout, dan pergantian outlet | Recovery evidence dengan request key dan status final | QA + POS owner | F3.2 | Kasir dapat membedakan final, pending, failed, dan conflict |
| F3.4 | Uji konflik lintas kanal dan aturan stok negatif | Scenario report: reservation vs online POS vs offline sale | Backend + Operations | F2.2, F3.2 | Konflik masuk ke jalur keputusan merchant, bukan hilang |
| F3.5 | Verifikasi receipt offline/pending dan kontrak print bridge | Receipt samples, reprint/idempotency evidence, failure runbook | POS owner | F3.1 | Receipt tidak mengklaim payment/settlement yang belum final |
| F3.6 | Lindungi cache lokal dan tetapkan kebijakan penghapusan perangkat | Threat review, logout/device reset test, retention decision | Security + Privacy | F0.4, F3.2 | Data tenant/outlet lain tidak dapat dipulihkan dari device |

**Go/no-go Fase 3:** pilot hanya boleh memakai operasi offline yang sudah dilabeli, dapat dipulihkan, dan memiliki support path. Payment online, order marketplace, settlement, serta laporan final tetap memerlukan online.

### 9.5 Matriks eksekusi Fase 4 — laporan dan rekonsiliasi

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F4.1 | Kunci fixture transaksi canonical untuk omzet, diskon, pajak, retur, HPP, beban, dan settlement | Golden dataset dengan expected totals | Finance + Backend | F0.3, F1.1 | Semua layar/export memakai definisi yang sama |
| F4.2 | Uji posted journal, debit=kredit, cash/payment ledger, hutang/piutang | Journal and ledger reconciliation report | Finance/Accounting | F4.1 | Selisih punya alasan dan adjustment audit |
| F4.3 | Uji tutup shift dan rekonsiliasi kas per outlet | Shift-close scenarios termasuk selisih, pending, dan approval | POS + Finance | F3.2, F4.1 | Merchant dapat menjelaskan saldo aktual versus sistem |
| F4.4 | Uji export laporan dan akuntansi dengan timezone/periode yang sama | Export samples dan import/validation result | Finance + QA | F4.1–F4.2 | Export tidak menggandakan transaksi atau mengubah histori |
| F4.5 | Label dan review laporan pajak/keuangan yang belum resmi | Copy review, disclaimer, sign-off policy | Finance/Legal | F0.4 | Tidak ada klaim “laporan resmi” tanpa dasar dan approval |

**Go/no-go Fase 4:** laporan boleh dipakai untuk keputusan operasional setelah fixture dan rekonsiliasi staging lulus; laporan resmi/pajak tetap menunggu approval yang sesuai.

### 9.6 Matriks eksekusi Fase 5 — pertumbuhan dan monetisasi lanjutan

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F5.1 | Bangun category builder dan kontrak template prioritas | Versioned category/template config dengan approval dan rollback | Product + Backend | F2.5, F4.1 | Kategori baru tidak membutuhkan deploy untuk aturan dasar |
| F5.2 | Bangun fee engine dengan effective date dan fee snapshot | Simulasi dampak, order/payout snapshot, adjustment ledger | Finance + Backend | F0.2–F0.3, F4.1 | Tarif baru tidak retroaktif dan konsisten di checkout/payout/report |
| F5.3 | Implementasikan usage fee provider/ojek dan wallet ledger | Batch invoice, grace, waiver, dispute, access state, idempotency report | Payments + Operations | F5.2, F0.4 | Pendapatan provider terpisah dari fee platform |
| F5.4 | Implementasikan identity link, risk review, false-positive appeal, dan abuse flags | Risk policy, review queue, appeal evidence, audit sample | Trust/Safety + Privacy | F0.4, F5.3 | Tidak ada pemblokiran otomatis dari satu sinyal |
| F5.5 | Lengkapi payout hold, maker-checker, refund besar, dan koreksi saldo | Approval matrix, dual-control test, payout aging report | Finance + Operations | F0.3, F4.2 | Tidak ada koreksi saldo langsung tanpa adjustment/audit |
| F5.6 | Bangun control tower, onboarding checklist, SLA, dan incident queue | Queue dashboard, owner/SLA, escalation and postmortem template | Operations | F0.5, F1.5 | Setiap alert bisnis punya owner dan target penyelesaian |

**Go/no-go Fase 5:** monetisasi lanjutan hanya boleh diaktifkan setelah ledger, approval, risk review, support SLA, dan rollback tersedia. Fitur yang hanya memiliki UI tidak dihitung selesai.

### 9.7 Matriks eksekusi Fase 6 — staging dan pilot

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F6.1 | Siapkan staging parity dan akses operator | Environment matrix, secrets/config checklist, Auth redirect, Edge Function, webhook, Storage, Realtime | Platform/DevOps | F1.1, F5.6 | Staging dapat menjalankan smoke test end-to-end |
| F6.2 | Terapkan bundle Fase 2–5 dan lakukan rehearsal rollback | Apply log, checksum, backup, rollback/restore evidence | DBA/DevOps | F6.1 | Tidak ada migration drift atau data loss pada rehearsal |
| F6.3 | Jalankan test matrix fungsional, permission, concurrency, security, performance, dan recovery | Signed test report, defect severity, retest result | QA + Security | F6.2 | P0/P1 tertutup; risiko residual disetujui owner |
| F6.4 | Bentuk cohort pilot 10–20 merchant dan baseline per kategori | Merchant consent, cohort list, baseline metrics, support channel | Operations + Product | F0.1, F6.3 | Merchant memahami batas pilot dan jalur bantuan |
| F6.5 | Jalankan pilot dengan kill switch dan incident protocol | Daily/weekly pilot report: activation, first value, sync, conflict, payment, support | Pilot lead | F6.4 | Guardrail tidak melewati ambang berhenti |
| F6.6 | Ambil keputusan go/no-go setelah pilot | 30-day decision record, rollback/iterate/expand recommendation | Steering owner | F6.5 | Keputusan berbasis target, guardrail, feedback, dan unit economics |

**Gate wajib Fase 6:** tidak ada pilot transaksi uang nyata sebelum environment, backup/restore, monitoring, support escalation, privacy/terms, dan rollback disetujui.

### 9.8 Matriks eksekusi Fase 7 — partner, support, dan rollout

| ID | Tugas | Output/evidence | Owner accountable | Dependensi | Gate |
|---|---|---|---|---|---|
| F7.1 | Rollout bertahap berdasarkan cohort dan kategori yang lulus | Wave plan, eligibility, capacity limit, release notes | Product + Operations | F6.6 | Wave baru tidak dibuka saat guardrail wave sebelumnya gagal |
| F7.2 | Operasikan partner program dan promo dengan audit | Partner roster, redemption/reconciliation, expiry report | Partnerships + Finance | F5.2, F6.6 | Promo tidak dapat dipakai lintas merchant atau setelah expiry |
| F7.3 | Jalankan support SLA, incident response, dan postmortem | SLA report, escalation log, recurring-issue backlog | Support/Operations | F5.6, F6.5 | Overdue dan insiden memiliki owner serta tindakan |
| F7.4 | Rekonsiliasi dashboard dengan payment, order, dan support source of truth | Monthly metric reconciliation pack | Data + Finance | F0.5, F6.5 | MRR/churn/GMV tidak dipakai sebelum selisih dijelaskan |
| F7.5 | Tinjau 30/60/90 hari dan putuskan perluasan, perbaikan, atau penghentian | Review record dengan economics, quality, risk, dan merchant feedback | Steering owner | F7.1–F7.4 | Ekspansi hanya jika economics dan guardrail sehat |

### 9.9 Aturan ownership dan format laporan fase

Setiap tugas di atas harus memiliki satu **owner accountable** meskipun dikerjakan oleh beberapa tim. Sebelum fase ditutup, owner mengarsipkan satu paket evidence yang minimal berisi:

1. tujuan dan scope yang diuji;
2. environment, versi release/bundle, fixture, dan tanggal pengujian;
3. hasil sukses, hasil gagal yang diharapkan, permission, idempotensi, dan rollback;
4. defect residual, severity, workaround, dan owner;
5. dampak pada KPI, biaya, merchant, pelanggan, provider, dan data pribadi;
6. keputusan **go**, **go terbatas**, **hold**, atau **rollback**, beserta approver.

Status fase harus diturunkan kembali bila migration berubah, kontrak ledger berubah, payment provider berubah, ada incident P0/P1, atau evidence kedaluwarsa karena perubahan environment.

---

## 10. Risiko yang harus dihindari

### Jangan menyamakan “menu tersedia” dengan “produk siap”

Menu POS sudah luas, tetapi modul laporan, stok, audit, dan pembayaran harus dinilai dari atomicity, sumber data, dan rekonsiliasi—bukan hanya dari adanya halaman.

### Jangan menutup marketplace saat POS berhenti berlangganan

Marketplace adalah produk gratis dan kanal akuisisi. POS yang tidak aktif seharusnya menghentikan operasi POS baru, bukan menghapus etalase atau histori merchant.

### Jangan menjadikan POS sebagai syarat marketplace

Merchant harus dapat upload produk, menerima pesanan, mengonfirmasi fulfillment, dan mengelola toko tanpa membeli POS. Upgrade POS harus menjual efisiensi operasional, bukan membuka akses dasar marketplace yang sebelumnya sudah dijanjikan gratis.

### Jangan membiarkan dua sumber stok diedit bebas

Jika merchant POS boleh mengubah stok melalui `products` dan `pos_stock` sekaligus, integrasi akan kehilangan makna. Arah yang dipilih harus konsisten: POS outlet stock sebagai sumber operasional, marketplace sebagai projection.

### Jangan menyebut simulasi sebagai laporan resmi

Laporan pajak estimasi, cashflow perkiraan, atau ekspor yang tidak mengambil transaksi aktual harus diberi label yang jujur sampai formula dan sumber datanya benar.

### Jangan membuat offline tanpa rekonsiliasi

Offline adalah fitur keandalan, bukan izin untuk melewati aturan server. Semua transaksi offline harus punya status pending/synced/conflict yang dapat diaudit.

### Jangan menyamakan URL toko dengan konteks meja

Toko yang dibuka dari marketplace tetap harus menjadi toko publik biasa. Konteks meja hanya boleh dibuat dari QR POS yang valid, scoped ke outlet/meja, dan diverifikasi server.

### Jangan membayar payout sebelum order cukup aman

Payout terlalu cepat meningkatkan risiko fraud, refund, dan sengketa. Tetapkan status fulfillment, periode penahanan, rule pengecualian, dan jalur dispute sebelum saldo dianggap tersedia.

### Jangan membuat admin sebagai database editor

Admin harus bekerja melalui action bisnis yang terkontrol—approve, reject, refund, suspend, reaktivasi, rekonsiliasi—bukan mengubah row transaksi secara langsung. Koreksi harus menghasilkan adjustment dan audit trail.

### Jangan mengoptimalkan signup saja

Signup yang tidak menghasilkan produk terbit, order pertama, fulfillment, atau transaksi POS tidak menciptakan bisnis yang sehat. Funnel harus diukur sampai nilai nyata diterima merchant dan pelanggan.

### Jangan menambah fitur paid sebelum fondasi operasional siap

Paket tambahan tidak akan memperbaiki marketplace yang order-nya terlambat, payout tidak jelas, atau stok tidak dipercaya. Prioritaskan inbox order, fulfillment, payout, support, dan rekonsiliasi sebelum ekspansi modul.

### Jangan memakai satu alur order untuk semua kategori

Barang, makanan, jasa terjadwal, jasa panggilan, sewa, dan wisata memiliki kebutuhan status, jadwal, kapasitas, deposit, pembatalan, dan bukti selesai yang berbeda. Gunakan template dan state machine per kategori, tetapi jangan menggandakan payment, fee, dispute, dan audit ledger.

### Jangan mengubah tarif secara retroaktif

Admin boleh mengubah marketplace gratis menjadi berkomisi atau mengubah tarif kategori, tetapi order yang sudah dibuat harus memakai snapshot aturan sebelumnya. Perubahan baru memerlukan tanggal efektif, notifikasi, preview dampak, dan audit.

### Jangan memperluas kategori sebelum unit economics terlihat

GMV besar tidak selalu berarti bisnis sehat. Ukur take rate bersih setelah payment, support, refund, fraud, delivery, payout, dan biaya operasional. Kategori dengan order tinggi tetapi margin kontribusi negatif harus diperbaiki atau dibatasi sebelum diperluas.

### Jangan memperlakukan jasa, sewa, dan wisata seperti stok biasa

Jasa membutuhkan jadwal dan kapasitas provider, sewa membutuhkan kalender dan deposit, sedangkan wisata membutuhkan kapasitas, operator, titik temu, dan kebijakan no-show. Kesalahan model dapat menyebabkan double booking, aset hilang, atau sengketa keselamatan.

### Jangan mengumpulkan data kategori tanpa kebijakan privasi

Jasa panggilan, pijat, wisata, transportasi, dan booking dapat memerlukan alamat, jadwal, kontak, atau data peserta. Ambil data minimum yang diperlukan, batasi akses, simpan consent, dan tetapkan retensi serta penghapusan.

### Jangan membuat provider membayar sebelum memperoleh nilai

Untuk ojek dan provider jasa tertentu, model batch setelah order selesai lebih sehat daripada biaya daftar atau subscription wajib di muka. Provider harus dapat melihat gross fare, fee per order, total batch, jatuh tempo, grace period, dan dampak pembayaran terhadap akses platform.

### Jangan menghitung fee dari order yang belum sah

Order yang dibatalkan, self-order, fraud, atau belum selesai tidak boleh langsung masuk tagihan fee provider. Gunakan status validasi dan adjustment ledger agar platform tidak terlihat mengambil biaya dari order fiktif atau gagal.

### Jangan mengandalkan satu sinyal untuk memblokir akun

Nomor telepon, perangkat, lokasi, kendaraan, atau payout account masing-masing dapat memiliki false positive. Gabungkan beberapa sinyal, gunakan review manusia dan jalur banding, serta audit alasan pembatasan akses.

---

## 11. Rekomendasi keputusan sekarang

1. **Setujui model bisnis:** marketplace gratis, POS berbayar, POS memiliki trial terbatas.
2. **Gunakan satu katalog lintas kanal:** jangan membuat produk baru saat merchant mengaktifkan POS jika produk lama dapat di-link.
3. **Tetapkan POS stock sebagai sumber stok merchant POS:** `products.stock` hanya projection marketplace.
4. **Pisahkan status dan hak akses:** merchant marketplace tetap aktif meskipun POS suspended.
5. **Prioritaskan kualitas ledger sebelum menambah fitur:** order state machine, stock adjustment atomic, payment/cash ledger, dan laporan canonical.
6. **Mulai dengan satu atau dua paket POS:** terlalu banyak paket akan membingungkan merchant dan admin.
7. **Gunakan trial sebagai onboarding, bukan sekadar masa gratis:** ukur setup selesai dan transaksi pertama.
8. **Lakukan pilot terbatas:** 10–20 merchant dengan tipe usaha berbeda sebelum membuka POS secara luas.
9. **Jangan mengiklankan laporan keuangan/pajak sebagai resmi sebelum rekonsiliasi selesai.**
10. **Jadikan status sinkronisasi terlihat:** merchant harus tahu produk/stok/transaksi mana yang gagal atau menunggu.
11. **Pertahankan inbox pesanan marketplace sebagai fitur gratis:** POS hanya menambah kanal kasir, stok outlet, dan automasi operasional.
12. **Bangun QR meja sebagai mode order terpisah:** gunakan katalog dan stok bersama, tetapi simpan source, konteks meja, dan fulfillment state secara eksplisit.
13. **Jadikan QR dapat dicabut dan diaudit:** merchant harus dapat menonaktifkan meja/outlet atau mengganti QR tanpa memutus toko publik.
14. **Bangun onboarding sampai nilai pertama:** ukur produk pertama terbit, order pertama, fulfillment pertama, dan transaksi POS pertama.
15. **Jadikan admin control tower:** tampilkan antrean tindakan, SLA, risiko, payout, dispute, dan dampak status POS terhadap marketplace.
16. **Pisahkan kewenangan admin:** gunakan role operasional, keuangan, produk/POS, dan super admin dengan maker-checker untuk tindakan berisiko.
17. **Tahan payout secara terukur:** lepaskan dana berdasarkan status fulfillment dan aturan risiko, bukan hanya karena order dibuat.
18. **Jadikan kualitas dan keamanan sebagai fitur bisnis:** moderasi katalog, deteksi abuse, QR yang dapat dicabut, audit, dan pemulihan harus masuk prioritas produk.
19. **Gunakan template kategori:** jangan memaksa kaos, makanan, jasa, sewa, dan wisata memakai form atau state machine yang sama.
20. **Bangun fee engine sebagai konfigurasi bisnis:** admin dapat mengatur komisi, biaya booking, biaya tetap, dan siapa yang membayar tanpa deploy kode.
21. **Mulai dari kategori dengan supply dan demand nyata:** perluas vertikal hanya setelah order, fulfillment, dispute, payout, dan margin kontribusinya terbukti.
22. **Jaga kepercayaan saat monetisasi berubah:** tarif baru harus transparan, terjadwal, tidak retroaktif, dapat diaudit, dan tidak menghukum order yang sudah dibuat.
23. **Gunakan usage fee untuk ojek/provider yang sensitif terhadap biaya di muka:** daftar dan order gratis, fee muncul setelah order selesai, lalu ditagihkan per batch.
24. **Pisahkan pendapatan perjalanan dari fee platform:** provider harus dapat melihat perhitungan gross fare, fee per order, batch, saldo, dan akses secara jelas.
25. **Jadikan anti-abuse bagian dari onboarding:** identity link, verifikasi provider, risk scoring, batch hold, review, banding, dan audit harus dirancang sejak awal.

## Kesimpulan

Strategi terbaik bukan memilih antara online atau offline. Bangun **marketplace multi-vertikal sebagai pintu masuk**, **POS omnichannel berbayar sebagai mesin operasional**, dan **fee engine yang dapat dikonfigurasi sebagai mesin monetisasi**. Keduanya memakai identitas merchant, payment, fee, dispute, dan audit ledger yang konsisten, tetapi memiliki aturan transaksi yang berbeda:

- marketplace mengutamakan jangkauan dan reservasi stok;
- POS mengutamakan kecepatan kasir dan ketahanan offline;
- QR POS menambahkan konteks order meja tanpa membuat toko kedua;
- barang memakai stok dan fulfillment;
- makanan memakai kesiapan produksi dan delivery/pickup;
- jasa memakai jadwal, provider, dan bukti selesai;
- sewa memakai kalender, deposit, dan kondisi aset;
- wisata/ojek memakai kapasitas, rute, operator, dan no-show policy;
- admin mengatur kategori, fee, dan monetisasi dengan tanggal efektif serta audit;
- server menjadi sumber kebenaran;
- admin mengendalikan entitlement, harga, dan kualitas;
- merchant selalu dapat melihat status data dan rekonsiliasinya.

Dengan urutan ini, SaDesa dapat bertumbuh dari marketplace komunitas menjadi SaaS operasional UMKM tanpa memaksa semua merchant membayar sejak awal dan tanpa mengorbankan integritas stok maupun keuangan.