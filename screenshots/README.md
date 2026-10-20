# SaDesa — Screenshot fitur utama

Screenshot ini adalah tangkapan langsung dari preview repository. Nama file menunjukkan fitur dan role. Beberapa halaman menggunakan data yang tersedia di preview, jadi daftar wisata/penyedia dapat terlihat kosong.

## Pembeli

| Fitur | Rute | Screenshot | Catatan |
|---|---|---|---|
| Beranda marketplace | `/` | [01-beranda-marketplace.jpg](01-beranda-marketplace.jpg) | Screenshot menampilkan panduan pengenalan fitur di atas beranda. |
| Login dan pintu masuk pendaftaran pembeli | `/auth` | [02-login-pendaftaran-pembeli.jpg](02-login-pendaftaran-pembeli.jpg) | Tombol “Daftar” mengarah ke alur pendaftaran; screenshot menangkap tampilan login awal. |
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
| Permintaan jasa | `/services/requests` | [14-permintaan-jasa.jpg](14-permintaan-jasa.jpg) | Rute mengarahkan pengguna ke login sebelum melihat permintaan. |

## Belum berhasil ditangkap

- **Formulir pendaftaran pedagang dan Ojek serta dashboard tambah produk/terima pesanan:** rute-rute tersebut dilindungi login. Capture browser tidak memiliki sesi pengguna dan autentikasi tidak dilewati.
- **Pembayaran checkout:** `/checkout` menampilkan error Vite karena `@googlemaps/js-api-loader` tercantum di `package.json`, tetapi paket tidak tersedia di `node_modules`. Tidak ada screenshot error yang disajikan sebagai screenshot fitur.
- **Konfirmasi pembayaran:** perlu order aktif agar halaman konfirmasi menampilkan data nyata.

