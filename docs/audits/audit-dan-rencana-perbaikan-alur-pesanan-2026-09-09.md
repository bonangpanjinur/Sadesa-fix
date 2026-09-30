# Audit dan Rencana Perbaikan Alur Pesanan SaDesa

**Tanggal audit:** 9 September 2026  
**Repository:** `bonangpanjinur/Sadesa-fix`  
**Ruang lingkup:** penerimaan order merchant, pesan terkait order, pengiriman mandiri, kurir desa, status order, pembayaran, sisi pembeli, serta biaya layanan antar sendiri.

## Ringkasan eksekutif

Fondasi fitur sudah cukup luas, tetapi alur operasional saat ini belum menggunakan satu kontrak status dan satu sumber kebenaran untuk perubahan order. UI merchant masih melakukan `UPDATE orders` langsung, sebagian status dikirim tanpa validasi transisi, assignment kurir dilakukan langsung oleh merchant tanpa tahap penawaran/acceptance, dan beberapa fitur baru sudah memiliki kolom/migrasi namun belum terhubung penuh ke UI maupun RPC yang aman.

Prioritas tertinggi adalah **memperbaiki kontrak status dan mutasi order di server**, bukan sekadar mengganti label tombol. Setelah itu baru dilakukan penyempurnaan UX chat, peta kurir, live GPS, pembayaran, dan ledger biaya.

## Temuan audit

### 1. Error antar sendiri: `orders_status_check`

Pada `src/components/merchant/OrderStatusManager.tsx`, saat merchant memilih antar sendiri, aplikasi langsung menjalankan:

```ts
.update({
  is_self_delivery: true,
  status: 'DELIVERING',
  updated_at: new Date().toISOString()
})
```

Sementara pada `supabase/bootstrap/43_20260909180000_order_fulfillment_flow.sql`, status `DELIVERING` memang sudah dimasukkan ke constraint baru. Artinya, error yang dilaporkan menunjukkan salah satu dari dua hal berikut:

1. Migrasi `43_20260909180000_order_fulfillment_flow.sql` belum diterapkan ke database yang sedang dipakai aplikasi; atau
2. Database memiliki constraint/status berbeda dari branch ini akibat urutan bootstrap/migration tidak sinkron.

**Kesimpulan:** masalah utama bukan tombolnya, melainkan tidak adanya pemeriksaan schema/version dan tidak adanya RPC server-side untuk perubahan status. UI juga hanya menampilkan pesan umum sehingga akar error tidak terlihat merchant.

**Perbaikan segera:**

- verifikasi constraint aktual di database staging/production;
- terapkan migrasi 43 melalui pipeline migrasi resmi, bukan edit manual di production;
- tambahkan smoke test yang mencoba transisi `PROCESSED -> DELIVERING` untuk self-delivery;
- ubah mutasi langsung menjadi RPC `merchant_transition_order`, dengan validasi role, status asal, payment status, delivery method, dan audit log;
- tampilkan pesan error yang aman tetapi informatif, misalnya “Alur pengiriman belum tersedia di server. Hubungi admin.”

### 2. Status order belum konsisten

`src/lib/orderStatus.ts` sudah mendefinisikan status yang lebih lengkap, tetapi komponen merchant masih menggunakan konfigurasi status yang lebih pendek. Di repository juga masih ditemukan status legacy seperti `PROCESSING`, `ON_DELIVERY`, dan `COMPLETED` pada komponen tertentu, sedangkan constraint terbaru memakai `PROCESSED`, `DELIVERING`, dan `DONE`.

Dampaknya:

- filter/tab dapat menyembunyikan order;
- label pada merchant, pembeli, admin, dan kurir dapat berbeda;
- status yang valid di UI belum tentu valid di database;
- notifikasi dapat mengirim kode status mentah;
- laporan dapat menghitung `DONE` dan `COMPLETED` sebagai dua kelompok terpisah.

### 3. Tombol pesan di “Kelola Pesanan Masuk” belum menjadi jalur utama

Chat sudah mendukung `orderId` dan navigasi dari thread ke order. Di `MerchantChatPage` dan `BuyerChatPage`, produk/thread yang memiliki `orderId` sudah dapat diklik menuju order terkait. Namun pada daftar order merchant, tombol utama yang terlihat masih WhatsApp/telepon; belum ada field **Pesan** yang konsisten untuk membuka chat order tersebut.

Selain itu, metadata product pada thread belum menjadi kontrak universal. Sebagian thread dapat menampilkan `productName/productImage`, tetapi percakapan harus tetap ditautkan pada `order_id` dan, bila relevan, `product_id`/`order_item_id` agar tidak ambigu untuk order dengan banyak produk.

### 4. Assignment kurir saat ini terlalu dini dan terlalu manual

Pada `OrderStatusManager`:

- merchant memilih metode “Kurir Desa”;
- aplikasi mengambil daftar kurir berdasarkan `village_id`;
- merchant memilih kurir dari dropdown;
- order langsung diubah ke `SENT` dan `courier_id` langsung diisi.

Belum ada alur nyata:

- pencarian kurir terdekat berdasarkan koordinat;
- profil/detail kurir yang dapat dilihat merchant;
- penawaran order ke kurir;
- tombol kurir **Ambil** atau **Tolak**;
- daftar kurir yang menolak agar tidak ditawarkan ulang;
- reservation/lock agar dua merchant tidak memberikan order sama ke kurir yang sama;
- timeout penawaran dan fallback ke kurir lain;
- perubahan status `COURIER_ACCEPTED` sebelum kurir menuju toko.

Migrasi 43 sudah menambahkan `courier_rejected_ids`, `courier_assigned_at`, dan `courier_accepted_at`, tetapi kolom tersebut belum membentuk workflow lengkap. Ini adalah tanda bahwa desain data sudah mulai disiapkan, namun implementasi aplikasi belum selesai.

### 5. GPS dan maps belum terhubung ke lifecycle delivery

Data kurir memiliki `last_location_update`, tetapi belum terlihat kontrak end-to-end yang menghubungkan:

- permission lokasi kurir;
- heartbeat lokasi saat order aktif;
- lokasi merchant dan pembeli;
- peta pada sisi merchant/pembeli;
- rute/ETA;
- penghentian sharing lokasi setelah order selesai atau dibatalkan;
- perlindungan privasi dan retensi lokasi.

GPS berjalan sebaiknya hanya aktif ketika kurir menerima order sampai order selesai, bukan sepanjang hari tanpa alasan operasional.

### 6. Pembayaran dan status order perlu dipisahkan secara eksplisit

`merchant_verify_order_payment` sudah digunakan untuk verifikasi pembayaran dan mengubah order menjadi `PROCESSED` serta `payment_status = 'PAID'`. Namun UI pembeli harus menggunakan `payment_status` sebagai sumber keputusan tombol pembayaran, bukan hanya `order.status`.

Kontrak UX yang disarankan:

| `payment_status` | Tombol/teks pembeli |
|---|---|
| `UNPAID` / `PENDING` | **Bayar sekarang** |
| `PROOF_SUBMITTED` / menunggu verifikasi | **Menunggu verifikasi pembayaran** |
| `PAID` | **Cek status pesanan** |
| `REJECTED` | **Perbaiki pembayaran** |
| `REFUNDED` | **Dana dikembalikan** |

Perubahan merchant/admin harus realtime atau minimal melakukan invalidation query sehingga card pembeli berubah tanpa reload manual.

### 7. Aturan 10% dan batas dua kali antar sendiri belum memiliki ledger

Repository sudah memiliki pengaturan komisi/platform fee umum (`app_settings`, halaman Admin Komisi/Finance), tetapi belum terlihat model khusus yang menjawab:

- persentase self-delivery yang berlaku saat order dibuat;
- apakah basisnya ongkir atau nilai order;
- tagihan per pengantaran;
- batas gratis dua kali dan periode penghitungannya;
- status tagihan (`UNPAID`, `DUE`, `PAID`, `WAIVED`, `OVERDUE`);
- enforcement agar merchant tidak dapat memakai self-delivery ketika tunggakan;
- audit perubahan persentase admin;
- idempotensi agar tagihan tidak dibuat dua kali.

Aturan bisnis perlu dikunci sebelum coding. Interpretasi yang paling aman dari permintaan adalah: **dua pengantaran self-delivery pertama bebas biaya platform; pengantaran berikutnya dikenai persentase yang dikonfigurasi admin dari ongkir order tersebut**, dengan snapshot persentase pada saat order/assignment dibuat. Jika yang dimaksud adalah setiap pengantaran dikenai 10% sejak awal, aturan itu harus dipilih secara eksplisit karena berdampak pada checkout dan rekonsiliasi.

## Status order yang direkomendasikan

Gunakan satu set status canonical. Label bahasa Indonesia disimpan di frontend, sedangkan database memakai kode stabil.

| Kode | Label pengguna | Aktor utama | Makna |
|---|---|---|---|
| `NEW` | Pesanan baru | Merchant | Order masuk, belum dikonfirmasi |
| `PENDING_PAYMENT` | Menunggu pembayaran | Pembeli | Order belum lunas |
| `PENDING_CONFIRMATION` | Menunggu konfirmasi toko | Merchant | Pembayaran/permintaan perlu ditinjau |
| `PROCESSED` | Sedang disiapkan | Merchant | Merchant menerima dan memproses |
| `READY` | Siap dikirim/diambil | Merchant | Barang siap untuk fulfillment |
| `ASSIGNED` | Mencari kurir | Platform/merchant | Penawaran kurir sedang berjalan |
| `COURIER_ACCEPTED` | Kurir menuju toko | Kurir | Kurir menerima dan menuju merchant |
| `PICKED_UP` | Sudah diambil kurir | Kurir | Barang telah diterima kurir |
| `DELIVERING` | Sedang diantarkan | Kurir/merchant | Dalam perjalanan ke pembeli |
| `DELIVERED` | Sudah sampai | Kurir/pembeli | Bukti serah terima tercatat |
| `DONE` | Selesai | Sistem/pembeli | Order ditutup dan siap settlement |
| `CANCELED` | Dibatalkan | Pembeli/merchant/admin | Dibatalkan sesuai aturan |
| `REJECTED` | Ditolak toko | Merchant | Merchant menolak order |
| `REFUNDED` | Dana dikembalikan | Admin/sistem | Settlement dibalikkan |

Status tambahan `COURIER_REJECTED` tidak perlu menjadi status order yang bertahan lama; lebih baik dicatat sebagai event/attempt kurir, lalu order kembali ke `ASSIGNED` selama masih mencari kurir. `SENT` sebaiknya dihapus dari alur baru karena ambigu: pada sebagian UI berarti “dikirim”, pada alur lain berarti “siap diambil”. Data legacy tetap dibaca melalui mapping saat migrasi.

### Transisi inti

```text
NEW/PENDING_CONFIRMATION
  -> PROCESSED
  -> READY
  -> ASSIGNED                 (kurir desa)
  -> COURIER_ACCEPTED
  -> PICKED_UP
  -> DELIVERING
  -> DELIVERED
  -> DONE
```

Untuk self-delivery:

```text
PROCESSED -> READY -> DELIVERING -> DELIVERED -> DONE
```

Untuk pickup oleh pembeli:

```text
PROCESSED -> READY -> DELIVERED -> DONE
```

Semua transisi harus memvalidasi state asal. Tidak boleh ada client yang dapat mengubah `NEW` langsung menjadi `DONE` hanya dengan `UPDATE` biasa.

## Rencana pengembangan bertahap

### Fase 0 — Stabilkan produksi/staging

1. Bandingkan schema staging/production dengan bootstrap, khususnya constraint `orders_status_check` dan migrasi 43.
2. Buat migration checksum/version check pada deployment.
3. Jalankan smoke test untuk status `DELIVERING`, `COURIER_ACCEPTED`, `PICKED_UP`, dan `DONE`.
4. Tambahkan error logging terstruktur untuk RPC/database error code.
5. Bekukan penambahan status baru sampai canonical status disepakati.

**Output:** error antar sendiri hilang dan status database/UI tidak lagi berbeda antar environment.

### Fase 1 — Kontrak status dan order inbox

1. Buat enum/constant canonical bersama frontend dan database.
2. Buat RPC `merchant_transition_order(p_order_id, p_to_status, p_reason)`.
3. Buat tabel `order_status_history` atau pastikan event audit yang ada mencatat actor, from/to, reason, dan timestamp.
4. Tambahkan komponen `OrderStatusTimeline` yang dipakai pembeli, merchant, admin, dan kurir.
5. Tambahkan field **Pesan** pada setiap card order merchant.
6. Buka `OrderChat` dengan `orderId`, tampilkan ringkasan order, merchant/buyer, dan item yang relevan.
7. Tambahkan deep-link aman `/merchant/orders?orderId=...` dan `/orders/:orderId` dengan pemeriksaan akses server.

**Acceptance criteria:** satu perubahan status terlihat di semua role dalam hitungan detik; setiap order dapat membuka chat yang tepat; status ilegal ditolak server.

### Fase 2 — Pembayaran dan realtime buyer card

1. Standarkan `payment_status` ke nilai canonical.
2. Pisahkan status pembayaran dari status fulfillment.
3. Perbarui `OrdersPage` agar tombol berdasarkan `payment_status` berubah menjadi **Cek status pembayaran** setelah lunas.
4. Subscribe buyer ke perubahan order dan payment event; invalidasi cache setelah webhook/RPC verifikasi.
5. Kirim notifikasi ketika merchant menerima, menyiapkan, mengirim, atau menyelesaikan order.
6. Pastikan verifikasi pembayaran idempotent dan tidak mengurangi stock dua kali.

### Fase 3 — Kurir desa: offer, accept, reject

Tambahkan model minimal:

- `delivery_assignments`: order, courier, state, offered_at, expires_at, responded_at, rejection_reason;
- `courier_location_events` atau tabel lokasi dengan retensi terbatas;
- `courier_rejected_ids` hanya sebagai cache/kemudahan query, bukan satu-satunya audit;
- constraint unik agar hanya ada satu assignment aktif untuk satu order.

Alur:

1. Merchant memilih **Kurir Desa**.
2. Server mengambil kurir aktif berdasarkan radius, desa, availability, dan jarak dari toko.
3. Merchant melihat map, jarak, ETA, rating, jumlah order aktif, dan profil publik kurir.
4. Merchant memilih kurir; server membuat `delivery_assignment` berstatus `OFFERED`.
5. Kurir menerima notifikasi dengan tombol **Ambil**/**Tolak**.
6. **Ambil** mengubah assignment menjadi `ACCEPTED`, order menjadi `COURIER_ACCEPTED`, dan mengunci order.
7. **Tolak** mencatat alasan/waktu lalu mengecualikan kurir dari penawaran ulang.
8. Timeout atau penolakan mengembalikan order ke `ASSIGNED` dan merchant dapat memilih kandidat berikutnya.
9. Setelah pickup, kurir mengubah ke `PICKED_UP`; mulai perjalanan mengubah ke `DELIVERING`.
10. Serah terima memakai OTP/foto/tanda tangan sesuai kebutuhan, lalu `DELIVERED` dan akhirnya `DONE`.

### Fase 4 — Maps dan GPS yang aman

1. Simpan koordinat toko dan alamat pembeli dengan kualitas/accuracy.
2. Gunakan provider map yang dipilih proyek dan simpan API key hanya di konfigurasi aman.
3. Tampilkan peta kandidat kurir di merchant; jangan expose lokasi presisi kurir yang tidak dipilih.
4. Saat order diterima, kirim lokasi kurir berkala dengan interval adaptif.
5. Tampilkan posisi/ETA hanya kepada pihak yang berhak selama order aktif.
6. Hentikan tracking setelah `DELIVERED`/`CANCELED`, dan terapkan retensi/penghapusan lokasi.
7. Sediakan fallback ketika GPS mati, permission ditolak, atau koneksi offline.

### Fase 5 — Self-delivery fee dan enforcement

Tambahkan pengaturan admin, misalnya:

- `self_delivery_fee_percent`;
- `self_delivery_free_limit` default 2;
- `self_delivery_fee_basis` (`SHIPPING_COST` atau `ORDER_SUBTOTAL`);
- `self_delivery_billing_period` bila batas dua kali dihitung per bulan/periode;
- `self_delivery_block_on_overdue`.

Tambahkan tabel ledger:

- `merchant_delivery_fee_ledger`: merchant, order, basis_amount, percent_snapshot, fee_amount, attempt_number, status, due_at, paid_at;
- `merchant_self_delivery_usage`: merchant, period, used_count, free_limit_snapshot;
- `merchant_service_restrictions`: merchant, service, reason, starts_at, ends_at.

Aturan penting:

- snapshot konfigurasi saat fee dibuat; perubahan admin tidak mengubah tagihan lama;
- gunakan unique key `(order_id, fee_type)` untuk idempotensi;
- blokir pemilihan self-delivery di RPC/server, bukan hanya menonaktifkan tombol UI;
- tampilkan sisa kuota gratis dan tagihan pada merchant;
- admin dapat waive/adjust dengan audit reason;
- pembayaran fee harus punya bukti dan status yang dapat direkonsiliasi.

### Fase 6 — Hardening, testing, dan rollout

Tambahkan test matrix:

| Area | Skenario minimum |
|---|---|
| Status | transisi valid, transisi ilegal, retry, double click |
| Payment | unpaid, proof submitted, paid, rejected, webhook duplicate |
| Self-delivery | penggunaan ke-1, ke-2, ke-3, tunggakan, perubahan persen |
| Courier | accept, reject, timeout, dua merchant memilih kurir sama |
| GPS | permission denied, offline, stale location, order selesai |
| Chat | akses pembeli/merchant/kurir, order multi-item, orderId invalid |
| Realtime | event terlambat, reconnect, duplicate event |
| RLS | user lain mencoba membaca order/chat/location |

Rollout dilakukan di staging dengan golden dataset, dilanjutkan pilot terbatas merchant/kurir, feature flag per desa, monitoring error rate dan status stuck, lalu perluasan bertahap.

## Keputusan bisnis yang perlu dikunci sebelum implementasi fee

1. “Gratis dua kali” dihitung per merchant per hari, minggu, bulan, atau selamanya?
2. Persentase 10% dihitung dari ongkir, subtotal barang, atau total transaksi?
3. Fee dibayar sebelum merchant boleh memulai pengantaran berikutnya, atau boleh menjadi invoice jatuh tempo?
4. Jika ongkir nol, apakah ada minimum fee?
5. Apakah fee berlaku untuk self-delivery oleh merchant saja atau juga staf/kurir internal merchant?
6. Apakah kegagalan pengantaran/cancel/refund mengembalikan kuota dan fee?

## Urutan pengerjaan yang disarankan

1. **P0:** sinkronisasi migration 43 dan perbaiki error `DELIVERING`.
2. **P0:** canonical status + RPC transition + audit history.
3. **P0:** field Pesan pada order merchant dan deep-link chat berbasis order.
4. **P1:** payment status buyer card + realtime notification.
5. **P1:** courier offer/accept/reject dan exclusion kurir.
6. **P1:** map kandidat dan detail profil kurir.
7. **P2:** GPS aktif selama delivery dan proof of delivery.
8. **P2:** ledger fee self-delivery, kuota dua kali, pembayaran, dan block.
9. **P2:** migrasi legacy status, laporan, observability, dan rollout pilot.

## Kesimpulan

SaDesa tidak perlu menambah banyak tombol sebelum kontrak server diperbaiki. Fondasi yang benar adalah **state machine order yang tervalidasi server, event history, pemisahan payment/fulfillment, assignment kurir berbasis offer, dan ledger biaya yang idempotent**. Dengan urutan tersebut, kebutuhan pengguna—pesan langsung dari order, kurir terdekat, penolakan kurir, GPS, status pembeli yang selalu berubah, dan aturan fee self-delivery—dapat dibangun tanpa memperbesar utang status dan inkonsistensi antar role.
