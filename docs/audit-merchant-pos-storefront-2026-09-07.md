# Audit Merchant, POS, dan Storefront

Tanggal audit: 7 September 2026

Pembaruan terakhir: 7 September 2026 — status per fase diperbarui setelah implementasi source code, ledger stok lintas kanal, pemulihan dependency, dan verifikasi workflow.

## Ringkasan eksekutif

Proyek sudah memiliki fondasi yang cukup lengkap untuk tiga area yang diaudit:

- Workspace merchant marketplace dengan katalog, order, stok, promosi, ulasan, payout, dan pengaturan toko.
- POS yang sudah dipusatkan di namespace merchant (`/merchant/pos/*`), dengan outlet, role internal, modul, offline queue, checkout atomik, dan audit.
- Storefront publik berbasis slug/ID yang menampilkan katalog, jam buka, kuota marketplace, ulasan, galeri, dan status toko.

Namun, integrasi saat ini belum sepenuhnya aman dan belum memiliki kontrak bisnis yang tunggal. Risiko terbesar bukan kekurangan halaman, melainkan perbedaan sumber kebenaran, alur aktivasi yang dapat melompati billing, dan guard UI yang tidak konsisten.

### Status keseluruhan

| Area | Kondisi | Kesimpulan |
|---|---|---|
| Merchant workspace | Terhubung ke Supabase dan memiliki guard terpusat | Source code selesai; perlu uji RLS lintas role di staging |
| POS routing/role | Routing canonical sudah diarahkan ke `/merchant/pos/*`; permission matrix dan menu berbasis role/modul tersedia | Source code selesai; perlu validasi mutation per role dan outlet |
| POS–merchant catalog | Trigger, RPC projection, guard manual, rekonsiliasi, dan ledger reservation lintas kanal tersedia | Source code selesai; migration dan concurrency belum dibuktikan di staging |
| POS checkout | Menggunakan `process_pos_sale`, request key, acceptance matrix, dan kontrak receipt terpusat | Source code selesai; validasi RPC/RLS dengan database staging masih terbuka |
| Storefront publik | `/s/:slug` menjadi URL canonical; legacy slug/UUID diarahkan dan metadata dinamis diperbarui | Source code selesai; perlu smoke test storefront dengan data staging |
| Operasional Replit | Dapat dijalankan dan diaudit | Workflow aktif pada Node 22/port 5000; audit dependency 0 vulnerability |

### Pembaruan verifikasi Fase 0

Setelah dependency dipulihkan dan runtime workspace diselaraskan ke Node 22:

- Workflow `Start application` aktif pada port 5000.
- Preview homepage berhasil tampil dan browser console tidak melaporkan error aplikasi.
- Typecheck berhasil.
- `npm run lint` berhasil dengan 6 warning Fast Refresh pada komponen/page tertentu, tanpa error.
- `npm run build` berhasil, termasuk PWA service worker.
- `npm test` berhasil: 36 test files, 123 passed, 20 skipped.
- `npm run validate:package-manager` berhasil.
- `npm audit --audit-level high` berhasil dengan 0 vulnerability setelah pembaruan `qs` dan override `esbuild` ke versi direct dependency yang aman.

Dengan hasil tersebut, kemampuan verifikasi aplikasi dan gate dependency sudah pulih. Gate staging database, identitas nyata, dan acceptance transaksi tetap terbuka.

### Status implementasi saat ini

#### Selesai

- Runtime Node diselaraskan ke Node 22, dependency dipulihkan dari lockfile, dan workflow `npm run dev` berjalan di port 5000.
- Guard workspace merchant memeriksa role serta status merchant; dashboard pending/rejected tetap dapat dibuka, sedangkan subhalaman memerlukan merchant approved dan active.
- Aktivasi POS sekarang memiliki entitlement gate server-side untuk merchant approved/active dan subscription/trial POS yang masih aktif.
- Storefront berbasis slug dan UUID memakai aturan publishability yang sama; merchant non-approved/non-active tidak dirender sebagai storefront publik.
- Projection katalog merchant ke POS tetap tersedia melalui trigger/RPC.
- Kontrak stok dasar sudah dibuat: `pos_stock` per outlet menjadi sumber operasional, sedangkan `products.stock` menjadi projection marketplace.
- Sinkronisasi stok POS → marketplace sudah memiliki agregasi seluruh outlet aktif, pengurangan `reserved_quantity`, RPC server-side, trigger otomatis, dan tombol manual yang memakai RPC yang sama.
- Reservation marketplace sekarang memiliki ledger alokasi per outlet POS melalui migration `17_20260907030000_marketplace_pos_stock_ledger.sql`, termasuk lifecycle reserve, release, expire, dan consume.
- Guard server-side mencegah edit manual `products.stock` untuk produk yang tertaut POS; halaman katalog merchant juga menandai produk POS dan menonaktifkan input stoknya.
- Storefront dan detail produk sekarang menampilkan alasan ketersediaan yang spesifik: produk nonaktif, kuota habis, toko tutup, atau stok habis. Cart memblokir checkout jika validasi stok terbaru menemukan perubahan.
- Halaman integrasi POS memiliki rekonsiliasi per produk yang membandingkan total outlet, reservasi, stok tersedia POS, projection marketplace, delta, dan tombol recovery sinkronisasi.
- Navigasi POS dipisahkan menjadi kelompok `Operasional POS` dan disaring berdasarkan role/modul; dashboard memisahkan ringkasan Marketplace dan Operasional POS.
- Checklist onboarding POS tersedia untuk workspace, outlet, modul, printer, dan transaksi pertama.
- Event observability untuk aktivasi POS, sinkronisasi stok/order, dan transisi order marketplace sudah ditambahkan.
- Acceptance matrix source code untuk permission, pembayaran, retry/duplicate, offline, workflow return/transfer, dan unavailable reason tersedia di `src/lib/phase4Acceptance.test.ts`.
- Kontrak cetak tunggal untuk checkout dan reprint tersedia di `src/lib/receiptPrintContract.ts`, dengan outbox idempotent, fallback browser, dan status antrean.
- Test kontrak printer mencakup bridge sukses, fallback browser, dan kegagalan USB di `src/lib/receiptPrintContract.test.ts`.
- Typecheck, lint tanpa error, test suite, production build, PWA build, validasi migration, dan validasi bootstrap bundle sudah lulus.

#### Sebagian selesai

- Migration POS activation, projection stok, guard, dan ledger (`10` sampai `17`) masih tersimpan di repository dan belum diterapkan ke Supabase staging/production karena belum ada database environment yang terhubung.
- RLS, permission mutation, RPC activation, checkout, dan trigger stok belum diuji dengan identitas nyata owner, manager, kasir, staff gudang, purchasing, finance, auditor, buyer, serta beberapa tenant/outlet.
- Sinkronisasi POS → marketplace belum memiliki bukti runtime dari database staging; hasil validasi saat ini masih static/local.

#### Belum selesai

- Penerapan dan pembuktian runtime migration ledger stok pada Supabase staging/production.
- Acceptance matrix transaksi POS dan permission lintas role/outlet pada runtime staging.
- Uji runtime printer pada perangkat USB, Bluetooth, WiFi, Print Bridge, dan browser fallback; invoice marketplace tetap memakai format dokumen A4/browser print.
- Penyamaan loading/error/empty/retry state pada seluruh halaman merchant/POS, di luar fondasi POS yang sudah tersedia.

## Batasan audit

Audit ini dilakukan melalui pembacaan source code, route, query Supabase, migration/bootstrap SQL, log workflow, dan preview homepage. Belum dilakukan:

- login dengan akun buyer, merchant owner, kasir, manager, finance, atau staff;
- query ke database Supabase yang sedang terhubung;
- uji RLS dengan beberapa identitas;
- uji transaksi POS nyata, offline sync, realtime, printer, upload, dan pembayaran;
- screenshot interaktif untuk halaman yang membutuhkan login merchant/POS.

Karena itu, temuan bertanda **perlu verifikasi staging** harus menjadi acceptance test sebelum dianggap selesai.

## Temuan prioritas

### P0 — Wajib dibereskan sebelum merchant/POS dipakai produksi

#### P0-1. Workflow aplikasi tidak dapat start

- **Bukti:** workflow `Start application` menjalankan `npm run dev`, lalu berhenti dengan `sh: 1: vite: not found`.
- **Dampak:** tidak bisa melakukan smoke test, screenshot, maupun validasi UI di Replit.
- **Status:** selesai. Dependency dipulihkan, runtime diselaraskan ke Node 22, workflow dan preview sudah berhasil diverifikasi.

#### P0-2. Aktivasi workspace POS dapat melewati langganan/persetujuan admin

- `POSSetupPage` langsung memanggil `activate_merchant_pos_workspace`.
- Function tersebut mengatur `pos_tenants.status = 'active'`, `is_active = true`, dan modul terpilih.
- Jalur `/merchant/pos/setup` dapat diakses merchant sebelum ada subscription aktif.
- Jalur subscription terpisah (`MerchantPOSSubscribePage`) membuat request `PENDING`, tetapi tidak menjadi prasyarat pada function aktivasi.
- **Dampak:** merchant berpotensi memakai POS aktif tanpa trial/subscription yang sah atau tanpa approval admin.
- **Status:** implementasi selesai di `supabase/bootstrap/14_20260907000000_pos_activation_entitlement_gate.sql`. RPC sekarang mensyaratkan merchant approved/active dan subscription/trial POS yang ACTIVE serta belum kedaluwarsa. Penerapan ke Supabase staging/production tetap perlu dilakukan saat environment database tersedia.

#### P0-3. Guard merchant terlalu longgar dan tidak konsisten

- Route `/merchant/*` umumnya hanya memakai `ProtectedRoute` tanpa `allowedRoles`.
- `useMerchantGuard` dipakai oleh sebagian halaman, tetapi tidak semua halaman merchant melakukan guard yang sama.
- `/merchant` sendiri dapat dirender oleh user login non-merchant dan baru kemudian mencoba mencari merchant berdasarkan `user_id`.
- **Dampak:** alur buyer ke halaman merchant tidak jelas; akses UI bergantung pada implementasi masing-masing halaman. RLS tetap penting, tetapi UX dan defense-in-depth tidak konsisten.
- **Status:** akses role dan status merchant sekarang diperiksa terpusat oleh `ProtectedRoute` untuk seluruh workspace merchant. Dashboard `/merchant` tetap dapat dibuka agar bisa menampilkan pending/rejected, sedangkan subhalaman membutuhkan merchant approved dan ACTIVE.

#### P0-4. Storefront UUID dapat melewati status publik

- `MerchantSlugResolver` hanya memuat `registration_status` saat parameter bukan UUID.
- Akses `/merchant/:uuid` langsung meneruskan ke `MerchantProfilePage`.
- `MerchantProfilePage` mengambil merchant berdasarkan ID tanpa filter/validasi `registration_status` atau status publik.
- **Dampak:** toko pending/rejected/inactive berpotensi tetap tampil jika URL ID diketahui, berbeda dengan perilaku URL slug.
- **Status:** selesai di `MerchantSlugResolver`; slug dan UUID sekarang mengambil status merchant dengan aturan yang sama dan toko non-approved/non-active tidak dirender sebagai storefront publik.

#### P0-5. Kontrak stok online dan POS sudah ada, tetapi belum lengkap lintas kanal

- `products` tetap menjadi katalog merchant, `pos_products` menjadi projection katalog POS, dan `pos_stock` menyimpan stok operasional per outlet.
- **Status:** kontrak satu arah POS → marketplace sudah diimplementasikan pada `15_20260907010000_pos_marketplace_stock_projection.sql`. `products.stock` diperbarui dari agregat stok tersedia seluruh outlet aktif, setelah dikurangi `reserved_quantity` POS.
- Sinkronisasi manual di `POSIntegrasiPage` sekarang memakai RPC server-side dan tidak lagi membaca satu baris `pos_stock` atau melakukan update `products` langsung dari client.
- **Batasan:** order marketplace masih memiliki lifecycle `products.stock`/`reserved_stock` sendiri dan belum mengurangi outlet POS secara atomik. Karena itu kontrak stok sudah lebih jelas, tetapi ledger lintas kanal belum konsisten penuh.
- **Status terbaru:** strategi alokasi outlet dan lifecycle ledger sudah diimplementasikan di migration `17_20260907030000_marketplace_pos_stock_ledger.sql`; rekonsiliasi UI source-code tersedia di halaman integrasi POS.
- **Sisa pekerjaan:** terapkan migration ke staging dan uji concurrency/RLS dengan identitas nyata.

### P1 — Penting untuk alur jelas dan kemudahan penggunaan

#### P1-1. POS sudah di-embed ke merchant, tetapi navigasi terlalu padat

- `MerchantSidebar` menggabungkan menu merchant marketplace dan banyak kategori POS.
- Ada puluhan item POS: kasir, inventori, laporan, workforce, finance, integrasi, dan administrasi.
- Search sidebar membantu, tetapi hierarchy dan prioritas untuk owner/kasir belum cukup sederhana.
- **Status:** source code selesai sebagian besar. Menu POS dipisahkan dari kelompok merchant, difilter berdasarkan role/modul, dashboard memiliki ringkasan Marketplace vs Operasional POS, dan checklist onboarding POS tersedia. Pengujian role/outlet nyata masih terbuka.

#### P1-2. Permission UI perlu diuji bersama permission database

- Matrix `posPermissions` membatasi route berdasarkan `posRole`.
- Sebagian halaman melakukan mutation langsung ke tabel Supabase, sebagian menggunakan RPC.
- Policy lama banyak membedakan owner tenant dan anggota `pos_users`; hasil akhirnya perlu diuji untuk kasir, staff gudang, purchasing, finance, dan auditor.
- **Status:** matrix route dan guard source code tersedia, tetapi matriks acceptance route/query/mutation/outlet dan expected error belum dijalankan di staging. Mutation sensitif tetap harus dibuktikan melalui RLS/RPC dengan identitas nyata.

#### P1-3. Integrasi katalog sudah ada, tetapi lifecycle produk belum lengkap

- Produk merchant dibuat/diubah di `MerchantProductsPage`.
- Trigger `trg_sync_merchant_product_to_pos` memproyeksikan insert/update ke POS.
- Status projection dan stock rows belum sepenuhnya terlihat di UI merchant.
- Perubahan kategori, varian, SKU/barcode, cost, dan aturan harga perlu dipastikan konsisten dengan POS.
- **Status:** kontrak stok dasar sudah diterapkan di migration `15_20260907010000_pos_marketplace_stock_projection.sql`: `pos_stock` menjadi sumber kebenaran operasional untuk produk tertaut, sedangkan `products.stock` menjadi projection marketplace. RPC menghitung total `quantity - reserved_quantity` dari seluruh outlet aktif; trigger menjalankan projection setelah perubahan stok POS; tombol sinkronisasi memakai RPC server-side yang sama. Guard edit manual ditambahkan di `16_20260907020000_pos_marketplace_stock_guard.sql`, dan rekonsiliasi per produk tersedia di UI integrasi. Migration masih perlu diterapkan dan diuji di Supabase staging.
- **Sisa risiko:** penjualan marketplace masih memiliki lifecycle stok sendiri (`products.stock`/`reserved_stock`) dan belum mengalokasikan pengurangan ke outlet POS tertentu. Rekonsiliasi lintas kanal dan fulfillment marketplace perlu menjadi pekerjaan lanjutan sebelum mengklaim ledger stok gabungan sudah konsisten.

#### P1-4. Checkout POS sudah memakai RPC atomik, tetapi acceptance flow belum terbukti

- `POSKasirPage` memanggil `processAtomicPOSSale`.
- `posCheckout.ts` mengirim `request_key`, tenant, outlet, cashier, sale, dan items.
- Ada dukungan promo, voucher, loyalty, split payment, QR Pay, offline queue, dan receipt.
- **Dampak:** kompleksitas tinggi; bug kecil dapat memengaruhi uang, stok, poin, dan retry.
- **Rencana:** uji skenario nominal, pembayaran kurang, split payment, retry request key, offline cash, duplicate sync, voucher expired, loyalty redemption, stok habis, dan dua kasir pada outlet sama. Pecah UI kasir menjadi modul yang dapat diuji terpisah bila acceptance menemukan regresi.

#### P1-5. Error dan loading state belum seragam

- Banyak halaman merchant/POS menangkap error dengan pesan generik atau hanya `console.error`.
- Beberapa query mengabaikan `error` dan tetap memakai `data || []`.
- **Dampak:** merchant dapat melihat layar kosong seolah tidak ada data, padahal query gagal.
- **Status:** fondasi state bersama sudah digunakan di layout/halaman POS; cakupan seluruh halaman merchant/POS belum selesai.

#### P1-6. Merchant dashboard mencampur marketplace dan POS tanpa ringkasan operasional yang cukup jelas

- Dashboard merchant memuat order online, stok, review, quota, kas, jam buka, QR toko, dan status POS.
- POS adalah workspace terpisah secara data, tetapi entry point utamanya tetap dashboard merchant.
- **Status:** ringkasan `Marketplace` dan `Operasional POS`, outlet aktif, jumlah outlet, modul aktif, order pending, dan CTA kasir/rekonsiliasi sudah dipisahkan. Penjualan POS hari ini dan CTA stok kritis masih perlu diperdalam.

### P2 — Peningkatan UX dan maintainability

#### P2-1. Storefront perlu aturan ketersediaan yang terlihat oleh pembeli

- Produk storefront menandai `isAvailable` berdasarkan kuota, jam buka, dan `is_active`.
- UI perlu membedakan `toko tutup`, `produk habis`, `kuota habis`, `produk nonaktif`, dan `di luar jam operasional`.
 - **Status:** selesai di source code. Kartu/detail produk membedakan produk nonaktif, kuota habis, toko tutup, dan stok habis; cart memblokir checkout ketika validasi stok terbaru menemukan konflik. Tetap perlu verifikasi staging untuk reservation dan concurrency.

#### P2-2. URL storefront perlu canonical dan SEO consistency

- Tersedia `/s/:slug` dan `/merchant/:slugOrId`.
- **Status:** selesai di source code. `/s/:slug` ditetapkan sebagai canonical, route legacy merchant diarahkan ke sana, dan title/description/OG/Twitter/canonical link mengikuti merchant yang publishable.

#### P2-3. Printer dan receipt belum satu jalur

- Catatan audit sebelumnya menunjukkan jalur browser print, Web Serial/Web Bluetooth, dan print bridge belum sepenuhnya seragam.
- `POSTransaksiPage` dan invoice masih memiliki jalur `window.print`.
- **Status:** source code POS selesai. Checkout dan reprint memakai `printReceiptWithContract`, outbox idempotent, fallback browser, dan status `printed`/`queued`. Invoice marketplace tetap diperlakukan sebagai dokumen A4, bukan struk POS. Uji perangkat nyata masih terbuka.

#### P2-4. Observability bisnis perlu dilengkapi

- Checkout sudah memiliki observability event.
- Belum ada matriks event yang konsisten untuk activation POS, product projection failure, stock mismatch, order status transition, subscription approval, dan storefront unavailable reason.
- **Status:** sebagian selesai. Event activation POS, sinkronisasi stok/order, dan transisi order sudah tersedia; funnel lengkap, projection failure, subscription approval, dan unavailable reason belum seluruhnya dimatrikkan.

## Rencana implementasi yang disarankan

### Fase 0 — Pulihkan kemampuan verifikasi (**SELESAI**)

1. Pasang dependency dari lockfile yang ditetapkan repository.
2. Pastikan `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, dan `VITE_SUPABASE_PROJECT_ID` tersedia melalui environment Replit/Supabase yang benar.
3. Start workflow, buka preview, dan dokumentasikan smoke test minimum.
4. Jalankan typecheck, lint, build, dan test yang tidak membutuhkan environment production.

### Fase 1 — Tutup risiko akses dan billing (**SOURCE CODE SELESAI; STAGING BELUM**)

1. **Selesai:** guard role/status merchant sudah terpusat di `ProtectedRoute`.
2. **Selesai sebagian:** status merchant dan entitlement POS sudah divalidasi di jalur akses/activation, tetapi state machine lintas seluruh flow belum memiliki acceptance test staging.
3. **Selesai di source code:** entitlement trial/subscription sudah menjadi validasi server-side pada activation RPC; migration belum diterapkan ke Supabase.
4. **Selesai:** resolver storefront menggunakan aturan publishability yang sama untuk slug dan UUID.
5. **Belum:** staging tests untuk buyer, merchant pending, merchant approved, admin, dan POS member.

### Fase 2 — Tetapkan integrasi katalog dan stok (**SOURCE CODE SELESAI; STAGING BELUM**)

1. Definisikan sumber kebenaran produk, harga, varian, dan stok. **Stok produk tertaut sekarang ditetapkan: `pos_stock` operasional per outlet → `products.stock` sebagai projection marketplace.**
2. Audit semua query/mutation `products`, `pos_products`, `pos_stock`, `orders`, dan `pos_sales` berdasarkan scope merchant/tenant/outlet.
3. Tambahkan reconciliation dan status projection. **Projection agregat server-side dan sinkronisasi manual sudah tersedia; status per produk serta laporan selisih masih perlu diperdalam.**
4. **Selesai di source code:** reservation marketplace mengalokasikan stok produk POS ke outlet melalui ledger atomik; release/expire/consume mengembalikan atau mengurangi `pos_stock`.
5. **Selesai di source code:** rekonsiliasi per produk dan recovery sync tersedia; validasi runtime, concurrency, dan RLS masih perlu dilakukan di staging.

### Fase 3 — Sederhanakan pengalaman merchant dan POS (**SEBAGIAN BESAR SELESAI; STATE GLOBAL BELUM**)

1. **Selesai di source code:** sidebar POS dipisahkan dan disaring berdasarkan role/modul.
2. **Selesai di source code:** checklist onboarding POS mencakup workspace, outlet, modul, printer, dan first sale.
3. **Selesai di source code:** dashboard memisahkan ringkasan Marketplace dan Operasional POS.
4. **Sebagian selesai:** fondasi loading/error/empty/retry ada di POS, tetapi belum seragam di seluruh merchant/POS.
5. **Selesai sebagian:** outlet aktif dan ketersediaan menu berbasis role/modul tersedia; pengujian lintas role/outlet masih terbuka.

### Fase 4 — Validasi transaksi dan operasional (**SOURCE CODE SELESAI; STAGING/PERANGKAT NYATA BELUM**)

1. **Selesai di source code:** acceptance matrix mencakup role/permission, pembayaran kurang, split payment, non-tunai offline, retryable status, duplicate transition, unavailable reason, dan workflow return/stock transfer.
2. **Selesai di source code:** permission route dan kontrak pembayaran diuji; mutation/RLS nyata masih perlu staging.
3. **Sebagian selesai:** retry/offline recovery dan observability diuji secara unit; realtime order dan recovery setelah koneksi terputus perlu staging.
4. **Selesai di source code:** checkout/reprint memakai kontrak receipt terpusat; uji printer fisik masih perlu dilakukan.
5. **Sebagian selesai:** preview homepage sudah diverifikasi; screenshot authenticated untuk dashboard merchant, katalog, storefront, kasir, stok, dan setup perlu session staging.

## Acceptance criteria akhir

- [x] Buyer tidak dapat membuka storefront pending/rejected/inactive melalui slug maupun UUID (source code).
- [x] Buyer tidak dapat masuk ke workspace merchant melalui route langsung (source guard).
- [x] POS tidak dapat aktif tanpa entitlement yang sah (server-side RPC source code).
- [ ] Owner, manager, kasir, staff gudang, purchasing, finance, dan auditor hanya melihat serta menjalankan kemampuan yang diizinkan (perlu staging).
- [x] Produk yang dibuat/diubah merchant memiliki projection dan rekonsiliasi yang terlihat (source code).
- [ ] Angka stok, penjualan, dan laporan konsisten pada scope global vs outlet (perlu runtime ledger/reconciliation staging).
- [x] Checkout POS memiliki acceptance matrix source code untuk retry/duplicate, pembayaran, offline, dan konflik.
- [ ] Checkout POS terbukti aman pada RPC/RLS dengan transaksi nyata (perlu staging).
- [x] Storefront menjelaskan alasan produk/toko tidak tersedia (source code).
- [x] POS checkout dan reprint memakai kontrak receipt terpusat dengan fallback/outbox yang terlihat.
- [ ] Printer fisik, realtime order, dan screenshot authenticated sudah diverifikasi di staging/perangkat.
- [x] Workflow Replit start bersih dan preview dapat digunakan untuk smoke test.

## Prioritas pengerjaan

1. **Selesai:** dependency/workflow, merchant guard, subscription gate, storefront publishability.
2. **Selesai di source code / terbuka di staging:** kontrak stok merchant–POS, ledger reservation, dan permission mutation.
3. **Selesai di source code / terbuka di staging:** checkout acceptance matrix, permission matrix runtime, dan error states global.
4. **Selesai sebagian besar:** navigasi, onboarding, dashboard, storefront messaging.
5. **Selesai di source code / terbuka di perangkat:** printer consistency POS dan observability bisnis lengkap.
