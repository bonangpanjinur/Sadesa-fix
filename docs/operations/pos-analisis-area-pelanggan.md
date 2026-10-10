# Analisis Area Pelanggan Teramai di POS

Fitur ini membantu pedagang melihat area asal pelanggan yang paling banyak bertransaksi. Ringkasan tersedia di **POS → Pelanggan & Promo POS → Analitik Pelanggan → Area Teramai**.

## Cara menggunakan

1. Buka **POS → Pelanggan**.
2. Tambah atau edit profil pelanggan, lalu isi **Kecamatan** dan **Kabupaten/Kota**. Alamat lama tidak otomatis diubah menjadi wilayah; lengkapi profil yang ingin dianalisis.
3. Buka **Analitik Pelanggan → Area Teramai**.
4. Pilih periode analisis. Peringkat mengikuti outlet aktif yang dipilih di POS.

Setiap baris area menampilkan jumlah pelanggan unik, jumlah transaksi, dan omzet. Area diurutkan berdasarkan jumlah pelanggan unik. CSV Analitik Pelanggan juga menyertakan ringkasan area.

## Cakupan dan privasi

- Hanya transaksi selesai yang terhubung ke profil pelanggan dengan wilayah terisi yang dihitung. Transaksi pelanggan umum/tanpa profil atau profil tanpa wilayah tidak masuk ke peringkat.
- Area memakai kecamatan dan kabupaten/kota terkini pada profil pelanggan; wilayah historis saat transaksi tidak disimpan terpisah.
- Tab menampilkan data agregat tanpa nama pelanggan atau koordinat GPS.
- Fitur mengikuti akses POS berbayar dan hak akses modul laporan yang sudah berlaku.

## Prasyarat rilis

Sebelum aplikasi yang memuat fitur ini dirilis, terapkan [migration POS customer area analytics](../../supabase/bootstrap/94_20261010113000_pos_customer_area_analytics.sql) melalui alur deployment database yang disetujui. Setelah migration diterapkan, lengkapi wilayah profil pelanggan agar data dapat muncul.
