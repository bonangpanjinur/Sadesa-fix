# Audit Route `/dashboard`

**Tanggal:** 3 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** route entrypoint, authentication, role resolution, redirect precedence, dan regression tests.

## Ringkasan

Sebelum perubahan, tidak ada route literal `/dashboard` di `src/App.tsx`; URL tersebut masuk ke catch-all `NotFound`. Aplikasi sudah memiliki dashboard terpisah bagi admin, admin desa, verifikator, merchant, kurir, dan penyedia jasa, serta fungsi `getRedirectPathForRoles` sebagai sumber prioritas tujuan. Akibatnya, pengguna yang membuka tautan/bookmark umum `/dashboard` tidak dapat mencapai workspace mereka.

## Temuan dan Perbaikan

| Prioritas | Temuan | Implementasi |
|---|---|---|
| P1 | `/dashboard` tidak terdaftar dan menampilkan 404. | Menambahkan `DashboardRoute` pada route `/dashboard` sebagai pintu masuk dashboard umum. |
| P1 | Pengguna tanpa sesi tidak menerima alur autentikasi yang mempertahankan konteks route. | Pengunjung diarahkan ke `/auth` dengan `/dashboard` disimpan dalam `state.from`; redirect memakai `replace`. |
| P1 | Pemilihan dashboard harus menunggu role agar tidak terjadi redirect awal ke tujuan yang keliru. | Menampilkan status pemuatan yang dapat diakses selama sesi atau role sedang dimuat. |
| P2 | Pemetaan role tidak boleh menyalin prioritas ke daftar baru. | Menggunakan `getRedirectPathForRoles` yang sudah menjadi kontrak role aplikasi; role ganda mengikuti prioritas yang sama dengan redirect app-entry. |

## Tujuan Peran

- Admin → `/admin`
- Admin desa → `/desa`
- Verifikator → `/verifikator`
- Merchant → `/merchant`
- Kurir → `/courier`
- Penyedia jasa → `/services`
- Buyer → `/`

Route tujuan spesifik tetap menjadi kontrol akses; `/dashboard` hanya entrypoint/redirect, bukan pemberian izin.

## Validasi

| Pemeriksaan | Hasil |
|---|---|
| Test terarah route dan role | Lulus: 18 tes pada 2 file; dijalankan ulang setelah assertion konteks login diperkuat. |
| `pnpm test` | Lulus: 108 file, 421 tes lulus, 20 tes terskip. |
| `pnpm lint` | Lulus. |
| `pnpm build` | Lulus; bundle aplikasi dan service worker PWA berhasil dibangun. |
| `pnpm exec tsc --noEmit -p tsconfig.app.json` | Belum lulus: 16 diagnostic terkait global `google`/`window.google` di `GoogleAddressInput.tsx`, `GoogleRideMap.tsx`, dan `lib/googleMaps.ts`; tidak ada diagnostic pada file perubahan. |
| `git diff --check` | Lulus. |

Test komponen mencakup tujuan tiap role, redirect login yang mempertahankan `/dashboard` sebagai `state.from`, dan loading role.

## Batasan

Redirect penyedia jasa mengikuti pemetaan otoritatif yang sudah ada (`/services`), sementara pintasan akun yang telah ada tetap menuju riwayat penyedia (`/services/provider-history`). Tidak ada perubahan pada skema database, data, izin, atau backend. Type-check penuh masih memerlukan koreksi tipe global Google Maps yang tidak terkait dengan route ini.
