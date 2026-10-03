# Audit Halaman Profil (`/profile`)

**Tanggal:** 3 Oktober 2026
**Cakupan:** routing `/profile`, halaman akun/profil yang sudah ada (`/account`), pemuatan ulang profil, dan aksesibilitas form profil.

## Ringkasan

`/profile` sebelumnya tidak terdaftar di `App.tsx`, sehingga URL yang diminta jatuh ke halaman 404. Implementasi profil sudah ada pada `AccountPage`, yang juga melayani `/account`. Perbaikan menambahkan `/profile` sebagai **alias terlindungi** ke halaman yang sama; `/account` tetap menjadi URL yang dipakai navigasi yang sudah ada.

## Temuan dan perbaikan

| Prioritas | Temuan | Perbaikan |
| --- | --- | --- |
| P1 | `/profile` tidak memiliki route dan berakhir pada 404. | Mendaftarkan route `/profile` dengan `ProtectedRoute` dan `AccountPage`, sama seperti `/account`. Menambahkan `/profile` ke daftar buyer paths. |
| P2 | Aksi muat ulang/retry profil tidak memasuki state `loading`; tombol bisa ditekan berulang dan UI tampak tidak merespons. | `fetchProfile` kini memulai loading state untuk request awal maupun pemuatan ulang; indikator loading diberi role/status aksesibel. |
| P2 | Tombol kamera untuk unggah avatar tidak memiliki nama aksesibel dan target sentuhnya kecil. | Memberi `aria-label`/title dan memperbesar target kontrol. |
| P2 | Label nama lengkap dan nomor WhatsApp tidak terhubung ke input masing-masing; nama masih dapat diubah saat save sedang berjalan. | Menghubungkan `Label` ke input, memberi autofill metadata, dan menonaktifkan input nama selama save. |

### Cakupan yang dipertahankan

- Kedua route tetap memakai `ProtectedRoute`; alias tidak membuka data profil ke pengguna anonim.
- Alur onboarding role, validasi nomor/NIK, alamat, dan penyimpanan yang ada tidak diubah.
- Menu yang ada tetap menggunakan `/account`; hanya direct-link `/profile` yang ditambahkan.
- Tidak ada perubahan database atau migration.

## Validasi

| Pemeriksaan | Hasil |
| --- | --- |
| Suite Vitest penuh | Lulus: 113 file test; 438 lulus, 20 dilewati |
| ESLint (`pnpm lint`) | Lulus |
| Production build + PWA (`pnpm build`) | Lulus; service worker berhasil dibuat |
| TypeScript (`tsc --noEmit -p tsconfig.app.json`) | Masih gagal dengan 16 diagnostic baseline pada `GoogleAddressInput.tsx`, `GoogleRideMap.tsx`, dan `googleMaps.ts` (deklarasi global Google Maps). Tidak ada diagnostic pada file yang diubah dalam audit ini. |
