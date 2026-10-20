# SaDesa — Screenshot fitur utama

Screenshot ini adalah tangkapan langsung dari preview repository. Nama file menunjukkan fitur dan role. Beberapa halaman menggunakan data yang tersedia di preview, jadi daftar wisata/penyedia dapat terlihat kosong.

Catatan: browser screenshot berjalan di sesi terpisah dari preview pengguna. Status login di preview tidak ikut terbawa, sehingga rute yang butuh autentikasi hanya dapat ditangkap sebagai gerbang login.

## Pembeli

| Fitur | Rute | Screenshot | Catatan |
|---|---|---|---|
| Beranda marketplace | `/` | [01-beranda-marketplace.jpg](01-beranda-marketplace.jpg) | Screenshot menampilkan panduan pengenalan fitur di atas beranda. |
| Login pembeli | `/auth` | [02-login-pembeli.jpg](02-login-pembeli.jpg) | Tampilan awal login; formulir pendaftaran belum dibuka pada screenshot. |
| Jelajahi katalog produk | `/products` | [03-katalog-produk-pembeli.jpg](03-katalog-produk-pembeli.jpg) | Kategori dan jumlah produk yang tampil di preview. |
| Keranjang | `/cart` | [04-keranjang-pesanan.jpg](04-keranjang-pesanan.jpg) | Keranjang kosong pada sesi screenshot. |
| Info checkout dan checkout tamu | `/checkout-info` | [05-checkout-data-pengiriman.jpg](05-checkout-data-pengiriman.jpg) | Menjelaskan alur keranjang, data pengiriman, dan pembayaran. |
| Wisata desa | `/tourism` | [07-daftar-wisata.jpg](07-daftar-wisata.jpg) | Filter wisata tersedia, tetapi belum ada data wisata di preview. |
| Pilih layanan Ojek/kurir | `/ride` | [08-layanan-ojek-transportasi.jpg](08-layanan-ojek-transportasi.jpg) | Memisahkan layanan ojek penumpang dan kurir barang. |

## Pedagang

| Fitur | Rute | Screenshot | Catatan |
|---|---|---|---|
| Daftar menjadi pedagang | `/register/merchant` | [09-daftar-merchant-terlindungi-login.jpg](09-daftar-merchant-terlindungi-login.jpg) | Rute membutuhkan login; yang tertangkap adalah gerbang login, bukan formulir pendaftaran. |
| Tambah/kelola produk | `/merchant/products` | [11-tambah-produk-pedagang-terlindungi-login.jpg](11-tambah-produk-pedagang-terlindungi-login.jpg) | Dashboard pedagang membutuhkan akun pedagang. |

## Ojek

| Fitur | Rute | Screenshot | Catatan |
|---|---|---|---|
| Daftar menjadi Ojek/kurir | `/register/courier` | [10-daftar-ojek-terlindungi-login.jpg](10-daftar-ojek-terlindungi-login.jpg) | Rute membutuhkan login; yang tertangkap adalah gerbang login, bukan formulir pendaftaran. |
| Terima pesanan pengantaran | `/courier/deliveries` | [12-terima-pesanan-ojek-terlindungi-login.jpg](12-terima-pesanan-ojek-terlindungi-login.jpg) | Dashboard order membutuhkan akun kurir/Ojek. |

## Jasa

| Fitur | Rute | Screenshot | Catatan |
|---|---|---|---|
| Direktori penyedia jasa | `/services` | [06-direktori-jasa.jpg](06-direktori-jasa.jpg) | Daftar kategori dan alur mencari penyedia; data preview saat capture menunjukkan 0 penyedia. |
| Permintaan jasa | `/services/requests` | [14-permintaan-jasa-terlindungi-login.jpg](14-permintaan-jasa-terlindungi-login.jpg) | Rute mengarahkan pengguna ke login sebelum melihat permintaan. |

## Screenshot demo lokal — data contoh

Layar berikut dibuat khusus untuk dokumentasi karena sesi screenshot tidak berbagi login preview dan sebagian data belum tersedia. Buka [indeks demo lokal](demo/index.html) untuk melihat daftar layar. Semua layar menampilkan label **DEMO — data contoh, bukan transaksi nyata**; tombol tidak membuat akun, pesanan, atau pembayaran.

| Role | Fitur | Screenshot demo |
|---|---|---|
| Pembeli | Daftar akun | [19-demo-daftar-pembeli.jpg](19-demo-daftar-pembeli.jpg) |
| Pembeli | Detail produk | [20-demo-detail-produk-pembeli.jpg](20-demo-detail-produk-pembeli.jpg) |
| Pembeli | Keranjang berisi pesanan | [21-demo-keranjang-berisi.jpg](21-demo-keranjang-berisi.jpg) |
| Pembeli | Checkout dan pilihan pembayaran | [22-demo-checkout-pembayaran.jpg](22-demo-checkout-pembayaran.jpg) |
| Pembeli | Instruksi pembayaran dan status pesanan | [23-demo-konfirmasi-pembayaran.jpg](23-demo-konfirmasi-pembayaran.jpg) |
| Pedagang | Daftar menjadi pedagang | [24-demo-daftar-pedagang.jpg](24-demo-daftar-pedagang.jpg) |
| Pedagang | Tambah produk | [25-demo-tambah-produk-pedagang.jpg](25-demo-tambah-produk-pedagang.jpg) |
| Ojek | Daftar Ojek/kurir | [26-demo-daftar-ojek.jpg](26-demo-daftar-ojek.jpg) |
| Ojek | Terima pesanan pengantaran | [27-demo-terima-pesanan-ojek.jpg](27-demo-terima-pesanan-ojek.jpg) |
| Jasa | Formulir permintaan jasa | [28-demo-permintaan-jasa.jpg](28-demo-permintaan-jasa.jpg) |
| Wisata | Detail wisata dan formulir pemesanan | [29-demo-pemesanan-wisata.jpg](29-demo-pemesanan-wisata.jpg) |
| Jasa | Profil penyedia jasa | [30-demo-profil-penyedia-jasa.jpg](30-demo-profil-penyedia-jasa.jpg) |

## Batasan screenshot aplikasi live

- Screenshot live untuk formulir pendaftaran pembeli/pedagang/Ojek, dashboard produk pedagang, dan pesanan Ojek masih menampilkan gerbang login. Browser screenshot memakai sesi terpisah dari preview pengguna.
- `/checkout` live belum tertangkap karena Vite gagal menemukan `@googlemaps/js-api-loader` di `node_modules`, meskipun paket tercantum di `package.json` dan lockfile. Percobaan pemulihan dependensi tidak berhasil.
- Status pembayaran demo adalah contoh transfer tertunda; tidak ada order atau pembayaran nyata.
- Direktori jasa dan wisata live belum memiliki data saat screenshot diambil. Screenshot detail jasa/wisata di atas adalah ilustrasi demo lokal.

