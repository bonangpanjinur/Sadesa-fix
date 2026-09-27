# Audit dan Implementasi `/products` — Makanan & Minuman

**Tanggal:** 27 September 2026  
**Scope:** buyer catalog `/products` ketika dibuka dari kategori makanan/kuliner (`?type=makanan`, `?type=minuman`, atau `?type=kuliner`).

## Temuan sebelum perbaikan

1. Halaman memakai layout katalog generik untuk semua kategori sehingga konteks makanan tidak terasa khusus.
2. Tidak ada hero kuliner, kategori visual, rekomendasi menu horizontal/berbentuk kartu, atau daftar warung sebagai discovery layer.
3. Kartu produk generik menampilkan terlalu banyak metadata untuk katalog makanan dan tombol tambah berada di dalam `Link`, yaitu struktur interaktif bersarang yang kurang baik untuk keyboard/screen reader.
4. Header katalog masih mengikuti header global; referensi membutuhkan header kontekstual dengan tombol kembali, judul kategori, dan akses keranjang.
5. Error state dan retry sudah ada di katalog generik, tetapi belum disajikan dalam pengalaman makanan yang lebih ringkas.

## Implementasi

Perubahan pada `src/pages/ProductsPage.tsx`:

- Menambahkan `FoodCatalogView` khusus ketika `catalogProfile.isFood` bernilai true.
- Menambahkan header kontekstual: kembali, judul `Makanan & Minuman`, dan shortcut keranjang.
- Menambahkan search field `Cari makanan atau minuman...`.
- Menambahkan hero kuliner berbasis gambar produk live pertama yang tersedia, sehingga tidak membutuhkan aset baru.
- Menambahkan kategori horizontal: Semua, Nasi, Mie, Minuman, Snack, Kopi.
- Menambahkan section `Rekomendasi untuk kamu` dengan kartu menu dua kolom.
- Menambahkan rating, merchant, estimasi pengantaran, harga, wishlist toggle, dan tombol tambah keranjang.
- Memisahkan tombol tambah dari navigasi kartu secara event handling untuk mencegah navigasi saat menambah produk.
- Menambahkan section `Warung Terdekat` yang dikelompokkan berdasarkan `merchantId` (bukan nama merchant).
- Mempertahankan layout generik untuk kategori non-makanan agar tidak mengubah perilaku katalog lain.
- Mempertahankan loading, error, retry, URL category state, dan data dari `fetchProducts`.

## Validasi

| Pemeriksaan | Hasil |
|---|---|
| `pnpm exec tsc --noEmit` | PASS |
| `pnpm run lint` | PASS |
| `pnpm run build` | PASS |
| `git diff --check` | PASS |
| `pnpm test -- --run` | 3 gagal lama di area ekspedisi/chat; 76 file lulus, 289 test lulus, 20 skip |

Kegagalan test yang ada tidak mengarah ke file `ProductsPage.tsx`; assertion yang gagal berkaitan dengan field UI `p_service_type: 'JOB'` dan validasi SQL `FULL JOIN` pada acceptance test chat.
