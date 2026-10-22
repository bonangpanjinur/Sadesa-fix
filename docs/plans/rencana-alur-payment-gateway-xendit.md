# Rencana Alur Payment Gateway SaDesa dengan Xendit

**Status:** Rancangan implementasi
**Tanggal:** 22 Oktober 2026
**Gateway yang dipilih:** Xendit Invoice API
**Cakupan awal:** Checkout marketplace produk

## 1. Keputusan arsitektur

SaDesa menggunakan Xendit melalui Supabase Edge Functions. Browser tidak pernah memegang secret key Xendit, callback token, service-role key, atau nominal pembayaran sebagai sumber kebenaran. Browser hanya meminta pembuatan invoice untuk order milik user, menerima `invoice_url`, lalu diarahkan ke halaman pembayaran Xendit.

Transfer bank manual tetap tersedia sebagai fallback. Guest checkout tetap memakai transfer manual sampai autentikasi, akses status order, dan rekonsiliasi guest selesai diuji terpisah. Marketplace jasa tidak langsung dicampur ke checkout produk; integrasi gateway jasa sebaiknya menjadi fase kedua karena memiliki escrow, payout, refund, dan sengketa.

## 2. Alur pengguna yang disarankan

1. Pembeli memilih produk dari satu toko dan masuk ke checkout.
2. Server melakukan quote ulang: produk, harga terbaru, stok, voucher, ongkir, dan total. Total pada browser hanya untuk tampilan.
3. Pembeli memilih **Bayar Online**, **Transfer Bank**, atau metode fallback yang memang diaktifkan toko.
4. Saat pembeli menekan bayar, server membuat order dengan status `PENDING_PAYMENT` dan `payment_status = UNPAID` secara idempotent.
5. Untuk `ONLINE`, frontend memanggil Edge Function `xendit-payment/create-invoice` dengan `order_id` dan `Idempotency-Key`.
6. Edge Function memverifikasi JWT, kepemilikan order, status order, dan total dari database. Edge Function membuat satu invoice Xendit menggunakan total server dan mata uang `IDR`.
7. Frontend mengarahkan pembeli ke `invoice_url`. Redirect sukses hanya menjadi pengalaman navigasi, bukan bukti pembayaran.
8. Xendit mengirim webhook invoice ke `xendit-webhook`.
9. Webhook memvalidasi `x-callback-token`, bentuk payload, invoice ID, external ID, nominal, dan event idempotency. Selanjutnya webhook memanggil RPC `SECURITY DEFINER` untuk perubahan status atomik.
10. Jika status `PAID`, order berubah menjadi lunas dan proses fulfillment/notifikasi boleh dimulai. Jika `EXPIRED`, order tetap belum dibayar dan pembeli boleh membuat invoice baru. Event duplikat atau event yang datang tidak berurutan tidak boleh menurunkan status terminal.
11. Halaman order membaca status dari database/realtime. Parameter `?payment=success` atau `?payment=failed` hanya menampilkan informasi dan memicu refresh status.

## 3. State machine pembayaran

| Kondisi | Status order | Status pembayaran | Aksi yang diizinkan |
|---|---|---|---|
| Order dibuat | `PENDING_PAYMENT` | `UNPAID` | Buat invoice atau pilih transfer manual |
| Invoice dibuat | `PENDING_PAYMENT` | `PENDING` | Buka invoice, tunggu webhook |
| Pembayaran provider berhasil | `PROCESSING`/status fulfillment awal | `PAID` | Mulai proses pesanan |
| Invoice kedaluwarsa | `PENDING_PAYMENT` | `EXPIRED` | Buat invoice baru |
| Provider menolak/error | `PENDING_PAYMENT` | `FAILED` atau tetap `UNPAID` sesuai kebijakan | Retry dengan idempotency key yang sama |
| Transfer manual diajukan | `PENDING_PAYMENT` | `PENDING_TRANSFER` | Upload bukti, review admin |
| Bukti ditolak | `PENDING_PAYMENT` | `FAILED` | Upload bukti pengganti |
| Order dibatalkan | `CANCELLED` | `CANCELLED`/status terminal | Tidak boleh membuat invoice baru |

Status fulfillment dan status pembayaran dipisahkan. Order tidak boleh dikirim hanya karena invoice URL dibuka atau browser kembali dari Xendit.

## 4. Kontrak server

### `xendit-payment/create-invoice`

- Wajib memakai JWT user.
- Menerima hanya `order_id` berbentuk UUID.
- Memastikan `orders.buyer_id = auth.uid()`.
- Menolak order `PAID`, `CANCELLED`, atau order terminal yang tidak boleh dibayar ulang.
- Mengambil total dari database; tidak menerima `amount` dari frontend.
- Menggunakan `Idempotency-Key` yang stabil per order/attempt.
- Mengembalikan invoice yang sudah tersimpan jika invoice aktif sudah ada.
- Menyimpan `payment_invoice_id`, `payment_invoice_url`, expiry, dan reservation request melalui RPC atomik.
- Tidak mengembalikan secret, callback token, konfigurasi internal, atau response provider mentah.

### `xendit-webhook`

- `verify_jwt = false` hanya untuk endpoint callback provider.
- Wajib memvalidasi `x-callback-token` dari Supabase Function Secret.
- Wajib memvalidasi `external_id`, `invoice_id`, status yang didukung, dan nominal.
- Menyimpan event key/provider event ID untuk idempotency.
- Memproses perubahan melalui RPC `SECURITY DEFINER` dengan row lock.
- Tidak memproses nominal berbeda dari total order.
- Mengembalikan respons sukses untuk callback duplikat yang sudah diproses agar provider tidak melakukan retry tanpa akhir.
- Log hanya boleh berisi metadata aman: order ID, invoice ID terpotong bila perlu, status, dan hasil proses. Jangan log key, token, Authorization, atau payload sensitif penuh.

## 5. Perbaikan keamanan wajib sebelum produksi

1. Pindahkan `XENDIT_SECRET_KEY` dan `XENDIT_CALLBACK_TOKEN` ke Supabase Edge Function Secrets dan baca melalui `Deno.env`.
2. Hapus `secret_key` dan `callback_token` dari response `fetchAppSettings()` serta dari form halaman admin.
3. `app_settings.payment_xendit` hanya menyimpan konfigurasi nonrahasia seperti `enabled`, channel yang diizinkan, expiry default, dan lingkungan logis.
4. Pisahkan project Supabase staging dan production serta gunakan test key dan live key yang berbeda.
5. Jangan gunakan sakelar UI `is_production` sebagai kontrol keamanan. Environment ditentukan oleh secret yang terpasang pada project; bila field dipertahankan, fungsinya hanya sebagai label informasi.
6. Setelah migrasi, rotasi key/token yang pernah berada di database atau terkirim ke browser.
7. Pastikan RLS tidak memberikan akses publik ke konfigurasi provider dan transaksi tetap hanya dapat dimutasi melalui RPC/Edge Function.
8. Tambahkan tes handler dengan mock provider untuk autentikasi, nominal mismatch, duplikasi webhook, event tidak berurutan, timeout provider, retry, dan concurrency.

## 6. Pembagian fase implementasi

### Fase 1 — Checkout marketplace produk

- Hardening secret dan konfigurasi server.
- Pertahankan endpoint Xendit yang sudah ada.
- Rapikan UI status `Menunggu pembayaran`, `Berhasil`, `Kedaluwarsa`, dan `Gagal`.
- Tambahkan halaman refresh status setelah redirect.
- Uji staging dengan Xendit test key dan webhook test.

### Fase 2 — Refund dan operasional

- Tambahkan record refund dan audit trail yang terpisah dari status order.
- Untuk awal, refund dicatat setelah transfer eksternal diverifikasi finance; jangan menampilkan seolah-olah refund otomatis jika endpoint refund belum tersedia.
- Sediakan laporan rekonsiliasi: order ID, invoice ID, paid amount, waktu webhook, status internal, dan settlement reference.
- Siapkan kill switch untuk menghentikan invoice baru tanpa mematikan webhook invoice lama.

### Fase 3 — Marketplace jasa

Jangan memakai tabel order produk secara langsung. Buat payment intent khusus jasa yang terhubung ke `service_requests`, menyimpan agreed price, fee, escrow state, provider invoice ID, payment event, refund, dan payout. Alur minimal:

`WAITING_PAYMENT` → `INVOICE_PENDING` → `PAID_TO_ESCROW` → `APPROVED_TO_START` → `IN_PROGRESS` → `WAITING_CONFIRMATION` → `PAYOUT_PENDING` → `COMPLETED`.

Payout dan refund tetap harus memiliki kontrol admin, referensi eksternal, audit log, dan idempotency. Integrasi ini dilakukan setelah checkout produk stabil karena risiko rekonsiliasinya lebih tinggi.

## 7. Checklist go-live

- [ ] Secret hanya tersedia di Supabase Edge Function Secrets.
- [ ] Browser/admin tidak menerima secret atau callback token.
- [ ] Edge Functions dan migration versi yang sama sudah ter-deploy ke staging.
- [ ] Webhook Xendit staging menunjuk ke endpoint yang benar.
- [ ] Test invoice berhasil, expired, retry, dan callback duplikat sudah diverifikasi.
- [ ] Nominal di provider selalu sama dengan total server.
- [ ] Order tidak berubah `PAID` karena redirect frontend.
- [ ] RLS dan RPC diuji dengan user pemilik dan bukan pemilik order.
- [ ] Live key dan channel pembayaran sudah diverifikasi oleh finance/operasional.
- [ ] Kill switch, monitoring, rekonsiliasi, dan prosedur refund tersedia.
- [ ] `payment_xendit.enabled` baru diaktifkan setelah seluruh bukti staging lengkap.

## 8. Kesimpulan

Untuk SaDesa, pendekatan paling aman adalah melanjutkan fondasi Xendit yang sudah ada untuk checkout marketplace produk, bukan menambah gateway kedua. Prioritas pertama bukan membuat tombol pembayaran baru, melainkan mengamankan secret, memastikan webhook menjadi satu-satunya sumber kebenaran status lunas, dan menyelesaikan uji staging. Setelah itu, baru payment gateway jasa dapat dirancang sebagai payment intent/escrow terpisah.
