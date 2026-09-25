# Operasional Marketplace Services

## Status implementasi

Untuk fase saat ini, pembayaran tetap dilakukan melalui **transfer manual ke rekening admin**. Buyer mengunggah bukti transfer, admin memverifikasi nominal dan bukti, lalu sistem memindahkan request ke tahap pekerjaan. Payout provider tetap dicatat setelah transfer manual benar-benar dilakukan dan referensinya dimasukkan admin.

Migration `41_20260925110000_service_ledger_rental_notifications.sql` menambahkan empat lapisan kontrol:

1. `service_transaction_ledger` menyimpan event transaksi secara append-only.
2. `payment_status`, `work_status`, `dispute_status`, dan `payout_status` memisahkan domain status dari status request utama.
3. Trigger transaksi membuat notifikasi in-app untuk buyer dan provider.
4. `service_run_sla_sweep` membatalkan request yang melewati batas negosiasi atau pembayaran.

## Menjalankan sweep SLA

`service_run_sla_sweep(integer)` dirancang untuk dipanggil oleh worker service-role atau admin. Fungsi ini tidak dijalankan oleh browser buyer/provider.

Pada lingkungan yang sudah memiliki scheduler database, jalankan secara periodik dengan interval yang disepakati, misalnya setiap 15 menit. Jika scheduler belum tersedia, panggil fungsi tersebut melalui worker backend terautentikasi. Jangan memberi hak execute fungsi ini kepada role `anon` atau `authenticated` biasa.

Contoh operasi di lingkungan database:

```sql
select public.service_run_sla_sweep(100);
```

Sebelum production, tetapkan pemilik operasional untuk memantau `service_sla_events`, notifikasi gagal, dan request yang dibatalkan otomatis.

## Aturan manual transfer

Admin harus memverifikasi hal berikut sebelum menyetujui bukti:

- nominal transfer sama dengan harga kesepakatan;
- rekening tujuan dan waktu transfer sesuai instruksi;
- bukti dapat dibaca dan tidak digunakan ulang untuk request lain;
- transfer reference dicatat jika tersedia;
- keputusan approval atau rejection diberi catatan.

Admin tidak boleh mengubah status finansial melalui update tabel langsung. Gunakan RPC state machine yang tersedia agar ledger, status request, dan notifikasi tetap konsisten.

## Jalur migrasi ke payment gateway

Integrasi payment gateway berikutnya sebaiknya mempertahankan kontrak bisnis yang sudah ada, bukan mengganti state machine secara langsung. Tahap yang disarankan adalah:

1. Buat payment intent server-side berdasarkan harga kesepakatan dan idempotency key.
2. Simpan gateway transaction ID pada tabel payment reference baru atau pada payment proof yang diperluas.
3. Terima webhook terverifikasi dari gateway untuk status paid, expired, failed, dan refunded.
4. Jadikan webhook sebagai sumber kebenaran pembayaran; upload bukti manual menjadi fallback terbatas untuk kanal yang belum terintegrasi.
5. Catat setiap callback sebagai event ledger yang immutable.
6. Untuk payout dan refund, simpan provider transfer ID, status asynchronous, retry count, dan error terakhir.
7. Jalankan reconciliation harian antara ledger aplikasi dan laporan gateway.

Pembayaran gateway tidak boleh mengizinkan client menetapkan nominal, status paid, atau status refund. Semua nilai tersebut harus berasal dari server dan signature webhook yang valid.

## Monitoring minimum

Pantau metrik berikut sebelum membuka layanan secara publik:

- jumlah request per status;
- usia request yang menunggu negosiasi, pembayaran, verifikasi, pekerjaan, dan payout;
- jumlah proof ditolak dan alasan penolakan;
- jumlah payout pending lebih dari SLA;
- jumlah refund approved yang belum completed;
- jumlah notifikasi gagal atau tidak terbaca;
- selisih ledger dengan saldo manual rekening admin.

## Pengujian staging wajib

Jalankan skenario buyer A, buyer B, provider A, provider B, dan admin. Pastikan setiap aktor hanya dapat membaca data yang berhak diakses. Uji juga retry RPC, proof nominal salah, payout ganda, refund ganda, timeout SLA, dan perubahan data rental yang tidak valid.
