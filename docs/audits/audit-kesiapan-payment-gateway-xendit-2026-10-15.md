# Audit Kesiapan API Payment Gateway Xendit — 15 Oktober 2026

## Keputusan

**Belum siap untuk menerima transaksi produksi.** Fondasi integrasi Xendit sudah ada untuk invoice marketplace dan top-up wallet komisi, tetapi pengelolaan credential dan pemisahan test/live belum aman dan konsisten. Perbaiki dua temuan P1 di bawah sebelum mengaktifkan pembayaran online di production.

Audit ini adalah pemeriksaan kode dan dokumentasi repository. Audit **tidak** memeriksa Supabase production, nilai secret, Dashboard Xendit, status deployment Edge Function, aktivasi payment channel, atau transaksi nyata. Status lingkungan tersebut tetap **belum terverifikasi**.

## Cakupan integrasi yang ditemukan

| Alur | Status dalam repository | Catatan |
|---|---|---|
| Checkout marketplace dengan metode `ONLINE` | Implementasi ada | Client meminta invoice; Edge Function membuat invoice IDR dari total order yang dibaca di server. |
| Status invoice marketplace | Implementasi ada | Client dapat meminta status dari provider; webhook memproses status ke database. Redirect browser bukan bukti pembayaran. |
| Top-up wallet komisi merchant/courier | Implementasi ada | Memakai invoice Xendit dan jalur callback/RPC tersendiri. |
| Guest checkout | Online gateway tidak didukung | Guest checkout dibatasi ke transfer manual; jangan menganggapnya tercakup oleh integrasi Xendit. |
| Marketplace jasa | Belum memakai gateway | Panduan layanan menyebut pembayaran manual dan rekonsiliasi di luar aplikasi. |
| POS / Midtrans | Belum terbukti terintegrasi | Layar konfigurasi Midtrans ada, tetapi tidak ditemukan Edge Function atau caller API Midtrans yang setara dengan jalur Xendit. |

## Kontrol yang sudah tersedia

- `xendit-payment` memerlukan JWT dan memvalidasi user melalui Supabase Auth. Pembuatan invoice memastikan order dimiliki user yang login; nominal dan mata uang (`IDR`) berasal dari data order di server.
- Invoice memakai kunci idempotensi dan reservasi database agar retry tidak langsung membuat invoice/order baru.
- `xendit-webhook` memang dikonfigurasi `verify_jwt = false` untuk menerima callback provider, tetapi handler memvalidasi header `x-callback-token` sebelum memproses data.
- RPC webhook mengunci order, mencocokkan ID invoice, memeriksa nominal paid terhadap total order, dan mengabaikan event duplikat. Akses RPC ledger dibatasi untuk `service_role`.
- RLS `app_settings` mengecualikan `payment_xendit` dari policy pembacaan publik.
- Aturan checkout database menolak metode `ONLINE` jika `payment_xendit.enabled` tidak aktif. Nilai seed pada bootstrap dimulai dalam keadaan nonaktif.

Kontrol tersebut adalah hasil inspeksi source; belum membuktikan bahwa versi Edge Function, migration, secret, dan webhook yang sama sudah diterapkan di lingkungan staging atau production.

## Temuan dan keputusan yang dibutuhkan

### P1 — Secret key dan callback token masuk ke browser admin

Edge Function membaca `secret_key` dan `callback_token` dari JSON `app_settings.payment_xendit`. Halaman admin memanggil `fetchAppSettings()` yang mengambil `select('*')`, lalu mengisi kedua nilai tersebut ke komponen formulir. Karena itu, meskipun policy publik mengecualikan baris ini, secret tetap dikirim ke browser setiap admin yang berhak membaca pengaturan.

Ini juga tidak sesuai dengan `.env.example` dan `scripts/check-production-env.sh`, yang menyebut `XENDIT_SECRET_KEY` dan `XENDIT_CALLBACK_TOKEN` sebagai secret server-side. Kedua Edge Function saat ini **tidak membaca** nama environment tersebut; konfigurasi lewat Function Secrets saja tidak akan mengaktifkan jalur kode yang sekarang.

**Sebelum production:**

1. Pindahkan pembacaan secret ke Supabase Edge Function Secrets (`Deno.env`); jangan kirim atau render secret di React.
2. Simpan hanya status nonrahasia, misalnya `enabled`, di `app_settings`; hapus input dan pemuatan secret dari layar admin.
3. Gunakan key test dan live yang berbeda pada project/environment Supabase yang berbeda.
4. Jika secret pernah disimpan di database yang dapat dibaca admin, rotasi key dan callback token setelah migrasi. Jangan menyalin nilainya ke Git, `VITE_*`, log, atau dokumen.

### P1 — Sakelar “Mode Production” tidak mengendalikan environment API

UI menyimpan `is_production`, tetapi tidak ada penggunaan field tersebut di Edge Function. Kode memanggil endpoint invoice Xendit yang sama dan mengambil key dari `app_settings`; tidak ada guard yang menolak live key di staging atau test key di production.

Dokumentasi Xendit menyatakan test dan live memakai API key terpisah; mode request ditentukan oleh key yang digunakan. Perlakukan field UI saat ini sebagai **tidak efektif**, bukan perlindungan lingkungan. Hapus/ubah sakelar tersebut atau implementasikan guard server-side yang nyata sebelum operasional.

### P1 — Status setup provider di luar repository belum diketahui

Kode saja tidak membuktikan bahwa:

- kedua Edge Function versi terbaru sudah di-deploy;
- migration/RPC payment sudah diterapkan pada database target;
- webhook Invoice Status di Dashboard Xendit menunjuk ke endpoint `xendit-webhook` yang benar dan memakai token yang sama;
- payment channel yang diperlukan sudah aktif untuk akun live;
- secret tersimpan pada environment Supabase yang benar;
- `payment_xendit.enabled` sengaja tetap nonaktif sampai uji staging lulus.

Jangan menyalakan toggle production untuk menutup ketidakpastian ini.

### P2 — Belum ada tes terisolasi untuk handler Edge Function

Repository memiliki tes kontrak checkout dan guard metode pembayaran, tetapi tidak ditemukan tes unit langsung untuk handler `xendit-payment` atau `xendit-webhook`. Pemeriksaan source tidak menguji autentikasi callback, respons provider, retry, concurrency, atau hasil RPC pada database nyata. Full test suite lokal pada audit setup terakhir juga tidak selesai dalam batas lima menit; hasil itu **bukan** bukti bahwa suite lulus maupun gagal.

Tambahkan tes handler dengan mock provider/database, lalu jalankan tes integrasi pada project staging sebelum mengaktifkan transaksi.

## Urutan kesiapan yang disarankan

### 1. Amankan sumber konfigurasi

- [ ] Pindahkan `secret_key` dan `callback_token` dari `app_settings` ke Supabase Function Secrets.
- [ ] Pastikan Edge Function membaca secret dari server environment dan gagal tertutup jika secret tidak tersedia.
- [ ] Hilangkan pemuatan/penyimpanan secret oleh `AdminSettingsPage` dan pastikan secret lama tidak tersisa di response atau cache.
- [ ] Tentukan satu sumber konfigurasi yang konsisten; sinkronkan `.env.example`, pemeriksaan environment, dan dokumentasi operasional.
- [ ] Buat key test berizin minimum untuk money-in; simpan hanya melalui secrets tooling. Jangan kirim secret melalui chat atau commit.

### 2. Siapkan staging dan callback

- [ ] Pakai project Supabase staging terpisah dari production dan Xendit test key.
- [ ] Terapkan migration/bundle yang sesuai lewat prosedur database resmi; jangan menerapkan ulang bootstrap ke database yang sudah memiliki migration history.
- [ ] Deploy `xendit-payment` dan `xendit-webhook` ke staging.
- [ ] Daftarkan callback invoice ke URL Edge Function staging dari Dashboard Xendit; simpan callback token di secret manager Supabase.
- [ ] Gunakan fitur **Test & Save** di Dashboard dan pastikan request uji diterima handler staging.
- [ ] Verifikasi log hanya memuat metadata yang dibutuhkan dan tidak pernah memuat key, callback token, atau header Authorization.

### 3. Uji alur dan kegagalan

- [ ] User tanpa sesi, user dengan order milik orang lain, order tidak valid, dan invoice yang tidak cocok ditolak.
- [ ] Invoice menggunakan total server yang benar, `IDR`, serta expiry yang diharapkan.
- [ ] Pembayaran sukses mengubah status satu kali; nominal yang berbeda ditolak.
- [ ] Status `PENDING` dan `EXPIRED`, invoice kedaluwarsa lalu retry, serta order yang sudah dibayar tidak menghasilkan status ganda.
- [ ] Callback dengan token salah ditolak; callback duplikat tidak menggandakan perubahan atau top-up.
- [ ] Callback datang berulang atau tidak berurutan tidak menurunkan status terminal yang sudah benar.
- [ ] Provider timeout/error dan kegagalan simpan database dapat dipulihkan tanpa invoice ganda atau pembayaran tanpa order yang dapat direkonsiliasi.
- [ ] Uji top-up wallet secara terpisah dari checkout marketplace; pastikan saldo hanya bertambah satu kali setelah pembayaran terverifikasi.
- [ ] Pastikan keberhasilan redirect browser saja tidak menandai order sebagai `PAID`.

Xendit menyebut webhook dapat dikirim ulang dan tidak selalu tiba dalam urutan tetap. Handler perlu tetap idempotent dan tahan terhadap retry; jangan mengandalkan urutan redirect atau callback.

### 4. Go-live dan rollback

- [ ] UAT staging ditandatangani oleh pemilik produk, operasi, dan finance; cocokkan order, invoice, payment status, serta settlement.
- [ ] Buat live key terpisah dengan izin minimum; aktifkan payment channel yang benar di Dashboard Xendit.
- [ ] Konfigurasikan live secret dan callback di Supabase production secara langsung melalui secrets tooling.
- [ ] Verifikasi migration serta deployment Edge Function production; baru setelah itu aktifkan `payment_xendit.enabled`.
- [ ] Siapkan proses rekonsiliasi, dukungan pelanggan, pembatalan, dan refund. Tidak ada API refund Xendit yang ditemukan pada jalur ini; jangan menganggap refund otomatis tersedia.
- [ ] Untuk rollback, nonaktifkan pembuatan invoice baru melalui flag server/database. Biarkan webhook tetap tersedia untuk menyelesaikan invoice yang sudah dibuat, rekonsiliasi pembayaran terlambat, lalu tangani refund sesuai prosedur finance.

## Referensi source

- `src/lib/paymentApi.ts`
- `src/pages/CheckoutPage.tsx`
- `src/pages/CommissionWalletPage.tsx`
- `src/pages/admin/AdminSettingsPage.tsx`
- `src/lib/adminApi.ts`
- `supabase/functions/xendit-payment/index.ts`
- `supabase/functions/xendit-webhook/index.ts`
- `supabase/config.toml`
- `supabase/bootstrap/01_20260127034916_to_20260907020000.sql`
- `supabase/bootstrap/31_20260924161000_recover_stuck_payment_and_notification_jobs.sql`
- `supabase/bootstrap/119_20261014113000_to_20261014113000.sql`
- `.env.example`
- `scripts/check-production-env.sh`
- `src/lib/checkoutServerContract.test.ts`

## Referensi Xendit

Diperiksa pada 15 Oktober 2026:

- [API keys](https://docs.xendit.co/docs/api-keys) — pemisahan test/live, secret key harus tetap rahasia/server-side, dan least privilege.
- [Pre-integration checklist](https://docs.xendit.co/docs/payments-integration-setup) — aktivasi channel live dan pendaftaran webhook.
- [Handling webhooks](https://docs.xendit.co/docs/handling-webhooks) — `x-callback-token`, callback duplikat, retry, dan urutan event yang tidak tetap.

Dokumen bisnis untuk verifikasi merchant Xendit, seperti alamat usaha, katalog, dan kebijakan publik, berada terpisah di `docs/plans/rencana-perbaikan-verifikasi-xendit.md`; audit tersebut tidak menggantikan kesiapan teknis API ini.
