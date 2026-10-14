# Notifikasi Background SaDesa: Pesanan dan Chat

## Yang bisa dan tidak bisa dilakukan

SaDesa adalah Progressive Web App (PWA), bukan aplikasi Android dengan foreground service. Browser/PWA tidak dapat menjaga JavaScript halaman atau audio terus berjalan setelah aplikasi ditutup; Android dan iOS dapat menangguhkan atau menghentikan proses untuk menghemat daya.

Cara yang didukung untuk menerima pesanan dan chat saat halaman berada di background atau ditutup adalah **Web Push**. Service worker browser dapat menampilkan notifikasi sistem tanpa halaman aplikasi tetap aktif, jika perangkat, subscription browser, dan worker server sudah dikonfigurasi. Pengiriman tetap dapat tertunda/dibatasi oleh pengaturan baterai/data OS, izin yang dicabut, atau koneksi terputus.

Audio alarm di dalam aplikasi hanya tersedia ketika halaman berjalan dan audio sudah dibuka dengan interaksi pengguna. Saat aplikasi ditutup, perangkat menjalankan perilaku notifikasi sistem (suara/getar mengikuti pengaturan perangkat), bukan audio aplikasi yang terus hidup.

## Aktivasi di perangkat

1. Buka SaDesa lewat HTTPS di browser terbaru yang mendukung Web Push. Di Android, gunakan **Install app**/**Add to Home screen**. Di iOS, tambahkan situs ke Home Screen bila menggunakan Web Push.
2. Masuk ke akun yang akan menerima notifikasi pada perangkat tersebut.
3. Dari halaman merchant/kurir, tekan **Aktifkan Alarm & Notifikasi** dan izinkan notifikasi browser/OS. Subscription disimpan untuk akun yang sedang login; tidak dibagikan ke akun lain.
4. Pastikan aplikasi melaporkan notifikasi background aktif. Jika izin pernah diblokir, ubah izin situs ke **Allow** di pengaturan browser lalu aktivasi ulang.
5. Izinkan suara notifikasi dan background data di pengaturan sistem. Pada Android, uji dengan pengaturan baterai yang sesuai dan periksa pembatasan vendor; Battery Saver/Data Saver/task killer dapat menunda pengiriman.
6. Uji menggunakan akun pengirim/pembeli terpisah: buat order baru, lalu kirim pesan chat baru kepada akun penerima setelah PWA diminimalkan/ditutup. Pastikan notifikasi OS tampil. Jangan menguji dengan hanya membuka dropdown notifikasi di halaman.

## Jalur server

### Pesanan

1. Trigger database memasukkan job `push` ke `notification_delivery_jobs`.
2. `process-notification-queue` mengambil job dan mengirim Web Push.
3. Service worker menerima event `push`, menjalankan `showNotification`, lalu membuka deep link saat pengguna mengetuk notifikasi.

### Chat

1. Trigger `chat_messages_notify_recipient` memanggil `send_chat_notification`, yang tetap membuat notifikasi in-app.
2. Jika penerima memiliki `push_subscriptions` aktif, fungsi yang sama menambah satu job `new_chat_message` ke antrean. Push tidak memuat isi pesan; hanya nama pengirim dan teks generik agar konten tidak tampil di lock screen.
3. Trigger queue menjalankan worker segera; cron satu-menit tetap menjadi fallback/retry. Service worker membuka tautan chat sesuai peran penerima.

Job chat dideduplikasi per pasangan pesan/penerima. Jika penerima tidak berlangganan push, notifikasi in-app/Realtime tetap bekerja dan job push tidak dibuat.

## Konfigurasi server dan verifikasi staging

Kebutuhan Edge Function:

- `VAPID_PUBLIC_KEY` dan `VAPID_PRIVATE_KEY` pada secrets Edge Functions; gunakan pasangan yang sama saat `push-subscription` menghasilkan subscription.
- `WORKER_CRON_SECRET` pada Edge Functions dan nilai yang sama pada Supabase Vault.
- Supabase Vault entries: `sadesa_project_url`, `sadesa_publishable_key`, `sadesa_notification_worker_secret`.
- Migration `20261005150000_notification_delivery_worker_cron.sql` harus sudah diterapkan dan job `sadesa-notification-delivery` terdaftar pada `cron.job`.
- Deploy `push-subscription` dan `process-notification-queue`; `process-notification-queue` memakai `verify_jwt = false`, tetapi handler tetap memeriksa header `x-worker-secret`.

Urutan uji pada **staging saja**:

1. Verifikasi `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` dan `WORKER_CRON_SECRET` tersedia tanpa mencetak nilainya; pastikan key publik pada endpoint berpasangan dengan private key.
2. Pastikan scheduler `sadesa-notification-delivery` aktif. Periksa log `process-notification-queue` untuk error VAPID, endpoint 404/410, atau job yang gagal.
3. Login sebagai penerima merchant dan aktifkan push di PWA perangkat uji; konfirmasi satu baris subscription pada `push_subscriptions` untuk user tersebut.
4. Buat order uji: pastikan job `new_merchant_order` dibuat lalu statusnya menjadi `sent`.
5. Kirim pesan chat dari akun lain: pastikan job `new_chat_message` dibuat satu kali dengan deep link yang benar, body push generik, lalu status `sent`.
6. Tutup/minimalkan PWA penerima sebelum pengiriman. Verifikasi notifikasi OS muncul dan tautan membukanya ke order/chat yang sesuai.
7. Tanpa subscription penerima, pastikan pesan chat tetap membuat notifikasi in-app namun tidak membuat job push. Jika provider menolak job, periksa `last_error`, percobaan berikutnya, dan status dead-letter.

Jangan masukkan service-role key, VAPID private key, atau worker secret ke kode frontend, Git, log, maupun pesan. Jalankan migrasi dan uji hanya pada staging yang memang ditetapkan sebagai non-production.

## Batas izin

- Izin notifikasi tidak diminta otomatis; pengguna harus menekan tombol aktivasi.
- Aplikasi tidak dapat mengubah izin browser dari **Block** ke **Allow** atau mengesampingkan pembatasan OS/vendor.
- Service worker dapat bangun untuk event push dan menampilkan notifikasi; ia tidak menjaga halaman aplikasi tetap hidup.
- Keberhasilan build lokal tidak membuktikan konfigurasi VAPID, scheduler, trigger database, subscription, maupun pengiriman ke perangkat nyata.

Lihat [Evaluasi Background Services PWA dan Native](../architecture/background-services-pwa-native-evaluation-2026-10-06.md) untuk lokasi kurir/alarm yang memerlukan platform native.
