# Xendit webhook idempotency notes

Sumber resmi yang dibaca pada 23 Agustus 2026:

1. https://docs.xendit.co/docs/handling-webhooks — Handling webhooks, diperbarui 20 Juni 2025.
2. https://docs.xendit.co/apidocs/webhook-behavior — Webhook behavior, diperbarui 1 Juli 2025.
3. https://docs.xendit.co/apidocs/payment-status-callback-webhook — Payment Status Callback, diperbarui 1 April 2026.

Temuan yang relevan:

- Xendit menjelaskan bahwa duplicate webhook dapat terjadi ketika acknowledgement tidak diterima atau provider/payment channel mengirim ulang event.
- Untuk mencegah duplicate processing dan money loss, Xendit merekomendasikan validasi webhook sebelum fulfillment; `payment_id` dan `capture_id` dapat dipakai untuk mengidentifikasi event unik pada alur payment.
- Webhook wajib diautentikasi. Dokumentasi handling webhooks menyebut `x-callback-token`; dokumentasi payment status callback terbaru juga mendeskripsikan `X-Callback-Signature` dan `X-Callback-Timestamp` untuk callback tertentu.
- Webhook sebaiknya diproses di server, bukan client.
- Endpoint harus cepat mengembalikan status 2xx; logic kompleks sebaiknya menggunakan buffer/queue.
- Jika endpoint tidak mengembalikan 2xx, Xendit dapat melakukan retry hingga enam kali dengan exponential backoff. Dokumentasi webhook behavior mencantumkan interval relatif: 15 menit, 45 menit, 2 jam, 3 jam, 6 jam, dan 12 jam.
- Webhook tidak dijamin tiba dalam urutan tetap, sehingga state transition harus tahan terhadap event out-of-order.

Keputusan implementasi repository:

- `payment_webhook_events` memakai unique key provider/event untuk deduplikasi sebelum update order.
- `payment_invoice_requests` mereservasi satu proses pembuatan invoice per provider/order sebelum request ke provider, sehingga dua request concurrent tidak sama-sama membuat invoice.
- Header `Idempotency-Key` diteruskan ke provider sebagai defense-in-depth, tetapi reservation database tetap menjadi boundary idempotency utama.
- Retry client memakai request key yang sama selama request POS belum berhasil; request key dihapus hanya setelah RPC mengembalikan sukses.
