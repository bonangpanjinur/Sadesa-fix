# Audit Performa Aplikasi SaDesa — Buyer, Ojek, dan Pedagang

**Tanggal:** 3 Oktober 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Cakupan:** startup aplikasi, autentikasi, routing/lazy loading, service worker, katalog buyer, background polling, dan route operasional ojek/pedagang.

## Ringkasan eksekutif

Fondasi performa aplikasi sudah cukup baik: halaman sudah lazy-loaded, service worker hanya melakukan precache terhadap app shell, retry query dibatasi, dan katalog homepage memakai payload yang lebih kecil. Build produksi menghasilkan **19 entry precache sekitar 1.083 KiB**.

Perbaikan yang diterapkan pada audit ini berfokus pada request yang terjadi sebelum dan sesudah layar pertama:

1. **Login lebih ringan:** pengecekan pemulihan role sekarang hanya membaca tabel profil yang memang diperlukan. Akun normal tidak lagi selalu melakukan query ke tabel `merchants` dan `couriers` sekaligus.
2. **Sesi ojek/pedagang lebih ringan:** polling notifikasi restok wishlist hanya aktif untuk role `buyer`; sesi ojek dan pedagang tidak lagi melakukan query wishlist/produk dan potensi insert notifikasi saat startup.

## Temuan dan tindakan

| Area | Temuan | Tindakan | Dampak yang diharapkan |
|---|---|---|---|
| Auth startup | Setelah role authoritative terbaca, aplikasi tetap memeriksa `merchants` dan `couriers` untuk setiap user. | Query recovery dibuat kondisional berdasarkan role yang belum ada. | Buyer normal menghemat 2 request; merchant/courier menghemat minimal 1 request pada login. |
| Background buyer feature | `useRestockNotification` berjalan untuk semua user authenticated, termasuk ojek dan pedagang. | Handler mengaktifkan hook hanya saat role mencakup `buyer`; hook diberi parameter `enabled`. | Tidak ada query wishlist/product dan polling 5-menit pada sesi non-buyer. |
| App shell | Route sudah lazy-loaded dan transisi global tidak lagi mengirim `framer-motion` pada entry route. | Dipertahankan; tidak diubah ulang. | Startup tetap menggunakan route chunks sesuai kebutuhan. |
| PWA install | Precache sudah dibatasi ke shell kritis. | Dipertahankan. | Install/update PWA tidak menarik seluruh route admin, merchant, POS, dan aset media. |
| Katalog buyer | Homepage memakai `limit: 48` dan `includeReviews: false`; katalog memakai `includeReviews: false` serta cache React Query. | Dipertahankan; tidak mengubah kontrak katalog. | Payload katalog tetap terkendali tanpa menghilangkan fitur pencarian/filter. |
| Ojek realtime | Alarm courier memakai query yang scoped ke courier dan polling 15 detik untuk recovery. | Tidak diubah karena terkait keandalan offer dan batas visibilitas data. | Optimasi tidak mengorbankan penerimaan order/ride offer. |
| Pedagang realtime | Alarm merchant memakai query scoped ke merchant dan channel realtime. | Tidak diubah karena diperlukan untuk order baru. | Notifikasi order tetap responsif. |

## Validasi teknis

- `pnpm exec tsc --noEmit` — **lulus**
- `pnpm lint` — **lulus**
- `pnpm build` — **lulus**
- Precache service worker — **19 entry / 1.083 KiB**
- Test terarah auth/hooks — **30 test lulus dalam 9 file**
- `git diff --check` — **lulus**

Catatan: percobaan pertama memakai opsi Jest `--runInBand`, yang tidak didukung Vitest. Test kemudian dijalankan ulang dengan perintah Vitest yang benar dan lulus.

## Prioritas lanjutan

### P0 — ukur di staging/perangkat nyata

1. Uji buyer, ojek, dan pedagang pada Android kelas menengah melalui jaringan 3G/4G.
2. Catat `LCP`, `INP`, `CLS`, waktu sampai halaman interaktif, jumlah request sampai first content, dan waktu query Supabase.
3. Uji cold load, reload, navigasi kedua, dan kondisi offline/reconnect.

### P1 — optimasi aset

- Logo fallback WebP sudah dipakai di header/footer/splash, tetapi `public/branding/sadesa-logo.png` masih berukuran sekitar 782 KB dan tetap perlu dipertahankan hanya bila ada integrasi legacy yang masih merujuknya.
- Audit lanjutan dapat memeriksa seluruh referensi gambar langsung `<img>` di halaman operasional dan menggantinya secara bertahap dengan `OptimizedImage`, khususnya gambar katalog, dashboard pedagang, dan daftar order.
- Jangan mengoptimalkan dokumen privat, bukti pembayaran, atau bukti pengantaran dengan cache publik.

### P1 — observability

Tambahkan pengukuran client-side untuk:

- durasi `auth.getSession()` dan query role;
- waktu query katalog buyer;
- durasi first route chunk untuk `/courier`, `/merchant`, dan `/merchant/pos`;
- jumlah request dan ukuran response per route;
- error/reconnect realtime.

## Batasan audit

Audit ini adalah inspeksi source code dan build lokal. Belum ada pengukuran browser nyata terhadap deployment staging/production, belum ada fixture volume besar, dan belum ada profiling jaringan pada perangkat pengguna. Karena itu, angka LCP/INP/CLS dan dampak query harus dikonfirmasi setelah deploy staging.

## File yang diubah

- `src/App.tsx`
- `src/contexts/AuthContext.tsx`
- `src/hooks/useRestockNotification.ts`
- `docs/audits/audit-performa-semua-role-2026-10-03.md`
