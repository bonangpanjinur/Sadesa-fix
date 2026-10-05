# Audit Tampilan Depan — Kategori dan Produk Terbaru

**Tanggal:** 5 Oktober 2026

## Temuan sebelum perubahan

1. Kartu paling atas masih memakai layanan statis: `Makanan & Minuman`, `Ojek`, dan `Belanja`.
2. Komponen `ProductCategoryCards` sudah tersedia dan membaca kategori aktif dari database, tetapi belum dirender di `Index.tsx`.
3. Konfigurasi section `categories` ada, tetapi render halaman depan secara eksplisit melewati section tersebut.
4. Produk terbaru sudah memiliki tombol `Lihat semua`, tetapi menampilkan hingga enam produk sehingga area awal cukup panjang.
5. Kategori admin dapat memiliki subkategori dan kategori tambahan dinamis, tetapi belum terlihat pada beranda.

## Perubahan

### Kategori utama

Kartu utama beranda sekarang menampilkan:

- Makanan
- Minuman
- Belanja

Masing-masing mengarah ke katalog produk dengan filter kategori yang sesuai.

### Kategori lainnya dinamis

Kategori aktif selain kategori utama dibaca dari tabel kategori admin dan ditampilkan secara horizontal dengan batas maksimal enam kartu. Ini mencakup kategori tambahan maupun subkategori yang dikonfigurasi admin.

Section ini memiliki tombol **Lihat semua** menuju katalog produk.

### Produk terbaru

Section `Produk terbaru` tetap menampilkan produk berdasarkan `created_at` terbaru, tetapi dibatasi menjadi maksimal empat produk pada tampilan depan. Tombol **Lihat semua** tetap menuju katalog lengkap.

Produk promo yang sudah tampil di blok promo tidak diulang pada blok produk terbaru.

## Validasi

- ESLint file tampilan: lulus.
- TypeScript: lulus.
- Uji fisik tampilan responsif: masih disarankan pada viewport mobile dan desktop.

## Catatan produk

Ojek tidak dihapus dari sistem atau route, tetapi dikeluarkan dari tiga kartu kategori produk utama agar fokus awal beranda sesuai kebutuhan: makanan, minuman, dan belanja. Akses layanan ojek tetap tersedia melalui route dan navigasi aplikasi.
