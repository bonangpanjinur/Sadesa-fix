# Audit dan rancangan panduan fitur pengguna

## Cakupan

Panduan satu kali tampil untuk akun pembeli, pedagang, dan ojek/courier. Panduan tidak muncul pada route admin, admin desa, atau verifikator. Pengguna harus masuk agar progres dapat dipisahkan berdasarkan akun. Halaman login, pendaftaran, checkout, QR pay, dan penghapusan akun tidak diberi overlay panduan.

## Materi per persona

### Pembeli

1. Katalog produk dan toko lokal.
2. Keranjang, alamat pengantaran, dan checkout.
3. Status pesanan, pelacakan, dan riwayat.
4. Ojek dan layanan antar.
5. Wisata dan jasa lokal.
6. Akun, alamat, dan dukungan.

### Pedagang

1. Dashboard dan pengelolaan pesanan.
2. Katalog produk serta stok.
3. Fulfillment, refund, dan chat pelanggan.
4. Promo, flash sale, voucher, dan loyalitas.
5. Analitik penjualan dan laporan keuangan.
6. Wallet komisi, saldo/tagihan, dan top-up; halaman kuota lama hanya histori.

### Ojek/courier

1. Dashboard, status kerja, dan izin lokasi.
2. Penawaran perjalanan ojek.
3. Pengiriman barang/marketplace.
4. Riwayat, pendapatan, dan performa.
5. Wallet komisi dan top-up, terpisah dari setoran operasional.
6. Chat dan pencairan saldo.

Setiap tip menyediakan tautan langsung ke bagian terkait. Daftar langkah dipilih sesuai role dan route kerja saat itu.

## Aturan tampil dan penyimpanan progres

- Setiap langkah memiliki ID sendiri; ketika ditampilkan, ID dicatat dan tidak ditampilkan kembali pada akun-role yang sama di browser/perangkat tersebut.
- Tombol **Nanti** atau tutup menunda sisa langkah untuk sesi tab saat ini. Langkah yang belum ditampilkan akan dilanjutkan pada sesi aplikasi berikutnya.
- Penyimpanan menggunakan `localStorage`, dibatasi per user ID dan role; tidak membutuhkan tabel/migration SQL baru.
- Admin/internal staff dikecualikan sebelum membaca atau menulis progres panduan.
- Data lokal browser dapat dihapus dengan membersihkan data aplikasi/situs. Sebagian platform PWA dapat mempertahankan penyimpanan origin setelah ikon aplikasi dihapus; dalam kasus itu, bersihkan data situs/aplikasi untuk mengulang panduan.

## File implementasi

- `src/lib/featureTour.ts`: katalog tip, penentuan role-route, dan pembacaan progres.
- `src/components/onboarding/FeatureTour.tsx`: kartu panduan kecil responsif lintas halaman.
- `src/App.tsx`: pemasangan pada root aplikasi; role admin/staff tidak menampilkan panduan.
- `src/lib/featureTour.test.ts`: tes role, route aman, pemisahan progres, dan tip yang belum terlihat.
