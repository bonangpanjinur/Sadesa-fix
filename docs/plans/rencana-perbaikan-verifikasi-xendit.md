# Rencana Perbaikan Website SaDesa untuk Verifikasi Xendit

**Tujuan:** membuat `https://www.sadesa.id/` memenuhi pemeriksaan Xendit terkait bukti bisnis, produk/layanan, harga, checkout, alamat usaha, dan kontak yang dapat diverifikasi publik.

## Ringkasan prioritas

| Prioritas | Masalah | Perbaikan | Target selesai |
|---|---|---|---|
| P0 | Alamat usaha dan kontak belum terlihat jelas | Tambahkan halaman Kontak/Tentang Kami dan tampilkan di footer | Sebelum pengajuan ulang |
| P0 | Produk terlihat berstatus “Tutup” | Pastikan produk contoh aktif, stok tersedia, dan dapat dimasukkan ke keranjang | Sebelum pengajuan ulang |
| P0 | Checkout belum mudah diverifikasi | Sediakan alur publik dari produk ke checkout dan pastikan tidak rusak | Sebelum pengajuan ulang |
| P0 | Informasi badan usaha belum lengkap | Tampilkan nama legal PT, alamat, email, telepon, dan identitas usaha yang konsisten | Sebelum pengajuan ulang |
| P1 | Layanan ojek hanya mengarah ke login | Buat halaman publik berisi deskripsi layanan, area, tarif/contoh harga, dan cara pemesanan | Setelah perbaikan P0 atau bersamaan |
| P1 | Informasi kebijakan transaksi belum terlihat kuat | Tambahkan refund, pembatalan, pengiriman, privasi, dan syarat & ketentuan | Sebelum pengajuan ulang |
| P1 | Crawler Xendit mungkin tidak melihat konten dinamis | Pastikan konten penting tersedia dalam HTML yang dapat dibaca tanpa login/interaksi kompleks | Sebelum pengajuan ulang |

## Fase 1 — Audit dan konsistensi data usaha

### 1.1 Kumpulkan data resmi

Siapkan satu sumber data yang sama untuk website dan dashboard Xendit:

- Nama badan usaha: **PT RAKA SISTEM NUSANTARA** atau nama legal yang tercantum pada dokumen.
- Nama brand: **SaDesa**.
- Alamat terdaftar dan alamat operasional, bila berbeda.
- Nomor telepon/WhatsApp bisnis yang aktif.
- Email bisnis yang dapat menerima balasan.
- Jam operasional.
- Deskripsi bisnis yang singkat dan konsisten.
- Wilayah layanan dan jenis produk/layanan.

**Catatan:** jangan menggunakan alamat, nomor, atau nama yang berbeda dari dokumen legal dan data yang dikirim ke Xendit.

### 1.2 Cocokkan dengan dashboard Xendit

- Samakan deskripsi bisnis dengan isi halaman Tentang Kami.
- Pastikan kategori bisnis sesuai: marketplace/platform produk lokal, makanan-minuman, kebutuhan harian, dan/atau layanan antar.
- Pastikan domain yang dikirim adalah domain utama yang aktif: `https://www.sadesa.id/`.
- Pastikan dokumen Business License menggunakan dokumen legal yang relevan dengan badan usaha pemilik website.

## Fase 2 — Tambahkan halaman informasi publik

### 2.1 Halaman Tentang Kami

Buat `/about` atau `/tentang-kami` yang menjelaskan:

- SaDesa adalah apa dan siapa target penggunanya.
- Produk/layanan yang tersedia.
- Hubungan SaDesa dengan PT RAKA SISTEM NUSANTARA.
- Wilayah operasi.
- Cara penjual/mitra dan pelanggan menggunakan platform.

Contoh deskripsi:

> SaDesa adalah platform marketplace lokal yang membantu pelanggan membeli makanan, minuman, kebutuhan harian, dan menggunakan layanan antar dari pelaku usaha lokal. SaDesa dioperasikan oleh PT RAKA SISTEM NUSANTARA.

### 2.2 Halaman Kontak

Buat `/contact` atau `/kontak` yang dapat dibuka tanpa login. Tampilkan:

- Nama legal perusahaan.
- Alamat lengkap.
- Nomor telepon dan/atau WhatsApp.
- Email dukungan.
- Jam operasional.
- Formulir kontak sederhana, bila tersedia.
- Tautan Google Maps, bila sesuai.

Tambahkan tautan halaman ini di footer semua halaman utama.

### 2.3 Footer global

Footer minimal berisi tautan ke:

- Tentang Kami
- Kontak
- Produk/Katalog
- Cara Belanja
- Kebijakan Privasi
- Syarat & Ketentuan
- Kebijakan Refund/Pembatalan
- Kebijakan Pengiriman atau Layanan Antar

## Fase 3 — Rapikan katalog produk dan layanan

### 3.1 Produk

Untuk minimal 3–5 produk contoh, pastikan:

- Produk aktif dan dapat dipesan.
- Status bukan “Tutup”.
- Ada foto produk.
- Ada nama dan deskripsi yang jelas.
- Ada harga dalam Rupiah.
- Ada informasi stok atau ketersediaan.
- Ada nama toko/penjual.
- Ada variasi atau biaya tambahan bila relevan.
- Tombol “Tambah ke Keranjang” berfungsi tanpa error.

Hindari mengirimkan website untuk verifikasi ketika seluruh produk contoh sedang tutup.

### 3.2 Layanan ojek/antar

Buat halaman publik `/ride` yang tidak langsung memaksa login. Isi minimal:

- Penjelasan layanan.
- Area layanan.
- Tarif dasar atau contoh perhitungan tarif.
- Estimasi waktu.
- Cara pemesanan.
- Biaya tambahan bila ada.
- Ketentuan pembatalan.

Login tetap boleh diperlukan untuk pemesanan, tetapi informasi dasar layanan dan harga harus dapat dibaca publik.

## Fase 4 — Pastikan checkout dapat diverifikasi

Buat satu skenario uji yang mudah dilakukan oleh reviewer:

1. Buka halaman utama.
2. Buka katalog.
3. Pilih produk yang aktif.
4. Tambahkan produk ke keranjang.
5. Lihat subtotal, biaya pengiriman, dan total.
6. Isi alamat pengiriman.
7. Lanjut ke halaman checkout.
8. Lihat metode pembayaran dan ringkasan pesanan.

Pastikan:

- Tidak ada 404, error JavaScript, atau halaman kosong.
- Total harga konsisten dari keranjang ke checkout.
- Harga dan mata uang terlihat jelas sebagai Rupiah.
- Produk tidak hilang saat pindah halaman.
- Checkout dapat diuji tanpa akun khusus reviewer, atau sediakan akun demo melalui kanal resmi Xendit bila memang diperlukan.
- Jika login wajib, halaman sebelum login tetap menampilkan produk, harga, keranjang, dan penjelasan cara checkout.
- Jangan meminta pembayaran nyata saat pengujian internal.

## Fase 5 — Tambahkan kebijakan transaksi

Sediakan halaman yang mudah ditemukan untuk:

- **Refund:** kondisi refund, proses pengajuan, estimasi waktu, dan metode pengembalian dana.
- **Pembatalan:** kapan pesanan dapat dibatalkan dan siapa yang dapat membatalkan.
- **Pengiriman/layanan:** area cakupan, estimasi, biaya, dan kendala operasional.
- **Syarat & Ketentuan:** aturan penggunaan platform dan transaksi.
- **Privasi:** data yang dikumpulkan dan tujuan penggunaannya.
- **Keluhan:** kanal pengaduan dan waktu respons.

## Fase 6 — Optimasi agar mudah dibaca reviewer dan crawler

- Pastikan website bisa dibuka tanpa login untuk halaman utama, katalog, detail produk, Tentang Kami, dan Kontak.
- Gunakan teks HTML untuk nama produk, harga, alamat, dan nomor kontak; jangan hanya menaruh informasi di gambar/banner.
- Pastikan halaman tidak diblokir oleh `robots.txt`, firewall, atau geoblocking.
- Pastikan HTTPS valid dan tidak ada redirect berulang.
- Pastikan `www.sadesa.id` dan `sadesa.id` konsisten mengarah ke website yang sama.
- Tambahkan metadata dasar: nama bisnis, deskripsi, alamat, dan URL kanonis.
- Periksa tampilan desktop dan mobile.
- Pastikan halaman penting tidak bergantung sepenuhnya pada data yang hanya muncul setelah login.

## Fase 7 — Checklist QA sebelum kirim ulang

### Uji sebagai pengunjung tanpa login

- [ ] Beranda menampilkan deskripsi bisnis.
- [ ] Katalog dapat dibuka.
- [ ] Produk aktif terlihat.
- [ ] Harga terlihat dalam Rupiah.
- [ ] Detail produk dapat dibuka.
- [ ] Alamat usaha terlihat.
- [ ] Nomor telepon/WhatsApp terlihat.
- [ ] Email bisnis terlihat.
- [ ] Tentang Kami dapat dibuka.
- [ ] Kontak dapat dibuka.
- [ ] Syarat & Ketentuan dapat dibuka.
- [ ] Kebijakan Privasi dapat dibuka.
- [ ] Refund/pembatalan dapat dibuka.

### Uji checkout

- [ ] Produk dapat ditambahkan ke keranjang.
- [ ] Subtotal dan total dihitung benar.
- [ ] Alamat pengiriman dapat diisi.
- [ ] Biaya pengiriman ditampilkan atau dijelaskan.
- [ ] Halaman checkout dapat dibuka.
- [ ] Metode pembayaran ditampilkan.
- [ ] Tidak ada error di console atau halaman.

### Uji akses publik

- [ ] Website bisa dibuka dari mode incognito.
- [ ] Website bisa dibuka dari jaringan seluler.
- [ ] Tidak ada halaman maintenance.
- [ ] Tidak semua produk berstatus “Tutup”.
- [ ] Semua tautan footer bekerja.
- [ ] URL utama yang dikirim ke Xendit mengarah ke halaman yang informatif.

## Urutan implementasi paling cepat

1. Aktifkan 3–5 produk uji dengan harga dan stok yang realistis.
2. Tambahkan alamat, nomor telepon/WhatsApp, email, dan nama legal ke footer.
3. Buat halaman Tentang Kami dan Kontak.
4. Perbaiki alur produk → keranjang → checkout.
5. Buat halaman publik untuk layanan ojek/antar.
6. Tambahkan kebijakan refund, pembatalan, dan pengiriman.
7. Uji seluruh website melalui mode incognito.
8. Ambil screenshot internal sebagai bukti QA, bila diperlukan.
9. Kirim ulang URL utama ke Xendit dan isi ulang bagian yang diminta dengan data yang konsisten.

## Kriteria selesai

Perbaikan dianggap siap dikirim ulang apabila reviewer Xendit yang belum login dapat:

- memahami SaDesa menjual atau menyediakan apa;
- melihat produk/layanan dan harga;
- menemukan alamat dan kontak bisnis;
- membuka detail produk;
- memahami cara melakukan checkout;
- menemukan kebijakan transaksi;
- melihat bahwa website aktif dan tidak seluruh produknya sedang tutup.

## Catatan risiko

- Jika produk memang hanya tersedia pada jam tertentu, tetap sediakan beberapa produk demo/aktif atau jadwal operasional yang jelas saat proses verifikasi.
- Jika SaDesa adalah marketplace, jelaskan apakah pembayaran diterima oleh platform atau langsung diteruskan ke merchant.
- Jangan menampilkan data kontak atau alamat yang tidak benar hanya untuk melewati verifikasi; semua informasi harus sesuai dokumen dan operasi bisnis sebenarnya.
