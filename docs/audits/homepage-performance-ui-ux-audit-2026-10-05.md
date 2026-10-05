# Audit Homepage SaDesa — Performa & UI/UX

Tanggal: 5 Oktober 2026  
Scope: first viewport homepage publik (`/`), loading awal, hierarchy navigasi, dan asset/query yang langsung dipakai halaman awal.

## Temuan utama

### P0 — Payload produk homepage terlalu besar
Homepage sebelumnya meminta hingga **48 produk**, sementara layar awal hanya menampilkan maksimal 6 kartu promo dan 4 kartu produk terbaru. Query ini juga membawa relasi merchant dan menjalankan pemeriksaan quota untuk seluruh item yang diambil.

**Dampak:** request database, normalisasi data, dan potensi image discovery lebih berat dari kebutuhan first visit.

### P1 — Konfigurasi gambar kartu layanan selalu stale
`homepage-service-card-images` menggunakan `staleTime: 0`, sehingga navigasi kembali ke homepage dapat memicu request ulang walaupun konfigurasi jarang berubah.

**Dampak:** request tambahan pada interaksi yang seharusnya instant.

### P1 — First viewport dapat kosong di area hero
Hero hanya dirender jika query promosi memiliki hasil. Saat query lambat, error, atau tidak ada promosi aktif, area discovery utama hilang dan halaman langsung melompat ke konten berikutnya.

**Dampak UX:** hierarchy tidak stabil, CTA discovery tidak konsisten, dan halaman terasa belum siap.

### P2 — Prioritas image first viewport belum eksplisit
Kartu layanan utama belum membedakan image pertama yang langsung terlihat dengan image berikutnya.

## Implementasi

- Menurunkan limit query produk homepage dari `48` menjadi `16`, cukup sebagai buffer untuk kombinasi promo dan produk terbaru tanpa mengambil katalog penuh.
- Menetapkan cache kartu layanan: `staleTime` 5 menit dan `gcTime` 15 menit.
- Menetapkan image kartu makanan pertama sebagai `loading="eager"`; kartu lain tetap `lazy`, seluruhnya `decoding="async"`.
- Menambahkan `DEFAULT_HERO_SLIDES` berbasis asset lokal terkompresi untuk menjaga first viewport tetap informatif saat promosi remote belum tersedia.
- Fallback hero tetap memakai CTA yang relevan: kuliner, Ojek Desa, dan wisata.
- Menambahkan `public/manus-routes.json` berisi 249 route halaman yang diturunkan dari definisi route aktual, tanpa route 404 wildcard.

## Prinsip UI/UX yang dipertahankan

- Tugas utama tetap terlihat paling awal: pilih layanan, pilih alamat, cari, atau masuk ke katalog.
- CTA fallback menggunakan bahasa tindakan yang jelas dan sesuai konteks.
- Tidak mengubah kontrak API, alur checkout, auth, atau aturan bisnis.
- Fallback lokal tidak memanggil analytics promosi karena bukan banner sponsor yang berasal dari database.

## Validasi

- `pnpm exec eslint src/pages/Index.tsx src/components/home/HomeServiceCards.tsx src/components/home/HeroCarousel.tsx src/components/home/heroDefaults.ts` — **lulus tanpa error/warning**.
- `pnpm exec vitest run src/components/home/HeroCarousel.test.tsx` — **2 test lulus**.
- `pnpm build` — **sukses**.
- `git diff --check` — **bersih**.
- Manifest route JSON — **249 route valid**, termasuk `/`.

## Catatan lanjutan

Build masih menghasilkan warning existing terkait dynamic import Supabase yang juga di-static-import oleh banyak modul; ini tidak memblokir build. Test HeroCarousel juga menampilkan warning React existing karena `fetchPriority` diteruskan melalui Framer Motion; perilakunya tidak gagal dan dapat ditangani terpisah jika ingin membersihkan seluruh warning test suite.
