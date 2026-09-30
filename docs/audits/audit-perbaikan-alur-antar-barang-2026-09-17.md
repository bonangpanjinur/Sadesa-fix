# Audit dan Perbaikan Alur Antar Barang

**Tanggal:** 17 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** pemesan, dispatch/penawaran kurir, pickup, pengantaran, estimasi biaya/ETA, live tracking, penyelesaian, dan riwayat buyer.

## Alur operasional yang disepakati

1. **Pemesan mengisi booking.** Pemesan menentukan mode kirim/ambil, titik pickup, titik tujuan, penerima, nomor telepon, jenis barang, berat, catatan, dan bila perlu COD. Peta menampilkan rute jalan dan estimasi tarif berdasarkan jarak, berat, serta biaya COD.
2. **Harga dikunci sebelum order dibuat.** RPC `create_courier_order` memvalidasi autentikasi, koordinat, alamat, penerima, jenis barang, berat maksimum 50 kg, dan jarak layanan maksimum 10 km. Order disimpan sebagai `COURIER_DELIVERY`, dengan `subtotal = 0`, biaya layanan pada `shipping_cost`, dan total pada `total`.
3. **Dispatch mencari kurir.** Order masuk pada status `ASSIGNED`. Server menawarkan order ke kurir aktif/approved/available yang memiliki lokasi GPS dan paling dekat dengan pickup. Jika belum ada kurir, order tetap `ASSIGNED` dan dapat dicoba kembali.
4. **Kurir menerima atau menolak.** Kurir melihat pickup, tujuan, penerima, catatan, estimasi pendapatan, total order, jarak, ETA, dan countdown expiry. Tombol **Terima** dan **Tolak** memanggil RPC authoritative; order tidak dianggap diterima hanya karena UI berubah.
5. **Kurir menuju pickup.** Setelah diterima, status menjadi `COURIER_ACCEPTED`. Kurir memiliki navigasi ke titik pickup. Setelah barang diserahkan dan diverifikasi sesuai kebijakan, status menjadi `PICKED_UP`.
6. **Kurir mengantar.** Kurir memulai perjalanan dan status menjadi `DELIVERING`/`SENT` sesuai kompatibilitas status legacy. Buyer melihat status yang sudah dibedakan sebagai “Kurir Mengantar” atau “Dalam Perjalanan”, bukan “Diantar Penjual”.
7. **Buyer memantau.** Halaman tracking menampilkan kurir, ETA, jarak, dan peta live selama status aktif dan kurir memiliki koordinat terbaru. Chat/telepon kurir hanya tersedia pada status dan pihak yang diizinkan.
8. **Serah terima dan penutupan.** Kurir mengunggah proof of delivery lalu status menjadi `DELIVERED`. Buyer dapat mengonfirmasi penerimaan melalui RPC `buyer_confirm_delivery`, yang hanya mengizinkan transisi `DELIVERED -> DONE` untuk order milik buyer tersebut. Jika buyer tidak mengonfirmasi, mekanisme auto-complete yang sudah ada tetap menjadi fallback.
9. **Riwayat buyer.** Order antar barang tampil sebagai **Ojek & Kurir → Antar barang**, menampilkan pickup, tujuan, jenis/berat paket, dan **Biaya Layanan**. Order marketplace tetap menampilkan toko, item, subtotal, reorder, invoice, dan chat penjual. Ride penumpang tetap tampil sebagai subtype terpisah dalam kategori Ojek & Kurir.

## Perbaikan yang diterapkan

- Memperbaiki label status buyer: `DELIVERING` menjadi **Kurir Mengantar** dan `SENT` menjadi **Dalam Perjalanan**.
- Memperbaiki urutan progress buyer agar mencakup `READY`, `COURIER_ACCEPTED`, `PICKED_UP`, dan `DELIVERING`.
- Menambahkan tombol **Lacak Kurir** pada kartu riwayat order kurir aktif; aksi produk tidak ditampilkan untuk order kurir.
- Menambahkan detail pickup, paket, berat, dan catatan pada halaman tracking buyer.
- Mengubah ringkasan finansial order kurir menjadi **Biaya Layanan/Tarif antar**, tanpa subtotal produk palsu.
- Menambahkan jarak dan ETA pada kartu penawaran kurir menggunakan koordinat pickup dan tujuan.
- Mengganti update langsung status `DONE` pada buyer dengan RPC `buyer_confirm_delivery` dan pencatatan `order_status_history`.
- Menambahkan migrasi `74_20260917201000_buyer_delivery_confirmation.sql` untuk RPC tersebut.

## Acceptance criteria

| Area | Hasil |
|---|---|
| Klasifikasi riwayat | Order kurir tidak lagi dianggap sebagai toko/produk |
| Harga | Buyer melihat biaya layanan; kurir melihat estimasi pendapatan |
| Penawaran | Offer memiliki expiry, pickup, tujuan, jarak, ETA, dan aksi terotorisasi |
| Tracking | Buyer dapat membuka live tracking dari riwayat dan halaman detail |
| Keamanan status | Konfirmasi selesai buyer dibatasi RPC dan ownership buyer |
| Kompatibilitas | Fallback legacy tetap memakai klasifikasi deterministik dan status lama masih dibaca |
| Verifikasi | Lint, build, dan test lulus: 63 test files, 230 passed, 20 skipped |

## Dependensi rollout

Migrasi database harus dijalankan melalui pipeline Supabase resmi sebelum tombol konfirmasi buyer digunakan di environment target. Live tracking bergantung pada kurir memberikan heartbeat GPS; bila GPS stale atau offline, UI harus memperlakukan posisi sebagai tidak realtime dan tetap menampilkan status terakhir. Reassign otomatis setelah kurir menolak atau offer timeout masih merupakan pekerjaan lanjutan karena memerlukan kebijakan radius, prioritas, dan batas percobaan.
