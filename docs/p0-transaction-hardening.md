# P0 Transaction Hardening

## Scope

P0 menutup dua kelas kegagalan transaksi: POS checkout yang sebelumnya terdiri dari banyak write client-side, dan payment invoice/webhook yang dapat dipanggil ulang akibat timeout, retry, atau delivery out-of-order.

## Atomic POS checkout

Migration `20260823070000_atomic_pos_checkout.sql` menambahkan tabel `pos_sale_requests` dan fungsi `public.process_pos_sale(...)`. Fungsi tersebut memvalidasi identitas cashier dan akses tenant/outlet, membuat reservation request yang unik, membuat header sale, membuat seluruh sale items, mengunci baris stok dengan `FOR UPDATE`, mengurangi stok, menulis stock mutation, mengurangi bahan baku berdasarkan resep, memperbarui aggregate customer, dan menggunakan voucher—semuanya di dalam satu transaksi PostgreSQL.

Jika salah satu validasi atau write gagal, transaksi dibatalkan sehingga tidak ada sale parsial, item yatim, pengurangan stok tanpa sale, atau voucher usage tanpa transaksi. `request_key` yang sama mengembalikan response sebelumnya; request concurrent yang belum selesai ditolak dengan kondisi in-progress.

Client `POSKasirPage` sekarang memanggil `processAtomicPOSSale` melalui `supabase.rpc`. Request key disimpan dalam ref dan hanya dihapus setelah RPC berhasil. Jika terjadi timeout setelah database sebenarnya committed, retry dengan key yang sama tidak membuat transaksi kedua.

## Payment invoice idempotency

Migration `20260823071000_payment_invoice_idempotency.sql` menambahkan `payment_invoice_requests` dengan unique constraint provider/order. Fungsi `reserve_payment_invoice_request` membuat reservation sebelum request ke Xendit. Request concurrent kedua tidak dapat melewati reservation dan menerima status in-progress. Attempt yang gagal dapat diambil kembali untuk retry; attempt completed mengembalikan invoice yang sudah disimpan.

Endpoint `xendit-payment` menerima `Idempotency-Key`, menggunakan reservation database, meneruskan key ke provider sebagai defense-in-depth, menyimpan invoice identifier sebelum update order, dan memiliki recovery path untuk memperbaiki order jika proses terputus setelah provider membuat invoice. Client memakai key deterministik `payment-invoice:<orderId>` sehingga retry order yang sama mempertahankan identitas logisnya.

## Payment webhook idempotency

Endpoint `xendit-webhook` tetap menggunakan `payment_webhook_events` sebagai unique ledger. Jika Xendit mengirim `webhook-id`, nilai tersebut dipakai sebagai event key yang stabil; callback lama memakai fallback deterministik berdasarkan invoice, status, dan waktu pembayaran. Duplicate event dikembalikan sukses tanpa memproses order dua kali. Callback `PENDING` yang tiba setelah order `EXPIRED` tidak menurunkan status kembali.

## Staging rollout checklist

Migration harus diaplikasikan terlebih dahulu pada Supabase staging menggunakan migration runner resmi. Setelah itu, jalankan test matrix dengan dua tenant dan minimal dua outlet: sale normal, duplicate request key, concurrent same-key request, insufficient stock, missing stock row, missing raw material, wrong tenant, wrong outlet, wrong cashier, voucher usage limit, dan customer dari tenant lain.

Untuk payment staging, kirim request invoice yang sama dua kali dengan `Idempotency-Key` sama dan dua request parallel dengan key berbeda untuk order yang sama. Hanya satu request boleh memanggil provider; retry harus mengembalikan invoice yang sama atau status in-progress. Kirim webhook PAID duplikat, webhook EXPIRED setelah PAID, webhook PENDING setelah EXPIRED, callback dengan invoice mismatch, dan callback dengan token salah.

RLS integration test production-like belum dapat dijalankan dari sandbox karena tidak tersedia kredensial service role atau Supabase CLI staging. Migration ini harus diuji di staging sebelum deploy production.
