# Audit Menyeluruh Modul POS dan Rencana Perbaikan

**Repository:** `bonangpanjinur/remix-of-umkm-sadesa`  
**Tanggal audit:** 28 Agustus 2026  
**Cakupan:** seluruh route `/pos`, layout bersama, sidebar, alur kasir, stok, pembelian, meja, KDS, menu QR, laporan, akses, pengaturan, serta validasi build/lint/test.

## Ringkasan eksekutif

Modul POS sudah memiliki cakupan fitur yang luas, tetapi saat ini lebih menyerupai kumpulan halaman operasional daripada satu sistem POS yang memiliki pola UI, state machine, permission model, dan error recovery yang seragam. Risiko terbesar berada pada tiga area: **kontrol akses**, **konsistensi transaksi dan stok**, serta **kualitas operasional pada layar kasir**. Masalah visual pada screenshot Menu QR bukan hanya soal estetika; alur cetaknya masih bergantung pada popup browser, HTML yang dibangun dengan `document.write`, dan CDN eksternal.

Build produksi saat ini berhasil dan lint tidak menemukan error, tetapi suite test tidak dapat berjalan penuh karena konfigurasi runtime Supabase publik belum tersedia. Dengan demikian, keberhasilan build belum dapat dianggap sebagai bukti bahwa seluruh alur POS aman untuk transaksi nyata, multi-outlet, printer, jaringan terputus, atau concurrent cashier.

> **Kesimpulan utama:** sebelum menambah fitur POS baru, perlu dilakukan konsolidasi shell UI, permission per menu, transaction orchestration server-side, standardisasi state loading/error/empty, dan pengujian end-to-end berbasis skenario kasir.

## Status validasi teknis

| Pemeriksaan | Hasil | Interpretasi |
|---|---:|---|
| `pnpm build` | Berhasil | Bundle PWA dapat dibuat pada environment audit. |
| `pnpm lint` | Berhasil dengan 3 warning | Tidak ada error lint; warning Fast Refresh berada di file non-POS. |
| `pnpm test` | Gagal pada 3 suite | Test gagal saat import karena `VITE_SUPABASE_URL` belum tersedia, sehingga assertion POS belum dapat dinilai. |
| Audit route | Ditemukan 42 route POS dan sekitar 39 tautan sidebar | Terdapat route orphan `/pos/harga` dan `/pos/setup` yang tidak muncul di sidebar. |
| Audit live | Redirect ke halaman utama dengan parameter redirect | Sesi audit tidak terautentikasi; verifikasi visual live dibatasi pada screenshot pengguna dan static code review. |

## Inventaris modul POS

| Kelompok | Halaman atau route | Risiko audit utama |
|---|---|---|
| Core cashier | Dashboard, Kasir, Transaksi, Retur | Atomicity, duplicate submit, payment state, receipt, reprint. |
| Floor and kitchen | Meja, KDS, Menu Digital QR, Kiosk | State transition, realtime refresh, print/popup, responsive modal, public abuse. |
| Inventory | Produk, Kategori, Stok, Bahan Baku, Resep, Gudang, Transfer Stok | Scope outlet, negative stock, approval, unit conversion, stale data. |
| Procurement and finance | Pembelian, Supplier, Hutang, Kas Harian, Hutang & Piutang | Approval, payment/receiving consistency, ledger, period closing. |
| Customer and growth | Customer, Promosi & Voucher, Loyalty | Duplicate redemption, stacking, expiry/timezone, customer scope. |
| Workforce and access | Pengguna, Manajemen Akses, Jadwal, Absensi, Penggajian | Role enforcement, approval, sensitive data exposure. |
| Reporting | Penjualan, Laba Rugi, Per Kasir, Stok, Cashflow, Outlet, Analitik | Reproducibility, timezone, outlet filter, reconciliation. |
| Administration and integrations | Pengaturan, Integrasi Marketplace, Akuntansi, Audit Trail, Target Omzet | Configuration ownership, export correctness, traceability, operational observability. |

## Daftar bug dan risiko prioritas

Status **bug terkonfirmasi** berarti masalah terlihat langsung dari static review atau route configuration. Status **risiko terindikasi** berarti pola kodenya berpotensi bermasalah dan wajib dibuktikan dengan test skenario atau environment staging sebelum dinyatakan sebagai defect produksi.

| ID | Status | Prioritas | Area | Temuan dan bukti | Dampak |
|---|---|---|---|---|---|
| POS-001 | Bug terkonfirmasi | P0 | Access control | Route `/pos/harga` pada `src/App.tsx:1075` tidak dibungkus `ProtectedRoute`, berbeda dari route POS lain. | Halaman harga dapat terbuka tanpa guard autentikasi yang sama; harus diverifikasi segera. |
| POS-002 | Risiko terindikasi | P0 | RBAC | `POSSidebar` merender daftar menu statis dan tidak terlihat melakukan filter role/permission, sementara `POSAksesPage` hanya mengelola data akses. | Kasir/staff dapat melihat menu sensitif seperti laporan, payroll, akses, audit, atau pengaturan. Route guard autentikasi bukan pengganti authorization per aksi. |
| POS-003 | Risiko terindikasi | P0 | Transaction integrity | Checkout, voucher, loyalty, stok, bahan baku, dan payment berada pada alur client-side yang kompleks. | Partial success, transaksi ganda, stok tidak sinkron, atau poin/diskon terpotong dua kali saat request gagal atau dua kasir checkout bersamaan. |
| POS-004 | Bug/risiko UI terkonfirmasi | P1 | Menu QR printing | `POSMenuQRPage.tsx:129-164` memakai `window.open`, `document.write`, dan `window.print`; cetak semua QR memakai popup serta CDN eksternal pada baris 182-210. | Popup diblokir, printer dialog browser muncul, bergantung pada CDN, dan gagal mencapai target “langsung cetak tanpa browser”. |
| POS-005 | Risiko keamanan terindikasi | P1 | QR print HTML | Nama tenant, nama meja, section, dan URL disisipkan langsung ke string HTML yang ditulis ke window baru. | Karakter khusus dapat merusak markup; data yang mengandung HTML perlu di-escape sebelum dimasukkan ke dokumen print. |
| POS-006 | Bug UX terkonfirmasi dari screenshot | P1 | QR modal | Modal preview sangat besar untuk viewport browser, konten/action berpotensi keluar dari area layar, dan hierarchy antara preview, URL, serta tombol cetak belum seimbang. | Kasir harus melakukan scroll yang tidak jelas, tombol dapat terasa terpotong, dan hasil terlihat seperti halaman browser alih-alih aplikasi POS. |
| POS-007 | Risiko responsive terindikasi | P1 | Shared layout | `POSLayout.tsx:75-109` menggabungkan outer `min-h-screen`, content `h-screen`, header sticky, dan nested `overflow-y-auto`. | Pada layar pendek atau mobile/tablet dapat muncul nested scroll, header/content clipping, dan modal yang tidak memiliki tinggi efektif yang konsisten. |
| POS-008 | Risiko maintainability terkonfirmasi | P1 | Kasir | `POSKasirPage.tsx` menampung pencarian produk, varian, cart, promo, voucher, loyalty, split payment, QR Pay, held bill, offline, checkout, dan print dalam satu komponen besar. | Perubahan kecil mudah menimbulkan regresi; unit test dan ownership logic sulit dibuat. |
| POS-009 | Risiko state terindikasi | P1 | Cart | Fungsi cart melakukan mutasi object array sementara, misalnya pola `newCart[idx].qty = ...` dan `newCart[idx].discount = ...`. | Stale state atau race pada klik cepat/keyboard input dapat menghasilkan jumlah atau diskon yang tidak sesuai. Gunakan functional immutable update. |
| POS-010 | Risiko operasional terindikasi | P1 | Printer | Bridge lokal sudah memiliki fondasi USB/TCP, tetapi koneksi printer fisik, tray process, installer production, auto-update, dan recovery belum diuji dengan model printer nyata. | Test print dapat terlihat berhasil di aplikasi tetapi gagal pada komputer kasir sebenarnya; perlu diagnostic dan job history yang terlihat. |
| POS-011 | Risiko konsistensi data | P1 | Outlet scope | Query tersebar di banyak page; sebagian memakai tenant scope, sebagian outlet scope, dan sebagian perlu dibuktikan lewat RLS. | Laporan atau mutasi dapat mengambil data lintas outlet, atau data terlihat kosong setelah outlet diganti tanpa refetch yang konsisten. |
| POS-012 | Risiko state transition | P1 | Meja/KDS | `POSMejaPage` dan `POSKDSPage` menyediakan aksi perubahan status dari UI. Perlu dipastikan transition matrix dan authorization server-side benar-benar menolak lompatan status. | Order dapat langsung menjadi served/cancelled tanpa precondition; optimistic UI dapat tidak rollback ketika request gagal. |
| POS-013 | Risiko realtime | P1 | KDS/notifikasi | KDS melakukan polling periodik dan event refresh, tetapi audit perlu memastikan subscription/polling tidak menggandakan fetch atau meninggalkan timer setelah unmount. | Order dapur terlambat, dobel, atau resource browser bocor setelah pindah halaman. |
| POS-014 | Risiko bisnis | P1 | Promo/voucher/loyalty | Perhitungan promo, voucher, tanggal aktif, happy hour, limit, dan loyalty tersebar di UI serta belum terlihat sebagai pricing engine tunggal. | Total kasir dapat berbeda dari order/marketplace; rounding, stacking, timezone, atau double redemption dapat salah. |
| POS-015 | Bug konfigurasi/UX terindikasi | P1 | Settings | `POSPengaturanPage` memuat banyak subsection tenant/outlet/brand/printer, tetapi loading state dan grouping konfigurasi belum seragam. | Pengguna tidak tahu apakah perubahan tersimpan, pada outlet mana konfigurasi berlaku, atau apakah konfigurasi printer aktif. |
| POS-016 | Risiko laporan | P1 | Reporting | Beberapa report menghitung data langsung di client dengan filter waktu dan outlet yang berbeda-beda. | Angka omzet, cashflow, laba rugi, per kasir, dan stok dapat tidak sama untuk periode yang sama. |
| POS-017 | Risiko payroll/privacy | P1 | Penggajian | Payroll, absensi, akses, dan laporan per kasir berada dalam namespace POS yang sama; perlu verifikasi authorization per role dan field-level visibility. | Kasir dapat melihat informasi gaji atau data staff yang seharusnya hanya manager/owner/finance. |
| POS-018 | Risiko testability terkonfirmasi | P1 | Test infrastructure | `pnpm test` berhenti pada suite yang membutuhkan `VITE_SUPABASE_URL`; tidak ada bukti kuat dari output bahwa alur POS end-to-end dijalankan. | Perubahan POS dapat lolos build tetapi gagal saat runtime karena env, RLS, RPC, atau query shape. |
| POS-019 | Bug navigasi/produk terkonfirmasi | P2 | Sidebar/route | `/pos/setup` dan `/pos/harga` terdaftar di `App.tsx`, tetapi tidak tampil sebagai item sidebar. | User tidak menemukan fitur yang tersedia; route `/pos/harga` juga perlu diputuskan apakah akan menjadi menu resmi atau dihapus. |
| POS-020 | Risiko public QR | P2 | Menu QR | QR menu menghasilkan URL publik yang perlu rate limit, validasi tenant/table, dan perlindungan dari table ID enumeration. | QR dapat disalahgunakan untuk scraping atau memesan ke meja/outlet yang tidak semestinya jika backend public route lemah. |
| POS-021 | Risiko export/print | P2 | Reports | Beberapa halaman laporan masih menggunakan browser print atau `window.open`, walaupun struk thermal sudah diarahkan ke bridge. | Pengalaman “tanpa browser” belum konsisten; user dapat menemukan dialog print berbeda-beda antar menu. |
| POS-022 | Risiko error handling | P2 | Semua page | Pola `toast.error` tersedia, tetapi belum ada error boundary domain POS, retry policy seragam, correlation ID, atau halaman status operasi. | Error sulit didiagnosis dan user tidak tahu apakah harus mengulang, menunggu, atau memeriksa data. |

## Masalah UI/UX lintas halaman

Secara visual, POS perlu diperlakukan sebagai aplikasi kerja dengan frekuensi klik tinggi, bukan sekadar halaman dashboard. Sidebar memuat puluhan menu dalam satu daftar panjang tanpa grouping domain, pencarian menu, favorit, atau penandaan fitur berdasarkan role. Hal ini membuat kasir melihat banyak menu yang tidak relevan dan memperbesar waktu mencari fungsi.

Header global menempatkan judul, notifikasi QR, dan action page dalam satu baris tanpa pola lebar yang jelas. Pada layar kasir yang sempit, action dapat menyusut atau bertabrakan. Setiap halaman juga perlu menggunakan pola yang sama untuk skeleton, empty state, error state, filter bar, pagination, bulk action, confirmation dialog, dan feedback penyimpanan.

Screenshot Menu QR memperlihatkan masalah khusus pada preview. Preview seharusnya memiliki `max-height` berbasis viewport, body yang dapat discroll, footer action sticky, ukuran QR adaptif, dan tombol yang tetap terlihat. Teks URL panjang sebaiknya memiliki tombol salin dengan feedback, bukan menjadi elemen panjang yang mendorong layout. Browser toolbar pada screenshot adalah chrome browser pengguna, bukan elemen aplikasi; tetapi popup print dan `window.print` memang menyebabkan aplikasi bergantung pada chrome tersebut.

## Rencana perbaikan bertahap

### Fase 0 — Baseline, observability, dan definition of done

Sebelum mengubah UI, siapkan test account dua tenant, dua outlet, role owner/manager/kasir/staff gudang/finance, serta fixture produk, stok, voucher, meja, order KDS, dan transaksi. Tambahkan konfigurasi test Supabase dummy/staging agar `pnpm test` dapat berjalan tanpa secret production. Setiap defect pada tabel berikut harus memiliki reproduction step, expected result, actual result, severity, dan test yang mencegah regresi.

### Fase 1 — Perbaiki trust boundary dan navigasi

Bungkus `/pos/harga` dengan guard yang sama atau hapus route tersebut bila sudah tidak digunakan. Bentuk permission registry terpusat yang memetakan `menu`, `read`, `create`, `update`, `delete`, `approve`, `close`, dan `export` ke role. Gunakan registry itu di sidebar untuk menyembunyikan menu yang tidak relevan, di route guard untuk menolak akses langsung, dan di tombol aksi untuk mencegah privilege escalation. Backend RLS/RPC tetap menjadi enforcement terakhir.

Atur ulang sidebar ke kelompok **Operasional**, **Inventori**, **Keuangan**, **SDM**, **Laporan**, dan **Administrasi**. Tambahkan compact mode, menu search, recently used, serta indikator outlet aktif yang selalu terlihat. Pastikan `/pos/setup` hanya muncul saat onboarding atau di Pengaturan, sedangkan `/pos/harga` memiliki lokasi navigasi yang jelas.

### Fase 2 — Konsolidasi shell dan design system POS

Buat komponen bersama `POSPageShell`, `POSFilterBar`, `POSDataTable`, `POSEmptyState`, `POSErrorState`, `POSLoadingSkeleton`, `POSConfirmDialog`, `POSStatusBadge`, dan `POSPermissionGate`. Tetapkan token untuk spacing, border radius, warna status, typography, table density, button height, dan modal width.

Hilangkan nested scroll yang tidak perlu. Gunakan satu area scroll utama, modal dengan `max-h-[calc(100dvh-2rem)]`, body modal `overflow-y-auto`, dan footer action sticky. Semua halaman harus lulus viewport 360px, tablet portrait, laptop 1366px, serta layar kasir dengan scaling 125%.

### Fase 3 — Pisahkan domain kasir dan bangun pricing engine

Pecah `POSKasirPage` menjadi hook dan domain module: `useProductSearch`, `useCart`, `usePricing`, `usePayment`, `useHeldBills`, `useOfflineSale`, dan `useReceipt`. Terapkan immutable functional update pada cart. Pindahkan kalkulasi promo, voucher, pajak, rounding, minimum purchase, happy hour, dan loyalty ke satu pricing engine yang menerima input snapshot dan menghasilkan breakdown deterministik.

Tambahkan test untuk item tunggal, varian, qty pecahan, diskon item, diskon order, promo bundle, voucher limit, promo bertumpuk, pajak, split payment, pembayaran kurang, pembayaran berlebih, pembulatan rupiah, dan timezone boundary. Tampilan checkout harus menampilkan breakdown yang sama dengan payload yang dikirim ke server.

### Fase 4 — Atomic checkout, stock ledger, dan state machine

Checkout harus menggunakan RPC/service atomic dengan idempotency key. Satu operasi harus memvalidasi harga dan stok server-side, membuat sale dan item, mengurangi stok, mencatat stock ledger, menerapkan voucher/loyalty, dan menyimpan receipt snapshot. Jika satu langkah gagal, seluruh transaksi rollback atau masuk ke status recovery yang dapat direkonsiliasi.

Gunakan state machine untuk sale, payment, return, table order, KDS, stock transfer, purchase receiving, dan cash session. Setiap transition harus memiliki actor, precondition, side effect, idempotency behavior, dan audit event. UI wajib melakukan rollback optimistic state ketika server menolak aksi.

### Fase 5 — Printer, Menu QR, dan mode offline

Pertahankan Print Bridge untuk struk thermal, tetapi tambahkan job history, device identity, retry dengan exponential backoff, diagnostic detail, dan status yang dibedakan antara bridge offline, printer offline, paper out, dan job failed. Sediakan installer Windows production-ready dan uji dengan printer TCP/IP serta USB nyata.

Untuk Menu QR, ganti popup `window.open` dan `document.write` dengan preview component yang dapat diunduh sebagai PNG/PDF melalui pipeline aplikasi. Jika cetak fisik diperlukan, kirim dokumen ke print bridge atau gunakan export dokumen yang eksplisit; jangan memakai CDN runtime untuk menghasilkan QR. Escape semua teks, validasi URL, dan tambahkan bulk print queue dengan progress serta retry per meja.

Outbox offline harus menyimpan event dengan idempotency key, created-at asli, device ID, schema version, dan checksum. Tampilkan conflict center apabila harga, produk, outlet, atau stok berubah saat event dikirim ulang.

### Fase 6 — Standardisasi laporan, pengaturan, dan workflow approval

Semua laporan harus memiliki filter periode/outlet yang sama, timezone eksplisit, definisi KPI yang terdokumentasi, query source-of-truth, dan export yang menyimpan filter serta timestamp. Sediakan reconciliation view untuk sales-to-cash, sales-to-stock, return, voucher, loyalty, purchase receiving, dan cash closing.

Pisahkan konfigurasi tenant, outlet, printer, branding, dan role access. Setiap save harus menampilkan scope perubahan, versi konfigurasi, user pengubah, timestamp, serta status sinkronisasi. Payroll, audit, dan finance harus memiliki permission khusus dan tidak boleh hanya disembunyikan melalui UI.

### Fase 7 — E2E, accessibility, dan release hardening

Buat matriks E2E untuk login, setup tenant, ganti outlet, checkout cash/QR/split, held bill, auto-print, bridge mati, printer dicabut, cetak ulang, retur, stok negatif, transfer approval, KDS transition, Menu QR, laporan, cash closing, dan role denial. Uji reload, double-click, network offline/online, dua tab kasir, dua device, dan restart bridge.

Tambahkan keyboard shortcut untuk scan/search/payment, focus management dialog, ARIA label pada icon-only button, kontras warna, screen reader text untuk status, serta tampilan touch-friendly. Release hanya jika build, lint, unit, integration, E2E, dan staging RLS matrix lulus.

## Prioritas eksekusi

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Lindungi `/pos/harga`, permission registry, route/action authorization | Mencegah akses tidak semestinya sebelum perbaikan visual. |
| P0 | Atomic checkout dan idempotency sale/payment | Mencegah kerugian transaksi, stok, voucher, dan loyalty. |
| P0 | Fixture staging dan perbaikan test runtime env | Tanpa test yang berjalan, regresi tidak dapat diukur. |
| P1 | POS shell/design system dan responsive modal | Menurunkan friksi kasir dan memperbaiki seluruh menu sekaligus. |
| P1 | Refactor kasir/pricing engine | Mengurangi risiko regresi pada fungsi transaksi inti. |
| P1 | QR print tanpa popup/CDN dan Print Bridge diagnostic | Menyelesaikan masalah yang terlihat langsung oleh pengguna. |
| P1 | State machine KDS/meja/retur/transfer | Mencegah status invalid dan operasi yang tidak dapat direkonsiliasi. |
| P2 | Standardisasi reports, settings, payroll, accessibility, dan analytics | Meningkatkan konsistensi dan kesiapan operasional setelah trust boundary aman. |

## Definition of done

Perbaikan POS dapat dianggap selesai bila seluruh route memiliki permission yang sesuai, tidak ada route sensitif yang terbuka tanpa guard, dan setiap mutasi penting memiliki enforcement server-side. Checkout harus idempotent dan atomic, laporan harus reproducible untuk outlet dan timezone yang sama, serta outbox printer harus dapat dipulihkan setelah bridge atau jaringan mati.

Dari sisi UX, setiap halaman harus memiliki loading, empty, error, retry, success feedback, dan responsive behavior yang konsisten. Modal tidak boleh terpotong pada viewport yang didukung. Menu QR tidak boleh membutuhkan popup browser atau CDN runtime. Setiap P0/P1 harus memiliki regression test, dan suite CI harus berjalan dengan konfigurasi staging yang aman.

## Urutan commit yang disarankan untuk implementasi berikutnya

| Commit | Fokus |
|---|---|
| `fix(pos): protect price route and centralize permissions` | Guard route, permission registry, sidebar/action gate. |
| `refactor(pos): introduce shared page shell and states` | Layout, modal, table, filter, loading/error/empty primitives. |
| `refactor(pos): extract cashier pricing and cart domains` | Cart immutable update, pricing engine, unit tests. |
| `fix(pos): make checkout atomic and idempotent` | RPC/service, stock ledger, sale/payment recovery. |
| `feat(pos): replace QR popup printing with bridge document jobs` | Preview responsive, QR generation offline/local, bulk queue. |
| `fix(pos): add state transition guards and reconciliation` | KDS, meja, retur, transfer, cash close. |
| `test(pos): add staging RLS and end-to-end scenario matrix` | Test runtime, role denial, multi-outlet, offline/recovery. |

## Catatan batasan audit

Audit ini merupakan static review repository, validasi build/lint/test, route comparison, dan pemeriksaan screenshot yang diberikan pengguna. Live page diarahkan ke halaman utama dengan parameter redirect karena sesi audit tidak terautentikasi, sehingga tidak dilakukan login atau pengujian data pengguna. Temuan yang berlabel risiko harus dikonfirmasi melalui staging dan printer/perangkat nyata sebelum diperlakukan sebagai bug produksi.
