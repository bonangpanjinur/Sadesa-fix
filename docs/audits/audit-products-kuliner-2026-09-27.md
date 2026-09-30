# Audit halaman `/products?type=kuliner`

**Tanggal:** 27 September 2026  
**URL audit:** <https://www.sadesa.id/products?type=kuliner>

## Temuan live

1. **Popup install PWA terlalu cepat dan menutupi katalog.** Pada first visit, dialog muncul ketika pengguna sedang membaca produk sehingga mengganggu discovery dan menutup konteks halaman.
2. **Fallback foto menyesatkan.** Produk tanpa foto memakai foto keripik sebagai fallback global; di live ditemukan menu dimsum tampil dengan gambar keripik.
3. **Konten rekomendasi kurang memprioritaskan produk yang bisa dipesan.** Banyak item pertama berstatus `Toko Tutup`, sehingga area rekomendasi terlihat tidak actionable.
4. **Label “Warung Terdekat” tidak selalu akurat.** Data live menunjukkan jarak sekitar 22–34 km, sehingga istilah “terdekat” terlalu menjanjikan.
5. **Rating `0.0` tidak informatif.** Nilai nol pada merchant tanpa ulasan terbaca seperti rating buruk, bukan data yang belum tersedia.

## Perbaikan yang diimplementasikan

- `src/components/pwa/InstallBanner.tsx`
  - Menunda prompt dari 5 menjadi 15 detik.
  - Tidak menampilkan prompt pada alur `/products`, `/cart`, `/checkout`, dan `/orders`; install tetap tersedia di `/install`.
- `src/lib/api.ts`
  - Mengganti fallback global foto keripik dengan `/placeholder.svg` ketika produk tidak memiliki foto sendiri.
- `src/pages/ProductsPage.tsx`
  - Memprioritaskan merchant yang sedang buka pada daftar warung.
  - Memprioritaskan produk yang tersedia pada promo dan rekomendasi.
  - Mengubah judul menjadi `Warung di sekitar` hanya jika radius terdekat ≤10 km; jika tidak, memakai `Warung pilihan`.
  - Mengganti rating nol/null menjadi `Belum ada ulasan`.

## Validasi

- `pnpm exec tsc --noEmit` — PASS
- `pnpm lint` — PASS
- `pnpm run build` — PASS
- `git diff --check` — PASS
