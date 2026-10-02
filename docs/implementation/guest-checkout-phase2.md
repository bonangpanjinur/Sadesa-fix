# Tahap 2 — Frontend Guest Checkout dan Payment UI

Frontend sekarang menjalankan flow checkout yang sama untuk user login maupun guest. Route `/checkout` tidak lagi mengarahkan guest ke halaman login; guest mengisi nama, nomor telepon, alamat, lokasi, pengiriman, dan memilih transfer bank.

## Token dan link status

Session checkout guest memiliki key lokal yang stabil untuk idempotensi. Setelah RPC guest berhasil, token akses disimpan lokal bersama order ID dan expiry, lalu dipakai untuk membentuk link:

- Status: `/guest-orders/:orderId?guest_token=...`
- Pembayaran transfer: `/payment/:orderId?guest_token=...`

Halaman status memanggil `get_guest_order_status`, menampilkan item, subtotal, ongkir, total, status order, expiry token, serta tombol ke payment UI dan salin link. Token tetap diperlukan; order ID saja tidak cukup.

## Payment UI

`PaymentConfirmationPage` sekarang mendukung dua mode:

- User login tetap membaca order dengan ownership query lama.
- Guest membaca payment context melalui `get_guest_order_payment_context`.

Guest dapat melihat rekening/QRIS merchant, menyalin rekening dan nominal, serta mengunggah bukti transfer. Upload guest menggunakan path `orders/<order-id>/<sha256-token>/<random-file>` dan RPC `guest_submit_payment_proof`; policy storage anon hanya menerima path yang cocok dengan hash token order guest yang masih berlaku.

Pembayaran online Xendit tetap ditampilkan hanya untuk user login pada tahap ini karena endpoint invoice existing memerlukan auth session. Guest menggunakan transfer bank/QRIS sampai endpoint invoice token-scoped ditambahkan.

## Validasi

Build production, `tsc --noEmit`, lint file yang diubah, validator bootstrap, dan test kontrak order/payment existing harus lulus sebelum deployment. Migration bundle `66_20261002190000_guest_payment_ui.sql` harus diterapkan lebih dahulu atau bersamaan dengan frontend.
