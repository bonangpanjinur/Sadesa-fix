# Audit Merchant, POS, dan Storefront

Tanggal audit: 7 September 2026

## Ringkasan eksekutif

Proyek sudah memiliki fondasi yang cukup lengkap untuk tiga area yang diaudit:

- Workspace merchant marketplace dengan katalog, order, stok, promosi, ulasan, payout, dan pengaturan toko.
- POS yang sudah dipusatkan di namespace merchant (`/merchant/pos/*`), dengan outlet, role internal, modul, offline queue, checkout atomik, dan audit.
- Storefront publik berbasis slug/ID yang menampilkan katalog, jam buka, kuota marketplace, ulasan, galeri, dan status toko.

Namun, integrasi saat ini belum sepenuhnya aman dan belum memiliki kontrak bisnis yang tunggal. Risiko terbesar bukan kekurangan halaman, melainkan perbedaan sumber kebenaran, alur aktivasi yang dapat melompati billing, dan guard UI yang tidak konsisten.

### Status keseluruhan

| Area | Kondisi | Kesimpulan |
|---|---|---|
| Merchant workspace | Terhubung ke Supabase dan memiliki guard terpusat | Implementasi guard role/status selesai; perlu uji RLS lintas role di staging |
| POS routing/role | Routing canonical sudah diarahkan ke `/merchant/pos/*`; permission matrix tersedia | Fondasi baik, perlu validasi mutation per role dan outlet |
| POS–merchant catalog | Trigger dan RPC projection tersedia | Metadata tetap diproyeksikan; stok tertaut kini memakai agregat POS multi-outlet sebagai projection marketplace |
| POS checkout | Menggunakan `process_pos_sale` dan request key | Jalur transaksi relatif matang, perlu pengujian role/outlet/offline |
| Storefront publik | Slug dan URL `/s/:slug` tersedia; status publishability diterapkan untuk slug dan UUID | Bypass UUID sudah ditutup; alasan unavailable dan canonical URL masih perlu dirapikan |
| Operasional Replit | Sudah dapat dijalankan | Workflow aktif pada Node 22 dan port 5000; gate audit dependency masih merah |

### Pembaruan verifikasi Fase 0

Setelah dependency dipulihkan dan runtime workspace diselaraskan ke Node 22:

- Workflow `Start application` aktif pada port 5000.
- Preview homepage berhasil tampil dan browser console tidak melaporkan error aplikasi.
- Typecheck berhasil.
- `npm run lint` berhasil dengan 6 warning Fast Refresh pada komponen/page tertentu, tanpa error.
- `npm run build` berhasil, termasuk PWA service worker.
- `npm test -- --run` berhasil: 33 test files, 94 passed, 20 skipped.
- `npm run validate:package-manager` berhasil.
- `npm audit --audit-level high` masih gagal karena 18 vulnerability dependency (10 high, 4 moderate, 4 low); perbaikannya sengaja dipisahkan dari pemulihan workflow agar tidak melakukan upgrade paksa tanpa regression check.

Dengan hasil tersebut, kemampuan verifikasi aplikasi sudah pulih. Gate keamanan dependency tetap terbuka dan harus dibereskan sebelum release production.

### Status implementasi saat ini

#### Sudah selesai di source code

- Runtime Node diselaraskan ke Node 22, dependency dipulihkan dari lockfile, dan workflow `npm run dev` berjalan di port 5000.
- Guard workspace merchant memeriksa role serta status merchant; dashboard pending/rejected tetap dapat dibuka, sedangkan subhalaman memerlukan merchant approved dan active.
- Aktivasi POS sekarang memiliki entitlement gate server-side untuk merchant approved/active dan subscription/trial POS yang masih aktif.
- Storefront berbasis slug dan UUID memakai aturan publishability yang sama; merchant non-approved/non-active tidak dirender sebagai storefront publik.
- Projection katalog merchant ke POS tetap tersedia melalui trigger/RPC.
- Kontrak stok dasar sudah dibuat: `pos_stock` per outlet menjadi sumber operasional, sedangkan `products.stock` menjadi projection marketplace.
- Sinkronisasi stok POS → marketplace sudah memiliki agregasi seluruh outlet aktif, pengurangan `reserved_quantity`, RPC server-side, trigger otomatis, dan tombol manual yang memakai RPC yang sama.
- Typecheck, lint tanpa error, test suite, production build, PWA build, validasi migration, dan validasi bootstrap bundle sudah lulus.

#### Sudah diimplementasikan tetapi belum dinyatakan production-ready

- Migration POS activation dan projection stok (`10` sampai `15`) masih tersimpan di repository dan belum diterapkan ke Supabase staging/production karena belum ada database environment yang terhubung.
- RLS, permission mutation, RPC activation, checkout, dan trigger stok belum diuji dengan identitas nyata owner, manager, kasir, staff gudang, purchasing, finance, auditor, buyer, serta beberapa tenant/outlet.
- Sinkronisasi POS → marketplace belum memiliki bukti runtime dari database staging; hasil validasi saat ini masih static/local.

#### Belum selesai

- Ledger dua arah untuk order marketplace dan stok outlet POS. Order online masih memakai `products.stock`/`reserved_stock` tanpa alokasi atomik ke outlet POS tertentu.
- Guard agar edit manual stok merchant tidak dapat membuat produk tertaut POS berbeda dari sumber stok operasional.
- Reconciliation per produk yang menampilkan total outlet, delta marketplace, projection hilang, error, dan recovery action di UI.
- Acceptance matrix transaksi POS untuk role, outlet, offline queue, retry/duplicate, split payment, refund/return, voucher, loyalty, stok habis, realtime, dan printer.
- Penanganan 18 vulnerability dependency tanpa upgrade paksa dan tanpa regresi.

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
- **Sisa pekerjaan:** terapkan migration ke staging, uji concurrency/RLS, tambahkan reconciliation UI, lalu tentukan strategi alokasi outlet untuk order marketplace.

### P1 — Penting untuk alur jelas dan kemudahan penggunaan

#### P1-1. POS sudah di-embed ke merchant, tetapi navigasi terlalu padat

- `MerchantSidebar` menggabungkan menu merchant marketplace dan banyak kategori POS.
- Ada puluhan item POS: kasir, inventori, laporan, workforce, finance, integrasi, dan administrasi.
- Search sidebar membantu, tetapi hierarchy dan prioritas untuk owner/kasir belum cukup sederhana.
- **Rencana:** tampilkan dashboard POS sebagai entry point yang berisi checklist setup dan shortcut berdasarkan role; kelompokkan menu menjadi `Jualan`, `Stok`, `Pelanggan`, `Laporan`, `Tim`, `Pengaturan`; sembunyikan menu yang tidak relevan dengan role dan modul; tambahkan breadcrumb/indikator outlet aktif.

#### P1-2. Permission UI perlu diuji bersama permission database

- Matrix `posPermissions` membatasi route berdasarkan `posRole`.
- Sebagian halaman melakukan mutation langsung ke tabel Supabase, sebagian menggunakan RPC.
- Policy lama banyak membedakan owner tenant dan anggota `pos_users`; hasil akhirnya perlu diuji untuk kasir, staff gudang, purchasing, finance, dan auditor.
- **Rencana:** buat matriks akses yang mencakup route, query, mutation, outlet scope, dan expected error. Uji setiap role di staging. Mutation sensitif (uang, stok, role, subscription, return) harus melalui RPC server-side dengan validasi role/outlet.

#### P1-3. Integrasi katalog sudah ada, tetapi lifecycle produk belum lengkap

- Produk merchant dibuat/diubah di `MerchantProductsPage`.
- Trigger `trg_sync_merchant_product_to_pos` memproyeksikan insert/update ke POS.
- Status projection dan stock rows belum sepenuhnya terlihat di UI merchant.
- Perubahan kategori, varian, SKU/barcode, cost, dan aturan harga perlu dipastikan konsisten dengan POS.
- **Status:** kontrak stok dasar sudah diterapkan di migration `15_20260907010000_pos_marketplace_stock_projection.sql`: `pos_stock` menjadi sumber kebenaran operasional untuk produk tertaut, sedangkan `products.stock` menjadi projection marketplace. RPC menghitung total `quantity - reserved_quantity` dari seluruh outlet aktif; trigger menjalankan projection setelah perubahan stok POS; tombol sinkronisasi memakai RPC server-side yang sama. Migration masih perlu diterapkan dan diuji di Supabase staging.
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
- **Rencana:** gunakan pola state bersama untuk `loading`, `empty`, `error`, `retry`, dan `partial data`; tampilkan pesan yang bisa ditindaklanjuti tanpa membocorkan detail internal.

#### P1-6. Merchant dashboard mencampur marketplace dan POS tanpa ringkasan operasional yang cukup jelas

- Dashboard merchant memuat order online, stok, review, quota, kas, jam buka, QR toko, dan status POS.
- POS adalah workspace terpisah secara data, tetapi entry point utamanya tetap dashboard merchant.
- **Rencana:** bedakan ringkasan `Marketplace` dan `Operasional POS`, tampilkan outlet aktif, penjualan hari ini POS, order online pending, stok kritis, dan CTA yang jelas untuk masalah yang perlu tindakan.

### P2 — Peningkatan UX dan maintainability

#### P2-1. Storefront perlu aturan ketersediaan yang terlihat oleh pembeli

- Produk storefront menandai `isAvailable` berdasarkan kuota, jam buka, dan `is_active`.
- UI perlu membedakan `toko tutup`, `produk habis`, `kuota habis`, `produk nonaktif`, dan `di luar jam operasional`.
- **Rencana:** tampilkan alasan unavailable di kartu/detail produk dan cegah checkout dengan pesan yang konsisten.

#### P2-2. URL storefront perlu canonical dan SEO consistency

- Tersedia `/s/:slug` dan `/merchant/:slugOrId`.
- **Rencana:** tetapkan satu URL publik canonical, redirect URL lama, dan pastikan title/meta/OG mengikuti merchant yang sedang dibuka tanpa mengekspos toko yang tidak publishable.

#### P2-3. Printer dan receipt belum satu jalur

- Catatan audit sebelumnya menunjukkan jalur browser print, Web Serial/Web Bluetooth, dan print bridge belum sepenuhnya seragam.
- `POSTransaksiPage` dan invoice masih memiliki jalur `window.print`.
- **Rencana:** tetapkan printer contract tunggal, status koneksi nyata, retry, fallback yang terlihat, dan acceptance test untuk USB/Bluetooth/bridge/browser print.

#### P2-4. Observability bisnis perlu dilengkapi

- Checkout sudah memiliki observability event.
- Belum ada matriks event yang konsisten untuk activation POS, product projection failure, stock mismatch, order status transition, subscription approval, dan storefront unavailable reason.
- **Rencana:** ukur funnel merchant dari pendaftaran → approved → setup → first product → first sale, lalu ukur failure rate per tahap.

## Rencana implementasi yang disarankan

### Fase 0 — Pulihkan kemampuan verifikasi

1. Pasang dependency dari lockfile yang ditetapkan repository.
2. Pastikan `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, dan `VITE_SUPABASE_PROJECT_ID` tersedia melalui environment Replit/Supabase yang benar.
3. Start workflow, buka preview, dan dokumentasikan smoke test minimum.
4. Jalankan typecheck, lint, build, dan test yang tidak membutuhkan environment production.

### Fase 1 — Tutup risiko akses dan billing (**sebagian besar selesai; staging belum**)

1. **Selesai:** guard role/status merchant sudah terpusat di `ProtectedRoute`.
2. **Selesai sebagian:** status merchant dan entitlement POS sudah divalidasi di jalur akses/activation, tetapi state machine lintas seluruh flow belum memiliki acceptance test staging.
3. **Selesai di source code:** entitlement trial/subscription sudah menjadi validasi server-side pada activation RPC; migration belum diterapkan ke Supabase.
4. **Selesai:** resolver storefront menggunakan aturan publishability yang sama untuk slug dan UUID.
5. **Belum:** staging tests untuk buyer, merchant pending, merchant approved, admin, dan POS member.

### Fase 2 — Tetapkan integrasi katalog dan stok (**kontrak dasar selesai; ledger lintas kanal belum**)

1. Definisikan sumber kebenaran produk, harga, varian, dan stok. **Stok produk tertaut sekarang ditetapkan: `pos_stock` operasional per outlet → `products.stock` sebagai projection marketplace.**
2. Audit semua query/mutation `products`, `pos_products`, `pos_stock`, `orders`, dan `pos_sales` berdasarkan scope merchant/tenant/outlet.
3. Tambahkan reconciliation dan status projection. **Projection agregat server-side dan sinkronisasi manual sudah tersedia; status per produk serta laporan selisih masih perlu diperdalam.**
4. **Belum:** pastikan penjualan online dan POS memakai reservation/ledger yang konsisten serta mengalokasikan stok ke outlet.
5. **Belum:** tambahkan laporan selisih stok dan recovery path yang dapat digunakan merchant.

### Fase 3 — Sederhanakan pengalaman merchant dan POS

1. Susun ulang sidebar berdasarkan tugas dan role.
2. Tambahkan POS onboarding checklist: merchant profile, katalog, outlet, printer, kasir, pembayaran, dan first sale.
3. Pisahkan ringkasan marketplace dari POS di dashboard.
4. Seragamkan loading/error/empty/retry state.
5. Tampilkan outlet aktif dan alasan menu/fitur tidak tersedia.

### Fase 4 — Validasi transaksi dan operasional

1. Uji checkout online, offline, retry, duplicate, split payment, refund, return, voucher, loyalty, dan stok habis.
2. Uji role/permission pada route dan mutation.
3. Uji realtime order dan recovery setelah koneksi terputus.
4. Uji printer dan receipt pada jalur yang didukung.
5. Ambil screenshot desktop dan mobile untuk dashboard merchant, katalog, storefront, kasir, stok, dan setup.

## Acceptance criteria akhir

- Buyer tidak dapat membuka storefront pending/rejected/inactive melalui slug maupun UUID.
- Buyer tidak dapat masuk ke workspace merchant melalui route langsung.
- POS tidak dapat aktif atau melakukan mutation operasional tanpa entitlement yang sah.
- Owner, manager, kasir, staff gudang, purchasing, finance, dan auditor hanya melihat serta menjalankan kemampuan yang diizinkan.
- Produk yang dibuat/diubah merchant memiliki status projection yang dapat dilihat dan tidak membuat data POS diam-diam stale.
- Angka stok, penjualan, dan laporan menjelaskan scope global vs outlet dan tidak saling bertentangan.
- Checkout POS aman terhadap retry/duplicate dan memberikan feedback yang jelas pada sukses, gagal, offline, dan konflik.
- Storefront menjelaskan alasan produk/toko tidak tersedia.
- Workflow Replit start bersih dan preview dapat digunakan untuk smoke test.

## Prioritas pengerjaan

1. **P0:** dependency/workflow, merchant guard, subscription gate, storefront publishability.
2. **P0/P1:** kontrak stok merchant–POS dan permission mutation.
3. **P1:** checkout acceptance matrix dan error states.
4. **P1/P2:** navigasi, onboarding, dashboard, storefront messaging.
5. **P2:** printer consistency, observability, dan refinement visual.
