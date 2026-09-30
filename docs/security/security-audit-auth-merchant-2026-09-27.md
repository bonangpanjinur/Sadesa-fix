# Audit Keamanan Autentikasi & API Pedagang

**Tanggal:** 27 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix` (private)  
**Baseline audit:** `e85f1bc` (`fix: resolve remaining TypeScript errors`)  
**Cakupan:** signup/login, role/route guards, pendaftaran pedagang, fungsi RPC merchant, grants/RLS pada tabel merchant dan produk, static RLS inventory, dependency audit, serta E2E alur buyer dan merchant.

## Ringkasan

Audit menemukan **2 risiko HIGH**, **1 risiko MEDIUM**, dan **1 ketidaksesuaian kebijakan yang perlu keputusan produk**. Pengujian UI E2E lokal lulus **5/5 skenario**. E2E memakai backend mock sepenuhnya; tidak ada akun, email, atau data produksi yang dibuat.

**Tindakan prioritas:** batasi hak update pemilik merchant atas kolom state/approval dan hentikan akses baca langsung ke kolom privat dari tabel `merchants`. Temuan ini berasal dari SQL/grants yang ada di repo; belum diuji terhadap project Supabase langsung karena kredensial staging tidak tersedia.

## Temuan

### H-01 — Pemilik merchant dapat mengubah sendiri state approval/status

**Severity: HIGH**

Role `authenticated` memiliki `UPDATE` tabel `public.merchants` (`supabase/bootstrap/01_20260127034916_to_20260907020000.sql:21112`). Policy `Merchants can update own data` membatasi baris dengan `user_id = auth.uid()`, tetapi tidak membatasi kolom yang dapat diubah (`...sql:22238-22245`). RLS adalah pembatas baris, bukan pembatas kolom. Tidak ditemukan policy pengganti yang menghapus hak update mandiri ini setelah policy dibuat.

Akibatnya, pemilik merchant dapat mengubah kolom workflow yang sama pada baris miliknya—termasuk `registration_status` dan `status`—tanpa alur review/otorisasi khusus. Ini juga bertentangan dengan komentar pada trigger bahwa admin dapat menonaktifkan merchant kemudian: policy update pemilik dapat dipakai untuk mengaktifkan kembali baris sendiri. Kebijakan update produk juga memberi merchant kendali `FOR ALL` atas produk miliknya (`...sql:23537-23539`), sementara pembacaan publik produk hanya mensyaratkan `is_active = true` (`...sql:23502-23509`).

**Rekomendasi:** hapus update generik oleh pemilik untuk state yang dilindungi; pindahkan perubahan ke RPC yang memeriksa pemilik dan kolom yang diizinkan, atau gunakan trigger guard eksplisit. Status persetujuan, aktivasi/deaktivasi, identitas pemilik, assignment verifikator, dan status halal harus hanya diubah oleh otoritas yang berwenang. Uji bahwa merchant dapat memperbarui pengaturan yang memang diizinkan, tetapi tidak dapat mengubah approval/status, termasuk setelah admin menonaktifkan atau menolak merchant.

### H-02 — Seluruh kolom merchant aktif dapat dibaca oleh role publik/pengguna terautentikasi

**Severity: HIGH**

Tabel diberi `GRANT SELECT ON public.merchants TO anon` dan `GRANT SELECT ... TO authenticated` pada seluruh tabel (`...sql:21105-21112`). Policy anon memungkinkan pembacaan baris merchant `ACTIVE`/`APPROVED` (`...sql:22280-22287`); policy authenticated juga membuka baris aktif selain baris milik sendiri (`supabase/bootstrap/24_20260924110000_verifikator_own_scope.sql:7-17`). Policy tersebut membatasi baris, bukan kolom.

Skema tabel mencakup data yang bukan informasi publik toko, antara lain `bank_account_number`, `bank_account_name`, `halal_certificate_url`, dan `ktp_url` (`...sql:20645-20670`). Pembatasan field pada komponen React tidak melindungi REST API: klien dapat meminta kolom lain selama role memiliki table-level `SELECT`.

**Rekomendasi:** cabut `SELECT` langsung publik pada tabel dasar; buat permukaan baca publik berbentuk view/API allowlist yang hanya memuat informasi toko aman. Batasi tabel dasar ke pemilik/admin/verifikator sesuai kebutuhan dan lindungi data bank serta dokumen identitas secara terpisah. Migrasi perlu mencakup audit seluruh caller frontend dan tes anon/buyer/merchant/admin pada staging agar tidak memutus katalog dan pencarian.

### M-01 — RPC registrasi belum memvalidasi sejumlah field tepercaya di server

**Severity: MEDIUM**

`register_merchant_atomic` sudah melakukan pemeriksaan penting: `auth.uid()` harus sama dengan `p_user_id`, pendaftaran aktif ganda ditolak, kategori harus aktif, dan jadwal harus berisi tujuh hari unik (`supabase/bootstrap/48_20260927150000_atomic_merchant_registration_and_settings.sql:40-85`). Hak eksekusinya juga dicabut dari `PUBLIC`/`anon` dan diberikan hanya kepada `authenticated` (`:192-193`).

Namun, fungsi kemudian menyimpan nilai dari pemanggil untuk `p_halal_status`, URL sertifikat/KTP, kategori teks, kode verifikator, dan grup tanpa validasi otoritatif yang sebanding (`:88-104`). UI hanya membatasi pilihan halal ke `NONE`, `PENDING_VERIFICATION`, atau `REQUESTED` dan mensyaratkan foto KTP untuk kondisi kategori kuliner tertentu (`src/pages/RegisterMerchantPage.tsx:107-109, 326-329`); pemeriksaan browser dapat dilewati dengan memanggil RPC secara langsung. Nilai `VERIFIED` digunakan aplikasi untuk badge/filter halal dan seharusnya bukan klaim mandiri.

**Rekomendasi:** validasi enum/status di database dan jangan izinkan status `VERIFIED` dari RPC pendaftaran; turunkan kategori utama dari ID kategori yang divalidasi; validasi kode referral/grup dari tabel otoritatif; validasi bahwa path berkas berada di bucket/path pengguna yang sedang mendaftar; tegakkan kewajiban dokumen kategori kuliner di sisi server.

### P-01 — Kebijakan auto-approval database tidak selaras dengan UI pendaftaran

**Severity: perlu konfirmasi kebijakan bisnis (HIGH bila verifikasi manusia memang wajib)**

RPC registrasi mengirim nilai awal `PENDING`/`INACTIVE` (`...48_20260927150000_atomic_merchant_registration_and_settings.sql:88-104`), dan UI menampilkan proses review/pending. Namun trigger `auto_approve_merchant_registration` berjalan `BEFORE INSERT`, mengganti semua insert menjadi `APPROVED`/`ACTIVE` dan memberi role `buyer` serta `merchant` (`supabase/bootstrap/10_20260922191500_auto_approve_merchants.sql:7-28, 33-38`). Policy insert authenticated juga dibangun dengan asumsi input `PENDING` (`:81-89`). Ini tampak disengaja oleh migrasi auto-approval, tetapi berlawanan dengan pesan UI seperti “Verifikasi Tim” dan state dashboard “Menunggu persetujuan”.

**Rekomendasi:** putuskan secara eksplisit apakah merchant memang langsung aktif. Jika perlu review, hilangkan auto-approval dan role/akses aktif sebelum approval. Jika auto-approval memang produk yang dikehendaki, perbarui UI, state pending yang tidak tercapai, dan kebijakan moderasi agar konsisten. Kedua pilihan perlu tes integrasi staging.

## Kontrol yang berfungsi / pemeriksaan tambahan

- `ProtectedRoute` mengarahkan pengguna anonim ke halaman auth dan menolak pengguna tanpa role merchant; jalur merchant yang bukan dashboard juga memeriksa status merchant.
- `user_roles` hanya dapat dibaca oleh pemilik/admin; insert/update/delete dibatasi untuk admin dalam policy yang diaudit.
- `update_merchant_settings_atomic` memeriksa sesi, kepemilikan merchant, status `ACTIVE` dan `APPROVED`, serta ID kategori aktif sebelum menulis.
- Static RLS inventory: **216 tabel**, **214 RLS aktif**, **209 tabel dengan policy**, **491 fungsi SECURITY DEFINER** terdeteksi. Dua tabel chat-retention tanpa RLS memiliki `REVOKE ALL` dari `PUBLIC`, `anon`, dan `authenticated`; tabel tanpa policy lainnya yang ditinjau juga memakai RLS aktif atau privilege client yang dicabut. Ini pemeriksaan inventory, bukan review semantik seluruh 491 fungsi.
- `pnpm audit --audit-level high`: **No known vulnerabilities found**.

## Hasil E2E

Chromium berjalan terhadap Vite lokal. Semua request Supabase, email/auth, dan API wilayah **diintersep/dimock atau diblokir**; kredensial sesi hanya dummy lokal. Hasil:

1. **PASS** — homepage buyer merender konten, blok kategori produk yang sebelumnya dihapus tidak muncul, tanpa uncaught JS error.
2. **PASS** — pengguna anonim yang membuka pendaftaran merchant diarahkan ke auth.
3. **PASS** — signup buyer dengan input valid mencapai halaman konfirmasi email pada auth mock.
4. **PASS** — buyer terautentikasi memilih kategori/alamat dan mengirim formulir; mock memverifikasi RPC memakai `p_user_id` sesi, ID kategori, dan tujuh hari jadwal, lalu halaman dashboard merchant aktif dirender.
5. **PASS** — pengguna ber-role buyer tanpa role merchant ditolak dari workspace merchant.

**Hasil:** `5/5 passed`. Perilaku backend trigger auto-approval dimodelkan sebagai response `APPROVED`/`ACTIVE`; hasil ini tidak menggantikan tes transaksi/RLS database.

## Batas audit dan tindak lanjut

- `scripts/security-api-smoke.sh` tidak dapat dijalankan terhadap backend karena `SUPABASE_TEST_URL` (serta variabel staging terkait) tidak dikonfigurasi. Skrip berhenti aman sebelum mengirim request.
- `src/test/rls.integration.test.ts` membutuhkan akun/fixture multi-tenant staging; tidak dijalankan tanpa fixture tersebut.
- Tidak ada migrasi SQL yang diterapkan ke Supabase dan tidak ada request tulis ke backend nyata selama audit ini.
- Sebelum menyebut temuan H-01/H-02 selesai, jalankan tes RLS negatif/positif di staging untuk anon, buyer, merchant pemilik, merchant lain, verifikator, dan admin; verifikasi pula penolakan update status dan pembacaan data bank/KTP.
