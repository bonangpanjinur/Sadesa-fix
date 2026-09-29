# Audit dan Pembatalan Otomatis Ojek serta Kurir Barang

**Tanggal:** 29 September 2026
**Repository:** `bonangpanjinur/Sadesa-fix`
**Cakupan:** permintaan ojek penumpang dan pemesanan kurir langsung untuk barang (`service_type = COURIER_DELIVERY`).
**SLA yang diterapkan:** dibatalkan otomatis setelah 5 menit tanpa driver/kurir menerima.

## Ringkasan

Sebelum perubahan, kedua alur memiliki sebagian logika timeout di klien, tetapi belum memiliki penyelesaian server-side yang berjalan tanpa browser aktif:

- **Ojek penumpang:** penawaran pertama ditujukan ke driver terdekat selama 30 detik dan penolakan/expiry dapat mengirim penawaran ke driver berikutnya. Halaman tracking penumpang juga memiliki timer 5 menit dan memanggil `cancel_ride()`, tetapi itu bergantung pada halaman tetap terbuka. Pemrosesan expiry ojek juga sebelumnya bergantung pada sesi courier aktif.
- **Kurir barang langsung:** order dibuat berstatus `ASSIGNED`; offer driver berjangka lima menit dan dispatch dapat dicoba ulang dari tracking. Tidak ada worker backend yang menutup order setelah tidak seorang pun menerima. `scheduled_pickup` tersedia dan tidak boleh terkena aturan timeout ini.

**Perubahan:** migration baru menyediakan `auto_cancel_unanswered_transport_orders()` yang dijalankan `pg_cron` setiap menit. Ride yang masih `SEARCHING` dan pesanan kurir langsung yang masih `ASSIGNED` tanpa courier akan dibatalkan setelah berusia lima menit. Offer tertunda ditutup, alasan dan timestamp disimpan, histori order dicatat, dan pembeli diberi notifikasi. Booking pickup terjadwal, ride yang sudah memiliki driver, serta order yang kurirnya sudah menerima tidak dibatalkan.

## Temuan audit

| Area | Temuan sebelum perubahan | Dampak | Tindakan |
|---|---|---|---|
| Ojek, masa offer | Dispatch sekuensial memberikan 30 detik ke satu driver, lalu mencoba driver eligible berikutnya. | Tanpa dispatcher/browser aktif, perpindahan offer dapat tertunda. | Cron memiliki jalur terminal 5 menit yang tidak bergantung pada sesi driver. |
| Ojek, SLA total | Timer 5 menit berada di `RideTrackingPage` dan memanggil RPC cancel. | Buyer yang menutup halaman atau kehilangan koneksi tidak menjamin order berakhir. | DB worker membatalkan `SEARCHING` secara server-side; timer UI tetap menjadi feedback cepat. |
| Kurir barang | Order direct courier dapat tetap `ASSIGNED`; percobaan dispatch dari tracking bukan batas waktu terminal. | Buyer dapat menunggu tanpa batas dan offer dapat terus dicoba ulang. | Job membatalkan hanya order direct courier non-terjadwal yang belum diterima setelah 5 menit. |
| State/history | Pembatalan sistem sebelumnya tidak memiliki actor manusia yang dapat dicatat. | Riwayat audit dan alasan pembatalan kurang eksplisit. | Ride menyimpan `cancelled_at`/`cancellation_reason`; order menyimpan `cancellation_type = SYSTEM`, alasan, timestamp, serta `order_status_history`. |
| Visibilitas buyer | Kartu tracking hanya mengenali state fulfillment; status batal sebelumnya dapat jatuh ke fallback “NEW”. | UI tidak selalu menunjukkan pembatalan/reason dengan benar. | Tambah status terminal yang diterjemahkan dan banner alasan batal pada tracking kurir. |

## Perilaku yang diterapkan

1. **Satu batas waktu konsisten:** 5 menit sejak `created_at`. Tawaran ojek individual tetap berjangka 30 detik; total batas waktu mencakup pergantian driver.
2. **Frekuensi job:** satu kali per menit melalui `pg_cron`. Pembatalan terjadi pada tick pertama setelah ambang 5 menit (umumnya paling lambat sekitar satu menit setelah ambang).
3. **Kondisi ojek:** hanya `status = SEARCHING` dan `driver_id IS NULL`; status akhir mengikuti kontrak ojek saat ini, yaitu `CANCELLED`.
4. **Kondisi kurir barang:** hanya `service_type = COURIER_DELIVERY`, status `ASSIGNED`, `courier_id IS NULL`, serta `scheduled_pickup = false`. Status order akhir `CANCELED`.
5. **Race protection:** pemrosesan ojek memakai advisory lock yang juga dipakai dispatch/accept. Pemrosesan courier mengunci order dan assignment dengan `NOWAIT`, melewati konflik transaksi, dan mencoba lagi pada tick berikutnya.
6. **Tidak ada pembatalan pasca-acceptance:** ride yang sudah memiliki driver dan order/assignment yang diterima tidak cocok dengan kondisi auto-cancel.
7. **Pemberitahuan:** notifikasi in-app dikirim ke passenger/buyer dengan tautan tracking dan instruksi membuat pesanan baru.

## Validasi lokal

- Test kontrak fitur, dispatch ojek, dan kartu status: **15 lulus**.
- Production build: **lulus**; lint pada semua file source yang diubah: **lulus**.
- Parser PostgreSQL menerima 7 statement tingkat atas migration; `validate:migrations` memvalidasi 57 deployment SQL files (dengan warning timestamp duplikat lama pada prefix `11`).
- Seluruh suite: **81 file lulus, 3 file gagal, 20 test dilewati**. Kegagalan yang terlihat berada pada test lain yang tidak diubah: `rpcOverloadCleanup.test.ts`, `serviceEnhancementContract.test.ts`, dan `chat/phase8Acceptance.test.ts`.
- Validator bootstrap keseluruhan masih melaporkan hash/wrapper mismatch pada enam bundle lama (`01`, `05`, `10`, `29`, `46`, dan satu `11`). Bundle `56` yang ditambahkan pada tugas ini lulus pemeriksaan hash, sumber migration, dan wrapper sendiri.
- Migration harus diterapkan lewat jalur deployment database resmi. Audit sandbox tidak terhubung ke database staging/production, jadi status cron/job aktif dan perilaku runtime belum dibuktikan pada environment tersebut.

## Test matrix staging

| Skenario | Ekspektasi |
|---|---|
| Ride SEARCHING belum 5 menit | Tetap mencari driver |
| Ride SEARCHING melewati 5 menit tanpa browser passenger | Menjadi `CANCELLED`; offer pending menjadi `EXPIRED`; passenger mendapat notifikasi |
| Driver menerima tepat sebelum job mengambil lock | Ride menjadi `ACCEPTED`, tidak dibatalkan |
| Buyer membatalkan bersamaan dengan timeout | Hanya satu transisi terminal; request kedua tidak mengubah status |
| Direct courier ASSIGNED tanpa respons, usia > 5 menit | Menjadi `CANCELED`; offer menjadi `CANCELED`; histori dan notifikasi tercatat |
| Direct courier dengan `scheduled_pickup = true` | Tidak dibatalkan oleh job ini |
| Kurir menerima sebelum timeout | Order `COURIER_ACCEPTED`, tidak dibatalkan |
| Marketplace order (`service_type = MARKETPLACE`) berstatus serupa | Tidak disentuh worker direct-courier |
| UI dibuka setelah pembatalan kurir | Menampilkan status batal dan alasan, bukan fallback status baru |
| Job berjalan berulang pada order terminal | Tidak membuat histori/notifikasi duplikat |

## Batasan dan tindak lanjut

- Granularitas `pg_cron` satu menit berarti deadline bersifat *5 menit + hingga satu interval scheduler*, bukan pemrosesan tepat pada detik kelima.
- Perlu verifikasi migration dan job di staging setelah deployment, lalu jalankan concurrency tests dengan dua sesi authenticated.
- Pesanan `scheduled_pickup` dikecualikan karena tidak tepat dianggap terlambat hanya berdasarkan waktu dibuat; SLA pickup terjadwal perlu kebijakan terpisah bila dibutuhkan.
- Job ini hanya menangani booking langsung (`COURIER_DELIVERY`), bukan order marketplace toko atau layanan ekspedisi eksternal.
