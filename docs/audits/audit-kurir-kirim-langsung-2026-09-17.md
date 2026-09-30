# Audit Ulang: Kurir Kirim Barang Langsung

**Tanggal:** 17 September 2026  
**Ruang lingkup:** layanan barang milik pemesan sendiri, dikirim dari pickup ke penerima; bukan fulfillment pesanan toko.

## Pembedaan layanan

| Layanan | Sumber barang | Merchant | Data utama | Alur pembatalan |
|---|---|---|---|---|
| Kurir kirim langsung | Pemesan/pengirim | Tidak ada | Pickup, tujuan, penerima, paket, berat, biaya layanan | Bisa dibatalkan sebelum pickup |
| Antar pesanan toko | Merchant | Ada | Toko, order items, subtotal, ongkir | Mengikuti kebijakan order marketplace |
| Ojek penumpang | Penumpang | Tidak ada | Pickup penumpang, tujuan, tarif perjalanan | Mengikuti alur ride |

Secara database layanan langsung menggunakan `orders` dengan `service_type = COURIER_DELIVERY`, `merchant_id = NULL`, `subtotal = 0`, dan field pickup/package. Karena tabel transaksi masih dipakai bersama untuk kompatibilitas, setiap UI harus memakai discriminator tersebut dan tidak boleh menganggap semua `orders` sebagai pesanan toko.

## Temuan audit

1. Booking sudah menggunakan RPC `create_courier_order` dan menyimpan pickup, tujuan, penerima, paket, berat, jarak, dan biaya layanan.
2. Dispatch sudah membuat offer kurir dan mengubah status ke `COURIER_ACCEPTED` ketika kurir menerima.
3. Tracking sudah memiliki ETA, kurir, peta, dan status realtime.
4. **Gap kritis:** halaman tracking direct courier tidak menyediakan tombol **Batalkan pengiriman**.
5. **Gap kritis:** `buyer_cancel_order` sebelumnya hanya menerima `NEW`, `PENDING_PAYMENT`, dan `PENDING_CONFIRMATION`, sehingga direct courier yang masih `ASSIGNED` atau `COURIER_ACCEPTED` tidak dapat dibatalkan walaupun barang belum diambil.
6. **Gap UX:** halaman booking masih hanya menyebut “Layanan antar”, sehingga belum cukup tegas membedakan kirim barang pribadi dari antar pesanan toko.
7. **Gap UX:** aksi marketplace seperti refund merchant dan reorder produk tidak relevan untuk direct courier.

## Aturan pembatalan yang diperbaiki

- `ASSIGNED`: buyer dapat membatalkan; offer aktif ditutup dan courier assignment dibatalkan.
- `COURIER_ACCEPTED`: buyer masih dapat membatalkan selama kurir belum pickup; assignment ditutup, courier dilepas, dan notifikasi dikirim.
- `PICKED_UP`, `DELIVERING`, `DELIVERED`, `DONE`: buyer tidak dapat membatalkan dari tombol biasa. Kasus ini harus menggunakan bantuan/refund karena barang sudah berada dalam proses serah-terima.
- Semua pembatalan direct courier dicatat pada `order_status_history`.
- Ownership buyer dan alasan pembatalan tetap divalidasi server-side.

## Perbaikan yang diterapkan

- Menambahkan banner **Kirim barang langsung** pada halaman tracking.
- Menambahkan tombol **Batalkan pengiriman** pada status `ASSIGNED` dan `COURIER_ACCEPTED`.
- Menambahkan mode dialog pembatalan yang menjelaskan batas pickup.
- Menulis ulang RPC `buyer_cancel_order` melalui migration `75_20260917203000_direct_courier_cancellation.sql` agar menangani direct courier secara khusus.
- Menutup assignment aktif, mengosongkan courier pada order, mencatat history, dan memberi notifikasi kepada kurir ketika buyer membatalkan.
- Menyembunyikan refund merchant dan reorder produk untuk layanan direct courier.
- Memperjelas copy booking: **Kirim barang langsung**, bukan pengiriman pesanan toko.

## Verifikasi

`pnpm lint`, `pnpm build`, dan `pnpm test` berhasil pada verifikasi komprehensif: **63 test files passed, 230 tests passed, 20 skipped**. Validasi runtime Supabase belum dijalankan pada database target; migration harus diterapkan melalui pipeline resmi sebelum rollout.
