# Audit Lanjutan Modul Pembayaran dan Notifikasi

**Tanggal audit:** 11 September 2026  
**Cakupan:** checkout multi-merchant, pembuatan invoice Xendit, webhook payment, reservation/idempotensi, notification delivery worker, push/in-app notification, RLS, dan routing deep link.  
**Metode:** inspeksi statis source code frontend, Edge Functions, SQL bootstrap/migration, test yang tersedia, dan kontrak route. Tidak ada transaksi staging/produksi yang dijalankan.

## Ringkasan eksekutif

Webhooks pembayaran Xendit memiliki fondasi yang baik: callback memakai token, event dideduplikasi, invoice diverifikasi terhadap order, jumlah pembayaran dibandingkan dengan total order, dan transisi `PAID` dilindungi dari downgrade.

Meski demikian, ditemukan **satu bug finansial prioritas P0** pada checkout multi-merchant: ketika metode pembayaran `ONLINE` dipilih, proses membuat invoice lalu `return` dari dalam loop merchant. Hanya order merchant pertama yang dibuat dan dibayar; merchant berikutnya tidak pernah dibuat. Selain itu, terdapat risiko P1 berupa invoice reservation yang dapat macet selamanya, invoice expired yang tidak dapat dibuat ulang, job notifikasi yang dapat macet pada status `processing`, campaign yang dapat ditandai `sent` walaupun ada delivery dead-letter, serta channel push/email yang tidak diproses oleh worker yang ditemukan.

## Matriks temuan

| ID | Prioritas | Area | Temuan | Dampak |
|---|---|---|---|---|
| PAY-P0-01 | **P0** | Checkout multi-merchant | Handler `CheckoutPage` melakukan create invoice dan `return` di dalam loop `itemsByMerchant` untuk metode `ONLINE`. | Keranjang lintas merchant hanya membuat order merchant pertama. Item merchant lain tidak dibuat menjadi order, sementara pengguna langsung dialihkan ke payment provider. Ini menyebabkan transaksi parsial dan potensi kebingungan/selisih cart. |
| PAY-P1-02 | P1 | Invoice lifecycle | `payment_invoice_requests` memiliki status `processing`, tetapi tidak memiliki lease/timeout recovery. Jika Edge Function mati setelah reservation sebelum berhasil/provider response, semua retry berikutnya menerima “already in progress”. | Order tidak dapat memulai ulang pembayaran tanpa intervensi database/operator. |
| PAY-P1-03 | P1 | Invoice expired | `xendit-payment/create-invoice` mengembalikan invoice lama bila `payment_invoice_id` dan URL ada, tanpa memeriksa `payment_status = EXPIRED` atau expiry provider. | Setelah invoice expired, tombol bayar dapat terus mengembalikan URL invoice lama sehingga buyer tidak dapat membayar ulang. |
| NOTIF-P1-04 | P1 | Worker recovery | `claim_notification_delivery_job` mengubah job menjadi `processing`, tetapi tidak terlihat ada `locked_at`, lease, atau sweeper untuk job processing yang worker-nya mati. | Job dapat berhenti permanen di `processing` dan tidak pernah dicoba lagi. |
| NOTIF-P1-05 | P1 | Campaign status | `syncCampaignDelivery` menghitung status `queued` dan `failed`, tetapi tidak memasukkan `dead_letter`. Jika seluruh kegagalan sudah dead-letter, campaign dapat ditandai `sent`. | Dashboard campaign menyatakan pengiriman sukses walaupun sebagian delivery permanen gagal. |
| NOTIF-P1-06 | P1 | Channel support | Worker `process-notification-queue` hanya mengimplementasikan `whatsapp` dan `in_app`; `push` dan `email` justru dilempar sebagai `Unsupported notification channel`. | Job push/email yang masuk queue akan retry lalu gagal/dead-letter, kecuali ada worker lain yang tidak terlihat terhubung pada queue yang sama. |
| NOTIF-P1-07 | P1 | Inbox notification | Halaman notifikasi hanya mengambil 100 record dan dropdown 20 record tanpa pagination atau cursor. | Notifikasi lama tidak dapat diakses dan unread/history dapat terasa hilang pada user aktif lama. |
| PAY-P2-08 | P2 | Checkout atomicity | Order, order_items, reserve stock, dan invoice dibuat melalui beberapa request terpisah. Jika merchant kedua gagal, merchant pertama sudah tersimpan dan stok sudah ter-reserve. | Checkout multi-merchant dapat meninggalkan order parsial/reservation yang perlu rekonsiliasi. |
| PAY-P2-09 | P2 | Checkout stock race | Checkout melakukan pembacaan stock lebih dulu, baru insert order/items dan reserve melalui RPC. RPC menjaga reservation, tetapi order/items yang sudah dibuat tidak otomatis dibersihkan ketika reservation gagal. | User melihat error sementara order orphan dapat tersisa bila tidak ada cleanup/transaction wrapper. |
| NOTIF-P2-10 | P2 | Mark-as-read | `markAsRead` dipanggil tanpa `await` sebelum `navigate`. Pada navigasi cepat, request dapat dibatalkan/unmount sebelum tersimpan. | Notifikasi yang sudah diklik bisa tetap unread. Error update juga tidak ditampilkan. |
| NOTIF-P2-11 | P2 | Worker configuration | `maxBatch = Math.min(Number(env), 100)` dapat menghasilkan `NaN` jika environment invalid. | Query `.limit(NaN)` dapat gagal dan worker tidak memproses queue. |
| NOTIF-P2-12 | P2 | Query volume | Notification page membaca 100 row penuh dan menginvalidasi query pada setiap realtime event; dropdown melakukan refresh periodik 15 detik ketika terbuka. | Beban query meningkat pada akun dengan banyak event atau banyak tab. |

## Bukti dan analisis

### PAY-P0-01 — Online multi-merchant berhenti pada merchant pertama

Di `CheckoutPage`, item dikelompokkan dengan `itemsByMerchant`, kemudian setiap merchant diproses di dalam loop. Setelah order dibuat, order items diinsert, stok direserve, dan invoice online dibuat, kode mengarahkan browser ke `invoice.invoice_url` lalu menjalankan `return`:

```ts
for (const [merchantId, merchantData] of Object.entries(itemsByMerchant)) {
  // create order for merchant
  // insert order items
  // reserve stock
  if (paymentMethod === 'ONLINE' && xenditAvailable) {
    const invoice = await createPaymentInvoice({ orderId: orderData.id });
    window.location.href = invoice.invoice_url;
    return;
  }
}
```

Tidak ada guard yang memaksa checkout online hanya satu merchant. UI bahkan menghitung `merchantIds` dan secara eksplisit mendukung beberapa merchant. Akibatnya, pada cart lintas merchant, loop tidak pernah mencapai merchant kedua.

**Rekomendasi:** pilih satu kontrak bisnis yang eksplisit. Pilihan aman adalah memblokir `ONLINE` untuk cart multi-merchant sebelum membuat order, atau membuat satu parent checkout/payment intent yang memiliki child orders dan satu invoice dengan allocation. Jangan membuat beberapa child order lalu membayar salah satu invoice saja. Perbaikan tercepat dan aman: tampilkan validasi “Pembayaran online hanya mendukung satu toko per checkout” atau pecah checkout menjadi satu merchant per invoice.

### PAY-P1-02 — Reservation invoice dapat stuck

Tabel `payment_invoice_requests` menyimpan satu row unik per provider/order dengan status `processing`, `completed`, atau `failed`. RPC `reserve_payment_invoice_request` hanya dapat mengambil alih row ketika status `failed`. Tidak ada kondisi yang mengambil alih row `processing` berdasarkan umur `updated_at`.

Jika proses mati setelah baris reservation berhasil dibuat tetapi sebelum provider response atau update `failed`, request berikutnya masuk ke `can_process = false` dan menerima status “Payment initialization already in progress”.

**Rekomendasi:** tambahkan `lease_expires_at`/`processing_started_at`, klaim ulang reservation yang expired, dan lakukan rekonsiliasi provider berdasarkan `external_id` sebelum membuat invoice baru. Job cleanup harus menandai reservation lama sebagai failed/retryable.

### PAY-P1-03 — Invoice expired tidak dapat diregenerate

`create-invoice` mengembalikan invoice existing jika `payment_invoice_id` dan `payment_invoice_url` tidak null. Kondisi ini muncul sebelum pemeriksaan status provider. Webhook dapat mengubah order menjadi `EXPIRED`, tetapi identifier lama tetap tersimpan.

**Rekomendasi:** bila order `EXPIRED`, panggil endpoint status provider atau simpan `payment_invoice_expiry_at`; kemudian buat invoice baru dengan request key baru dan update invoice fields secara atomik. Jangan mengganti invoice pada order yang sudah `PAID`.

### NOTIF-P1-04 — Job processing tidak punya recovery lease

Worker mengambil candidate `queued`/`failed`, kemudian memanggil RPC claim yang mengubah status menjadi `processing`. Jika worker crash setelah claim atau timeout sebelum `complete_notification_delivery_job`, row tetap `processing`. Query candidate berikutnya tidak mengambil status tersebut.

**Rekomendasi:** tambahkan `locked_at`, `locked_by`, dan lease duration. Candidate query harus memasukkan `processing` yang lease-nya expired, atau buat sweeper periodik yang mengubahnya kembali ke `failed` dengan backoff. Completion harus memvalidasi token/claim owner bila worker paralel dipakai.

### NOTIF-P1-05 — Dead-letter tidak memengaruhi status campaign

`syncCampaignDelivery` menghitung delivery dengan status `queued` atau `failed`. Status `dead_letter` dikeluarkan dari hitungan. Karena itu ketika seluruh delivery yang gagal sudah menjadi dead-letter, `count = 0` dan campaign dengan status `sending` diubah menjadi `sent`.

**Rekomendasi:** hitung terminal failures secara terpisah. Campaign harus menjadi `failed` atau `partially_failed` bila ada delivery `dead_letter`; hanya `sent` bila seluruh delivery berhasil. Gunakan constraint/status enum dan test agregasi campaign.

### NOTIF-P1-06 — Worker channel mismatch

Tipe `NotificationJob.channel` mencantumkan `whatsapp`, `push`, `email`, dan `in_app`, tetapi `sendJob` hanya mengembalikan hasil untuk `whatsapp`/`in_app` dan melempar error untuk channel lain. Perlu dipastikan apakah push/email memakai queue dan worker terpisah. Dalam repository yang diaudit tidak ditemukan routing queue yang memastikan hal itu.

**Rekomendasi:** implementasikan sender push/email, atau pisahkan queue dan worker secara eksplisit dengan status ownership yang jelas. Tambahkan health check yang melaporkan channel tanpa consumer.

### NOTIF-P1-07 — Pagination notifikasi belum tersedia

`NotificationsPage` mengambil 100 notifikasi dan dropdown mengambil 20. Tidak ada cursor `created_at/id`, tombol “muat lebih banyak”, atau endpoint summary unread terpisah. Realtime hanya menjaga window di memory.

**Rekomendasi:** gunakan pagination cursor `(created_at, id)`, query unread count server-side, dan pertahankan cache dengan insert/update realtime tanpa reload penuh.

## Kontrol yang sudah baik

Webhook Xendit melakukan validasi callback token dengan perbandingan constant-time, memvalidasi format order UUID dan status, memastikan invoice callback cocok dengan invoice pada order, memeriksa paid amount sama dengan total order, lalu mende-duplikasi `(provider, event_key)` di dalam RPC transaction. Row order dikunci `FOR UPDATE`, dan trigger mencegah payment `PAID` diturunkan ke status lain.

Pembuatan invoice juga memeriksa bearer user, membatasi order pada buyer yang sedang login, memvalidasi total integer positif, memakai request key, dan memiliki reservation per provider/order. Worker notification memiliki auth secret, claim RPC atomik, exponential backoff, dan dead-letter setelah batas attempt.

## Rekomendasi perbaikan berdasarkan urutan

| Tahap | Pekerjaan | Prioritas |
|---|---|---|
| 1 | Blokir online checkout multi-merchant atau desain parent payment intent; tambahkan regression test. | P0 |
| 2 | Tambahkan recovery lease pada payment invoice reservation dan notification delivery job. | P1 |
| 3 | Tangani invoice expired dengan renewal/reconciliation provider. | P1 |
| 4 | Perbaiki agregasi campaign agar dead-letter menghasilkan failed/partial, bukan sent. | P1 |
| 5 | Pastikan push/email memiliki consumer queue atau tandai channel unsupported saat enqueue. | P1 |
| 6 | Tambahkan cursor pagination untuk notification page, inbox, dan dropdown. | P1/P2 |
| 7 | Bungkus checkout multi-step dalam RPC transaction atau cleanup compensation. | P2 |

## Test case minimum

1. Cart berisi produk dari dua merchant dengan `ONLINE`: sistem harus menolak sebelum order pertama dibuat, atau membuat satu parent payment yang mencakup keduanya.
2. Crash simulasi setelah `reserve_payment_invoice_request` dan sebelum provider call: retry setelah lease expiry harus dapat melanjutkan.
3. Order dengan invoice `EXPIRED`: klik bayar ulang harus menghasilkan invoice aktif baru.
4. Dua callback Xendit identik: hanya satu event yang menerapkan perubahan.
5. Callback `PAID` dengan amount berbeda: ditolak dan order tidak berubah.
6. Worker mati setelah claim job: lease sweeper mengembalikan job ke retryable state.
7. Campaign dengan satu delivery `dead_letter`: campaign tidak boleh berstatus `sent`.
8. Job channel `push`/`email`: diproses oleh consumer yang sesuai atau ditolak saat enqueue dengan alasan jelas.
9. User dengan lebih dari 100 notifikasi: pagination dapat membuka notifikasi lama.
10. Klik notifikasi lalu navigasi cepat: status read tetap tersimpan.

## Batasan audit

Audit belum menjalankan transaksi nyata pada Xendit, belum memeriksa konfigurasi cron/worker production, belum mengonfirmasi apakah ada consumer push/email di luar repository ini, dan belum menguji RLS pada database live. Temuan P0/P1 perlu diuji pada staging sebelum deployment produksi.
