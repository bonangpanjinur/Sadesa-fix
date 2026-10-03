# Audit Halaman `/account` dan Fitur Akun

**Tanggal:** 3 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** route `/account`, profile loading/editing, avatar, alamat, onboarding merchant/kurir/penyedia jasa, dashboard role, menu akun, logout, route target, `/settings`, dan quality gate frontend.

## Ringkasan Eksekutif

Halaman `/account` sudah memiliki cakupan fitur yang luas dan route utama yang lengkap. Pengguna dapat mengedit profil, mengelola alamat, membuka wishlist/chat/bantuan, melihat transaksi dan reward, mengakses dashboard sesuai role, serta keluar dari akun.

Temuan utama berada pada **kejujuran state UI dan konsistensi keamanan**, bukan pada ketiadaan fitur:

1. Error saat memuat profil hanya ditulis ke console sehingga pengguna melihat data kosong atau fallback tanpa tahu bahwa request gagal.
2. Error saat memeriksa status pendaftaran partner ditafsirkan sebagai kondisi yang menyembunyikan onboarding, bukan sebagai error yang dapat diulang.
3. Tombol edit profil hanya berupa icon tanpa accessible name dan target klik yang cukup besar.
4. `/settings` masih menerima password minimum 6 karakter, sedangkan registrasi menggunakan policy minimum 8 karakter dengan huruf besar, huruf kecil, dan angka.
5. Tidak ditemukan dead link pada menu AccountPage setelah dibandingkan dengan route aktual di `App.tsx`.

## Temuan dan Perbaikan

| ID | Prioritas | Area | Temuan | Perbaikan |
|---|---|---|---|---|
| ACC-P1-01 | P1 | Profile loading | `fetchProfile` hanya `console.error`, lalu halaman tetap menampilkan fallback/data kosong. | Menambahkan `profileError`, inline alert, tombol `Coba lagi`, dan tombol `Muat ulang`. |
| ACC-P1-02 | P1 | Partner onboarding | Kegagalan query merchant/courier/service dianggap `true`, sehingga onboarding dapat disembunyikan dan status tidak jelas. | Memisahkan state error dengan `partnerCheckError`; nilai aplikasi dikembalikan ke `null` dan tersedia retry. |
| ACC-P2-03 | P2 | Accessibility | Tombol edit profil tidak memiliki `type`, `aria-label`, tooltip, dan target klik minimum. | Menambahkan `type="button"`, `aria-label`, `title`, serta target minimum 44px. |
| ACC-P1-04 | P1 | Password policy | Settings menerima password 6 karakter, tidak konsisten dengan registrasi. | Menggunakan `passwordSchema` terpusat: minimal 8 karakter, huruf besar, huruf kecil, dan angka. |
| ACC-P2-05 | P2 | Navigation | Menu akun perlu diverifikasi terhadap route aktual agar tidak ada dead-end. | Semua target menu yang diaudit tersedia di `App.tsx`, termasuk `/help`, `/addresses`, `/wishlist`, `/notifications`, dan `/settings`. |

## Alur yang Diaudit

### Profil

- Auth loading dan profile loading dipisahkan.
- Profile query memiliki fallback compatibility untuk schema lama.
- Profile editor memvalidasi nama, nomor Indonesia, NIK merchant, alamat bertingkat, dan URL Google Maps.
- Upload avatar membatasi file ke image maksimal 2MB dan menyimpan ke bucket `profile-images` dengan path berbasis user ID.
- Profil belum lengkap tidak mengunci akses menu; kewajiban tambahan hanya berlaku sesuai role merchant/kurir.

### Onboarding Partner

- Status merchant, courier, dan service provider diperiksa berdasarkan `user.id`.
- Onboarding merchant/kurir hanya ditampilkan untuk buyer tanpa role bisnis aktif.
- Error pemeriksaan tidak lagi mengubah status menjadi seolah-olah sudah memiliki aplikasi.
- Retry memulai pemeriksaan ulang tanpa reload halaman.

### Role Dashboard

Dashboard ditampilkan berdasarkan role AuthContext:

- Admin
- Admin Desa
- Verifikator
- Merchant
- Kurir
- Penyedia jasa

Route guard tetap menjadi kontrol keamanan utama; tombol AccountPage hanya merupakan navigasi UI.

### Menu dan Route

Target menu yang diverifikasi:

- `/buyer/chat`
- `/wishlist`
- `/addresses`
- `/help`
- `/orders`
- `/reviews/mine`
- `/ride/history`
- `/langganan`
- `/cashback`
- `/loyalty`
- `/recently-viewed`
- `/notifications`
- `/settings`
- `/privacy`
- `/terms`

Tidak ditemukan target menu yang tidak memiliki route.

## Perubahan Source

- `src/pages/AccountPage.tsx`
  - Error profile yang terlihat pengguna.
  - Retry profile dan status onboarding.
  - Judul halaman `Akun Saya`.
  - Accessible edit profile control.
  - State `null` untuk status onboarding yang belum diketahui atau gagal dimuat.

- `src/pages/SettingsPage.tsx`
  - Validasi perubahan password memakai schema terpusat.
  - Copy placeholder mengikuti policy keamanan terbaru.

## Validasi

| Pemeriksaan | Hasil |
|---|---|
| `pnpm exec tsc --noEmit` | Lulus |
| `pnpm lint` | Lulus |
| `pnpm exec vitest run src/lib/serviceMarketplaceContract.test.ts src/lib/orderStatus.test.ts` | 13 test lulus |
| `pnpm build` | Berhasil |
| `git diff --check` | Bersih |

## Residual Risk dan Rekomendasi Lanjutan

1. Audit database live untuk policy profile, storage avatar, dan role tetap diperlukan; route guard/frontend bukan security boundary.
2. `AuthContext` masih memiliki fallback buyer ketika role query gagal. Ini fail-closed untuk akses role tinggi, tetapi dapat membingungkan pengguna merchant dan layak diberi state `rolesError` dengan retry.
3. Perubahan role admin sebaiknya tetap memakai RPC atomic dan guard admin terakhir sesuai audit auth terdahulu.
4. Belum ada automated component test khusus untuk `AccountPage` yang mensimulasikan profile query gagal, retry, dan partner query gagal. Test tersebut disarankan sebagai langkah berikutnya.
5. Pengujian visual pada viewport 320px, 375px, dan desktop belum dijalankan melalui browser; validasi saat ini berbasis source, route inspection, lint, typecheck, test, dan build.
